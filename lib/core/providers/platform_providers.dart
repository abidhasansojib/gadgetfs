import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/gadget_platform_api.dart';

final gadgetPlatformApiProvider = Provider<GadgetPlatformApi>((ref) {
  return GadgetPlatformApi();
});
