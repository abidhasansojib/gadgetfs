import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend/providers.dart';

final diagnosticsControllerProvider =
    AsyncNotifierProvider<DiagnosticsController, Map<String, dynamic>?>(
  DiagnosticsController.new,
);

class DiagnosticsController extends AsyncNotifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() {
    return null;
  }

  Future<Map<String, dynamic>> run() async {
    state = const AsyncLoading();
    final backend = ref.read(gadgetBackendProvider);
    try {
      final result = await backend.getDiagnostics();
      state = AsyncData(result);
      return result;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}
