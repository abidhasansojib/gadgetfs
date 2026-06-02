import 'dart:async';

import 'package:flutter/services.dart';

import '../models/gadget_profile.dart';
import '../models/gadget_status.dart';

class LogLine {
  final DateTime ts;
  final String tag;
  final String message;
  final String level;

  const LogLine({
    required this.ts,
    required this.tag,
    required this.message,
    required this.level,
  });

  factory LogLine.fromMap(Map<dynamic, dynamic> map) {
    return LogLine(
      ts: DateTime.tryParse(map['ts']?.toString() ?? '') ?? DateTime.now(),
      tag: map['tag']?.toString() ?? 'log',
      message: map['message']?.toString() ?? '',
      level: map['level']?.toString() ?? 'I',
    );
  }

  factory LogLine.fromEvent(dynamic event) {
    if (event is Map) {
      return LogLine.fromMap(event);
    }

    if (event is String) {
      final now = DateTime.now();
      final line = event.trimRight();

      // Expected: "HH:mm:ss.SSS [I] [tag] message"
      final firstSpace = line.indexOf(' ');
      if (firstSpace > 0) {
        final timePart = line.substring(0, firstSpace);
        DateTime ts = now;

        final tParts = timePart.split(':');
        if (tParts.length == 3 && tParts[2].contains('.')) {
          final secMs = tParts[2].split('.');
          final h = int.tryParse(tParts[0]);
          final m = int.tryParse(tParts[1]);
          final s = int.tryParse(secMs[0]);
          final ms = int.tryParse(secMs[1]);
          if (h != null && m != null && s != null && ms != null) {
            ts = DateTime(now.year, now.month, now.day, h, m, s, ms);
          }
        }

        int idx = firstSpace + 1;
        String level = 'I';
        String tag = 'log';
        String message = line.substring(firstSpace + 1);

        final lb1 = line.indexOf('[', idx);
        final rb1 = lb1 >= 0 ? line.indexOf(']', lb1 + 1) : -1;
        final lb2 = rb1 >= 0 ? line.indexOf('[', rb1 + 1) : -1;
        final rb2 = lb2 >= 0 ? line.indexOf(']', lb2 + 1) : -1;

        if (lb1 >= 0 && rb1 > lb1 && lb2 >= 0 && rb2 > lb2) {
          final lvl = line.substring(lb1 + 1, rb1).trim();
          if (lvl.isNotEmpty) {
            level = lvl.length > 1 ? lvl.substring(0, 1).toUpperCase() : lvl.toUpperCase();
          }
          tag = line.substring(lb2 + 1, rb2).trim();

          final after = rb2 + 1;
          if (after < line.length) {
            message = line.substring(after).trimLeft();
          } else {
            message = '';
          }
        }

        return LogLine(ts: ts, tag: tag, message: message, level: level);
      }

      return LogLine(ts: now, tag: 'log', message: line, level: 'I');
    }

    return LogLine(
      ts: DateTime.now(),
      tag: 'log',
      message: event?.toString() ?? '',
      level: 'I',
    );
  }

  @override
  String toString() => '[${ts.toIso8601String()}][$level][$tag] $message';
}

/// Public contract used by UI and Riverpod providers.
abstract class GadgetBackend {
  Future<GadgetStatus> getStatus();
  Future<GadgetStatus> refreshStatus();
  Future<Map<String, dynamic>> getDiagnostics();

  Stream<GadgetStatus> statusStream();
  Stream<LogLine> logStream();

  Future<bool> hasRoot();
  Future<bool> isSupported();
  Future<List<String>> listUdcs();

  Future<void> activateProfile(GadgetProfile profile);
  Future<void> deactivate();
  Future<void> panicStop();

  Future<void> testMouseMove({
    required int dx,
    required int dy,
    int wheel = 0,
    int buttons = 0,
  });

  Future<void> testKeyboardKey(String key);
  Future<void> testCtrlAltDel();
}

/// Default backend implementation backed by Android platform channels.
class MethodChannelGadgetBackend implements GadgetBackend {
  MethodChannelGadgetBackend();

  // Must match Android MainActivity.kt channel names.
  static const MethodChannel _methods = MethodChannel('org.kaijinlab.gadgetfs/gadget');
  static const EventChannel _statusEvents = EventChannel('org.kaijinlab.gadgetfs/gadget_status');
  static const EventChannel _logEvents = EventChannel('org.kaijinlab.gadgetfs/gadget_logs');

  Stream<GadgetStatus>? _statusStream;
  Stream<LogLine>? _logStream;

  @override
  Future<GadgetStatus> getStatus() async {
    final map = await _methods.invokeMethod<Map>('getStatus');
    return map == null ? GadgetStatus.empty : GadgetStatus.fromMap(map);
  }

  // UI-friendly alias used by diagnostics screen.
  @override
  Future<GadgetStatus> refreshStatus() => getStatus();

  @override
  Future<Map<String, dynamic>> getDiagnostics() async {
    final map = await _methods.invokeMethod<Map>('getDiagnostics');
    if (map == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(map);
  }

  @override
  Stream<GadgetStatus> statusStream() {
    _statusStream ??= (() async* {
      // Provide a first value so UI doesn't wait forever if no native events are emitted.
      try {
        yield await getStatus();
      } catch (_) {
        // Ignore; stream will still receive future native events.
      }

      yield* _statusEvents.receiveBroadcastStream().map((event) {
        final m = event as Map;
        return GadgetStatus.fromMap(m);
      });
    })().asBroadcastStream();

    return _statusStream!;
  }

  @override
  Stream<LogLine> logStream() {
    _logStream ??= _logEvents
        .receiveBroadcastStream()
        .map((event) => LogLine.fromEvent(event))
        .asBroadcastStream();
    return _logStream!;
  }

  @override
  Future<bool> hasRoot() async {
    // Android side exposes checkRoot(). Keep this alias for UI consistency.
    final ok = await _methods.invokeMethod<bool>('checkRoot');
    return ok ?? false;
  }

  @override
  Future<bool> isSupported() async {
    // Android side exposes checkSupport(). Keep this alias for UI consistency.
    final ok = await _methods.invokeMethod<bool>('checkSupport');
    return ok ?? false;
  }

  @override
  Future<List<String>> listUdcs() async {
    final list = await _methods.invokeMethod<List>('listUdcs');
    return (list ?? const []).map((e) => e.toString()).toList();
  }

  @override
  Future<void> activateProfile(GadgetProfile profile) async {
    // Android expects the profile map as top-level arguments.
    await _methods.invokeMethod<void>('activateProfile', profile.toJson());
  }

  @override
  Future<void> deactivate() async {
    await _methods.invokeMethod<void>('deactivate');
  }

  @override
  Future<void> panicStop() async {
    await _methods.invokeMethod<void>('panicStop');
  }

  @override
  Future<void> testMouseMove({
    required int dx,
    required int dy,
    int wheel = 0,
    int buttons = 0,
  }) async {
    await _methods.invokeMethod<void>('testMouseMove', {
      'dx': dx,
      'dy': dy,
      'wheel': wheel,
      'buttons': buttons,
    });
  }

  @override
  Future<void> testKeyboardKey(String key) async {
    // Kept for backwards compatibility with earlier UI.
    await _methods.invokeMethod<void>('testKeyboardKey', {'key': key});
  }

  @override
  Future<void> testCtrlAltDel() async {
    await _methods.invokeMethod<void>('testCtrlAltDel');
  }
}
