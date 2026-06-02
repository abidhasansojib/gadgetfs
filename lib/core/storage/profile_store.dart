import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/gadget_profile.dart';

class ProfileStore {
  static const _fileName = 'profiles.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<GadgetProfile>> loadProfiles() async {
    final f = await _file();
    if (!await f.exists()) {
      final defaults = _defaultProfiles();
      await saveProfiles(defaults);
      return defaults;
    }
    final raw = await f.readAsString();
    if (raw.trim().isEmpty) return _defaultProfiles();
    return GadgetProfile.decodeList(raw);
  }

  Future<void> saveProfiles(List<GadgetProfile> profiles) async {
    final f = await _file();
    await f.writeAsString(GadgetProfile.encodeList(profiles));
  }

  List<GadgetProfile> _defaultProfiles() {
    return [
      GadgetProfile.create(name: 'Mouse', roleType: GadgetRoleType.mouse, description: 'Boot mouse (relative)'),
      GadgetProfile.create(name: 'Keyboard', roleType: GadgetRoleType.keyboard, description: 'Boot keyboard'),
      GadgetProfile.create(name: 'Composite', roleType: GadgetRoleType.composite, description: 'Keyboard + mouse'),
    ];
  }
}
