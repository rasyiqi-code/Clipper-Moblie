import 'dart:math';

import '../models/video_segment.dart';

/// A contiguous time window rendered with a fixed horizontal crop offset.
typedef CropWindow = ({double startSec, double endSec, int xOffset});

/// Pure FFmpeg crop-filter geometry (no I/O, no platform deps), unit-testable.
class CropFilterBuilder {
  /// Calculates the FFmpeg crop filter string for converting 16:9 to 9:16.
  /// Supports dynamic keyframes expression for live speaker switching.
  ///
  /// Only safe for a handful of keyframes: the expression nests one `if(lt)`
  /// per keyframe, which FFmpeg rejects past ~90 levels. Dense sampling uses
  /// [generateChunkedFilterGraph] instead.
  String generateCropFilter({
    required int inputWidth,
    required int inputHeight,
    double cropXPercent = 0.5,
    double targetAspectRatio = 9 / 16,
    List<FaceKeyframe> keyframes = const [],
  }) {
    final geometry = _cropGeometry(
      inputWidth: inputWidth,
      inputHeight: inputHeight,
      targetAspectRatio: targetAspectRatio,
    );

    String xExpr;
    if (keyframes.length > 1) {
      String buildExpr(int index) {
        if (index >= keyframes.length - 1) {
          return '${_xOffsetFor(keyframes.last.xPercent, geometry)}';
        }
        final nextT = keyframes[index + 1].timeSec;
        return 'if(lt(t,${nextT.toStringAsFixed(2)}),'
            '${_xOffsetFor(keyframes[index].xPercent, geometry)},'
            '${buildExpr(index + 1)})';
      }

      xExpr = buildExpr(0);
    } else {
      xExpr = '${_xOffsetFor(cropXPercent, geometry)}';
    }

    return keyframes.length > 1
        ? "crop=${geometry.cropWidth}:${geometry.cropHeight}:"
            "'$xExpr':${geometry.yOffset}"
        : 'crop=${geometry.cropWidth}:${geometry.cropHeight}:'
            '$xExpr:${geometry.yOffset}';
  }

  /// Resolves the list of keyframes into contiguous [CropWindow]s, merging
  /// consecutive keyframes that map to the same pixel offset so the count
  /// tracks the number of real pan transitions (not the raw sample count).
  ///
  /// A leading window is prepended from the clip start (0.0) holding the first
  /// keyframe's offset, matching the "hold until it changes" behaviour, and
  /// the final window extends to [segmentDurationSec] so the tail keeps the
  /// last offset.
  List<CropWindow> buildCropWindows({
    required int inputWidth,
    required int inputHeight,
    required double segmentDurationSec,
    double cropXPercent = 0.5,
    double targetAspectRatio = 9 / 16,
    List<FaceKeyframe> keyframes = const [],
  }) {
    if (keyframes.isEmpty) return const [];

    final geometry = _cropGeometry(
      inputWidth: inputWidth,
      inputHeight: inputHeight,
      targetAspectRatio: targetAspectRatio,
    );

    final steps = <(double, int)>[];
    int? prevOffset;
    for (final k in keyframes) {
      final offset = _xOffsetFor(k.xPercent, geometry);
      if (offset != prevOffset) {
        steps.add((k.timeSec, offset));
        prevOffset = offset;
      }
    }
    if (steps.isEmpty) return const [];

    final windows = <CropWindow>[];
    for (var i = 0; i < steps.length; i++) {
      final start = steps[i].$1;
      final end =
          i + 1 < steps.length ? steps[i + 1].$1 : segmentDurationSec;
      if (end < start) continue;

      if (i == 0 && start > 0.0) {
        windows.add((
          startSec: 0.0,
          endSec: start,
          xOffset: steps[0].$2,
        ));
      }
      windows.add((startSec: start, endSec: end, xOffset: steps[i].$2));
    }
    return windows;
  }

  /// Builds a `filter_complex` graph (written to a file and passed via
  /// `-filter_complex_script`) that splits the input into one branch per
  /// [CropWindow], trims each branch to its window, resets its timestamps and
  /// applies the crop, then concatenates the branches back into a single
  /// `[vout]` stream.
  ///
  /// This is O(transitions) filters with no nesting, so it stays valid for
  /// hundreds/thousands of keyframes where the nested `if(lt(...))` expression
  /// would break FFmpeg's graph parser. Subtitles (if any) are chained onto
  /// `[vout]` by the caller.
  String generateChunkedFilterGraph({
    required int inputWidth,
    required int inputHeight,
    required double segmentDurationSec,
    double cropXPercent = 0.5,
    double targetAspectRatio = 9 / 16,
    List<FaceKeyframe> keyframes = const [],
  }) {
    final windows = buildCropWindows(
      inputWidth: inputWidth,
      inputHeight: inputHeight,
      segmentDurationSec: segmentDurationSec,
      cropXPercent: cropXPercent,
      targetAspectRatio: targetAspectRatio,
      keyframes: keyframes,
    );
    final geometry = _cropGeometry(
      inputWidth: inputWidth,
      inputHeight: inputHeight,
      targetAspectRatio: targetAspectRatio,
    );

    if (windows.isEmpty) {
      final xOffset = _xOffsetFor(cropXPercent, geometry);
      return 'crop=${geometry.cropWidth}:${geometry.cropHeight}:'
          '$xOffset:${geometry.yOffset}[vout]';
    }

    final firstOffset = windows.first.xOffset;
    final uniform = windows.every((w) => w.xOffset == firstOffset);
    if (uniform) {
      return 'crop=${geometry.cropWidth}:${geometry.cropHeight}:'
          '$firstOffset:${geometry.yOffset}[vout]';
    }

    final n = windows.length;
    final buffer = StringBuffer();
    buffer.write('[0:v]split=$n');
    for (var i = 0; i < n; i++) {
      buffer.write('[s$i]');
    }
    buffer.write(';');
    for (var i = 0; i < n; i++) {
      final w = windows[i];
      buffer.write(
        '[s$i]trim=start=${w.startSec.toStringAsFixed(3)}:'
        'end=${w.endSec.toStringAsFixed(3)},'
        'setpts=PTS-STARTPTS,'
        'crop=${geometry.cropWidth}:${geometry.cropHeight}:'
        '${w.xOffset}:${geometry.yOffset}[c$i];',
      );
    }
    buffer.write('[c0]');
    for (var i = 1; i < n; i++) {
      buffer.write('[c$i]');
    }
    buffer.write('concat=n=$n:v=1:a=0[vout]');
    return buffer.toString();
  }

  /// Crop geometry shared by every filter builder: even dimensions (chroma
  /// subsampling), centered vertical offset and the max horizontal pan range.
  ({
    int cropWidth,
    int cropHeight,
    int maxXOffset,
    int yOffset,
    int inputWidth,
  }) _cropGeometry({
    required int inputWidth,
    required int inputHeight,
    required double targetAspectRatio,
  }) {
    int cropHeight = inputHeight;
    int cropWidth = (cropHeight * targetAspectRatio).round();

    if (cropWidth > inputWidth) {
      cropWidth = inputWidth;
      cropHeight = (cropWidth / targetAspectRatio).round();
    }

    if (cropWidth % 2 != 0) cropWidth -= 1;
    if (cropHeight % 2 != 0) cropHeight -= 1;

    final maxXOffset = max(0, inputWidth - cropWidth);
    final maxYOffset = max(0, inputHeight - cropHeight);
    var yOffset = (maxYOffset / 2).round();
    if (yOffset % 2 != 0) yOffset -= 1;
    if (yOffset < 0) yOffset = 0;

    return (
      cropWidth: cropWidth,
      cropHeight: cropHeight,
      maxXOffset: maxXOffset,
      yOffset: yOffset,
      inputWidth: inputWidth,
    );
  }

  /// Converts a face-center fraction into an even, clamped pixel crop offset.
  int _xOffsetFor(
    double xPercent,
    ({
      int cropWidth,
      int cropHeight,
      int maxXOffset,
      int yOffset,
      int inputWidth,
    }) geometry,
  ) {
    final faceCenterX = xPercent.clamp(0.0, 1.0) * geometry.inputWidth;
    var xOffset =
        (faceCenterX - geometry.cropWidth / 2).round().clamp(0, geometry.maxXOffset);
    if (xOffset % 2 != 0) xOffset -= 1;
    return xOffset;
  }
}
