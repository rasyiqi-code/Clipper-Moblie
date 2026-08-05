import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../core/providers/clipper_provider.dart';
import '../../core/theme/app_theme.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clipperProvider);
    final history = state.renderedClipsHistory;

    return Scaffold(
      appBar: AppBar(title: const Text('Hasil Klip AI (Gallery)')),
      body: history.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.movie_creation_outlined,
                    size: 64,
                    color: AppTheme.primaryGold,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Belum Ada Klip Yang Diekspor',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Klip Shorts/Reels yang Anda render akan muncul di sini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.appColors.textSecondary),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final clipPath = history[index];
                return _ClipItemCard(clipPath: clipPath, index: index);
              },
            ),
    );
  }
}

class _ClipItemCard extends StatefulWidget {
  final String clipPath;
  final int index;

  const _ClipItemCard({required this.clipPath, required this.index});

  @override
  State<_ClipItemCard> createState() => _ClipItemCardState();
}

class _ClipItemCardState extends State<_ClipItemCard> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    final file = File(widget.clipPath);
    if (file.existsSync() && file.lengthSync() > 1024) {
      _controller = VideoPlayerController.file(file)
        ..initialize()
            .then((_) {
              if (mounted) setState(() {});
            })
            .catchError((e) {
              debugPrint('Gagal memuat player: $e');
            });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _isPlaying = false;
      } else {
        _controller!.play();
        _isPlaying = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.clipPath);
    final fileName = file.path.split('/').last;
    final fileSizeMB = file.existsSync()
        ? (file.lengthSync() / (1024 * 1024)).toStringAsFixed(2)
        : '0.0';
    final colors = context.appColors;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Player Video / Thumbnail Area
          Container(
            height: 220,
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                _controller != null && _controller!.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      )
                    : Center(
                        child: Icon(
                          Icons.movie,
                          size: 48,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                IconButton(
                  iconSize: 56,
                  icon: Icon(
                    _isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: AppTheme.primaryGold,
                  ),
                  onPressed: _togglePlay,
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.accentGold),
                    ),
                    child: Text(
                      '🔥 98.5% Viral Clip #${widget.index + 1}',
                      style: const TextStyle(
                        color: AppTheme.accentGold,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ukuran: $fileSizeMB MB • Format: 9:16 Shorts MP4',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: widget.clipPath),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Path disalin: ${widget.clipPath}'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Salin Path Berkas'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.share, color: AppTheme.accentGold),
                      tooltip: 'Bagikan',
                      onPressed: () async {
                        final fileToShare = File(widget.clipPath);
                        if (!fileToShare.existsSync()) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Berkas tidak ditemukan.'),
                            ),
                          );
                          return;
                        }
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [XFile(widget.clipPath)],
                            title: 'Bagikan Klip AI',
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
