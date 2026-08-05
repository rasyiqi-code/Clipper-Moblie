import 'package:flutter_test/flutter_test.dart';
import 'package:clipper_mobile/core/services/crop_filter_builder.dart';
import 'package:clipper_mobile/core/models/video_segment.dart';

/// 16:9 input, 9:16 target crop.
const inputW = 1920;
const inputH = 1080;
const cropW = 608; // (1080 * 9/16).round() → 608
const cropH = 1080;
const maxOffset = inputW - cropW; // 1312

FaceKeyframe kf(double t, double x) =>
    FaceKeyframe(timeSec: t, xPercent: x);

void main() {
  final service = CropFilterBuilder();

  group('generateCropFilter (9:16 crop of 16:9 video)', () {
    test('centers the crop on a center-positioned face', () {
      final filter = service.generateCropFilter(
        inputWidth: inputW,
        inputHeight: inputH,
        cropXPercent: 0.5,
      );
      // Face at center → crop window centered, face lands at crop center.
      expect(filter, 'crop=$cropW:$cropH:${maxOffset ~/ 2}:0');
    });

    test('left-positioned face pushes crop to the left edge', () {
      final filter = service.generateCropFilter(
        inputWidth: inputW,
        inputHeight: inputH,
        cropXPercent: 0.1,
      );
      // Face at 10% (x=192px): centered offset = 192 - 304 < 0 → clamped to 0.
      expect(filter, 'crop=$cropW:$cropH:0:0');
    });

    test('right-positioned face pushes crop to the right edge', () {
      final filter = service.generateCropFilter(
        inputWidth: inputW,
        inputHeight: inputH,
        cropXPercent: 0.9,
      );
      // Face at 90% (x=1728px): centered offset = 1728 - 304 = 1424 → clamp 1312.
      expect(filter, 'crop=$cropW:$cropH:1312:0');
    });

    test('keeps the face roughly centered inside the crop', () {
      // Face at x=960px. Crop spans 656..1264 → face center (960) is the
      // exact center of the crop.
      final filter = service.generateCropFilter(
        inputWidth: inputW,
        inputHeight: inputH,
        cropXPercent: 0.5,
      );
      final x = int.parse(
        RegExp(r'crop=\d+:\d+:(\d+):\d+').firstMatch(filter)!.group(1)!,
      );
      final faceInCrop = 960 - x;
      expect((faceInCrop - cropW / 2).abs(), lessThan(2));
    });

    test('landscape target does not pan', () {
      final filter = service.generateCropFilter(
        inputWidth: inputW,
        inputHeight: inputH,
        cropXPercent: 0.9,
        targetAspectRatio: 16 / 9,
      );
      expect(filter, contains(':0:0'));
    });
  });

  group('buildCropWindows (chunked render plan)', () {
    test('no keyframes yields no windows', () {
      final windows = service.buildCropWindows(
        inputWidth: inputW,
        inputHeight: inputH,
        segmentDurationSec: 10,
        keyframes: const [],
      );
      expect(windows, isEmpty);
    });

    test('single keyframe holds its offset before and after its time', () {
      final windows = service.buildCropWindows(
        inputWidth: inputW,
        inputHeight: inputH,
        segmentDurationSec: 10,
        keyframes: [kf(5, 0.5)],
      );
      expect(windows.length, 2);
      expect(windows[0].startSec, 0.0);
      expect(windows[0].endSec, 5.0);
      expect(windows[0].xOffset, maxOffset ~/ 2);
      expect(windows[1].startSec, 5.0);
      expect(windows[1].endSec, 10.0);
      expect(windows[1].xOffset, maxOffset ~/ 2);
    });

    test('splits on offset change and prepends a leading hold', () {
      final windows = service.buildCropWindows(
        inputWidth: inputW,
        inputHeight: inputH,
        segmentDurationSec: 12,
        keyframes: [kf(5, 0.1), kf(9, 0.9)],
      );
      expect(windows.length, 3);
      expect(windows[0].xOffset, 0);
      expect(windows[0].startSec, 0.0);
      expect(windows[0].endSec, 5.0);
      expect(windows[1].xOffset, 0);
      expect(windows[1].startSec, 5.0);
      expect(windows[1].endSec, 9.0);
      expect(windows[2].xOffset, maxOffset);
      expect(windows[2].startSec, 9.0);
      expect(windows[2].endSec, 12.0);
    });

    test('merges consecutive keyframes that map to the same pixel offset', () {
      final windows = service.buildCropWindows(
        inputWidth: inputW,
        inputHeight: inputH,
        segmentDurationSec: 12,
        keyframes: [kf(5, 0.1), kf(7, 0.11), kf(9, 0.9)],
      );
      // No boundary at t=7: same crop offset as t=5.
      expect(windows.length, 3);
      expect(windows.map((w) => w.startSec), [0.0, 5.0, 9.0]);
    });
  });

  group('generateChunkedFilterGraph', () {
    test('emits a flat split graph with no nested if(lt)', () {
      final graph = service.generateChunkedFilterGraph(
        inputWidth: inputW,
        inputHeight: inputH,
        segmentDurationSec: 12,
        keyframes: [kf(5, 0.1), kf(9, 0.9)],
      );
      expect(graph, isNot(contains('if(lt')));
      expect(graph, contains('split=3[s0][s1][s2]'));
      expect(graph, contains('concat=n=3:v=1:a=0[vout]'));
      expect('crop=$cropW:$cropH:'.allMatches(graph).length, 3);
    });

    test('falls back to a plain static crop for one uniform offset', () {
      final graph = service.generateChunkedFilterGraph(
        inputWidth: inputW,
        inputHeight: inputH,
        segmentDurationSec: 10,
        keyframes: [kf(3, 0.1), kf(7, 0.11)],
      );
      expect(graph, 'crop=$cropW:$cropH:0:0[vout]');
    });

    test('static crop fallback when no keyframes', () {
      final graph = service.generateChunkedFilterGraph(
        inputWidth: inputW,
        inputHeight: inputH,
        segmentDurationSec: 10,
        cropXPercent: 0.5,
        keyframes: const [],
      );
      expect(graph, 'crop=$cropW:$cropH:${maxOffset ~/ 2}:0[vout]');
    });

    test('handles hundreds of keyframes without deep nesting', () {
      final dense = List.generate(
        720,
        (i) => kf(i * 0.5, 0.2 + 0.6 * ((i * 137) % 719) / 719),
      );
      final graph = service.generateChunkedFilterGraph(
        inputWidth: inputW,
        inputHeight: inputH,
        segmentDurationSec: 360,
        keyframes: dense,
      );
      expect(graph, isNot(contains('if(lt')));
      expect(graph, contains('[vout]'));
    });
  });
}
