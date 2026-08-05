import 'dart:math';

import '../models/video_segment.dart';
import '../models/video_source.dart';
import 'whisper_service.dart';

class HighlightDetectorService {
  // Words that typically introduce a hook, secret or high-value claim.
  static const List<String> _hookWords = [
    'rahasia',
    'tips',
    'trik',
    'triks',
    'cara',
    'jangan',
    'stop',
    'wait',
    'penting',
    'wajib',
    'paling',
    'terbaik',
    'terbesar',
    'tercepat',
    'terbaru',
    'termurah',
    'gila',
    'mantap',
    'wow',
    'mengejutkan',
    'kaget',
    'secret',
    'nobody',
    'never',
    'unbelievable',
    'crazy',
    'shocking',
    'mistake',
    'dilarang',
    'bahaya',
    'awas',
    'perhatian',
    'simak',
    'dengerin',
    'tunggu',
    'langsung',
    'sekarang',
    'coba',
    'pelajari',
    'benci',
    'gagal',
    'salah',
    'beda',
    'diketahui',
    'rahasia',
  ];

  // Words that prompt engagement (calls to action).
  static const List<String> _ctaWords = [
    'subscribe',
    'like',
    'share',
    'comment',
    'bagikan',
    'langganan',
    'follow',
    'klik',
    'link',
    'join',
    'daftar',
    'simpan',
    'save',
    'tonton',
    'komentar',
    'ikutan',
    'catat',
    'jangan lupa',
  ];

  static const Duration maxClipDuration = Duration(seconds: 60);
  static const int minClipSeconds = 20;

  static int _maxSegmentsFor(int totalSeconds) {
    return (totalSeconds / 240).ceil().clamp(3, 15);
  }

  /// Detects viral segments using rule-based NLP over the Whisper transcript.
  ///
  /// Scoring signals: speech density (energetic talking), emphasised words
  /// (whisper.cpp emits loud words in ALL CAPS) and hook/CTA keywords. When
  /// no transcript is available a deterministic fallback is used.
  Future<List<VideoSegment>> detectHighlights(
    VideoSource source, {
    List<WhisperWord> transcribedWords = const [],
  }) async {
    if (transcribedWords.isEmpty) {
      return _fallbackSegments(source);
    }
    return _scoreTranscript(source, transcribedWords);
  }

  List<VideoSegment> _scoreTranscript(
    VideoSource source,
    List<WhisperWord> words,
  ) {
    final totalSeconds = max(1, source.duration.inSeconds);

    final pointPerSecond = List<double>.filled(totalSeconds + 1, 0);
    final wordsPerSecond = List<double>.filled(totalSeconds + 1, 0);
    final wordsInSecond = <int, List<String>>{};

    for (final w in words) {
      final t = w.start.inSeconds.clamp(0, totalSeconds);
      var score = 1.0;
      if (_isEmphasis(w.word)) score += 3.0;
      if (_isHook(w.word)) score += 4.0;
      if (_isCta(w.word)) score += 2.0;
      pointPerSecond[t] += score;
      wordsPerSecond[t] += 1;
      wordsInSecond.putIfAbsent(t, () => []).add(w.word);
    }

    final maxClip = maxClipDuration.inSeconds;
    final maxSegments = _maxSegmentsFor(totalSeconds);
    final segments = <VideoSegment>[];
    final covered = List<bool>.filled(totalSeconds + 1, false);

    while (segments.length < maxSegments) {
      double bestScore = 0;
      var bestStart = 0;
      var bestLen = maxClip;

      for (int start = 0; start < totalSeconds; start++) {
        final maxLenHere = min(maxClip, totalSeconds - start);
        if (maxLenHere < minClipSeconds) continue;
        if (_coverageRatio(covered, start, start + maxLenHere) > 0.4) continue;

        double windowBest = 0;
        var windowLen = maxClip;
        for (int len = minClipSeconds; len <= maxLenHere; len++) {
          final score =
              _windowScore(pointPerSecond, wordsPerSecond, start, len) -
              len * 0.05;
          if (score > windowBest) {
            windowBest = score;
            windowLen = len;
          }
        }

        if (windowBest > bestScore) {
          bestScore = windowBest;
          bestStart = start;
          bestLen = windowLen;
        }
      }

      if (bestScore <= 0) break;

      final end = min(totalSeconds, bestStart + bestLen);
      for (int t = bestStart; t < end; t++) {
        if (t < covered.length) covered[t] = true;
      }
      segments.add(
        _buildSegment(wordsInSecond, bestStart, end, totalSeconds, bestScore),
      );
    }

    if (segments.isEmpty) return _fallbackSegments(source);

    segments.sort((a, b) => a.startTime.compareTo(b.startTime));
    for (int i = 0; i < segments.length; i++) {
      segments[i] = segments[i].copyWith(id: 'seg_${i + 1}');
    }
    return segments;
  }

  double _windowScore(
    List<double> points,
    List<double> density,
    int start,
    int len,
  ) {
    final end = min(points.length - 1, start + len);
    var total = 0.0;
    var words = 0.0;
    for (int t = start; t < end; t++) {
      total += points[t];
      words += density[t];
    }
    // A solid, continuously-speaking window beats a sparse spike.
    final densityBonus = min(words / max(1, len), 1.5) * 10;
    return total + densityBonus;
  }

  double _coverageRatio(List<bool> covered, int start, int end) {
    if (end <= start) return 1.0;
    var count = 0;
    for (int t = start; t < min(end, covered.length); t++) {
      if (covered[t]) count++;
    }
    return count / (end - start);
  }

  VideoSegment _buildSegment(
    Map<int, List<String>> wordsInSecond,
    int start,
    int end,
    int totalSeconds,
    double rawScore,
  ) {
    final buffer = StringBuffer();
    var hooks = 0;
    var cta = false;
    var emphasis = false;
    for (int t = start; t < min(end, totalSeconds); t++) {
      for (final w in wordsInSecond[t] ?? const <String>[]) {
        buffer.write('$w ');
        if (_isHook(w)) hooks++;
        if (_isCta(w)) cta = true;
        if (_isEmphasis(w)) emphasis = true;
      }
    }

    final transcript = buffer.toString().trim();
    final score = (85.0 + rawScore).clamp(80.0, 99.5);
    final viralScore = double.parse(score.toStringAsFixed(1));

    final title = _pickTitle(hooks, cta, emphasis);
    return VideoSegment(
      id: 'seg_',
      title: title,
      startTime: Duration(seconds: start),
      endTime: Duration(seconds: min(end, totalSeconds)),
      viralScore: viralScore,
      summary: _pickSummary(hooks, cta, emphasis),
      transcript: transcript.isEmpty
          ? 'Transkrip otomatis dari Whisper AI.'
          : transcript,
    );
  }

  String _pickTitle(int hooks, bool cta, bool emphasis) {
    if (hooks > 0) return '💡 Hook Menarik & Poin Kunci';
    if (cta) return '🎯 Ajakan Interaksi (CTA)';
    if (emphasis) return '🔥 Momen Penuh Penekanan';
    return '⚡ Percakapan Padat Energi';
  }

  String _pickSummary(int hooks, bool cta, bool emphasis) {
    if (hooks > 0) {
      return 'Mengandung kata kunci hook yang memancing rasa penasaran penonton.';
    }
    if (cta) {
      return 'Berisi ajakan interaksi yang mendorong engagement (like/comment/share).';
    }
    if (emphasis) {
      return 'Penekanan vokal kuat yang menonjolkan poin penting pembicaraan.';
    }
    return 'Segmen percakapan dengan kepadatan kata tinggi yang cocok untuk Shorts/Reels.';
  }

  bool _isEmphasis(String raw) {
    final w = raw.trim();
    if (w.endsWith('!') || w.endsWith('?')) return true;
    return w.length >= 3 &&
        RegExp(r'[a-zA-Z]').hasMatch(w) &&
        w == w.toUpperCase();
  }

  bool _isHook(String raw) {
    final w = raw.toLowerCase();
    return _hookWords.any(w.contains);
  }

  bool _isCta(String raw) {
    final w = raw.toLowerCase();
    return _ctaWords.any(w.contains);
  }

  /// Deterministic fallback when Whisper produced no word-level timestamps.
  /// Clips are evenly spread across the whole video, each up to 1 menit, with
  /// the count scaled by the original duration.
  List<VideoSegment> _fallbackSegments(VideoSource source) {
    final totalSeconds = max(1, source.duration.inSeconds);
    if (totalSeconds < minClipSeconds) {
      return [
        VideoSegment(
          id: 'seg_1',
          title: 'Full Clip Highlight',
          startTime: Duration.zero,
          endTime: source.duration,
          viralScore: 92.5,
          summary:
              'Klip pendek berdurasi penuh dengan potensi engagement tinggi.',
          transcript: 'Transkrip otomatis dari Whisper AI.',
        ),
      ];
    }

    final segments = <VideoSegment>[];
    final chunk = min(
      maxClipDuration.inSeconds,
      max(minClipSeconds, totalSeconds ~/ 3),
    );
    final count = _maxSegmentsFor(totalSeconds);
    var start = 0;
    var index = 0;
    while (start + minClipSeconds < totalSeconds && index < count) {
      final end = min(totalSeconds, start + chunk);
      final label = _fallbackLabel(index);
      segments.add(
        VideoSegment(
          id: 'seg_${index + 1}',
          title: '⚡ Segmen Percakapan $label',
          startTime: Duration(seconds: start),
          endTime: Duration(seconds: end),
          viralScore: double.parse(
            (92.5 - index * 2.0).clamp(75.0, 99.0).toStringAsFixed(1),
          ),
          summary: 'Segmen percakapan yang berpotensi engagement tinggi.',
          transcript: 'Transkrip otomatis dari Whisper AI.',
        ),
      );
      start = end;
      index++;
    }
    return segments;
  }

  static String _fallbackLabel(int index) {
    const ordinals = ['Pertama', 'Kedua', 'Ketiga', 'Keempat', 'Kelima'];
    if (index < ordinals.length) return ordinals[index];
    return '${index + 1}';
  }
}
