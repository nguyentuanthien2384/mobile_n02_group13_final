import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the app-wide [ThemeMode] and persists the user's choice locally.
class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = 'themeMode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  /// Load the saved theme preference. Safe to call before runApp.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_prefsKey);
      _mode = _fromString(value);
      notifyListeners();
    } catch (_) {
      // Keep default on any failure.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _toString(mode));
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  /// Convenience toggle used by the simple switch in Profile.
  Future<void> toggleDark(bool enabled) =>
      setMode(enabled ? ThemeMode.dark : ThemeMode.light);

  static ThemeMode _fromString(String? value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }
}
