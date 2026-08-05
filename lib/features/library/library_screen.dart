import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/clipper_provider.dart';
import '../../core/models/video_project.dart';
import '../../core/models/video_source.dart';
import '../../core/theme/app_theme.dart';
import '../workspace/workspace_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _selectedFilterIndex = 0; // 0: Semua, 1: Belum Diklip, 2: Sudah Diklip
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clipperProvider);
    final projects = state.projects;

    final filteredProjects = projects.where((p) {
      if (_selectedFilterIndex == 1 && p.status != ClippingStatus.unclipped) {
        return false;
      }
      if (_selectedFilterIndex == 2 && p.status != ClippingStatus.clipped) {
        return false;
      }
      if (_searchQuery.isNotEmpty &&
          !p.source.title.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Pustaka & Status Video')),
      body: Column(
        children: [
          // Filter Tabs & Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Cari judul video...',
                    prefixIcon: Icon(
                      Icons.search,
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('Semua (${projects.length})', 0),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        '⚡ Belum Diklip (${projects.where((p) => p.status == ClippingStatus.unclipped).length})',
                        1,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        '✅ Sudah Diklip (${projects.where((p) => p.status == ClippingStatus.clipped).length})',
                        2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: filteredProjects.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.video_collection_outlined,
                          size: 64,
                          color: AppTheme.primaryGold,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Tidak ada video ditemukan',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Impor atau unduh video YouTube/Lokal di tab Downloader.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.appColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredProjects.length,
                    itemBuilder: (context, index) {
                      final project = filteredProjects[index];
                      return _ProjectCard(project: project);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilterIndex == index;
    final colors = context.appColors;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedFilterIndex = index);
        }
      },
      selectedColor: AppTheme.primaryGold,
      backgroundColor: colors.surfaceMuted,
      side: BorderSide(
        color: isSelected ? AppTheme.primaryGold : colors.border,
      ),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : colors.textSecondary,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

class _ProjectCard extends ConsumerWidget {
  final VideoProject project;

  const _ProjectCard({required this.project});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Proyek?'),
        content: Text(
          'Proyek "${project.source.title}" beserta segmen klipnya akan dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(clipperProvider.notifier).deleteProject(project.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isClipped = project.status == ClippingStatus.clipped;
    final colors = context.appColors;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isClipped
              ? AppTheme.accentGold.withValues(alpha: 0.6)
              : colors.border,
          width: isClipped ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: project.source.type == VideoSourceType.youtube
                      ? Colors.redAccent.withValues(alpha: 0.12)
                      : AppTheme.primaryGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  project.source.type == VideoSourceType.youtube
                      ? Icons.play_circle_fill_rounded
                      : Icons.video_file_rounded,
                  color: project.source.type == VideoSourceType.youtube
                      ? Colors.redAccent
                      : AppTheme.primaryGold,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.source.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Durasi: ${project.source.duration.inMinutes}m ${project.source.duration.inSeconds.remainder(60)}s • ${project.source.type == VideoSourceType.youtube ? "YouTube" : "File Lokal"}',
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isClipped
                      ? AppTheme.accentGold.withValues(alpha: 0.15)
                      : Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isClipped
                        ? AppTheme.accentGold.withValues(alpha: 0.5)
                        : Colors.amber.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  isClipped
                      ? '✅ Sudah Diklip (${project.renderedClipsCount} Klip)'
                      : '⚡ Belum Diklip',
                  style: TextStyle(
                    color: isClipped ? AppTheme.accentGold : Colors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    tooltip: 'Hapus Proyek',
                    onPressed: () => _confirmDelete(context, ref),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () {
                      ref.read(clipperProvider.notifier).loadProject(project);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const WorkspaceScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: Text(isClipped ? 'Edit Klip' : 'Buka Editor'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
