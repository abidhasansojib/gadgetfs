import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'usbids_repository.dart';

final usbIdsRepositoryProvider = Provider<UsbIdsRepository>((ref) {
  return UsbIdsRepository();
});
