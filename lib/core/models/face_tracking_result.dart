import 'video_segment.dart';

/// Outcome of a face-tracking analysis pass over a single video segment.
class FaceTrackingResult {
  /// Average X-center (0.0 = left, 1.0 = right) of the talking speaker.
  final double? speakerX;

  /// Timestamped speaker positions used to pan the crop while playing.
  final List<FaceKeyframe> keyframes;

  /// Human-readable reason when the analysis could not identify a speaker.
  /// `null` means the pass produced a usable result.
  final String? failureReason;

  const FaceTrackingResult({
    this.speakerX,
    this.keyframes = const [],
    this.failureReason,
  });

  bool get isSuccessful =>
      failureReason == null && (speakerX != null || keyframes.isNotEmpty);
}
