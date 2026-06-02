import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/gadget_profile.dart';
import '../persistence/profiles_repository.dart';

final profilesRepositoryProvider = Provider<ProfilesRepository>((ref) => ProfilesRepository());

final profilesControllerProvider = StateNotifierProvider<ProfilesController, List<GadgetProfile>>((ref) {
  final repo = ref.watch(profilesRepositoryProvider);
  return ProfilesController(repo);
});

class ProfilesController extends StateNotifier<List<GadgetProfile>> {
  ProfilesController(this._repo) : super(const <GadgetProfile>[]);

  final ProfilesRepository _repo;

  Future<void> load() async {
    final loaded = await _repo.loadAll();
    state = loaded;
  }

  Future<void> upsert(GadgetProfile profile) async {
    final idx = state.indexWhere((p) => p.id == profile.id);
    final next = [...state];
    if (idx >= 0) {
      next[idx] = profile;
    } else {
      next.add(profile);
    }
    next.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = next;
    await _repo.saveAll(state);
  }

  Future<void> delete(String id) async {
    state = state.where((p) => p.id != id).toList(growable: false);
    await _repo.saveAll(state);
  }

  GadgetProfile? byId(String id) => state.where((p) => p.id == id).cast<GadgetProfile?>().firstWhere((e) => e != null, orElse: () => null);

  Future<GadgetProfile> createDefault() async {
    final id = const Uuid().v4();
    final profile = GadgetProfile.defaults(id: id);
    await upsert(profile);
    return profile;
  }
}

const _kSelectedProfileId = 'selected_profile_id';

final selectedProfileIdProvider = StateNotifierProvider<SelectedProfileController, String?>((ref) {
  return SelectedProfileController();
});

class SelectedProfileController extends StateNotifier<String?> {
  SelectedProfileController() : super(null);

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    state = sp.getString(_kSelectedProfileId);
  }

  Future<void> set(String? id) async {
    final sp = await SharedPreferences.getInstance();
    if (id == null) {
      await sp.remove(_kSelectedProfileId);
      state = null;
      return;
    }
    await sp.setString(_kSelectedProfileId, id);
    state = id;
  }
}

