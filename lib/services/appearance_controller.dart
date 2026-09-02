import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _appearancePreferenceKey = 'appearance.themeMode.v1';

class AppearanceController extends ChangeNotifier {
  AppearanceController._(this._preferences, this._mode);

  final SharedPreferencesAsync _preferences;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  static Future<AppearanceController> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final resolvedPreferences = preferences ?? SharedPreferencesAsync();
    var mode = ThemeMode.system;
    try {
      mode = _decode(
        await resolvedPreferences.getString(_appearancePreferenceKey),
      );
    } on Object {
      // Appearance is a convenience preference. Storage failure must never
      // prevent the application from starting.
    }
    return AppearanceController._(resolvedPreferences, mode);
  }

  Future<bool> setMode(ThemeMode mode) async {
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }
    try {
      await _preferences.setString(_appearancePreferenceKey, mode.name);
      return true;
    } on Object {
      return false;
    }
  }

  static ThemeMode _decode(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}
