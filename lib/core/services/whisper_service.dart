import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

class WhisperWord {
  final String word;
  final Duration start;
  final Duration end;

  WhisperWord({required this.word, required this.start, required this.end});
}

class WhisperService {
  final WhisperController _controller = WhisperController();
  WhisperModel model = WhisperModel.base;

  /// Maps a persisted model key ('tiny'|'base') to a [WhisperModel].
  static WhisperModel resolveModel(String key) =>
      key == 'tiny' ? WhisperModel.tiny : WhisperModel.base;

  /// Number of parallel processors for whisper.cpp (faster on multi-core).
  static int get _nProcessors => Platform.numberOfProcessors.clamp(2, 4);

  /// Whether the local Whisper model has already been downloaded/cached.
  Future<bool> hasLocalModel() async {
    final path = await _controller.getPath(model);
    return File(path).exists();
  }

  /// Size in bytes of the cached Whisper model, or `null` when not downloaded.
  Future<int?> localModelSizeBytes() async {
    final path = await _controller.getPath(model);
    final file = File(path);
    if (!await file.exists()) return null;
    return file.length();
  }

  /// Removes the cached Whisper model from device storage.
  Future<void> deleteLocalModel() async {
    final path = await _controller.getPath(model);
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Returns the local ggml model file, downloading it (with progress) on
  /// first use. The model is cached in app storage afterwards.
  Future<File> getLocalModelFile({
    void Function(double progress)? onProgress,
  }) async {
    final path = await _controller.getPath(model);
    final file = File(path);
    if (await file.exists()) return file;

    await file.parent.create(recursive: true);
    final client = http.Client();
    try {
      final request = http.Request('GET', model.modelUri);
      final streamed = await client.send(request);
      final total = streamed.contentLength ?? 0;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream) {
        builder.add(chunk);
        if (total > 0) onProgress?.call(builder.length / total);
      }
      await file.writeAsBytes(builder.takeBytes(), flush: true);
    } finally {
      client.close();
    }
    return file;
  }

  /// Extracts 16kHz mono WAV audio from video using local FFmpegKit.
  Future<File> extractAudioForWhisper(String videoPath) async {
    final tempDir = await getTemporaryDirectory();
    final audioFile = File(
      '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    try {
      await FFmpegKit.executeWithArguments([
        '-i',
        videoPath,
        '-ar',
        '16000',
        '-ac',
        '1',
        '-c:a',
        'pcm_s16le',
        '-y',
        audioFile.path,
      ]);
    } catch (_) {}

    return audioFile;
  }

  /// Transcribes [audioFile] with on-device Whisper (whisper.cpp via
  /// whisper_ggml). Returns word-level timestamps which are used both for
  /// burned subtitles and for highlight analysis.
  ///
  /// Goes through `Whisper` + `TranscribeRequest` directly (bypassing
  /// `WhisperController`, which hardcodes `threads: 6`, disables `speedUp`
  /// and defaults to `lang: 'en'`) to make inference faster:
  ///   - [speedUp] uses whisper.cpp's faster, smaller-GMM decoding (~2x).
  ///   - `threads` scaled to modern device cores.
  ///   - [lang] defaults to `id` so no language auto-detect pass runs.
  Future<List<WhisperWord>> transcribeLocalAudio(
    File audioFile, {
    String lang = 'auto',
    bool speedUp = true,
    void Function(double progress)? onProgress,
  }) async {
    final modelPath = await _controller.getPath(model);
    final result = await Whisper(model: model).transcribe(
      transcribeRequest: TranscribeRequest(
        audio: audioFile.path,
        language: lang,
        threads: 8,
        nProcessors: _nProcessors,
        speedUp: speedUp,
        isNoTimestamps: false,
        splitOnWord: true,
        suppressNonSpeechTokens: true,
      ),
      modelPath: modelPath,
      onProgress: (percent) => onProgress?.call(percent / 100.0),
    );

    final words = <WhisperWord>[];
    for (final segment
        in result.segments ?? const <WhisperTranscribeSegment>[]) {
      final text = segment.text.trim();
      if (text.isEmpty) continue;
      words.add(
        WhisperWord(word: text, start: segment.fromTs, end: segment.toTs),
      );
    }

    // Fallback: no word timestamps available, expose the full text.
    if (words.isEmpty && (result.text.trim().isNotEmpty)) {
      words.add(
        WhisperWord(
          word: result.text.trim(),
          start: Duration.zero,
          end: const Duration(seconds: 10),
        ),
      );
    }

    return words;
  }
}
