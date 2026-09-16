import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/gadget_backend.dart';
import '../providers/touchpad_providers.dart';
import '../services/touchpad_controller.dart';
import 'touchpad_buttons_bar.dart';
import 'touchpad_nudge_panel.dart';
import 'touchpad_settings_sheet.dart';
import 'touchpad_surface.dart';

class TouchpadCard extends ConsumerStatefulWidget {
  final GadgetBackend backend;

  const TouchpadCard({super.key, required this.backend});

  @override
  ConsumerState<TouchpadCard> createState() => _TouchpadCardState();
}

class _TouchpadCardState extends ConsumerState<TouchpadCard> {
  late final TouchpadController _controller;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = TouchpadController(backend: widget.backend);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(touchpadSettingsProvider);
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Icon(Icons.mouse, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mouse & Touchpad Test',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        'Relative cursor control, gestures & clicks',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  iconSize: 20,
                  tooltip: 'Touchpad Settings',
                  icon: const Icon(Icons.tune),
                  onPressed: () => TouchpadSettingsSheet.show(context),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  iconSize: 20,
                  tooltip: 'Open Fullscreen Touchpad',
                  icon: const Icon(Icons.fullscreen),
                  onPressed: () => context.go('/touchpad'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Segmented mode switcher
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.touch_app, size: 16),
                    label: Text('Touchpad'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.tune, size: 16),
                    label: Text('Nudge & Tests'),
                  ),
                ],
                selected: {_selectedTabIndex},
                onSelectionChanged: (set) {
                  if (set.isNotEmpty) {
                    setState(() => _selectedTabIndex = set.first);
                  }
                },
              ),
            ),
            const SizedBox(height: 14),

            // Tab 0: Touchpad mode
            if (_selectedTabIndex == 0) ...[
              // Quick utility strip (Drag Lock, Wheel, Fullscreen)
              ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  final isDragLocked = _controller.dragLock;
                  return Row(
                    children: [
                      FilterChip(
                        selected: isDragLocked,
                        avatar: Icon(
                          isDragLocked ? Icons.lock : Icons.lock_open,
                          size: 16,
                          color: isDragLocked
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant,
                        ),
                        label: Text(isDragLocked ? 'Drag Locked' : 'Drag Lock'),
                        onSelected: (_) => _controller.toggleDragLock(),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Wheel Up',
                        icon: const Icon(Icons.arrow_drop_up),
                        onPressed: () => _controller.scroll(3),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Wheel Down',
                        icon: const Icon(Icons.arrow_drop_down),
                        onPressed: () => _controller.scroll(-3),
                      ),
                      const SizedBox(width: 6),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => context.go('/touchpad'),
                        icon: const Icon(Icons.open_in_full, size: 16),
                        label: const Text('Expand'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),

              // Touchpad Surface
              AspectRatio(
                aspectRatio: 1.25,
                child: TouchpadSurface(
                  controller: _controller,
                  settings: settings,
                  onSettingsTap: () => TouchpadSettingsSheet.show(context),
                  onFullscreenTap: () => context.go('/touchpad'),
                ),
              ),
              const SizedBox(height: 6),

              // Physical Mouse Buttons
              TouchpadButtonsBar(
                controller: _controller,
                hapticFeedback: settings.hapticFeedback,
                height: 48,
              ),
              const SizedBox(height: 8),

              // Gestures hint footer
              Text(
                '1-finger tap: Left click • 2-finger drag: Scroll • 2-finger tap: Right click • 3-finger tap: Mid click',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant.withOpacity(0.8),
                      fontSize: 11,
                    ),
              ),
            ] else ...[
              // Tab 1: Nudge & Tests
              TouchpadNudgePanel(controller: _controller),
            ],
          ],
        ),
      ),
    );
  }
}
