import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand / semantic colors shared by both light and dark themes.
class AppTheme {
  static const Color primaryGold = Color(0xFFF0B429);
  static const Color secondaryGold = Color(0xFFC98A00);
  static const Color accentGold = Color(0xFFFACC15);
  static const Color amberViral = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFF5C518), Color(0xFFC98A00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient neonGradient = LinearGradient(
    colors: [Color(0xFFFACC15), Color(0xFFC98A00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient viralGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get lightTheme => _buildTheme(Brightness.light);
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;

    final base = isDark ? ThemeData.dark() : ThemeData.light();

    return base.copyWith(
      scaffoldBackgroundColor: colors.background,
      primaryColor: primaryGold,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primaryGold,
        onPrimary: Colors.black,
        secondary: accentGold,
        onSecondary: Colors.black,
        error: danger,
        onError: Colors.white,
        surface: colors.surface,
        onSurface: colors.textPrimary,
      ),
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: colors.textPrimary),
        titleTextStyle: GoogleFonts.outfit(
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGold,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryGold,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryGold,
          side: const BorderSide(color: primaryGold),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceMuted,
        hintStyle: GoogleFonts.inter(color: colors.textSecondary, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryGold, width: 2),
        ),
      ),
      textTheme: TextTheme(
        headlineMedium: GoogleFonts.outfit(
          color: colors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.2,
        ),
        titleLarge: GoogleFonts.outfit(
          color: colors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        bodyLarge: GoogleFonts.inter(color: colors.textPrimary, fontSize: 14),
        bodyMedium: GoogleFonts.inter(
          color: colors.textSecondary,
          fontSize: 12,
          height: 1.4,
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        modalBackgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? colors.surfaceMuted : Colors.black87,
        contentTextStyle: GoogleFonts.inter(
          color: isDark ? colors.textPrimary : Colors.white,
          fontSize: 13,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: primaryGold,
        labelColor: primaryGold,
        unselectedLabelColor: colors.textSecondary,
        dividerColor: colors.border,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accentGold : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accentGold.withValues(alpha: 0.4)
              : null,
        ),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: const FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Theme-aware surface/text colors. Access via `context.appColors`.
class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
  });

  static const AppColors light = AppColors(
    background: Color(0xFFFAFAF6),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF3F2EA),
    border: Color(0xFFE6E3D8),
    textPrimary: Color(0xFF1C1917),
    textSecondary: Color(0xFF78716C),
  );

  static const AppColors dark = AppColors(
    background: Color(0xFF050505),
    surface: Color(0xFF121212),
    surfaceMuted: Color(0xFF1C1C1C),
    border: Color(0xFF2E2E2E),
    textPrimary: Color(0xFFF5F5F4),
    textSecondary: Color(0xFFA8A29E),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    );
  }
}

extension BuildContextX on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
