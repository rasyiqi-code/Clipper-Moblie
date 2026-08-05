import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../import/import_screen.dart';
import '../library/library_screen.dart';
import '../history/history_screen.dart';
import '../insight/insight_screen.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    ImportScreen(),
    LibraryScreen(),
    HistoryScreen(),
    InsightScreen(),
  ];

  List<BottomNavigationBarItem> _buildItems(BuildContext context) {
    return <BottomNavigationBarItem>[
      BottomNavigationBarItem(
        icon: Icon(Icons.add_circle_outline_rounded, size: 22),
        activeIcon: Icon(
          Icons.add_circle_rounded,
          size: 22,
          color: AppTheme.primaryGold,
        ),
        label: 'Impor Video',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.video_library_outlined, size: 22),
        activeIcon: Icon(
          Icons.video_library,
          size: 22,
          color: AppTheme.primaryGold,
        ),
        label: 'Pustaka',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.movie_creation_outlined, size: 22),
        activeIcon: Icon(
          Icons.movie_creation,
          size: 22,
          color: AppTheme.primaryGold,
        ),
        label: 'Hasil AI',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.lightbulb_outline, size: 22),
        activeIcon: Icon(
          Icons.lightbulb,
          size: 22,
          color: AppTheme.primaryGold,
        ),
        label: 'Insight',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) {
                  setState(() => _currentIndex = index);
                },
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: AppTheme.primaryGold,
                unselectedItemColor: colors.textSecondary,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
                unselectedLabelStyle: const TextStyle(fontSize: 10),
                items: _buildItems(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
