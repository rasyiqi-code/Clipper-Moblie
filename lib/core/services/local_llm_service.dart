import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/video_segment.dart';

/// A single LLM-produced verdict for a video segment.
class LlmSegmentVerdict {
  final String segmentId;
  final int score;
  final String title;
  final String summary;

  const LlmSegmentVerdict({
    required this.segmentId,
    required this.score,
    required this.title,
    required this.summary,
  });
}

/// On-device LLM grader (hybrid pipeline).
///
/// NLP rule-based windows are decided by [HighlightDetectorService]; this
/// service only grades those windows with a small local GGUF model and rewrites
/// titles/summaries. The model is loaded from Hugging Face (cached by the
/// llamadart download manager) and unloaded right after grading to free memory.
class LocalLlmService {
  /// Qwen2.5-0.5B-Instruct Q4_K_M (~491 MB) - balanced size/quality tradeoff.
  static const String modelSource =
      'hf://Qwen/Qwen2.5-0.5B-Instruct-GGUF/qwen2.5-0.5b-instruct-q4_k_m.gguf';

  final ModelSource _source = ModelSource.parse(modelSource);
  String? _cacheDir;

  /// App-private directory that hosts the downloaded GGUF model, kept stable
  /// so the settings screen and the pipeline can agree on where it lives.
  Future<String> _cacheDirectory() async {
    if (_cacheDir != null) return _cacheDir!;
    final support = await getApplicationSupportDirectory();
    _cacheDir = p.join(support.path, 'llm_models');
    return _cacheDir!;
  }

  String _modelFilePath(String cacheDir) =>
      p.join(cacheDir, _source.cacheDirectoryName, _source.fileName);

  /// Whether the local LLM model has been downloaded already.
  Future<bool> isModelDownloaded() async {
    final dir = await _cacheDirectory();
    return File(_modelFilePath(dir)).exists();
  }

  /// Size in bytes of the cached LLM model, or `null` when not downloaded.
  Future<int?> modelSizeBytes() async {
    final dir = await _cacheDirectory();
    final file = File(_modelFilePath(dir));
    if (!await file.exists()) return null;
    return file.length();
  }

  static const String _systemPrompt = '''
Kamu adalah editor video AI yang ahli memilih momen paling menarik dari sebuah video untuk dijadikan Shorts/Reels/TikTok.
Analisis setiap segmen percakapan lalu berikan:
- score: angka 0-100 seberapa viralnya segmen ini (bukan potongan biasa, tapi yang memancing rasa penasaran, emosi, atau ajakan).
- title: judul singkat dan menarik dalam bahasa Indonesia (maksimal 6 kata).
- summary: ringkasan 1 kalimat dalam bahasa Indonesia.
Balas HANYA dengan JSON berbentuk {"segments": [{"id": "...", "score": 90, "title": "...", "summary": "..."}]} tanpa teks lain.''';

  LlamaEngine? _engine;

  bool get isModelLoaded => _engine?.isReady ?? false;

  /// Loads (and caches) the GGUF model. No-op when already loaded.
  Future<void> loadModel({Function(double progress)? onProgress}) async {
    if (isModelLoaded) return;
    _engine ??= LlamaEngine(LlamaBackend());
    await _engine!.loadModelSource(
      _source,
      modelParams: const ModelParams(
        contextSize: 2048,
        gpuLayers: 0,
        useMlock: false,
      ),
      options: ModelLoadOptions(cacheDirectory: await _cacheDirectory()),
      onProgress: (p) => onProgress?.call(p.fraction ?? 0),
    );
  }

  /// Grades each window with the local LLM.
  ///
  /// Returns an empty list when the model is unavailable or any error occurs,
  /// so callers can keep the rule-based NLP verdicts untouched.
  Future<List<LlmSegmentVerdict>> gradeSegments({
    required String videoTitle,
    required List<VideoSegment> segments,
    Function(double progress)? onProgress,
  }) async {
    if (segments.isEmpty) return const [];

    try {
      await loadModel(onProgress: onProgress);
      if (!isModelLoaded) return const [];

      final messages = [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: _systemPrompt,
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: _buildUserPrompt(videoTitle, segments),
        ),
      ];

      final result = await _engine!.createStructuredJson<Map<String, dynamic>>(
        messages,
        output: LlamaStructuredOutput.jsonObject(decoder: (json) => json),
        params: const GenerationParams(
          temp: 0.2,
          topP: 0.6,
          topK: 40,
          seed: 42,
          maxTokens: 512,
        ),
        enableThinking: false,
      );

      return _decodeVerdicts(result);
    } catch (_) {
      return const [];
    }
  }

  String _buildUserPrompt(String videoTitle, List<VideoSegment> segments) {
    final buffer = StringBuffer()
      ..writeln('Judul video: ${_clip(videoTitle, 200)}')
      ..writeln('Segmen yang harus dinilai:');
    for (final s in segments) {
      final transcript = _clip(s.transcript, 180);
      buffer.writeln(
        '{"id": "${s.id}", "durasi": "${s.startTime.inSeconds}-${s.endTime.inSeconds}s", '
        '"transkrip": "$transcript"}',
      );
    }
    return buffer.toString();
  }

  List<LlmSegmentVerdict> _decodeVerdicts(Map<String, dynamic> json) {
    final raw = json['segments'];
    if (raw is! List) return const [];

    final verdicts = <LlmSegmentVerdict>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final segmentId = item['id']?.toString() ?? '';
      if (segmentId.isEmpty) continue;
      verdicts.add(
        LlmSegmentVerdict(
          segmentId: segmentId,
          score: ((item['score'] as num?)?.toInt() ?? 0).clamp(0, 100),
          title: item['title']?.toString() ?? '',
          summary: item['summary']?.toString() ?? '',
        ),
      );
    }
    return verdicts;
  }

  /// Frees the model from memory after grading.
  Future<void> unloadModel() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.dispose();
    } catch (_) {
      // Best-effort: memory pressure should never break the render flow.
    } finally {
      _engine = null;
    }
  }

  static String _clip(String value, int maxLength) {
    final v = value.replaceAll('"', '');
    return v.length <= maxLength ? v : '${v.substring(0, maxLength)}...';
  }
}
