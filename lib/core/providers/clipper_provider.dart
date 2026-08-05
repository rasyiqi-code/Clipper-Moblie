import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/video_source.dart';
import '../models/video_segment.dart';
import '../models/subtitle_style.dart';
import '../models/video_project.dart';
import '../models/transcribed_word.dart';
import '../services/highlight_detector_service.dart';
import '../services/ffmpeg_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/whisper_service.dart';
import '../services/local_llm_service.dart';
import '../services/face_tracking_service.dart';
import 'theme_provider.dart';

/// Pipeline steps surfaced to the UI as a checklist while analyzing a video.
enum AnalysisStage { idle, transcribing, analyzingNlp, gradingLlm, done }

class ClipperState {
  static const Object _unset = Object();

  final VideoSource? currentSource;
  final File? localVideoFile;
  final bool isLoading;
  final String statusMessage;
  final double downloadProgress;
  final AnalysisStage analysisStage;
  final double analysisProgress;
  final List<WhisperWord> transcribedWords;
  final List<VideoSegment> segments;
  final VideoSegment? selectedSegment;
  final SubtitleStyle subtitleStyle;
  final bool isRendering;
  final double renderProgress;
  final String? lastExportedPath;
  final List<VideoProject> projects;
  final List<String> renderedClipsHistory;
  final String transcribeLang;
  final String whisperModel;
  final double? faceTrackXPercent;
  final String? faceTrackedSegmentId;
  final bool faceTrackingRunning;
  final double faceTrackingProgress;
  final String? faceTrackingWarning;

  ClipperState({
    this.currentSource,
    this.localVideoFile,
    this.isLoading = false,
    this.statusMessage = '',
    this.downloadProgress = 0.0,
    this.analysisStage = AnalysisStage.idle,
    this.analysisProgress = 0.0,
    this.transcribedWords = const [],
    this.segments = const [],
    this.selectedSegment,
    this.subtitleStyle = const SubtitleStyle(),
    this.isRendering = false,
    this.renderProgress = 0.0,
    this.lastExportedPath,
    this.projects = const [],
    this.renderedClipsHistory = const [],
    this.transcribeLang = 'auto',
    this.whisperModel = 'base',
    this.faceTrackXPercent,
    this.faceTrackedSegmentId,
    this.faceTrackingRunning = false,
    this.faceTrackingProgress = 0.0,
    this.faceTrackingWarning,
  });

  ClipperState copyWith({
    VideoSource? currentSource,
    File? localVideoFile,
    bool? isLoading,
    String? statusMessage,
    double? downloadProgress,
    AnalysisStage? analysisStage,
    double? analysisProgress,
    List<WhisperWord>? transcribedWords,
    List<VideoSegment>? segments,
    VideoSegment? selectedSegment,
    SubtitleStyle? subtitleStyle,
    bool? isRendering,
    double? renderProgress,
    String? lastExportedPath,
    List<VideoProject>? projects,
    List<String>? renderedClipsHistory,
    String? transcribeLang,
    String? whisperModel,
    Object? faceTrackXPercent = _unset,
    Object? faceTrackedSegmentId = _unset,
    bool? faceTrackingRunning,
    double? faceTrackingProgress,
    Object? faceTrackingWarning = _unset,
  }) {
    return ClipperState(
      currentSource: currentSource ?? this.currentSource,
      localVideoFile: localVideoFile ?? this.localVideoFile,
      isLoading: isLoading ?? this.isLoading,
      statusMessage: statusMessage ?? this.statusMessage,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      analysisStage: analysisStage ?? this.analysisStage,
      analysisProgress: analysisProgress ?? this.analysisProgress,
      transcribedWords: transcribedWords ?? this.transcribedWords,
      segments: segments ?? this.segments,
      selectedSegment: selectedSegment ?? this.selectedSegment,
      subtitleStyle: subtitleStyle ?? this.subtitleStyle,
      isRendering: isRendering ?? this.isRendering,
      renderProgress: renderProgress ?? this.renderProgress,
      lastExportedPath: lastExportedPath ?? this.lastExportedPath,
      projects: projects ?? this.projects,
      renderedClipsHistory: renderedClipsHistory ?? this.renderedClipsHistory,
      transcribeLang: transcribeLang ?? this.transcribeLang,
      whisperModel: whisperModel ?? this.whisperModel,
      faceTrackXPercent: identical(faceTrackXPercent, _unset)
          ? this.faceTrackXPercent
          : faceTrackXPercent as double?,
      faceTrackedSegmentId: identical(faceTrackedSegmentId, _unset)
          ? this.faceTrackedSegmentId
          : faceTrackedSegmentId as String?,
      faceTrackingRunning: faceTrackingRunning ?? this.faceTrackingRunning,
      faceTrackingProgress: faceTrackingProgress ?? this.faceTrackingProgress,
      faceTrackingWarning: identical(faceTrackingWarning, _unset)
          ? this.faceTrackingWarning
          : faceTrackingWarning as String?,
    );
  }
}

class ClipperNotifier extends StateNotifier<ClipperState> {
  final Ref _ref;
  final HighlightDetectorService _highlightDetector =
      HighlightDetectorService();
  final FFmpegService _ffmpegService = FFmpegService();
  final WhisperService _whisperService = WhisperService();
  final LocalLlmService _llmService = LocalLlmService();
  late final FaceTrackingService _faceTrackingService;

  static const _transcribeLangKey = 'transcribe_lang';
  static const _whisperModelKey = 'whisper_model';
  static const _projectsKey = 'projects';

  /// Last project list that was written to disk, used to avoid redundant
  /// writes while other fields (progress, status) change constantly.
  List<VideoProject> _lastPersistedProjects = const [];

  ClipperNotifier(this._ref)
    : super(
        ClipperState(
          transcribeLang: _restoreTranscribeLang(_ref.read(prefsProvider)),
          whisperModel: _restoreWhisperModel(_ref.read(prefsProvider)),
          projects: _restoreProjects(_ref.read(prefsProvider)),
        ),
      ) {
    _lastPersistedProjects = state.projects;
    _faceTrackingService = FaceTrackingService(ffmpegService: _ffmpegService);
  }

  @override
  set state(ClipperState value) {
    super.state = value;
    if (!identical(value.projects, _lastPersistedProjects)) {
      _lastPersistedProjects = value.projects;
      _persistProjects(value.projects);
    }
  }

  static String _restoreTranscribeLang(SharedPreferences prefs) =>
      prefs.getString(_transcribeLangKey) ?? 'auto';

  static String _restoreWhisperModel(SharedPreferences prefs) =>
      prefs.getString(_whisperModelKey) ?? 'base';

  static List<VideoProject> _restoreProjects(SharedPreferences prefs) {
    final raw = prefs.getString(_projectsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => VideoProject.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persistProjects(List<VideoProject> projects) async {
    final prefs = _ref.read(prefsProvider);
    await prefs.setString(
      _projectsKey,
      jsonEncode(projects.map((p) => p.toJson()).toList()),
    );
  }

  /// Whisper's language code for transcription (`auto`, `id`, `en`, ...),
  /// persisted across sessions.
  void setTranscribeLang(String lang) {
    _ref.read(prefsProvider).setString(_transcribeLangKey, lang);
    state = state.copyWith(transcribeLang: lang);
  }

  /// Whisper model key (`tiny`|`base`), persisted across sessions.
  void setWhisperModel(String key) {
    _ref.read(prefsProvider).setString(_whisperModelKey, key);
    _whisperService.model = WhisperService.resolveModel(key);
    state = state.copyWith(whisperModel: key);
  }

  /// Pick a local video file from user device
  Future<void> pickLocalVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final file = File(filePath);

        state = state.copyWith(
          isLoading: true,
          statusMessage: 'Membaca video lokal...',
        );

        final probe = await _ffmpegService.probeVideo(filePath);

        final source = VideoSource(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: result.files.single.name,
          pathOrUrl: filePath,
          type: VideoSourceType.local,
          duration: probe.duration,
        );

        await _analyzeSource(source, file);
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        statusMessage: 'Gagal memilih video: $e',
      );
    }
  }



  /// Inserts or updates a [VideoProject] in the library (Pustaka).
  void _upsertProject(
    VideoSource source,
    File? videoFile,
    List<VideoSegment> segments, {
    List<WhisperWord> words = const [],
  }) {
    final existingIndex = state.projects.indexWhere((p) => p.id == source.id);
    final updatedProjects = List<VideoProject>.from(state.projects);
    final persistedWords =
        words
            .map(
              (w) => TranscribedWord(
                word: w.word,
                startSec: w.start.inMilliseconds / 1000.0,
                endSec: w.end.inMilliseconds / 1000.0,
              ),
            )
            .toList();
    if (existingIndex >= 0) {
      updatedProjects[existingIndex] = updatedProjects[existingIndex].copyWith(
        source: source,
        localFile: videoFile,
        segments: segments,
        transcribedWords:
            persistedWords.isNotEmpty
                ? persistedWords
                : updatedProjects[existingIndex].transcribedWords,
      );
    } else {
      final newProject = VideoProject(
        id: source.id,
        source: source,
        localFile: videoFile,
        createdAt: DateTime.now(),
        status: ClippingStatus.unclipped,
        segments: segments,
        transcribedWords: persistedWords,
      );
      updatedProjects.insert(0, newProject);
    }
    state = state.copyWith(projects: updatedProjects);
  }

  /// Runs Local Whisper Transcription & AI Highlight Detection
  Future<void> _analyzeSource(VideoSource source, File videoFile) async {
    state = state.copyWith(
      currentSource: source,
      localVideoFile: videoFile,
      analysisStage: AnalysisStage.transcribing,
      analysisProgress: 0.0,
      statusMessage: 'Menyiapkan transkripsi...',
    );

    var words = <WhisperWord>[];

    if (words.isEmpty) {
      _whisperService.model = WhisperService.resolveModel(state.whisperModel);
      if (!await _whisperService.hasLocalModel()) {
        state = state.copyWith(
          currentSource: null,
          localVideoFile: null,
          isLoading: false,
          analysisStage: AnalysisStage.idle,
          statusMessage:
              'Model Whisper belum diunduh. Buka Pengaturan → Model AI untuk mengunduh.',
        );
        return;
      }

      state = state.copyWith(
        analysisStage: AnalysisStage.transcribing,
        analysisProgress: 0.0,
        statusMessage: 'Mengisi audio & Transkripsi Whisper AI Lokal...',
      );

      final audioFile = await _whisperService.extractAudioForWhisper(
        videoFile.path,
      );
      words = await _whisperService.transcribeLocalAudio(
        audioFile,
        lang: state.transcribeLang,
        onProgress: (p) {
          state = state.copyWith(
            analysisStage: AnalysisStage.transcribing,
            analysisProgress: p,
            statusMessage: 'Transkripsi Whisper AI (${(p * 100).toInt()}%)...',
          );
        },
      );
    }

    state = state.copyWith(
      transcribedWords: words,
      analysisStage: AnalysisStage.analyzingNlp,
      analysisProgress: 0.0,
      statusMessage: 'Menganalisis segmen klip menarik (AI Auto-Highlight)...',
    );

    final finalSegments = await _gradeSegments(
      source,
      words,
      statusPrefix: 'Menganalisis segmen klip menarik',
    );

    _upsertProject(source, videoFile, finalSegments, words: words);

    state = state.copyWith(
      isLoading: false,
      statusMessage:
          'Selesai menganalisis! ${finalSegments.length} segmen klip terdeteksi (maks 1 menit/klip).',
      analysisStage: AnalysisStage.done,
      analysisProgress: 1.0,
      segments: finalSegments,
      selectedSegment: finalSegments.isNotEmpty ? finalSegments.first : null,
    );
  }

  /// Re-runs highlight detection + local LLM grading on the current video.
  ///
  /// When a cached transcript already exists, transcription is skipped so the
  /// re-analysis only covers NLP + LLM grading (much faster).
  Future<void> reanalyzeSegments() async {
    final source = state.currentSource;
    final file = state.localVideoFile;
    if (source == null || file == null) return;

    final words = state.transcribedWords;
    if (words.isEmpty) {
      await _analyzeSource(source, file);
      return;
    }

    state = state.copyWith(
      isLoading: true,
      analysisStage: AnalysisStage.analyzingNlp,
      analysisProgress: 0.0,
      statusMessage: 'Menganalisis ulang segmen (AI Auto-Highlight)...',
    );

    try {
      final finalSegments = await _gradeSegments(
        source,
        words,
        statusPrefix: 'Menganalisis ulang segmen',
      );

      state = state.copyWith(
        isLoading: false,
        statusMessage:
            'Selesai analisis ulang! ${finalSegments.length} segmen klip.',
        analysisStage: AnalysisStage.done,
        analysisProgress: 1.0,
        segments: finalSegments,
        selectedSegment: finalSegments.isNotEmpty
            ? finalSegments.first
            : state.selectedSegment,
        projects: _syncCurrentProjectSegments(finalSegments),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        statusMessage: 'Gagal menganalisis ulang: $e',
      );
    }
  }

  /// NLP window detection followed by local LLM grading (hybrid pipeline).
  Future<List<VideoSegment>> _gradeSegments(
    VideoSource source,
    List<WhisperWord> words, {
    required String statusPrefix,
  }) async {
    state = state.copyWith(
      analysisStage: AnalysisStage.analyzingNlp,
      analysisProgress: 0.0,
      statusMessage: '$statusPrefix (AI Auto-Highlight)...',
    );

    final detectedSegments = await _highlightDetector.detectHighlights(
      source,
      transcribedWords: words,
    );

    // The local LLM is optional: when it hasn't been downloaded yet in
    // Pengaturan, keep the rule-based NLP verdicts (no in-workflow download).
    if (!await _llmService.isModelDownloaded()) {
      state = state.copyWith(
        statusMessage: '$statusPrefix — LLM belum diunduh, memakai NLP saja.',
      );
      return detectedSegments;
    }

    state = state.copyWith(
      analysisStage: AnalysisStage.gradingLlm,
      analysisProgress: 0.0,
      statusMessage: 'Menilai segmen dengan LLM lokal (Qwen 2.5)...',
    );

    var verdicts = const <LlmSegmentVerdict>[];
    try {
      verdicts = await _llmService.gradeSegments(
        videoTitle: source.title,
        segments: detectedSegments,
        onProgress: (p) {
          state = state.copyWith(
            analysisStage: AnalysisStage.gradingLlm,
            analysisProgress: p,
            statusMessage:
                'Menilai segmen dengan LLM lokal (${(p * 100).toInt()}%)...',
          );
        },
      );
    } finally {
      await _llmService.unloadModel();
    }

    return _applyLlmVerdicts(detectedSegments, verdicts);
  }

  /// Hybrid pipeline: NLP decides the windows, the local LLM only rewrites
  /// score/title/summary. Falls back to NLP verdicts when the LLM is empty.
  List<VideoSegment> _applyLlmVerdicts(
    List<VideoSegment> segments,
    List<LlmSegmentVerdict> verdicts,
  ) {
    if (verdicts.isEmpty) return segments;
    final byId = {for (final v in verdicts) v.segmentId: v};
    return segments.map((seg) {
      final verdict = byId[seg.id];
      if (verdict == null) return seg;
      return seg.copyWith(
        title: verdict.title.isNotEmpty ? verdict.title : seg.title,
        summary: verdict.summary.isNotEmpty ? verdict.summary : seg.summary,
        viralScore: verdict.score.toDouble(),
      );
    }).toList();
  }

  void deleteProject(String projectId) {
    final isCurrentActive = state.currentSource?.id == projectId;
    final updatedList = state.projects.where((p) => p.id != projectId).toList();
    state = state.copyWith(
      projects: updatedList,
      currentSource: isCurrentActive ? null : state.currentSource,
      localVideoFile: isCurrentActive ? null : state.localVideoFile,
      segments: isCurrentActive ? const [] : state.segments,
      selectedSegment: isCurrentActive ? null : state.selectedSegment,
      transcribedWords: isCurrentActive ? const [] : state.transcribedWords,
      lastExportedPath: isCurrentActive ? null : state.lastExportedPath,
      analysisStage: isCurrentActive ? AnalysisStage.idle : state.analysisStage,
      analysisProgress: isCurrentActive ? 0.0 : state.analysisProgress,
    );
  }

  void loadProject(VideoProject project) {
    state = ClipperState(
      currentSource: project.source,
      localVideoFile: project.localFile,
      segments: project.segments,
      selectedSegment: project.segments.isNotEmpty
          ? project.segments.first
          : null,
      // Restore the persisted transcript so face tracking can still voice-gate
      // the speaker without re-running Whisper.
      transcribedWords: project.transcribedWords
          .map(
            (w) => WhisperWord(
              word: w.word,
              start: Duration(milliseconds: (w.startSec * 1000).round()),
              end: Duration(milliseconds: (w.endSec * 1000).round()),
            ),
          )
          .toList(),
      lastExportedPath: null,
      subtitleStyle: state.subtitleStyle,
      transcribeLang: state.transcribeLang,
      whisperModel: state.whisperModel,
      projects: state.projects,
      renderedClipsHistory: state.renderedClipsHistory,
    );
  }

  void selectSegment(VideoSegment segment) {
    state = state.copyWith(selectedSegment: segment);
  }

  /// Runs face tracking on [segment] (extract sample frames + ML Kit lip-motion
  /// detection) and stores the talking speaker's X-center for the preview.
  ///
  /// Idempotent: skips when the segment was already analysed successfully and
  /// coalesces concurrent calls for the same segment. Returns the updated
  /// segment (or the original when analysis failed) so callers like the render
  /// path can use the fresh keyframes.
  Future<VideoSegment?> runFaceTracking(VideoSegment segment) async {
    final file = state.localVideoFile;
    if (file == null) return null;
    if (state.faceTrackedSegmentId == segment.id &&
        segment.faceKeyframes.isNotEmpty) {
      return state.segments.firstWhere(
        (s) => s.id == segment.id,
        orElse: () => segment,
      );
    }
    if (state.faceTrackingRunning) return null;

    state = state.copyWith(
      faceTrackingRunning: true,
      faceTrackingProgress: 0.0,
      faceTrackingWarning: null,
    );
    try {
      final result = await _faceTrackingService.analyzeSegment(
        inputPath: file.path,
        segment: segment,
        onProgress: (processed, total) {
          final progress = total > 0 ? processed / total : 0.0;
          state = state.copyWith(faceTrackingProgress: progress);
        },
        // Voice-gate: Whisper's word timestamps tell us WHEN someone is
        // actually speaking (an open mouth is not proof of talking), so the
        // crop only locks to a talker while speech is present and releases the
        // hold once the speaker falls silent.
        voicedWindows: state.transcribedWords
            .map((w) => (
                  start: w.start.inMilliseconds / 1000.0,
                  end: w.end.inMilliseconds / 1000.0,
                ))
            .toList(),
      );
      final x = result.speakerX;
      final keyframes = result.keyframes;
      debugPrint(
        '[face-detect] runFaceTracking("${segment.title}") → '
        '${x == null ? "null (tidak terdeteksi)" : x.toStringAsFixed(3)}, '
        '${keyframes.length} keyframes',
      );

      final updatedSegments = result.isSuccessful
          ? _upsertFaceTrackedSegment(state.segments, segment, x, keyframes)
          : state.segments;

      final updatedSelected =
          result.isSuccessful && state.selectedSegment?.id == segment.id
          ? state.selectedSegment!.copyWith(
              cropXPercent: x ?? state.selectedSegment!.cropXPercent,
              faceKeyframes: keyframes.isNotEmpty
                  ? keyframes
                  : state.selectedSegment!.faceKeyframes,
            )
          : state.selectedSegment;

      state = state.copyWith(
        faceTrackXPercent: x,
        faceTrackedSegmentId: segment.id,
        faceTrackingRunning: false,
        faceTrackingProgress: 1.0,
        segments: updatedSegments,
        selectedSegment: updatedSelected,
        projects: _syncCurrentProjectSegments(updatedSegments),
        faceTrackingWarning: result.isSuccessful
            ? null
            : (result.failureReason ?? 'Wajah tidak terdeteksi'),
      );
      return updatedSelected;
    } catch (e) {
      debugPrint('[face-detect] error runFaceTracking: $e');
      state = state.copyWith(
        faceTrackedSegmentId: segment.id,
        faceTrackingRunning: false,
        faceTrackingWarning: 'Error: $e',
      );
      return null;
    }
  }

  /// Forces face tracking to re-run even if the segment was already analysed.
  Future<VideoSegment?> rerunFaceTracking(VideoSegment segment) async {
    state = state.copyWith(faceTrackedSegmentId: null);
    return runFaceTracking(segment);
  }

  void deleteSegment(String segmentId) {
    final updatedList = state.segments.where((s) => s.id != segmentId).toList();
    state = state.copyWith(
      segments: updatedList,
      selectedSegment: state.selectedSegment?.id == segmentId
          ? (updatedList.isNotEmpty ? updatedList.first : null)
          : state.selectedSegment,
      projects: _syncCurrentProjectSegments(updatedList),
    );
  }

  void updateSegment(VideoSegment updatedSegment) {
    final updatedList = state.segments.map((seg) {
      return seg.id == updatedSegment.id ? updatedSegment : seg;
    }).toList();

    state = state.copyWith(
      segments: updatedList,
      selectedSegment: state.selectedSegment?.id == updatedSegment.id
          ? updatedSegment
          : state.selectedSegment,
      projects: _syncCurrentProjectSegments(updatedList),
    );
  }

  /// Inserts (or updates) the analysed segment inside [segments] so keyframes
  /// survive state changes (e.g. the default segment that is created on the fly
  /// in the workspace) and are persisted with the project.
  List<VideoSegment> _upsertFaceTrackedSegment(
    List<VideoSegment> segments,
    VideoSegment segment,
    double? x,
    List<FaceKeyframe> keyframes,
  ) {
    for (final s in segments) {
      if (s.id == segment.id) {
        return segments.map((s) {
          if (s.id == segment.id) {
            return s.copyWith(
              cropXPercent: x ?? s.cropXPercent,
              faceKeyframes: keyframes.isNotEmpty ? keyframes : s.faceKeyframes,
            );
          }
          return s;
        }).toList();
      }
    }
    return [
      ...segments,
      segment.copyWith(
        cropXPercent: x ?? segment.cropXPercent,
        faceKeyframes: keyframes.isNotEmpty ? keyframes : segment.faceKeyframes,
      ),
    ];
  }

  /// Keeps the currently active project's stored segments in sync with edits.
  List<VideoProject> _syncCurrentProjectSegments(List<VideoSegment> segments) {
    final currentId = state.currentSource?.id;
    if (currentId == null) return state.projects;
    return state.projects.map((proj) {
      if (proj.id == currentId) return proj.copyWith(segments: segments);
      return proj;
    }).toList();
  }

  void updateSubtitleStyle(SubtitleStyle style) {
    state = state.copyWith(subtitleStyle: style);
  }

  /// Renders selected segment to Short format
  Future<bool> renderSelectedSegment() async {
    VideoSegment? segment = state.selectedSegment;

    if (segment == null && state.segments.isNotEmpty) {
      segment = state.segments.first;
    }

    if (segment == null && state.currentSource != null) {
      segment = VideoSegment(
        id: 'seg_default',
        title: '💡 Segmen Utama Video',
        startTime: Duration.zero,
        endTime: state.currentSource!.duration,
        viralScore: 95.0,
        summary: 'Klip pembuka utama video dengan analisis percakapan AI.',
        transcript: 'Poin utama percakapan dari awal hingga akhir video.',
        cropXPercent: 0.5,
      );
    }

    final videoFile = state.localVideoFile;

    if (segment == null || videoFile == null) return false;

    state = state.copyWith(
      selectedSegment: segment,
      isRendering: true,
      renderProgress: 0.1,
      lastExportedPath: null,
      statusMessage: 'Mulai merender video Shorts...',
    );

    final outputPath = await _renderSegmentToFile(
      segment,
      videoFile,
      onProgress: (p) => state = state.copyWith(renderProgress: p),
    );

    if (outputPath == null) {
      state = state.copyWith(
        isRendering: false,
        statusMessage: state.statusMessage.startsWith('Error')
            ? state.statusMessage
            : 'Gagal merender video.',
      );
      return false;
    }

    _recordRenderedClips([outputPath]);
    state = state.copyWith(
      isRendering: false,
      renderProgress: 1.0,
      lastExportedPath: outputPath,
      statusMessage: 'Video berhasil diekspor!',
    );
    return true;
  }

  /// Renders every detected segment into its own Short clip.
  Future<List<String>> renderAllSegments() async {
    final videoFile = state.localVideoFile;
    final segments = state.segments;
    if (videoFile == null || segments.isEmpty) return const [];

    state = state.copyWith(
      isRendering: true,
      renderProgress: 0.0,
      lastExportedPath: null,
      statusMessage: 'Mulai merender ${segments.length} segmen...',
    );

    final renderedPaths = <String>[];
    for (var i = 0; i < segments.length; i++) {
      state = state.copyWith(
        statusMessage: 'Merender segmen ${i + 1}/${segments.length}...',
        selectedSegment: segments[i],
      );
      final path = await _renderSegmentToFile(
        segments[i],
        videoFile,
        onProgress: (p) {
          state = state.copyWith(renderProgress: (i + p) / segments.length);
        },
      );
      if (path != null) renderedPaths.add(path);
    }

    if (renderedPaths.isNotEmpty) {
      _recordRenderedClips(renderedPaths);
    }
    state = state.copyWith(
      isRendering: false,
      renderProgress: 1.0,
      lastExportedPath: renderedPaths.isNotEmpty ? renderedPaths.first : null,
      statusMessage: renderedPaths.isNotEmpty
          ? 'Berhasil render ${renderedPaths.length} dari ${segments.length} segmen!'
          : 'Gagal merender semua segmen.',
    );
    return renderedPaths;
  }

  /// Renders a single segment into a temp MP4 and returns its path,
  /// or `null` on failure.
  Future<String?> _renderSegmentToFile(
    VideoSegment segment,
    File videoFile, {
    Function(double progress)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/short_${segment.id}_${DateTime.now().millisecondsSinceEpoch}.mp4';

      var renderSegment = segment;
      if (segment.faceKeyframes.isEmpty) {
        final tracked = await runFaceTracking(segment);
        if (tracked != null) renderSegment = tracked;
      }

      final success = await _ffmpegService.executeRender(
        inputPath: videoFile.path,
        outputPath: outputPath,
        segment: renderSegment,
        subtitleStyle: state.subtitleStyle,
        onProgress: onProgress,
      );

      final outputFile = File(outputPath);
      if (success &&
          await outputFile.exists() &&
          (await outputFile.length()) > 1024) {
        return outputPath;
      }
      return null;
    } catch (e) {
      state = state.copyWith(statusMessage: 'Error saat merender: $e');
      return null;
    }
  }

  /// Updates the active project (status/count/paths) and prepends the
  /// rendered clip paths to the history.
  void _recordRenderedClips(List<String> outputPaths) {
    final currentId = state.currentSource?.id;
    final updatedProjects = state.projects.map((proj) {
      if (proj.id == currentId) {
        return proj.copyWith(
          status: ClippingStatus.clipped,
          renderedClipsCount: proj.renderedClipsCount + outputPaths.length,
          exportedClipPaths: [...proj.exportedClipPaths, ...outputPaths],
        );
      }
      return proj;
    }).toList();

    state = state.copyWith(
      projects: updatedProjects,
      renderedClipsHistory: [...outputPaths, ...state.renderedClipsHistory],
    );
  }

  @override
  void dispose() {
    _faceTrackingService.dispose();
    super.dispose();
  }
}

final clipperProvider = StateNotifierProvider<ClipperNotifier, ClipperState>((
  ref,
) {
  return ClipperNotifier(ref);
});
