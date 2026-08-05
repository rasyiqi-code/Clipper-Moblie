/// A single transcribed word with its absolute timestamp (seconds into the
/// video). Persisted with the [VideoProject] so face tracking can voice-gate
/// the speaker lock even after the project is reopened (Whisper itself is too
/// slow to re-run on every load).
class TranscribedWord {
  final String word;
  final double startSec;
  final double endSec;

  TranscribedWord({
    required this.word,
    required this.startSec,
    required this.endSec,
  });

  Map<String, dynamic> toJson() => {
    'word': word,
    'startSec': startSec,
    'endSec': endSec,
  };

  factory TranscribedWord.fromJson(Map<String, dynamic> json) =>
      TranscribedWord(
        word: json['word'] as String? ?? '',
        startSec: (json['startSec'] as num? ?? 0).toDouble(),
        endSec: (json['endSec'] as num? ?? 0).toDouble(),
      );
}
