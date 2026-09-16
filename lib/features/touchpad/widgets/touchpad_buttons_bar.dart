import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/touchpad_controller.dart';

class TouchpadButtonsBar extends StatelessWidget {
  final TouchpadController controller;
  final bool hapticFeedback;
  final double height;

  const TouchpadButtonsBar({
    super.key,
    required this.controller,
    this.hapticFeedback = true,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isLeft = controller.isLeftPressed;
        final isMiddle = controller.isMiddlePressed;
        final isRight = controller.isRightPressed;

        return SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Click Button
              Expanded(
                flex: 5,
                child: _MouseButton(
                  label: 'LEFT',
                  icon: Icons.mouse,
                  isPressed: isLeft,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                  ),
                  onDown: () {
                    if (hapticFeedback) HapticFeedback.lightImpact();
                    controller.setButton(1, true);
                  },
                  onUp: () {
                    if (hapticFeedback) HapticFeedback.lightImpact();
                    controller.setButton(1, false);
                  },
                ),
              ),
              const SizedBox(width: 2),

              // Middle Click Button
              Expanded(
                flex: 3,
                child: _MouseButton(
                  label: 'MID',
                  icon: Icons.adjust,
                  isPressed: isMiddle,
                  borderRadius: BorderRadius.zero,
                  onDown: () {
                    if (hapticFeedback) HapticFeedback.mediumImpact();
                    controller.setButton(4, true);
                  },
                  onUp: () {
                    if (hapticFeedback) HapticFeedback.lightImpact();
                    controller.setButton(4, false);
                  },
                ),
              ),
              const SizedBox(width: 2),

              // Right Click Button
              Expanded(
                flex: 5,
                child: _MouseButton(
                  label: 'RIGHT',
                  icon: Icons.menu_open,
                  isPressed: isRight,
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(16),
                  ),
                  onDown: () {
                    if (hapticFeedback) HapticFeedback.lightImpact();
                    controller.setButton(2, true);
                  },
                  onUp: () {
                    if (hapticFeedback) HapticFeedback.lightImpact();
                    controller.setButton(2, false);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MouseButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPressed;
  final BorderRadius borderRadius;
  final VoidCallback onDown;
  final VoidCallback onUp;

  const _MouseButton({
    required this.label,
    required this.icon,
    required this.isPressed,
    required this.borderRadius,
    required this.onDown,
    required this.onUp,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bgColor = isPressed
        ? cs.primaryContainer
        : cs.surfaceContainerHigh;
    final fgColor = isPressed
        ? cs.onPrimaryContainer
        : cs.onSurfaceVariant;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: borderRadius,
          border: Border.all(
            color: isPressed ? cs.primary : cs.outlineVariant.withOpacity(0.5),
            width: isPressed ? 1.5 : 1.0,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fgColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fgColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
