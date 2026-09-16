import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/backend/providers.dart';
import '../../core/models/gadget_status.dart';
import 'providers/touchpad_providers.dart';
import 'services/touchpad_controller.dart';
import 'widgets/touchpad_buttons_bar.dart';
import 'widgets/touchpad_settings_sheet.dart';
import 'widgets/touchpad_surface.dart';

class TouchpadScreen extends ConsumerStatefulWidget {
  const TouchpadScreen({super.key});

  @override
  ConsumerState<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends ConsumerState<TouchpadScreen> {
  TouchpadController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final backend = ref.read(gadgetBackendProvider);
      _controller = TouchpadController(backend: backend);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _showGestureGuide() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.touch_app),
              SizedBox(width: 10),
              Text('Touchpad Gestures'),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _GestureGuideRow(
                  icon: Icons.pan_tool_alt,
                  title: '1 Finger Move',
                  desc: 'Smooth relative cursor movement with acceleration.',
                ),
                Divider(),
                _GestureGuideRow(
                  icon: Icons.touch_app,
                  title: '1-Finger Tap',
                  desc: 'Tap briefly to send Left Click.',
                ),
                Divider(),
                _GestureGuideRow(
                  icon: Icons.swipe_vertical,
                  title: 'Double-Tap & Drag',
                  desc: 'Tap once, then tap-and-hold to drag windows or select.',
                ),
                Divider(),
                _GestureGuideRow(
                  icon: Icons.swap_vert,
                  title: '2-Finger Scroll',
                  desc: 'Drag two fingers vertically for mouse wheel scrolling.',
                ),
                Divider(),
                _GestureGuideRow(
                  icon: Icons.menu_open,
                  title: '2-Finger Tap',
                  desc: 'Tap with two fingers simultaneously for Right Click.',
                ),
                Divider(),
                _GestureGuideRow(
                  icon: Icons.adjust,
                  title: '3-Finger Tap',
                  desc: 'Tap with three fingers for Middle Click.',
                ),
                Divider(),
                _GestureGuideRow(
                  icon: Icons.straighten,
                  title: 'Edge Scroll Strip',
                  desc: 'Slide one finger on the right edge to scroll quickly.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(gadgetStatusStreamProvider);
    final settings = ref.watch(touchpadSettingsProvider);
    final cs = Theme.of(context).colorScheme;
    final controller = _controller;

    final status = statusAsync.value ?? GadgetStatus.empty;
    final isActive = status.isActive;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('USB Touchpad'),
            Text(
              isActive ? 'Active • Connected' : 'Device Idle',
              style: TextStyle(
                fontSize: 12,
                color: isActive ? Colors.green : cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Gesture Guide',
            icon: const Icon(Icons.help_outline),
            onPressed: _showGestureGuide,
          ),
          IconButton(
            tooltip: 'Touchpad Settings',
            icon: const Icon(Icons.tune),
            onPressed: () => TouchpadSettingsSheet.show(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Status warning banner if idle
            if (!isActive)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, size: 20, color: cs.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Gadget is idle. Activate a mouse or composite profile to control the host.',
                        style: TextStyle(
                          color: cs.onErrorContainer,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: cs.onErrorContainer,
                      ),
                      onPressed: () => context.go('/'),
                      child: const Text('Dashboard'),
                    ),
                  ],
                ),
              ),

            // Top utility bar (Drag lock & scroll controls)
            if (controller != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final isLocked = controller.dragLock;
                    return Row(
                      children: [
                        FilterChip(
                          selected: isLocked,
                          avatar: Icon(
                            isLocked ? Icons.lock : Icons.lock_open,
                            size: 16,
                            color: isLocked
                                ? cs.onPrimaryContainer
                                : cs.onSurfaceVariant,
                          ),
                          label: Text(
                            isLocked ? 'Drag Lock (Active)' : 'Drag Lock',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onSelected: (_) => controller.toggleDragLock(),
                        ),
                        const Spacer(),
                        IconButton.filledTonal(
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Wheel Up',
                          icon: const Icon(Icons.arrow_drop_up),
                          onPressed: () => controller.scroll(3),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Wheel Down',
                          icon: const Icon(Icons.arrow_drop_down),
                          onPressed: () => controller.scroll(-3),
                        ),
                      ],
                    );
                  },
                ),
              ),

            // Touchpad Surface (Maximizes remaining screen area)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                child: controller != null
                    ? TouchpadSurface(
                        controller: controller,
                        settings: settings,
                        isFullscreen: true,
                        onSettingsTap: () =>
                            TouchpadSettingsSheet.show(context),
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),

            // Physical Mouse Buttons Bar
            if (controller != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: TouchpadButtonsBar(
                  controller: controller,
                  hapticFeedback: settings.hapticFeedback,
                  height: 62,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GestureGuideRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _GestureGuideRow({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
