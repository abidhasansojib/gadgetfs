import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gadget_providers.dart';

final logBufferProvider = StateNotifierProvider<LogBufferController, List<String>>((ref) {
  final ctrl = LogBufferController(maxLines: 2000);
  // Start listening to log stream.
  ref.listen<AsyncValue<String>>(gadgetLogsProvider, (prev, next) {
    next.whenData((line) {
      if (line.trim().isEmpty) return;
      ctrl.append(line);
    });
  });
  return ctrl;
});

class LogBufferController extends StateNotifier<List<String>> {
  LogBufferController({required this.maxLines}) : super(const <String>[]);
  final int maxLines;

  void append(String line) {
    final next = [...state, line];
    if (next.length > maxLines) {
      state = next.sublist(next.length - maxLines);
    } else {
      state = next;
    }
  }

  void clear() => state = const <String>[];
}
