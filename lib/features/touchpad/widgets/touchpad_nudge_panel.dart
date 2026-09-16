import 'package:flutter/material.dart';

import '../services/touchpad_controller.dart';

class TouchpadNudgePanel extends StatefulWidget {
  final TouchpadController controller;

  const TouchpadNudgePanel({super.key, required this.controller});

  @override
  State<TouchpadNudgePanel> createState() => _TouchpadNudgePanelState();
}

class _TouchpadNudgePanelState extends State<TouchpadNudgePanel> {
  int _stepSize = 25;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTesting = widget.controller.isAutomatedTestRunning;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step size selector
            Row(
              children: [
                Text(
                  'Nudge Step Size:',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1px')),
                    ButtonSegment(value: 5, label: Text('5px')),
                    ButtonSegment(value: 25, label: Text('25px')),
                    ButtonSegment(value: 100, label: Text('100px')),
                  ],
                  selected: {_stepSize},
                  onSelectionChanged: (set) {
                    if (set.isNotEmpty) setState(() => _stepSize = set.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // D-Pad and Scroll controls
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Directional D-Pad
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: 170,
                      height: 170,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Up
                          Positioned(
                            top: 0,
                            child: IconButton.filledTonal(
                              iconSize: 28,
                              tooltip: 'Nudge Up ($_stepSize px)',
                              icon: const Icon(Icons.arrow_drop_up),
                              onPressed: () =>
                                  widget.controller.nudge(0, -_stepSize),
                            ),
                          ),
                          // Down
                          Positioned(
                            bottom: 0,
                            child: IconButton.filledTonal(
                              iconSize: 28,
                              tooltip: 'Nudge Down ($_stepSize px)',
                              icon: const Icon(Icons.arrow_drop_down),
                              onPressed: () =>
                                  widget.controller.nudge(0, _stepSize),
                            ),
                          ),
                          // Left
                          Positioned(
                            left: 0,
                            child: IconButton.filledTonal(
                              iconSize: 28,
                              tooltip: 'Nudge Left ($_stepSize px)',
                              icon: const Icon(Icons.arrow_left),
                              onPressed: () =>
                                  widget.controller.nudge(-_stepSize, 0),
                            ),
                          ),
                          // Right
                          Positioned(
                            right: 0,
                            child: IconButton.filledTonal(
                              iconSize: 28,
                              tooltip: 'Nudge Right ($_stepSize px)',
                              icon: const Icon(Icons.arrow_right),
                              onPressed: () =>
                                  widget.controller.nudge(_stepSize, 0),
                            ),
                          ),
                          // Center Left Click
                          Center(
                            child: IconButton.filled(
                              iconSize: 22,
                              tooltip: 'Left Click',
                              icon: const Icon(Icons.touch_app),
                              onPressed: () => widget.controller.leftClick(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Vertical Wheel column
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Scroll',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 6),
                    FilledButton.tonalIcon(
                      onPressed: () => widget.controller.scroll(5),
                      icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                      label: const Text('+5'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => widget.controller.scroll(-5),
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                      label: const Text('-5'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Click action buttons
            Text(
              'Click Actions',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => widget.controller.leftClick(),
                  icon: const Icon(Icons.mouse, size: 18),
                  label: const Text('Left Click'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => widget.controller.doubleClick(),
                  icon: const Icon(Icons.touch_app, size: 18),
                  label: const Text('Double Click'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => widget.controller.rightClick(),
                  icon: const Icon(Icons.menu_open, size: 18),
                  label: const Text('Right Click'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => widget.controller.middleClick(),
                  icon: const Icon(Icons.adjust, size: 18),
                  label: const Text('Middle Click'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Automated Test Patterns
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_mode, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Automated Motion Verification',
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const Spacer(),
                      if (isTesting)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Automatically draws patterns with the host cursor to verify USB HID communication.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (isTesting)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Running ${widget.controller.activeTestName ?? ""} test…',
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              widget.controller.cancelAutomatedTest(),
                          icon: const Icon(Icons.stop, size: 16),
                          label: const Text('Stop'),
                        ),
                      ],
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => widget.controller.runCircleTest(),
                          icon: const Icon(Icons.circle_outlined, size: 18),
                          label: const Text('Circle Pattern'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => widget.controller.runSquareTest(),
                          icon: const Icon(Icons.crop_square, size: 18),
                          label: const Text('Square Pattern'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => widget.controller.runJiggleTest(),
                          icon: const Icon(Icons.vibration, size: 18),
                          label: const Text('Jiggle Test'),
                        ),
                      ],
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
