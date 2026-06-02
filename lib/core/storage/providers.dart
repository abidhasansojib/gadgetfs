import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'; // <-- StateNotifier/StateNotifierProvider moved here in Riverpod 3
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gadget_profile.dart';
import 'profile_store.dart';

final profileStoreProvider = Provider<ProfileStore>((ref) => ProfileStore());

class ProfilesController extends AsyncNotifier<List<GadgetProfile>> {
  @override
  Future<List<GadgetProfile>> build() async {
    final store = ref.read(profileStoreProvider);
    return store.loadProfiles();
  }

  Future<void> upsert(GadgetProfile profile) async {
    // Riverpod 3: valueOrNull removed -> use value (nullable)
    final List<GadgetProfile> current = state.value ?? await future;

    final List<GadgetProfile> next = <GadgetProfile>[
      for (final p in current)
        if (p.id != profile.id) p,
      profile,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    state = AsyncData<List<GadgetProfile>>(next);
    await ref.read(profileStoreProvider).saveProfiles(next);
  }

  Future<void> delete(String id) async {
    final List<GadgetProfile> current = state.value ?? await future;

    final List<GadgetProfile> next =
        current.where((p) => p.id != id).toList(growable: false);

    state = AsyncData<List<GadgetProfile>>(next);
    await ref.read(profileStoreProvider).saveProfiles(next);
  }

  Future<GadgetProfile?> byId(String id) async {
    final List<GadgetProfile> current = state.value ?? await future;

    for (final p in current) {
      if (p.id == id) return p;
    }
    return null;
  }
}

final profilesProvider =
    AsyncNotifierProvider<ProfilesController, List<GadgetProfile>>(
  ProfilesController.new,
);

// Riverpod 3: StateNotifierProvider is legacy (imported from legacy.dart)
final selectedProfileIdProvider =
    StateNotifierProvider<SelectedProfileIdController, String?>(
  (ref) => SelectedProfileIdController(ref),
);

class SelectedProfileIdController extends StateNotifier<String?> {
  SelectedProfileIdController(this.ref) : super(null) {
    _init();
  }

  final Ref ref;
  static const String _key = 'selectedProfileId';

  Future<void> _init() async {
    final sp = await SharedPreferences.getInstance();
    state = sp.getString(_key);
  }

  Future<void> setSelected(String? id) async {
    state = id;
    final sp = await SharedPreferences.getInstance();
    if (id == null) {
      await sp.remove(_key);
    } else {
      await sp.setString(_key, id);
    }
  }
}
