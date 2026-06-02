import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kDynamicColorsPrefKey = 'use_dynamic_colors_v1';

final dynamicColorsProvider = StateNotifierProvider<DynamicColorsController, bool>((ref) {
  return DynamicColorsController();
});

class DynamicColorsController extends StateNotifier<bool> {
  DynamicColorsController() : super(_defaultEnabled) {
    _load();
  }

  static bool get _defaultEnabled => Platform.isAndroid;

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getBool(_kDynamicColorsPrefKey);
      state = v ?? _defaultEnabled;
    } catch (_) {
      state = _defaultEnabled;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kDynamicColorsPrefKey, enabled);
    } catch (_) {}
  }
}
