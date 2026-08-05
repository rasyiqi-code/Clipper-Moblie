import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../core/providers/clipper_provider.dart';
import '../../core/models/video_source.dart';
import '../../core/models/video_segment.dart';
import '../../core/models/subtitle_preset.dart';
import '../../core/theme/app_theme.dart';
import '../export/export_screen.dart';

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  VideoPlayerController? _videoController;
  bool _isPlayerInitialized = false;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  void _initVideoPlayer() async {
    final state = ref.read(clipperProvider);
    if (state.localVideoFile != null) {
      _videoController = VideoPlayerController.file(state.localVideoFile!)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {
            _isPlayerInitialized = true;
          });
          _seekToSelectedSegment();
        });
    }
  }

  double _getLivePreviewFaceX(VideoSegment? segment) {
    if (segment == null) return 0.5;
    if (segment.faceKeyframes.isEmpty) {
      return segment.cropXPercent;
    }
    if (_videoController == null || !_isPlayerInitialized) {
      return segment.cropXPercent;
    }
    final currentPos = _videoController!.value.position;
    final relativeSec =
        ((currentPos - segment.startTime).inMilliseconds / 1000.0)
            .clamp(0.0, double.infinity);
    final kf = segment.faceKeyframes;
    // Hold the latest keyframe whose time has been reached, so the crop SNAPS
    // to the new speaker instead of gliding across the whole sampling gap.
    // (AnimatedAlign turns each step into a short ~250ms snap.)
    for (var i = kf.length - 1; i >= 0; i--) {
      if (relativeSec >= kf[i].timeSec) return kf[i].xPercent;
    }
    return kf.first.xPercent;
  }

  void _seekToSelectedSegment() {
    final segment = ref.read(clipperProvider).selectedSegment;
    if (_videoController == null || !_isPlayerInitialized) return;
    if (segment != null) {
      _videoController!.seekTo(segment.startTime);
    }
    // Always autoplay the preview so the live tracking frame visibly follows
    // the speaker. Relying on `segment != null` here skips play() at startup
    // when the (default) segment has not been analysed yet.
    _videoController!.play();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _startRender() async {
    HapticFeedback.mediumImpact();
    final notifier = ref.read(clipperProvider.notifier);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ExportScreen()));
    await notifier.renderSelectedSegment();
  }

  void _startRenderAll() async {
    HapticFeedback.mediumImpact();
    final notifier = ref.read(clipperProvider.notifier);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ExportScreen()));
    await notifier.renderAllSegments();
  }

  /// Re-runs the highlight pipeline (NLP + local LLM grading) on the cached
  /// transcript, showing a modal progress dialog while it works.
  Future<void> _startReanalyze() async {
    HapticFeedback.mediumImpact();
    final notifier = ref.read(clipperProvider.notifier);
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ReanalyzeDialog(),
    );

    await notifier.reanalyzeSegments();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ref.read(clipperProvider).statusMessage)),
    );
  }

  void _showFileInfoDialog(BuildContext context, ClipperState state) {
    final file = state.localVideoFile;
    final source = state.currentSource;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final fileSize = file != null && file.existsSync()
            ? (file.lengthSync() / (1024 * 1024)).toStringAsFixed(2)
            : '0';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.movie_outlined,
                    color: AppTheme.primaryGold,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Informasi Berkas Video',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              _buildInfoRow(context, 'Judul Video', source?.title ?? '-'),
              const SizedBox(height: 12),
              _buildInfoRow(
                context,
                'Sumber',
                source?.type == VideoSourceType.youtube
                    ? 'YouTube Download'
                    : 'File Lokal',
              ),
              const SizedBox(height: 12),
              _buildInfoRow(context, 'Ukuran Berkas', '$fileSize MB'),
              const SizedBox(height: 12),
              _buildInfoRow(context, 'Lokasi Penyimpanan', file?.path ?? '-'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _showQuickSettings(ClipperState state) {
    final segment = state.selectedSegment;
    if (segment == null) return;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final notifier = ref.read(clipperProvider.notifier);
            final current = state.selectedSegment ?? segment;
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        color: AppTheme.primaryGold,
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Pengaturan Cepat',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Burn Subtitle'),
                    subtitle: const Text('Bakar subtitle ke dalam video.'),
                    value: current.enableSubtitles,
                    activeThumbColor: AppTheme.accentGold,
                    onChanged: (val) {
                      notifier.updateSegment(
                        current.copyWith(enableSubtitles: val),
                      );
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Huruf Kapital (UPPERCASE)'),
                    subtitle: const Text('Tampilkan subtitle huruf besar.'),
                    value: state.subtitleStyle.isUppercase,
                    activeThumbColor: AppTheme.accentGold,
                    onChanged: (val) {
                      notifier.updateSubtitleStyle(
                        state.subtitleStyle.copyWith(isUppercase: val),
                      );
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bahasa Transkripsi Whisper',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: ref.watch(clipperProvider).transcribeLang,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: context.appColors.surfaceMuted,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'auto',
                        child: Text('Auto (Deteksi Otomatis)'),
                      ),
                      DropdownMenuItem(
                        value: 'id',
                        child: Text('Bahasa Indonesia'),
                      ),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: (val) {
                      if (val == null) return;
                      notifier.setTranscribeLang(val);
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Selesai'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clipperProvider);
    final selectedSegment =
        state.selectedSegment ??
        (state.segments.isNotEmpty
            ? state.segments.first
            : (state.currentSource != null
                  ? VideoSegment(
                      id: 'seg_default',
                      title: '💡 Segmen Utama Video',
                      startTime: Duration.zero,
                      endTime: state.currentSource!.duration,
                      viralScore: 95.0,
                      summary:
                          'Klip pembuka utama video dengan analisis percakapan AI.',
                      transcript:
                          'Poin utama percakapan dari awal hingga akhir video.',
                      cropXPercent: 0.5,
                    )
                  : null));

    // Auto-run face tracking for the preview whenever a segment has not been
    // analysed yet. A segment that already failed keeps a warning so this does
    // not retry forever; the user can re-trigger it manually. Only run when the
    // segment genuinely lacks keyframes — persisted analysis must not re-run
    // just because `faceTrackedSegmentId` resets after a fresh project load.
    final needsFaceAnalysis =
        selectedSegment != null &&
        selectedSegment.faceKeyframes.isEmpty &&
        state.faceTrackingWarning == null;
    if (needsFaceAnalysis && !state.faceTrackingRunning) {
      Future.microtask(
        () =>
            ref.read(clipperProvider.notifier).runFaceTracking(selectedSegment),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(state.currentSource?.title ?? 'Workspace Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Detail Berkas Video',
            onPressed: () => _showFileInfoDialog(context, state),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Pengaturan Cepat',
            onPressed: () {
              HapticFeedback.selectionClick();
              _showQuickSettings(state);
            },
          ),
        ],
      ),
      body: selectedSegment == null
          ? const Center(child: Text('Tidak ada segmen terpilih'))
          : Column(
              children: [
                // Top: Video Player Preview (Dynamic Frame Container)
                Container(
                  height: 280,
                  width: double.infinity,
                  color: Colors.black,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final parentW = constraints.maxWidth;
                      final parentH = constraints.maxHeight;
                      final videoAspect =
                          (_isPlayerInitialized &&
                              _videoController != null &&
                              _videoController!.value.aspectRatio > 0)
                          ? _videoController!.value.aspectRatio
                          : 16 / 9;
                      var vw = parentH * videoAspect;
                      var vh = parentH;
                      if (vw > parentW) {
                        vw = parentW;
                        vh = parentW / videoAspect;
                      }
                      const cropWidth = 280.0 * (9.0 / 16.0);
                      final frameW = cropWidth < vw ? cropWidth : vw;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: vw,
                            height: vh,
                            child:
                                _isPlayerInitialized && _videoController != null
                                ? VideoPlayer(_videoController!)
                                : const Center(
                                    child: CircularProgressIndicator(
                                      color: AppTheme.primaryGold,
                                    ),
                                  ),
                          ),
                          // Aspect Ratio Crop Overlay Guideline (moves live to
                          // follow the detected speaker position, panned within
                          // the video display area)
                          if (_isPlayerInitialized && _videoController != null)
                            SizedBox(
                              width: vw,
                              height: vh,
                              child: ValueListenableBuilder<VideoPlayerValue>(
                                valueListenable: _videoController!,
                                builder: (context, value, child) {
                                  final liveFaceX = _getLivePreviewFaceX(
                                    selectedSegment,
                                  ).clamp(0.0, 1.0);
                                  return AnimatedAlign(
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOut,
                                    alignment: Alignment(liveFaceX * 2 - 1, 0),
                                    child: child,
                                  );
                                },
                                child: Container(
                                  width: frameW,
                                  height: 280,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: AppTheme.accentGold,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Stack(
                                    children: [
                                      Align(
                                        alignment: Alignment.topCenter,
                                        child: Container(
                                          margin: const EdgeInsets.only(top: 8),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          color: Colors.black54,
                                          child: const Text(
                                            '9:16 Shorts',
                                            style: TextStyle(
                                              color: AppTheme.accentGold,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Subtitle Preview Overlay with Preset Styling
                                      if (selectedSegment.enableSubtitles)
                                        Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 16,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: state
                                                  .subtitleStyle
                                                  .backgroundColor,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              state.subtitleStyle.isUppercase
                                                  ? 'PREVIEW SUBTITLE ANIMASI'
                                                  : 'Preview Subtitle Animasi',
                                              style: TextStyle(
                                                color: state
                                                    .subtitleStyle
                                                    .textColor,
                                                fontSize:
                                                    state
                                                        .subtitleStyle
                                                        .fontSize *
                                                    0.45,
                                                fontWeight: FontWeight.bold,
                                                shadows:
                                                    state
                                                            .subtitleStyle
                                                            .strokeWidth >
                                                        0
                                                    ? [
                                                        Shadow(
                                                          color: state
                                                              .subtitleStyle
                                                              .strokeColor,
                                                          blurRadius: 3,
                                                        ),
                                                      ]
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          // Face Tracking Status Chip (updates dynamically live)
                          Positioned(
                            top: 8,
                            left: 8,
                            child:
                                _isPlayerInitialized && _videoController != null
                                ? ValueListenableBuilder<VideoPlayerValue>(
                                    valueListenable: _videoController!,
                                    builder: (context, value, child) {
                                      final liveFaceX = _getLivePreviewFaceX(
                                        selectedSegment,
                                      );
                                      final percentStr = (liveFaceX * 100)
                                          .toInt();
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        color: Colors.black54,
                                        child: Text(
                                          state.faceTrackingRunning
                                              ? 'Analisis wajah pembicara '
                                                    '${(state.faceTrackingProgress * 100).round()}%...'
                                              : state.faceTrackingWarning !=
                                                    null
                                              ? '⚠ ${state.faceTrackingWarning}'
                                              : 'Pembicara: X $percentStr%',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : const SizedBox.shrink(),
                          ),
                          // Play/Pause Floating Control
                          if (_isPlayerInitialized && _videoController != null)
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: FloatingActionButton.small(
                                backgroundColor: AppTheme.primaryGold,
                                onPressed: () {
                                  setState(() {
                                    if (_videoController!.value.isPlaying) {
                                      _videoController!.pause();
                                    } else {
                                      _videoController!.play();
                                    }
                                  });
                                },
                                child: Icon(
                                  _videoController!.value.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),

                // Middle Tabs
                Expanded(
                  child: DefaultTabController(
                    length: 3,
                    child: Column(
                      children: [
                        Container(
                          color: context.appColors.surface,
                          child: const TabBar(
                            indicatorColor: AppTheme.primaryGold,
                            labelColor: AppTheme.primaryGold,
                            tabs: [
                              Tab(text: 'Segmen Klip AI'),
                              Tab(text: 'Smart Reframe'),
                              Tab(text: 'Gaya Subtitle'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              // Tab 1: Segments List & Fine-Tune Trimmer
                              Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      12,
                                      4,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Segmen Deteksi AI',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleLarge,
                                              ),
                                              Text(
                                                'Pipeline: Whisper → NLP → LLM Lokal (Qwen 2.5)',
                                                style: TextStyle(
                                                  color: context
                                                      .appColors
                                                      .textSecondary,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _startReanalyze,
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            minimumSize: Size.zero,
                                          ),
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Re-Analisis'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      padding: const EdgeInsets.all(12),
                                      itemCount: state.segments.length,
                                      itemBuilder: (context, index) {
                                        final seg = state.segments[index];
                                        final isSelected =
                                            seg.id == selectedSegment.id;
                                        final colors = context.appColors;
                                        return Card(
                                          color: isSelected
                                              ? AppTheme.primaryGold
                                                    .withValues(alpha: 0.15)
                                              : colors.surface,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            side: BorderSide(
                                              color: isSelected
                                                  ? AppTheme.primaryGold
                                                  : colors.border,
                                              width: isSelected ? 2 : 1,
                                            ),
                                          ),
                                          margin: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            onTap: () {
                                              HapticFeedback.selectionClick();
                                              ref
                                                  .read(
                                                    clipperProvider.notifier,
                                                  )
                                                  .selectSegment(seg);
                                              _seekToSelectedSegment();
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                12.0,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          seg.title,
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 15,
                                                              ),
                                                        ),
                                                      ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 3,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: AppTheme
                                                              .accentGold
                                                              .withValues(
                                                                alpha: 0.2,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          'Score: ${seg.viralScore}',
                                                          style:
                                                              const TextStyle(
                                                                color: AppTheme
                                                                    .accentGold,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    'Durasi: ${seg.formatDuration(seg.startTime)} - ${seg.formatDuration(seg.endTime)} (${seg.clipDuration.inSeconds} detik)',
                                                    style: TextStyle(
                                                      color:
                                                          colors.textSecondary,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    seg.summary,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                    ),
                                                  ),

                                                  // Fine-Tune Controls for Selected Segment
                                                  if (isSelected) ...[
                                                    const SizedBox(height: 12),
                                                    const Divider(),
                                                    Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.tune,
                                                          size: 16,
                                                          color: AppTheme
                                                              .primaryGold,
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        const Text(
                                                          'Fine-Tune Waktu Mulai (Start):',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        Text(
                                                          seg.formatDuration(
                                                            seg.startTime,
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                                color: AppTheme
                                                                    .accentGold,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                    Builder(
                                                      builder: (context) {
                                                        final maxVal =
                                                            (seg.endTime.inSeconds -
                                                                    5)
                                                                .toDouble()
                                                                .clamp(
                                                                  1.0,
                                                                  99999.0,
                                                                );
                                                        final currentVal = seg
                                                            .startTime
                                                            .inSeconds
                                                            .toDouble()
                                                            .clamp(0.0, maxVal);
                                                        return Slider(
                                                          value: currentVal,
                                                          min: 0,
                                                          max: maxVal,
                                                          activeColor: AppTheme
                                                              .primaryGold,
                                                          onChanged: (val) {
                                                            ref
                                                                .read(
                                                                  clipperProvider
                                                                      .notifier,
                                                                )
                                                                .updateSegment(
                                                                  seg.copyWith(
                                                                    startTime: Duration(
                                                                      seconds: val
                                                                          .toInt(),
                                                                    ),
                                                                  ),
                                                                );
                                                            _seekToSelectedSegment();
                                                          },
                                                        );
                                                      },
                                                    ),
                                                  ],

                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: TextButton.icon(
                                                      onPressed: () {
                                                        ref
                                                            .read(
                                                              clipperProvider
                                                                  .notifier,
                                                            )
                                                            .deleteSegment(
                                                              seg.id,
                                                            );
                                                      },
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                        color: Colors.redAccent,
                                                        size: 18,
                                                      ),
                                                      label: const Text(
                                                        'Hapus Segmen Ini',
                                                        style: TextStyle(
                                                          color:
                                                              Colors.redAccent,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),

                              // Tab 2: Smart Reframe & Target Aspect Ratio Selector
                              SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Face-Tracking Otomatis',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Kamera secara otomatis mendeteksi dan mengunci posisi wajah pembicara aktif.',
                                        style: TextStyle(
                                          color:
                                              context.appColors.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: context.appColors.surfaceMuted,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: context.appColors.border,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  state.faceTrackingRunning
                                                      ? Icons.sync
                                                      : Icons
                                                            .check_circle_outline,
                                                  color:
                                                      state.faceTrackingRunning
                                                      ? AppTheme.primaryGold
                                                      : Colors.green,
                                                  size: 24,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        state.faceTrackingRunning
                                                            ? 'Sedang Menganalisis Wajah...'
                                                            : 'Live Tracking Aktif',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      Text(
                                                        selectedSegment
                                                                .faceKeyframes
                                                                .isNotEmpty
                                                            ? 'Kamera otomatis mengikuti pembicara (${selectedSegment.faceKeyframes.length} sampel waktu).'
                                                            : 'Kamera otomatis menyesuaikan posisi pembicara.',
                                                        style: TextStyle(
                                                          color: context
                                                              .appColors
                                                              .textSecondary,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (state.faceTrackingRunning) ...[
                                              const SizedBox(height: 12),
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: LinearProgressIndicator(
                                                  value: state
                                                      .faceTrackingProgress,
                                                  minHeight: 6,
                                                  backgroundColor:
                                                      context.appColors.border,
                                                  valueColor:
                                                      const AlwaysStoppedAnimation<
                                                        Color
                                                      >(AppTheme.primaryGold),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                'Memproses ${(state.faceTrackingProgress * 100).round()}%...',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: context
                                                      .appColors
                                                      .textSecondary,
                                                ),
                                              ),
                                            ],
                                            if (state.faceTrackingWarning !=
                                                null) ...[
                                              const SizedBox(height: 8),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Icon(
                                                    Icons.warning_amber_rounded,
                                                    color: Colors.orange,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      state
                                                          .faceTrackingWarning!,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.orange,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: state.faceTrackingRunning
                                              ? null
                                              : () => ref
                                                    .read(
                                                      clipperProvider.notifier,
                                                    )
                                                    .rerunFaceTracking(
                                                      selectedSegment,
                                                    ),
                                          icon: const Icon(
                                            Icons.refresh,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Deteksi Ulang Otomatis',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Tab 3: Viral Subtitle Preset Selector & Customizer
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: ListView(
                                  children: [
                                    Text(
                                      'Pilih Preset Gaya Subtitle Viral',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 100,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount:
                                            SubtitlePreset.presets.length,
                                        itemBuilder: (context, index) {
                                          final preset =
                                              SubtitlePreset.presets[index];
                                          return GestureDetector(
                                            onTap: () {
                                              ref
                                                  .read(
                                                    clipperProvider.notifier,
                                                  )
                                                  .updateSubtitleStyle(
                                                    preset.style,
                                                  );
                                            },
                                            child: Container(
                                              width: 130,
                                              margin: const EdgeInsets.only(
                                                right: 12,
                                              ),
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color:
                                                    context.appColors.surface,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color:
                                                      state
                                                              .subtitleStyle
                                                              .fontFamily ==
                                                          preset
                                                              .style
                                                              .fontFamily
                                                      ? AppTheme.accentGold
                                                      : context
                                                            .appColors
                                                            .border,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    preset.icon,
                                                    style: const TextStyle(
                                                      fontSize: 24,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    preset.name,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Divider(),
                                    SwitchListTile(
                                      title: const Text(
                                        'Otomatis Burn Subtitle',
                                      ),
                                      value: selectedSegment.enableSubtitles,
                                      activeThumbColor: AppTheme.accentGold,
                                      onChanged: (val) {
                                        ref
                                            .read(clipperProvider.notifier)
                                            .updateSegment(
                                              selectedSegment.copyWith(
                                                enableSubtitles: val,
                                              ),
                                            );
                                      },
                                    ),
                                    SwitchListTile(
                                      title: const Text(
                                        'Huruf Kapital (UPPERCASE)',
                                      ),
                                      value: state.subtitleStyle.isUppercase,
                                      activeThumbColor: AppTheme.primaryGold,
                                      onChanged: (val) {
                                        ref
                                            .read(clipperProvider.notifier)
                                            .updateSubtitleStyle(
                                              state.subtitleStyle.copyWith(
                                                isUppercase: val,
                                              ),
                                            );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Render Action Button
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: context.appColors.surface,
                    border: Border(
                      top: BorderSide(color: context.appColors.border),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppTheme.neonGradient,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accentGold.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _startRender,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                              ),
                              icon: const Icon(
                                Icons.movie_creation_outlined,
                                color: Colors.black,
                              ),
                              label: Text(
                                'Render Short (9:16) - ${selectedSegment.clipDuration.inSeconds}d',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (state.segments.length > 1) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: OutlinedButton.icon(
                              onPressed: _startRenderAll,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primaryGold,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                    color: AppTheme.primaryGold,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.layers_outlined, size: 20),
                              label: Text(
                                'Render Semua Segmen (${state.segments.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Non-dismissible modal shown while re-running the AI highlight pipeline.
class _ReanalyzeDialog extends ConsumerWidget {
  const _ReanalyzeDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clipperProvider);
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: AppTheme.primaryGold,
              strokeWidth: 4,
            ),
            const SizedBox(height: 20),
            Text(
              state.statusMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (state.analysisProgress > 0) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: state.analysisProgress,
                  minHeight: 6,
                  backgroundColor: context.appColors.surfaceMuted,
                  color: AppTheme.primaryGold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
