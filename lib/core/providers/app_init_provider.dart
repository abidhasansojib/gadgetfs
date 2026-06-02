import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gadget_providers.dart';
import 'platform_providers.dart';
import 'profiles_providers.dart';

final appInitProvider = FutureProvider<void>((ref) async {
  final profilesCtrl = ref.read(profilesControllerProvider.notifier);
  final selectedCtrl = ref.read(selectedProfileIdProvider.notifier);
  await Future.wait([
    profilesCtrl.load(),
    selectedCtrl.load(),
  ]);

  // Ensure at least one profile exists.
  final profiles = ref.read(profilesControllerProvider);
  if (profiles.isEmpty) {
    final p = await profilesCtrl.createDefault();
    await selectedCtrl.set(p.id);
  } else {
    // If selected profile missing, select first.
    final selected = ref.read(selectedProfileIdProvider);
    if (selected == null || !profiles.any((p) => p.id == selected)) {
      await selectedCtrl.set(profiles.first.id);
    }
  }

  // Optional: activate selected profile on open if it is configured to do so.
  final selectedId = ref.read(selectedProfileIdProvider);
  if (selectedId == null) return;

  final updatedProfiles = ref.read(profilesControllerProvider);
  final selectedProfile = updatedProfiles.firstWhere((p) => p.id == selectedId);

  if (!selectedProfile.activateOnOpen) return;

  // Defer activation slightly to allow UI to render.
  scheduleMicrotask(() async {
    final api = ref.read(gadgetPlatformApiProvider);
    final status = await api.getStatus();
    if (status.state == 'ACTIVE' || status.state == 'ACTIVATING') return;
    // Only attempt if root + support look good.
    final okRoot = await api.checkRoot();
    final okSupport = await api.checkSupport();
    if (okRoot && okSupport) {
      try {
        await api.activateProfile(selectedProfile);
      } catch (_) {
        // Avoid throwing during init.
      }
    }
  });

  // Keep provider alive.
  ref.watch(gadgetStatusProvider);
});
