import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/touchpad_settings.dart';

class TouchpadSettingsNotifier extends Notifier<TouchpadSettings> {
  static const String _prefsKey = 'gadgetfs_touchpad_settings_v1';

  @override
  TouchpadSettings build() {
    _loadFromPreferences();
    return const TouchpadSettings();
  }

  Future<void> _loadFromPreferences() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        state = TouchpadSettings.fromJson(raw);
      }
    } catch (_) {
      // Keep default settings on read error
    }
  }

  Future<void> update(TouchpadSettings Function(TouchpadSettings current) updateFn) async {
    final next = updateFn(state);
    state = next;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey, next.toJson());
    } catch (_) {
      // Ignore write error
    }
  }

  Future<void> reset() async {
    const next = TouchpadSettings();
    state = next;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_prefsKey);
    } catch (_) {
      // Ignore write error
    }
  }
}

final touchpadSettingsProvider =
    NotifierProvider<TouchpadSettingsNotifier, TouchpadSettings>(
  TouchpadSettingsNotifier.new,
);
