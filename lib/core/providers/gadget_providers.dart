import '../platform/gadget_platform_api.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gadget_profile.dart';
import '../models/gadget_status.dart';
import 'platform_providers.dart';
import 'profiles_providers.dart';

final gadgetStatusProvider = StreamProvider<GadgetStatus>((ref) async* {
  final api = ref.watch(gadgetPlatformApiProvider);
  // Emit initial snapshot
  yield await api.getStatus();
  // Then stream updates
  yield* api.watchStatus();
});

final gadgetLogsProvider = StreamProvider<String>((ref) {
  final api = ref.watch(gadgetPlatformApiProvider);
  return api.watchLogs();
});

final gadgetActionsProvider = Provider<GadgetActions>((ref) {
  final api = ref.watch(gadgetPlatformApiProvider);
  return GadgetActions(ref, api);
});

class GadgetActions {
  GadgetActions(this._ref, this._api);
  final Ref _ref;
  final GadgetPlatformApi _api;

  Future<void> activateSelected() async {
    final profiles = _ref.read(profilesControllerProvider);
    final selectedId = _ref.read(selectedProfileIdProvider);
    if (selectedId == null) {
      throw StateError('No profile selected');
    }
    final profile = profiles.firstWhere((p) => p.id == selectedId);
    await _api.activateProfile(profile);
  }

  Future<void> deactivate() async => _api.deactivate();
  Future<void> panicStop() async => _api.panicStop();

  Future<void> testMouseMove() async => _api.testMouseMove(dx: 20, dy: 0);
  Future<void> testKey(String key) async => _api.testKeyboardKey(key);
  Future<void> testCtrlAltDel() async => _api.testCtrlAltDel();
}
