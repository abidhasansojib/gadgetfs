import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gadget_status.dart';
import 'gadget_backend.dart';

final gadgetBackendProvider = Provider<GadgetBackend>((ref) {
  return MethodChannelGadgetBackend();
});

final gadgetStatusStreamProvider = StreamProvider<GadgetStatus>((ref) {
  final backend = ref.watch(gadgetBackendProvider);
  return backend.statusStream();
});

final gadgetLogsStreamProvider = StreamProvider<LogLine>((ref) {
  final backend = ref.watch(gadgetBackendProvider);
  return backend.logStream();
});
