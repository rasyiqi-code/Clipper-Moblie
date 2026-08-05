import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/clipper_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../settings/settings_screen.dart';
import '../workspace/workspace_screen.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  void _onProcessLocalFile() async {
    final notifier = ref.read(clipperProvider.notifier);
    await notifier.pickLocalVideo();

    if (!mounted) return;
    final state = ref.read(clipperProvider);
    if (state.currentSource != null) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const WorkspaceScreen()));
    } else if (state.statusMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.danger,
          content: Text(state.statusMessage),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final clipperState = ref.watch(clipperProvider);
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Brand Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryGold.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.content_cut,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Clipper',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                              letterSpacing: 0.3,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'MOBILE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Pengaturan',
                        icon: Icon(
                          Icons.settings_outlined,
                          color: colors.textPrimary,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: Theme.of(context).brightness == Brightness.dark
                            ? 'Ganti ke Tema Terang'
                            : 'Ganti ke Tema Gelap',
                        icon: Icon(
                          Theme.of(context).brightness == Brightness.dark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          color: colors.textPrimary,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          ref
                              .read(themeModeProvider.notifier)
                              .toggle(Theme.of(context).brightness);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: clipperState.isLoading
                  ? AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: clipperState.analysisStage != AnalysisStage.idle
                          ? _AnalysisPipelineView(
                              key: const ValueKey('pipeline'),
                              state: clipperState,
                            )
                          : _GenericLoadingView(
                              key: const ValueKey('generic'),
                              statusMessage: clipperState.statusMessage,
                            ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Local Video Card
                          _SourceCard(
                            icon: Icons.video_library_rounded,
                            iconColor: AppTheme.primaryGold,
                            title: 'Pilih File Video Lokal',
                            subtitle:
                                'Pilih file MP4, MKV, atau MOV dari galeri / penyimpanan perangkat Anda. AI akan menganalisis pembicara, transkripsi otomatis, dan membuat klip Shorts 9:16.',
                            buttonLabel: 'Buka Galeri / Berkas Video',
                            buttonIcon: Icons.folder_open_rounded,
                            gradient: AppTheme.primaryGradient,
                            buttonForegroundColor: Colors.white,
                            onPressed: _onProcessLocalFile,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                _FormatChip(label: 'MP4'),
                                SizedBox(width: 8),
                                _FormatChip(label: 'MKV'),
                                SizedBox(width: 8),
                                _FormatChip(label: 'MOV'),
                              ],
                            ),
                          ),
                          if (clipperState.currentSource != null) ...[
                            const SizedBox(height: 24),
                            _buildActiveProjectCard(context, clipperState),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildActiveProjectCard(BuildContext context, ClipperState state) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primaryGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.play_circle_outline,
              color: AppTheme.primaryGold,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Proyek Aktif Terakhir',
                  style: TextStyle(
                    color: AppTheme.primaryGold,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state.currentSource?.title ?? 'Proyek Video',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
              );
            },
            child: const Text('Buka Editor'),
          ),
        ],
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  final String label;

  const _FormatChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _GenericLoadingView extends StatelessWidget {
  final String statusMessage;

  const _GenericLoadingView({super.key, required this.statusMessage});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: AppTheme.primaryGold,
              strokeWidth: 4,
            ),
            const SizedBox(height: 24),
            Text(
              statusMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

/// Multi-step checklist shown while the AI pipeline (transcription, NLP,
/// local LLM grading) is running.
class _AnalysisPipelineView extends StatelessWidget {
  final ClipperState state;

  const _AnalysisPipelineView({super.key, required this.state});

  static const List<
    ({AnalysisStage stage, String title, String subtitle, IconData icon})
  >
  _steps = [
    (
      stage: AnalysisStage.transcribing,
      title: 'Transkripsi Audio',
      subtitle: 'Konversi suara menjadi teks',
      icon: Icons.graphic_eq_rounded,
    ),
    (
      stage: AnalysisStage.analyzingNlp,
      title: 'Analisis Highlight (NLP)',
      subtitle: 'Deteksi segmen paling menarik',
      icon: Icons.auto_awesome_rounded,
    ),
    (
      stage: AnalysisStage.gradingLlm,
      title: 'Penilaian LLM Lokal',
      subtitle: 'Qwen 2.5 menilai skor viral & judul',
      icon: Icons.psychology_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final current = state.analysisStage;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.auto_fix_high_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.statusMessage,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: state.analysisProgress > 0
                        ? state.analysisProgress
                        : null,
                    minHeight: 8,
                    backgroundColor: colors.surfaceMuted,
                    color: AppTheme.primaryGold,
                  ),
                ),
                const SizedBox(height: 20),
                ..._steps.map(
                  (step) => _PipelineStepTile(
                    step: step,
                    status: _stepStatus(step.stage, current),
                    progress: step.stage == current
                        ? state.analysisProgress
                        : 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _PipelineStepStatus _stepStatus(AnalysisStage step, AnalysisStage current) {
    if (step.index < current.index) return _PipelineStepStatus.done;
    if (step == current) return _PipelineStepStatus.active;
    return _PipelineStepStatus.pending;
  }
}

enum _PipelineStepStatus { pending, active, done }

class _PipelineStepTile extends StatelessWidget {
  final ({AnalysisStage stage, String title, String subtitle, IconData icon})
  step;
  final _PipelineStepStatus status;
  final double progress;

  const _PipelineStepTile({
    required this.step,
    required this.status,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isActive = status == _PipelineStepStatus.active;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.primaryGold.withValues(alpha: 0.1)
            : colors.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppTheme.primaryGold
              : status == _PipelineStepStatus.done
              ? AppTheme.accentGold.withValues(alpha: 0.5)
              : colors.border,
        ),
      ),
      child: Row(
        children: [
          _StatusIcon(status: status, icon: step.icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive && progress > 0
                      ? '${step.subtitle} (${(progress * 100).toInt()}%)'
                      : step.subtitle,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                if (isActive && progress > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: colors.surfaceMuted,
                      color: AppTheme.primaryGold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final _PipelineStepStatus status;
  final IconData icon;

  const _StatusIcon({required this.status, required this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    switch (status) {
      case _PipelineStepStatus.done:
        return const Icon(
          Icons.check_circle_rounded,
          color: AppTheme.accentGold,
          size: 24,
        );
      case _PipelineStepStatus.active:
        return SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            children: [
              Icon(icon, color: colors.textSecondary, size: 24),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primaryGold,
                  ),
                ),
              ),
            ],
          ),
        );
      case _PipelineStepStatus.pending:
        return Icon(
          icon,
          color: colors.textSecondary.withValues(alpha: 0.4),
          size: 24,
        );
    }
  }
}

class _SourceCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget child;
  final String buttonLabel;
  final IconData buttonIcon;
  final Gradient gradient;
  final VoidCallback onPressed;
  final Color? buttonForegroundColor;

  const _SourceCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.gradient,
    required this.onPressed,
    this.buttonForegroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          child,
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryGold.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                ),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onPressed();
                },
                icon: Icon(
                  buttonIcon,
                  color: buttonForegroundColor ?? Colors.white,
                ),
                label: Text(
                  buttonLabel,
                  style: TextStyle(
                    color: buttonForegroundColor ?? Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
