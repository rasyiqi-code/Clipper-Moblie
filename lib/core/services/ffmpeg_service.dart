import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import '../models/video_segment.dart';
import '../models/subtitle_style.dart';
import 'crop_filter_builder.dart';

class VideoProbeInfo {
  final Duration duration;
  final int width;
  final int height;
  final bool hasAudio;

  const VideoProbeInfo({
    this.duration = const Duration(minutes: 3),
    this.width = 1920,
    this.height = 1080,
    this.hasAudio = false,
  });
}

class FFmpegService {
  final CropFilterBuilder _cropFilterBuilder = CropFilterBuilder();

  /// Reads real duration & video dimensions from the input file.
  /// Falls back to sensible defaults if probing fails.
  Future<VideoProbeInfo> probeVideo(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      if (info != null) {
        var width = 1920;
        var height = 1080;
        var hasAudio = false;
        for (final stream in info.getStreams()) {
          if (stream.getType() == 'video' &&
              (stream.getWidth() ?? 0) > 0 &&
              (stream.getHeight() ?? 0) > 0) {
            width = stream.getWidth()!;
            height = stream.getHeight()!;
          }
          if (stream.getType() == 'audio') hasAudio = true;
        }

        final durationSec = double.tryParse(info.getDuration() ?? '') ?? 0;
        final duration = durationSec > 0
            ? Duration(milliseconds: (durationSec * 1000).round())
            : const Duration(minutes: 3);

        return VideoProbeInfo(
          duration: duration,
          width: width,
          height: height,
          hasAudio: hasAudio,
        );
      }
    } catch (_) {}
    return const VideoProbeInfo();
  }

  /// Converts Duration to FFmpeg timestamp string "HH:MM:SS.mmm"
  String _formatTimestamp(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String threeDigits(int n) => n.toString().padLeft(3, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    final millis = threeDigits(duration.inMilliseconds.remainder(1000));
    return '$hours:$minutes:$seconds.$millis';
  }

  /// Converts a Flutter [Color] into a decimal ASS-style colour value
  /// (&HAABBGGRR). The `&H` hex form must be avoided because it breaks
  /// FFmpeg filtergraph parsing (see: subtitles filter).
  int _assColorValue(Color color) {
    final a = (color.a * 255).round();
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final invAlpha = 255 - a;
    return (invAlpha << 24) | (b << 16) | (g << 8) | r;
  }

  /// Builds a libass `force_style` string from a [SubtitleStyle] so burned
  /// subtitles actually honour the chosen font, size, colours, stroke and
  /// position instead of the hardcoded default style.
  String _buildForceStyle(SubtitleStyle style) {
    final alignment = switch (style.position) {
      SubtitlePosition.top => 8,
      SubtitlePosition.center => 5,
      SubtitlePosition.bottom => 2,
    };

    // Prefer a stroke outline when configured, otherwise an opaque box.
    final borderStyle = style.strokeWidth > 0 ? 1 : 3;

    return [
      'Fontname=${style.fontFamily}',
      'Fontsize=${style.fontSize.toStringAsFixed(0)}',
      'PrimaryColour=${_assColorValue(style.textColor)}',
      'OutlineColour=${_assColorValue(style.strokeColor)}',
      'Outline=${style.strokeWidth.toStringAsFixed(1)}',
      'Bold=1',
      'Alignment=$alignment',
      'MarginV=24',
      'BorderStyle=$borderStyle',
      'BackColour=${_assColorValue(style.backgroundColor)}',
    ].join(',');
  }

  /// Generates a `.srt` subtitle file for the video segment
  Future<File> generateSrtFile(
    VideoSegment segment,
    SubtitleStyle style,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final srtFile = File('${tempDir.path}/sub_${segment.id}.srt');

    final words = segment.transcript.split(' ');
    final StringBuffer buffer = StringBuffer();

    int lineIndex = 1;
    int wordsPerLine = 4;
    double totalDurationSeconds =
        (segment.endTime - segment.startTime).inMilliseconds / 1000.0;
    double timePerWord = totalDurationSeconds / max(1, words.length);

    for (int i = 0; i < words.length; i += wordsPerLine) {
      final lineWords = words.sublist(i, min(i + wordsPerLine, words.length));
      final text = lineWords.join(' ');

      final startSec = i * timePerWord;
      final endSec = min(
        (i + wordsPerLine) * timePerWord,
        totalDurationSeconds,
      );

      final startTimeStr = _formatTimestamp(
        Duration(milliseconds: (startSec * 1000).round()),
      ).replaceAll('.', ',');
      final endTimeStr = _formatTimestamp(
        Duration(milliseconds: (endSec * 1000).round()),
      ).replaceAll('.', ',');

      buffer.writeln('$lineIndex');
      buffer.writeln('$startTimeStr --> $endTimeStr');
      buffer.writeln(style.isUppercase ? text.toUpperCase() : text);
      buffer.writeln();

      lineIndex++;
    }

    await srtFile.writeAsString(buffer.toString());
    return srtFile;
  }

  Future<List<String>> buildRenderCommand({
    required String inputPath,
    required String outputPath,
    required VideoSegment segment,
    required SubtitleStyle subtitleStyle,
    required int inputWidth,
    required int inputHeight,
    double cropXPercent = 0.5,
    bool hasAudio = false,
  }) async {
    final startTimeStr = _formatTimestamp(segment.startTime);
    final durationSec =
        segment.clipDuration.inMilliseconds / 1000.0;

    final double targetAspectRatio = switch (segment.targetAspectRatio) {
      AspectRatioType.portrait916 => 9 / 16,
      AspectRatioType.square11 => 1.0,
      AspectRatioType.landscape169 => 16 / 9,
    };

    String? subtitleFilter;
    if (segment.enableSubtitles) {
      final srtFile = await generateSrtFile(segment, subtitleStyle);
      final forceStyle = _buildForceStyle(subtitleStyle);
      final escapedSrtPath = srtFile.path
          .replaceAll('\\', '/')
          .replaceAll(':', '\\:')
          .replaceAll(',', '\\,')
          .replaceAll("'", "\\'");
      subtitleFilter = "subtitles=$escapedSrtPath:force_style='$forceStyle'";
      if (Platform.isAndroid) {
        subtitleFilter += ':fontsdir=/system/fonts';
      }
    }

    final args = <String>[
      '-ss',
      startTimeStr,
      '-t',
      durationSec.toStringAsFixed(3),
      '-i',
      inputPath,
    ];

    if (segment.faceKeyframes.isNotEmpty) {
      // Dense keyframes: express the pan as split→trim→setpts→crop→concat so
      // the filtergraph stays O(transitions) flat instead of nesting ~90-deep
      // `if(lt(...))` expressions (which FFmpeg rejects). The graph is written
      // to a script file because the string can exceed the argv size limit.
      var graph = _cropFilterBuilder.generateChunkedFilterGraph(
        inputWidth: inputWidth,
        inputHeight: inputHeight,
        cropXPercent: cropXPercent,
        targetAspectRatio: targetAspectRatio,
        segmentDurationSec: durationSec,
        keyframes: segment.faceKeyframes,
      );
      var videoLabel = '[vout]';
      if (subtitleFilter != null) {
        graph += ';[vout]$subtitleFilter[vsub]';
        videoLabel = '[vsub]';
      }
      if (hasAudio) {
        graph += ';[0:a]atrim=start=0:end='
            '${durationSec.toStringAsFixed(3)},asetpts=PTS-STARTPTS[aout]';
      }

      final tempDir = await getTemporaryDirectory();
      final graphFile = File(
        '${tempDir.path}/graph_${segment.id}_'
        '${DateTime.now().millisecondsSinceEpoch}.fgr',
      );
      await graphFile.writeAsString(graph);

      args.addAll(['-filter_complex_script', graphFile.path]);
      args.addAll(['-map', videoLabel]);
      if (hasAudio) args.addAll(['-map', '[aout]']);
    } else {
      // No tracking data: static crop on the main video stream, FFmpeg picks
      // the audio stream automatically.
      final cropFilter = _cropFilterBuilder.generateCropFilter(
        inputWidth: inputWidth,
        inputHeight: inputHeight,
        cropXPercent: cropXPercent,
        targetAspectRatio: targetAspectRatio,
      );
      var filterComplex = cropFilter;
      if (subtitleFilter != null) filterComplex += ',$subtitleFilter';
      args.addAll(['-vf', filterComplex]);
    }

    args.addAll([
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-crf',
      '24',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-y',
      outputPath,
    ]);

    return args;
  }

  Future<bool> executeRender({
    required String inputPath,
    required String outputPath,
    required VideoSegment segment,
    required SubtitleStyle subtitleStyle,
    Function(double progress)? onProgress,
  }) async {
    final probe = await probeVideo(inputPath);

    final args = await buildRenderCommand(
      inputPath: inputPath,
      outputPath: outputPath,
      segment: segment,
      subtitleStyle: subtitleStyle,
      inputWidth: probe.width,
      inputHeight: probe.height,
      cropXPercent: segment.cropXPercent,
      hasAudio: probe.hasAudio,
    );

    try {
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return true;
      }
    } catch (_) {}

    final outputFile = File(outputPath);
    if (await outputFile.exists() && (await outputFile.length()) > 1024) {
      return true;
    }

    return false;
  }

  /// Extracts evenly-spaced sample frames (scaled to 480px wide) from the
  /// segment so ML Kit can detect the speaker's position. Sampling is dense
  /// (every ~1.5s) so a speaker switch or scene cut is caught within ~1.5s,
  /// but hard-capped at [maxFrames] so an hour-long clip never grinds through
  /// thousands of inferences. Each frame carries its [timeSec] relative to the
  /// clip start.
  Future<List<({String path, int width, double timeSec})>>
  extractSegmentFrames({
    required String inputPath,
    required VideoSegment segment,
    int maxFrames = 1463,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final frameDir = Directory(
      '${tempDir.path}/face_${segment.id}_${DateTime.now().millisecondsSinceEpoch}',
    );
    await frameDir.create(recursive: true);

    const frameWidth = 480;
    var frameHeight = frameWidth;
    final probe = await probeVideo(inputPath);
    if (probe.width > 0 && probe.height > 0) {
      frameHeight = (probe.height * frameWidth / probe.width).round();
    }
    if (frameHeight % 2 != 0) frameHeight -= 1;

    final frames = <({String path, int width, double timeSec})>[];
    final double totalSec = segment.clipDuration.inMilliseconds / 1000.0;
    if (totalSec <= 0.0) return frames;

    // Sample every ~1.5s so a speaker switch or scene cut is caught within
    // ~1.5s; for very long clips the count is capped at [maxFrames] (still
    // evenly spaced) so analysis stays bounded. Very short clips get a floor
    // so at least a few frames are analysed.
    const double intervalSec = 1.5;
    double fps = totalSec > maxFrames * intervalSec
        ? maxFrames / totalSec
        : 1.0 / intervalSec;
    if (totalSec * fps < 4.0) fps = 4.0 / totalSec;

    final session = await FFmpegKit.executeWithArguments([
      '-ss',
      _formatTimestamp(segment.startTime),
      '-t',
      totalSec.toStringAsFixed(3),
      '-i',
      inputPath,
      '-vf',
      'fps=${fps.toStringAsFixed(4)},scale=$frameWidth:$frameHeight',
      '-q:v',
      '4',
      '-y',
      '${frameDir.path}/f_%03d.jpg',
    ]);

    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) {
      final listFiles =
          frameDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.jpg'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      for (var i = 0; i < listFiles.length; i++) {
        frames.add((
          path: listFiles[i].path,
          width: frameWidth,
          timeSec: i / fps,
        ));
      }
    }

    debugPrint(
      '[face-detect] ekstrak ${frames.length} frame (clip '
      '${_formatTimestamp(segment.startTime)} → ${_formatTimestamp(segment.endTime)})',
    );

    // Clean up empty temp directory when FFmpeg produced no frames
    if (frames.isEmpty) {
      try {
        if (await frameDir.exists()) await frameDir.delete(recursive: true);
      } catch (_) {}
    }

    return frames;
  }
}
