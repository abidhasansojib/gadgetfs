import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/touchpad_settings.dart';
import '../providers/touchpad_providers.dart';

class TouchpadSettingsSheet extends ConsumerWidget {
  const TouchpadSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const TouchpadSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(touchpadSettingsProvider);
    final notifier = ref.read(touchpadSettingsProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.tune, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Touchpad Settings',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => notifier.reset(),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reset'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  // Sensitivity
                  Text(
                    'Pointer Sensitivity: ${settings.sensitivity.toStringAsFixed(1)}x',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Slider(
                    value: settings.sensitivity,
                    min: 0.5,
                    max: 4.0,
                    divisions: 35,
                    label: '${settings.sensitivity.toStringAsFixed(1)}x',
                    onChanged: (v) => notifier.update((s) => s.copyWith(sensitivity: v)),
                  ),

                  // Acceleration
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cursor Acceleration'),
                    subtitle: const Text(
                        'Boosts cursor speed on fast swipes while keeping small movements precise'),
                    value: settings.acceleration,
                    onChanged: (v) => notifier.update((s) => s.copyWith(acceleration: v)),
                  ),
                  const SizedBox(height: 12),

                  // Scroll Sensitivity
                  Text(
                    'Scroll Sensitivity: ${settings.scrollSensitivity.toStringAsFixed(1)}x',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Slider(
                    value: settings.scrollSensitivity,
                    min: 0.4,
                    max: 3.0,
                    divisions: 26,
                    label: '${settings.scrollSensitivity.toStringAsFixed(1)}x',
                    onChanged: (v) => notifier.update((s) => s.copyWith(scrollSensitivity: v)),
                  ),

                  // Natural Scroll
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Natural Scrolling'),
                    subtitle: const Text(
                        'Content moves in the same direction as your fingers'),
                    value: settings.naturalScroll,
                    onChanged: (v) => notifier.update((s) => s.copyWith(naturalScroll: v)),
                  ),
                  const Divider(height: 24),

                  Text(
                    'Gestures',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tap to Click'),
                    subtitle: const Text('Single finger quick tap sends Left Click'),
                    value: settings.tapToClick,
                    onChanged: (v) => notifier.update((s) => s.copyWith(tapToClick: v)),
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Double-Tap Drag'),
                    subtitle: const Text(
                        'Tap once then tap and hold to drag windows or select text'),
                    value: settings.doubleTapDrag,
                    onChanged: (v) => notifier.update((s) => s.copyWith(doubleTapDrag: v)),
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Two-Finger Tap Right Click'),
                    subtitle: const Text('Tap with two fingers simultaneously for Right Click'),
                    value: settings.twoFingerTapRightClick,
                    onChanged: (v) =>
                        notifier.update((s) => s.copyWith(twoFingerTapRightClick: v)),
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Three-Finger Tap Middle Click'),
                    subtitle: const Text('Tap with three fingers for Middle Click'),
                    value: settings.threeFingerTapMiddleClick,
                    onChanged: (v) =>
                        notifier.update((s) => s.copyWith(threeFingerTapMiddleClick: v)),
                  ),

                  const Divider(height: 24),
                  Text(
                    'Interface & Feedback',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Haptic Feedback'),
                    subtitle: const Text('Vibrations on clicks, taps, and scroll wheel clicks'),
                    value: settings.hapticFeedback,
                    onChanged: (v) => notifier.update((s) => s.copyWith(hapticFeedback: v)),
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show Edge Scroll Strip'),
                    subtitle: const Text(
                        'Dedicated vertical scroll bar on the right edge of the trackpad'),
                    value: settings.showScrollStrip,
                    onChanged: (v) => notifier.update((s) => s.copyWith(showScrollStrip: v)),
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show Touch Points'),
                    subtitle: const Text('Display visual halos under touching fingers'),
                    value: settings.showTouchPoints,
                    onChanged: (v) => notifier.update((s) => s.copyWith(showTouchPoints: v)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
