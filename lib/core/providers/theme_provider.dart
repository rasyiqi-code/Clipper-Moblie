import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Injected in `main()` with the app-wide SharedPreferences instance.
final prefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override prefsProvider in main()');
});

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier(this._prefs) : super(_restore(_prefs));

  final SharedPreferences _prefs;
  static const _key = 'theme_mode';

  static ThemeMode _restore(SharedPreferences prefs) {
    final value = prefs.getString(_key);
    return ThemeMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => ThemeMode.dark,
    );
  }

  /// Toggles between light and dark based on the currently effective brightness.
  void toggle(Brightness currentBrightness) {
    setMode(
      currentBrightness == Brightness.light ? ThemeMode.dark : ThemeMode.light,
    );
  }

  void setMode(ThemeMode mode) {
    state = mode;
    _prefs.setString(_key, mode.name);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((
  ref,
) {
  return ThemeNotifier(ref.watch(prefsProvider));
});
