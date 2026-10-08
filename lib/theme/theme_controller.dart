import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controller managing the application's ThemeMode (light, dark, system).
/// Persists the selected mode to SharedPreferences.
class ThemeController extends ChangeNotifier {
  static const String _prefKey = 'app_theme_mode';

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  /// Loads the persisted theme mode from SharedPreferences.
  Future<void> loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null) {
        switch (saved) {
          case 'light':
            _themeMode = ThemeMode.light;
            break;
          case 'dark':
            _themeMode = ThemeMode.dark;
            break;
          case 'system':
          default:
            _themeMode = ThemeMode.system;
            break;
        }
        notifyListeners();
      }
    } catch (_) {
      // In case SharedPreferences fails or is in headless test
      _themeMode = ThemeMode.system;
    }
  }

  /// Sets a specific ThemeMode and persists it.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (_) {}
  }

  /// Cycles through Light -> Dark -> System -> Light.
  Future<void> cycleThemeMode() async {
    switch (_themeMode) {
      case ThemeMode.light:
        await setThemeMode(ThemeMode.dark);
        break;
      case ThemeMode.dark:
        await setThemeMode(ThemeMode.system);
        break;
      case ThemeMode.system:
        await setThemeMode(ThemeMode.light);
        break;
    }
  }

  /// Returns user-friendly name for the current theme mode.
  String get themeModeName {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  /// Returns an appropriate icon for the current mode.
  IconData get icon {
    switch (_themeMode) {
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
      case ThemeMode.system:
        return Icons.brightness_auto_rounded;
    }
  }
}

