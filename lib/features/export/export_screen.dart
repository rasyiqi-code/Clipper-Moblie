import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/providers/clipper_provider.dart';
import '../../core/theme/app_theme.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  VideoPlayerController? _exportedVideoController;

  @override
  void dispose() {
    _exportedVideoController?.dispose();
    super.dispose();
  }

  void _initExportedPlayer(String path) {
    final file = File(path);
    if (file.existsSync() && file.lengthSync() > 1024) {
      _exportedVideoController ??= VideoPlayerController.file(file)
        ..initialize()
            .then((_) {
              if (mounted) setState(() {});
              _exportedVideoController?.play();
              _exportedVideoController?.setLooping(true);
            })
            .catchError((e) {
              debugPrint('Gagal memuat player: $e');
            });
    }
  }

  Future<String> _resolveTargetDirectory() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (status.isGranted && await downloadDir.exists()) {
        return downloadDir.path;
      }
      final external = await getExternalStorageDirectory();
      if (external != null) return external.path;
    }
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  Future<void> _saveVideoToGallery(String? sourcePath) async {
    if (sourcePath == null || sourcePath.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Berkas video belum siap untuk disimpan.'),
        ),
      );
      return;
    }

    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Berkas video tidak ditemukan di penyimpanan.'),
          ),
        );
        return;
      }

      final targetDir = Directory(await _resolveTargetDirectory());
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final fileName = 'ClipperAI_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final targetPath = '${targetDir.path}/$fileName';

      await sourceFile.copy(targetPath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.accentGold,
          content: Text(
            '✓ Video berhasil disimpan ke Galeri HP / Folder Download!\nPath: $targetPath',
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal menyimpan video: $e')));
    }
  }

  Future<void> _shareExportedVideo(String? sourcePath) async {
    if (sourcePath == null || sourcePath.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Berkas video belum siap untuk dibagikan.'),
        ),
      );
      return;
    }
    final file = File(sourcePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Berkas video tidak ditemukan.')),
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(sourcePath)],
        title: 'Bagikan Klip AI Shorts/Reels',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clipperProvider);

    if (state.lastExportedPath != null && _exportedVideoController == null) {
      _initExportedPlayer(state.lastExportedPath!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Video Short'),
        automaticallyImplyLeading: !state.isRendering,
      ),
      body: state.isRendering
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      color: AppTheme.accentGold,
                      strokeWidth: 6,
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Merender Video Short 9:16...',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.statusMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    LinearProgressIndicator(
                      value: state.renderProgress > 0
                          ? state.renderProgress
                          : null,
                      color: AppTheme.accentGold,
                      backgroundColor: context.appColors.surfaceMuted,
                    ),
                  ],
                ),
              ),
            )
          : (state.lastExportedPath == null ||
                !File(state.lastExportedPath!).existsSync())
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 72,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Render Video Gagal',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.statusMessage.isNotEmpty
                          ? state.statusMessage
                          : 'Terjadi kesalahan saat memotong atau memproses video.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba Lagi di Editor'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 80,
                    color: AppTheme.accentGold,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Render Selesai!',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Video short Anda telah berhasil dipotong dan diringkas.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),

                  // Player Preview of Exported Short
                  if (_exportedVideoController != null &&
                      _exportedVideoController!.value.isInitialized)
                    Center(
                      child: Container(
                        height: 380,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.accentGold,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AspectRatio(
                            aspectRatio:
                                _exportedVideoController!.value.aspectRatio,
                            child: VideoPlayer(_exportedVideoController!),
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                  Text(
                    'Bagikan Langsung Ke Media Sosial:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.appColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ShareActionChip(
                        icon: Icons.video_library_rounded,
                        label: 'TikTok',
                        color: const Color(0xFFFE2C55),
                        onTap: () =>
                            _shareExportedVideo(state.lastExportedPath),
                      ),
                      _ShareActionChip(
                        icon: Icons.camera_alt_rounded,
                        label: 'Reels',
                        color: const Color(0xFFE1306C),
                        onTap: () =>
                            _shareExportedVideo(state.lastExportedPath),
                      ),
                      _ShareActionChip(
                        icon: Icons.play_arrow_rounded,
                        label: 'Shorts',
                        color: const Color(0xFFFF0000),
                        onTap: () =>
                            _shareExportedVideo(state.lastExportedPath),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () =>
                        _saveVideoToGallery(state.lastExportedPath),
                    icon: const Icon(Icons.download_done_rounded),
                    label: const Text('Simpan ke Galeri / Penyimpanan'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Kembali ke Workspace Editor'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ShareActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ShareActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
