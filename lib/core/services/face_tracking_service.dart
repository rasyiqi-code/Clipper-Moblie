import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/face_tracking_result.dart';
import '../models/video_segment.dart';
import 'ffmpeg_service.dart';
import 'mlkit_face_detector_service.dart';

/// Orchestrates a face-tracking pass: extracts bounded sample frames from the
/// clip, runs ML Kit face detection over them with progress reporting, and
/// returns the speaker's average X-center plus timestamped keyframes.
///
/// Kept free of UI and provider concerns so it can be unit-tested; ML Kit and
/// FFmpeg services are injectable.
class FaceTrackingService {
  FaceTrackingService({FFmpegService? ffmpegService})
    : _ffmpegService = ffmpegService ?? FFmpegService();

  final FFmpegService _ffmpegService;
  final MLKitFaceDetectorService _detector = MLKitFaceDetectorService();

  Future<FaceTrackingResult> analyzeSegment({
    required String inputPath,
    required VideoSegment segment,
    void Function(int processed, int total)? onProgress,
    List<({double start, double end})> voicedWindows = const [],
  }) async {
    var frames = const <({String path, int width, double timeSec})>[];
    try {
      frames = await _ffmpegService.extractSegmentFrames(
        inputPath: inputPath,
        segment: segment,
      );
      if (frames.isEmpty) {
        return const FaceTrackingResult(
          failureReason: 'Gagal ekstraksi frame (0 frame)',
        );
      }

      final res = await _detector.detectSpeakerKeyframesAcrossFrames(
        frames.map((f) => f.path).toList(),
        frameWidth: frames.first.width,
        timeSecs: frames.map((f) => f.timeSec).toList(),
        onProgress: onProgress,
        voicedWindows: voicedWindows,
        segmentStartSec: segment.startTime.inMilliseconds / 1000.0,
      );

      return FaceTrackingResult(
        speakerX: res.averageX,
        keyframes: res.keyframes
            .map((k) => FaceKeyframe(timeSec: k.timeSec, xPercent: k.xPercent))
            .toList(),
        failureReason: (res.averageX == null && res.keyframes.isEmpty)
            ? _detector.lastStatus
            : null,
      );
    } catch (e, st) {
      debugPrint('[face-detect] analyzeSegment error: $e\n$st');
      return FaceTrackingResult(failureReason: 'Error tracking: $e');
    } finally {
      if (frames.isNotEmpty) {
        try {
          final dir = File(frames.first.path).parent;
          if (await dir.exists()) await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  void dispose() {
    _detector.dispose();
  }
}
