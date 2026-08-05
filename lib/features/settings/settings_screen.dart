import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/clipper_provider.dart';
import '../../core/services/local_llm_service.dart';
import '../../core/services/whisper_service.dart';
import '../../core/theme/app_theme.dart';

/// Model AI management. Downloads happen here (Pengaturan), not inside the
/// video analysis workflow.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final WhisperService _whisper = WhisperService();
  final LocalLlmService _llm = LocalLlmService();

  bool _whisperDownloading = false;
  double _whisperProgress = 0;
  bool _llmDownloading = false;
  double _llmProgress = 0;

  int? _whisperSize;
  int? _llmSize;

  @override
  void initState() {
    super.initState();
    _whisper.model = WhisperService.resolveModel(
      ref.read(clipperProvider).whisperModel,
    );
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final whisperSize = await _whisper.localModelSizeBytes();
    final llmSize = await _llm.modelSizeBytes();
    if (!mounted) return;
    setState(() {
      _whisperSize = whisperSize;
      _llmSize = llmSize;
    });
  }

  Future<void> _downloadWhisper() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _whisperDownloading = true;
      _whisperProgress = 0;
    });
    try {
      await _whisper.getLocalModelFile(
        onProgress: (p) {
          if (mounted) setState(() => _whisperProgress = p);
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gagal mengunduh Whisper.')));
    }
    if (!mounted) return;
    setState(() {
      _whisperDownloading = false;
      _whisperProgress = 1;
    });
    await _refreshStatus();
  }

  Future<void> _deleteWhisper() async {
    HapticFeedback.selectionClick();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Model Whisper?'),
        content: const Text(
          'Model akan diunduh ulang nanti bila dibutuhkan di Pengaturan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _whisper.deleteLocalModel();
    await _refreshStatus();
  }

  Future<void> _downloadLlm() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _llmDownloading = true;
      _llmProgress = 0;
    });
    try {
      await _llm.loadModel(
        onProgress: (p) {
          if (mounted) setState(() => _llmProgress = p);
        },
      );
      await _llm.unloadModel();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gagal mengunduh LLM.')));
    }
    if (!mounted) return;
    setState(() {
      _llmDownloading = false;
      _llmProgress = 1;
    });
    await _refreshStatus();
  }

  String _sizeText(int? bytes) =>
      bytes == null ? '—' : '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';

  Widget _buildWhisperModelSelector() {
    final colors = context.appColors;
    final selected = ref.watch(clipperProvider).whisperModel;
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Model Whisper',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              'Tiny jauh lebih cepat untuk uji coba; Base lebih akurat.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selected,
              dropdownColor: colors.surface,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: colors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: 'tiny',
                  child: Text(
                    'Tiny — Cepat (rekomendasi uji coba)',
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  ),
                ),
                DropdownMenuItem(
                  value: 'base',
                  child: Text(
                    'Base — Akurat (lebih lambat)',
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                ref.read(clipperProvider.notifier).setWhisperModel(value);
                _refreshStatus();
              },
            ),
          ],
        ),
      ),
    );
  }

  String get selectedWhisperKey => ref.watch(clipperProvider).whisperModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Model AI Lokal', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Model diunduh sekali lalu disimpan di perangkat. Analisis video '
            'tidak lagi mengunduh di tengah proses.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _ModelCard(
            title: 'Whisper (Transkripsi)',
            description: selectedWhisperKey == 'tiny'
                ? 'ggml-tiny.bin · ~75 MB · jauh lebih cepat, akurasi sedikit '
                      'lebih rendah'
                : 'ggml-base.bin · ~142 MB · akurasi lebih baik, lebih lambat',
            icon: Icons.mic_none_rounded,
            status: _whisperDownloading
                ? 'Mengunduh ${(_whisperProgress * 100).toInt()}%'
                : _whisperSize != null
                ? 'Terunduh (${_sizeText(_whisperSize)})'
                : 'Belum diunduh',
            downloading: _whisperDownloading,
            progress: _whisperProgress,
            onDownload: _downloadWhisper,
            onDelete: _whisperSize != null ? _deleteWhisper : null,
          ),
          const SizedBox(height: 12),
          _buildWhisperModelSelector(),
          const SizedBox(height: 12),
          _ModelCard(
            title: 'Qwen 2.5 (Penilaian LLM)',
            description:
                'qwen2.5-0.5b-instruct-q4_k_m.gguf · ~491 MB · menilai skor '
                'viral, judul & ringkasan',
            icon: Icons.psychology_rounded,
            status: _llmDownloading
                ? 'Mengunduh ${(_llmProgress * 100).toInt()}%'
                : _llmSize != null
                ? 'Terunduh (${_sizeText(_llmSize)})'
                : 'Belum diunduh',
            downloading: _llmDownloading,
            progress: _llmProgress,
            onDownload: _downloadLlm,
            onDelete: null,
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String status;
  final bool downloading;
  final double progress;
  final VoidCallback onDownload;
  final VoidCallback? onDelete;

  const _ModelCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.status,
    required this.downloading,
    required this.progress,
    required this.onDownload,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: downloading
                          ? AppTheme.primaryGold
                          : status.startsWith('Terunduh')
                          ? Colors.green
                          : colors.textSecondary,
                    ),
                  ),
                ),
                if (onDelete != null)
                  TextButton(onPressed: onDelete, child: const Text('Hapus')),
                FilledButton.icon(
                  onPressed: downloading ? null : onDownload,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryGold,
                  ),
                  icon: Icon(
                    downloading
                        ? Icons.hourglass_top_rounded
                        : Icons.download_rounded,
                    size: 18,
                  ),
                  label: Text(downloading ? 'Mengunduh...' : 'Unduh'),
                ),
              ],
            ),
            if (downloading) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: colors.surfaceMuted,
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
