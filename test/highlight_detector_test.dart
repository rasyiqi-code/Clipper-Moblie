import 'package:flutter_test/flutter_test.dart';
import 'package:clipper_mobile/core/models/video_source.dart';
import 'package:clipper_mobile/core/services/highlight_detector_service.dart';
import 'package:clipper_mobile/core/services/whisper_service.dart';

void main() {
  group('HighlightDetectorService', () {
    group('maxClipDuration', () {
      test('is 60 seconds (1 menit maksimal)', () {
        expect(HighlightDetectorService.maxClipDuration,
            equals(const Duration(seconds: 60)));
      });
    });

    group('maxSegments scaling', () {
      test('1-hour transcript video yields >5 clips (not capped at 5)', () async {
        final words = List<WhisperWord>.generate(
          3600,
          (i) => WhisperWord(
            word: i % 10 == 0 ? 'penting' : 'kata',
            start: Duration(seconds: i),
            end: Duration(seconds: i + 1),
          ),
        );

        final source = VideoSource(
          id: 'src_scale_1h',
          title: '1-Jam Video',
          pathOrUrl: '',
          type: VideoSourceType.local,
          duration: const Duration(hours: 1),
        );

        final segments = await HighlightDetectorService()
            .detectHighlights(source, transcribedWords: words);

        expect(segments.length, greaterThan(5));
        for (final seg in segments) {
          expect(seg.clipDuration.inSeconds, lessThanOrEqualTo(60));
        }
      });

      test('short 90s video yields multiple clips, not just 1', () async {
        final words = List<WhisperWord>.generate(
          90,
          (i) => WhisperWord(
            word: i % 10 == 0 ? 'penting' : 'kata',
            start: Duration(seconds: i),
            end: Duration(seconds: i + 1),
          ),
        );

        final source = VideoSource(
          id: 'src_scale_90s',
          title: '90s Video',
          pathOrUrl: '',
          type: VideoSourceType.local,
          duration: const Duration(seconds: 90),
        );

        final segments = await HighlightDetectorService()
            .detectHighlights(source, transcribedWords: words);

        expect(segments.length, greaterThan(1));
        for (final seg in segments) {
          expect(seg.clipDuration.inSeconds, lessThanOrEqualTo(60));
        }
      });

      test('very short video (<20s) returns exactly 1 full clip', () async {
        final source = VideoSource(
          id: 'src_tiny',
          title: 'Tiny Clip',
          pathOrUrl: '',
          type: VideoSourceType.local,
          duration: const Duration(seconds: 10),
        );

        final segments = await HighlightDetectorService()
            .detectHighlights(source);

        expect(segments.length, equals(1));
        expect(segments.first.title, equals('Full Clip Highlight'));
      });

      test('1-hour fallback (no transcript) yields scaled count, each <=60s', () async {
        final source = VideoSource(
          id: 'src_fb_1h',
          title: '1-Hour No Transcript',
          pathOrUrl: '',
          type: VideoSourceType.local,
          duration: const Duration(hours: 1),
        );

        final segments = await HighlightDetectorService()
            .detectHighlights(source);

        expect(segments.length, greaterThan(5));
        for (final seg in segments) {
          expect(seg.clipDuration.inSeconds, lessThanOrEqualTo(60));
        }
      });
    });
  });
}