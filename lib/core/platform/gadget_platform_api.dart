import 'dart:async';

import 'package:flutter/services.dart';

import '../models/gadget_profile.dart';
import '../models/gadget_status.dart';

class GadgetPlatformApi {
  static const _method = MethodChannel('org.kaijinlab.gadgetfs/gadget');
  static const _statusEvents = EventChannel('org.kaijinlab.gadgetfs/gadget_status');
  static const _logEvents = EventChannel('org.kaijinlab.gadgetfs/gadget_logs');

  Stream<GadgetStatus>? _statusStream;
  Stream<String>? _logStream;

  Future<GadgetStatus> getStatus() async {
    final map = await _method.invokeMethod<Map>('getStatus');
    if (map == null) return GadgetStatus.initial();
    return GadgetStatus.fromJson(map);
  }

  Stream<GadgetStatus> watchStatus() {
    _statusStream ??= _statusEvents.receiveBroadcastStream().map((event) {
      if (event is Map) return GadgetStatus.fromJson(event);
      return GadgetStatus.initial();
    });
    return _statusStream!;
  }

  Stream<String> watchLogs() {
    _logStream ??= _logEvents.receiveBroadcastStream().map((event) => event?.toString() ?? '');
    return _logStream!;
  }

  Future<bool> checkRoot() async {
    final v = await _method.invokeMethod<bool>('checkRoot');
    return v ?? false;
  }

  Future<bool> checkSupport() async {
    final v = await _method.invokeMethod<bool>('checkSupport');
    return v ?? false;
  }

  Future<List<String>> listUdcs() async {
    final v = await _method.invokeMethod<List>('listUdcs');
    return v?.map((e) => e.toString()).toList(growable: false) ?? const <String>[];
  }

  Future<void> activateProfile(GadgetProfile profile) async {
    await _method.invokeMethod('activateProfile', profile.toJson());
  }

  Future<void> deactivate() async {
    await _method.invokeMethod('deactivate');
  }

  Future<void> panicStop() async {
    await _method.invokeMethod('panicStop');
  }

  Future<void> testMouseMove({int dx = 20, int dy = 0, int wheel = 0, int buttons = 0}) async {
    await _method.invokeMethod('testMouseMove', {
      'dx': dx,
      'dy': dy,
      'wheel': wheel,
      'buttons': buttons,
    });
  }

  Future<void> testKeyboardKey(String key) async {
    await _method.invokeMethod('testKeyboardKey', {'key': key});
  }

  Future<void> testCtrlAltDel() async {
    await _method.invokeMethod('testCtrlAltDel');
  }
}
