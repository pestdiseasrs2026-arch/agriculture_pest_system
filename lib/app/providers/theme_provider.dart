import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeController extends Notifier<ThemeMode> {
  static const _preferenceKey = 'theme_mode';

  @override
  ThemeMode build() {
    Future<void>.microtask(_restore);
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getString(_preferenceKey);
      if (!ref.mounted || value == null) return;
      state = ThemeMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      // System theme remains available when preference storage is unavailable.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_preferenceKey, mode.name);
    } catch (_) {
      // The selected theme still applies for the current session.
    }
  }

  void toggle(Brightness platformBrightness) {
    final currentlyDark =
        state == ThemeMode.dark ||
        (state == ThemeMode.system && platformBrightness == Brightness.dark);
    setMode(currentlyDark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
