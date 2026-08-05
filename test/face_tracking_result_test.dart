import 'package:flutter_test/flutter_test.dart';
import 'package:clipper_mobile/core/models/face_tracking_result.dart';
import 'package:clipper_mobile/core/models/video_segment.dart';

void main() {
  group('FaceTrackingResult.isSuccessful', () {
    test('succeeds when a speaker X-center was found', () {
      const result = FaceTrackingResult(speakerX: 0.42);
      expect(result.isSuccessful, isTrue);
    });

    test('succeeds with keyframes even when the average X is unknown', () {
      const result = FaceTrackingResult(
        keyframes: [FaceKeyframe(timeSec: 0, xPercent: 0.5)],
      );
      expect(result.isSuccessful, isTrue);
    });

    test('fails when nothing was detected', () {
      const result = FaceTrackingResult(
        failureReason: 'ML Kit: 0 wajah di 12 frame',
      );
      expect(result.isSuccessful, isFalse);
      expect(result.failureReason, isNotNull);
    });

    test('defaults to failure', () {
      const result = FaceTrackingResult();
      expect(result.isSuccessful, isFalse);
    });
  });
}
