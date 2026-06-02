import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/gadget_profile.dart';

class ProfilesRepository {
  static const _fileName = 'profiles.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<GadgetProfile>> loadAll() async {
    try {
      final f = await _file();
      if (!await f.exists()) return <GadgetProfile>[];
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return <GadgetProfile>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <GadgetProfile>[];
      return decoded
          .whereType<Map>()
          .map((e) => GadgetProfile.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return <GadgetProfile>[];
    }
  }

  Future<void> saveAll(List<GadgetProfile> profiles) async {
    final f = await _file();
    final raw = jsonEncode(profiles.map((e) => e.toJson()).toList(growable: false));
    await f.writeAsString(raw, flush: true);
  }
}
