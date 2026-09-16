import 'package:flutter_test/flutter_test.dart';
import 'package:gadgetfs/features/touchpad/models/touchpad_settings.dart';

void main() {
  test('TouchpadSettings default values and serialization', () {
    const settings = TouchpadSettings();
    expect(settings.sensitivity, 1.8);
    expect(settings.acceleration, true);
    expect(settings.tapToClick, true);
    expect(settings.doubleTapDrag, true);
    expect(settings.naturalScroll, true);

    final map = settings.toMap();
    final restored = TouchpadSettings.fromMap(map);
    expect(restored.sensitivity, settings.sensitivity);
    expect(restored.acceleration, settings.acceleration);
  });
}
