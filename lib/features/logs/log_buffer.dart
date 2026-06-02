import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend/providers.dart';
import '../../core/backend/gadget_backend.dart';

class LogBufferController extends Notifier<List<LogLine>> {
  StreamSubscription<LogLine>? _sub;

  @override
  List<LogLine> build() {
    _sub?.cancel();
    _sub = ref.read(gadgetBackendProvider).logStream().listen((line) {
      final next = [...state, line];
      // Keep memory bounded
      if (next.length > 1500) {
        state = next.sublist(next.length - 1200);
      } else {
        state = next;
      }
    });
    ref.onDispose(() => _sub?.cancel());
    return const [];
  }

  void clear() => state = const [];
}

final logBufferProvider = NotifierProvider<LogBufferController, List<LogLine>>(
  LogBufferController.new,
);
