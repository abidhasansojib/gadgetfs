import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/touchpad_settings.dart';
import '../services/touchpad_controller.dart';

class _PointerRecord {
  final int id;
  Offset currentPos;
  Offset lastPos;
  final Offset startPos;
  final int startMs;
  int lastMs;

  _PointerRecord({
    required this.id,
    required this.currentPos,
    required this.lastPos,
    required this.startPos,
    required this.startMs,
    required this.lastMs,
  });
}

class TouchpadSurface extends StatefulWidget {
  final TouchpadController controller;
  final TouchpadSettings settings;
  final double? height;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onFullscreenTap;
  final bool isFullscreen;

  const TouchpadSurface({
    super.key,
    required this.controller,
    required this.settings,
    this.height,
    this.onSettingsTap,
    this.onFullscreenTap,
    this.isFullscreen = false,
  });

  @override
  State<TouchpadSurface> createState() => _TouchpadSurfaceState();
}

class _TouchpadSurfaceState extends State<TouchpadSurface> {
  final Map<int, _PointerRecord> _pointers = {};

  int? _scrollStripPointer;
  double _stripWheelAccum = 0.0;
  double _twoFingerWheelAccum = 0.0;
  double _fractionalDx = 0.0;
  double _fractionalDy = 0.0;
  double _smoothedVelocity = 0.0;

  bool _isDoubleTapDragging = false;
  int _lastTapUpTime = 0;
  Offset _lastTapUpPos = Offset.zero;

  int _twoFingerStartMs = 0;
  double _twoFingerMaxTravel = 0.0;

  int _threeFingerStartMs = 0;

  String? _gestureBadge;
  Timer? _badgeTimer;

  static const double _scrollStripWidth = 48.0;

  void _showBadge(String text) {
    _badgeTimer?.cancel();
    setState(() => _gestureBadge = text);
    _badgeTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _gestureBadge = null);
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final pos = event.localPosition;
    final isStripArea = widget.settings.showScrollStrip &&
        pos.dx >= (context.size?.width ?? 300) - _scrollStripWidth;

    if (isStripArea && _scrollStripPointer == null) {
      _scrollStripPointer = event.pointer;
      _stripWheelAccum = 0.0;
      if (widget.settings.hapticFeedback) HapticFeedback.selectionClick();
      _showBadge('Scroll Strip');
    }

    _pointers[event.pointer] = _PointerRecord(
      id: event.pointer,
      currentPos: pos,
      lastPos: pos,
      startPos: pos,
      startMs: now,
      lastMs: now,
    );

    if (_scrollStripPointer != event.pointer) {
      if (_pointers.length <= 1) {
        _fractionalDx = 0.0;
        _fractionalDy = 0.0;
        _smoothedVelocity = 0.0;
      }
      if (_pointers.length == 1) {
        // Check double-tap drag
        final isRecentTap = (now - _lastTapUpTime) < 280;
        final isNearLast = (pos - _lastTapUpPos).distance < 35;
        if (widget.settings.doubleTapDrag && isRecentTap && isNearLast) {
          _isDoubleTapDragging = true;
          widget.controller.setButton(1, true);
          if (widget.settings.hapticFeedback) HapticFeedback.lightImpact();
          _showBadge('Drag Mode (Hold L)');
        }
      } else if (_pointers.length == 2) {
        _twoFingerStartMs = now;
        _twoFingerMaxTravel = 0.0;
        _twoFingerWheelAccum = 0.0;
        _showBadge('2-Finger Scroll');
      } else if (_pointers.length == 3) {
        _threeFingerStartMs = now;
        _showBadge('3-Finger Tap');
      }
    }

    setState(() {});
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final record = _pointers[event.pointer];
    if (record == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final pos = event.localPosition;
    final delta = pos - record.lastPos;
    final dt = (now - record.lastMs).clamp(4, 100);

    record.lastPos = record.currentPos;
    record.currentPos = pos;
    record.lastMs = now;

    // Handle Scroll Strip pointer
    if (_scrollStripPointer == event.pointer) {
      final stripDeltaY = delta.dy;
      final factor = widget.settings.scrollSensitivity * 0.35;
      final wheelVal =
          (widget.settings.naturalScroll ? -stripDeltaY : stripDeltaY) * factor;

      _stripWheelAccum += wheelVal;
      if (_stripWheelAccum.abs() >= 1.0) {
        final ticks = _stripWheelAccum.truncate();
        _stripWheelAccum -= ticks;
        widget.controller.sendDelta(wheel: ticks);
        if (widget.settings.hapticFeedback) HapticFeedback.selectionClick();
      }
      setState(() {});
      return;
    }

    // Two finger scroll
    if (_pointers.length == 2) {
      final keys = _pointers.keys.toList();
      final p1 = _pointers[keys[0]];
      final p2 = _pointers[keys[1]];
      if (p1 != null && p2 != null) {
        final travel = (pos - record.startPos).distance;
        if (travel > _twoFingerMaxTravel) _twoFingerMaxTravel = travel;

        final dy = delta.dy;
        final factor = widget.settings.scrollSensitivity * 0.35;
        final wheelVal =
            (widget.settings.naturalScroll ? -dy : dy) * factor;

        _twoFingerWheelAccum += wheelVal;
        if (_twoFingerWheelAccum.abs() >= 1.0) {
          final ticks = _twoFingerWheelAccum.truncate();
          _twoFingerWheelAccum -= ticks;
          widget.controller.sendDelta(wheel: ticks);
          if (widget.settings.hapticFeedback) HapticFeedback.selectionClick();
        }
      }
      if (widget.settings.showTouchPoints) {
        setState(() {});
      }
      return;
    }

    // Single finger cursor movement
    if (_pointers.length == 1) {
      final mag = delta.distance;
      double mult = widget.settings.sensitivity;
      if (widget.settings.acceleration && mag > 0) {
        // Physical fingertip speed in px/ms (refresh rate independent)
        final speedPxPerMs = mag / dt;
        // Exponential moving average filter to smooth timestamp quantization
        _smoothedVelocity = _smoothedVelocity == 0.0
            ? speedPxPerMs
            : (_smoothedVelocity * 0.65 + speedPxPerMs * 0.35);
        final speedBonus = ((_smoothedVelocity - 0.25) / 0.5).clamp(0.0, 3.5);
        mult *= (1.0 + speedBonus * widget.settings.accelerationFactor * 0.45);
      }

      // High-precision sub-pixel accumulator eliminates micro-stutter and stickiness
      _fractionalDx += delta.dx * mult;
      _fractionalDy += delta.dy * mult;

      final dx = _fractionalDx.truncate();
      final dy = _fractionalDy.truncate();

      if (dx != 0 || dy != 0) {
        _fractionalDx -= dx;
        _fractionalDy -= dy;
        widget.controller.sendDelta(dx: dx, dy: dy);
      }
      if (widget.settings.showTouchPoints) {
        setState(() {});
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = _pointers[event.pointer];

    if (_scrollStripPointer == event.pointer) {
      _scrollStripPointer = null;
      _stripWheelAccum = 0.0;
    }

    if (record != null) {
      final duration = now - record.startMs;
      final distance = (event.localPosition - record.startPos).distance;

      if (_isDoubleTapDragging) {
        _isDoubleTapDragging = false;
        widget.controller.setButton(1, false);
        if (widget.settings.hapticFeedback) HapticFeedback.lightImpact();
        _showBadge('Drag Released');
      } else if (_pointers.length == 1) {
        // 1-finger tap -> Left Click
        if (duration < 240 && distance < 14 && widget.settings.tapToClick) {
          widget.controller.leftClick();
          _lastTapUpTime = now;
          _lastTapUpPos = event.localPosition;
          _showBadge('Left Click');
          if (widget.settings.hapticFeedback) HapticFeedback.lightImpact();
        } else {
          _lastTapUpTime = 0;
        }
      } else if (_pointers.length == 2 &&
          widget.settings.twoFingerTapRightClick) {
        // 2-finger tap -> Right Click
        final twoFingerDuration = now - _twoFingerStartMs;
        if (twoFingerDuration < 260 && _twoFingerMaxTravel < 16) {
          widget.controller.rightClick();
          _showBadge('Right Click');
          if (widget.settings.hapticFeedback) HapticFeedback.mediumImpact();
        }
      } else if (_pointers.length == 3 &&
          widget.settings.threeFingerTapMiddleClick) {
        // 3-finger tap -> Middle Click
        final threeFingerDuration = now - _threeFingerStartMs;
        if (threeFingerDuration < 260) {
          widget.controller.middleClick();
          _showBadge('Middle Click');
          if (widget.settings.hapticFeedback) HapticFeedback.heavyImpact();
        }
      }
    }

    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) {
      _fractionalDx = 0.0;
      _fractionalDy = 0.0;
      _smoothedVelocity = 0.0;
    }
    setState(() {});
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_scrollStripPointer == event.pointer) {
      _scrollStripPointer = null;
    }
    if (_isDoubleTapDragging) {
      _isDoubleTapDragging = false;
      widget.controller.setButton(1, false);
    }
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) {
      _fractionalDx = 0.0;
      _fractionalDy = 0.0;
      _smoothedVelocity = 0.0;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget surface = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background canvas with grid dots & touch ripples
          CustomPaint(
            painter: _TouchpadCanvasPainter(
              colorScheme: cs,
              pointers: widget.settings.showTouchPoints
                  ? _pointers.values.map((p) => p.currentPos).toList()
                  : const [],
              showScrollStrip: widget.settings.showScrollStrip,
              scrollStripWidth: _scrollStripWidth,
              isStripActive: _scrollStripPointer != null,
            ),
            child: const SizedBox.expand(),
          ),

          // Scroll strip icon overlays
          if (widget.settings.showScrollStrip)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _scrollStripWidth,
              child: IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.keyboard_arrow_up,
                        size: 20,
                        color: cs.onSurface.withOpacity(0.35),
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        Icons.unfold_more,
                        size: 18,
                        color: cs.onSurface.withOpacity(0.45),
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: cs.onSurface.withOpacity(0.35),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Gesture feedback badge
          if (_gestureBadge != null)
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _gestureBadge != null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.inverseSurface.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _gestureBadge!,
                      style: TextStyle(
                        color: cs.onInverseSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Action overlays (Settings / Fullscreen if provided)
          Positioned(
            bottom: 8,
            left: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onSettingsTap != null)
                  IconButton.filledTonal(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Touchpad Settings',
                    icon: const Icon(Icons.tune),
                    onPressed: widget.onSettingsTap,
                  ),
                if (widget.onFullscreenTap != null) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    tooltip: widget.isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                    icon: Icon(widget.isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen),
                    onPressed: widget.onFullscreenTap,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.6),
          width: 1.2,
        ),
      ),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: surface,
      ),
    );
  }
}

class _TouchpadCanvasPainter extends CustomPainter {
  final ColorScheme colorScheme;
  final List<Offset> pointers;
  final bool showScrollStrip;
  final double scrollStripWidth;
  final bool isStripActive;

  _TouchpadCanvasPainter({
    required this.colorScheme,
    required this.pointers,
    required this.showScrollStrip,
    required this.scrollStripWidth,
    required this.isStripActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = colorScheme.onSurface.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    // Grid dots
    const step = 28.0;
    final maxX = showScrollStrip ? size.width - scrollStripWidth : size.width;
    for (double x = step; x < maxX; x += step) {
      for (double y = step; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }

    // Scroll strip separator and track
    if (showScrollStrip) {
      final stripX = size.width - scrollStripWidth;
      final linePaint = Paint()
        ..color = colorScheme.outlineVariant.withOpacity(0.4)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(stripX, 0), Offset(stripX, size.height), linePaint);

      if (isStripActive) {
        final highlight = Paint()
          ..color = colorScheme.primary.withOpacity(0.12)
          ..style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromLTWH(stripX, 0, scrollStripWidth, size.height),
          highlight,
        );
      }
    }

    // Pointer rings
    final ringPaint = Paint()
      ..color = colorScheme.primary.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final glowPaint = Paint()
      ..color = colorScheme.primary.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    for (final p in pointers) {
      canvas.drawCircle(p, 26, glowPaint);
      canvas.drawCircle(p, 20, ringPaint);
      canvas.drawCircle(p, 3.5, Paint()..color = colorScheme.primary);
    }
  }

  @override
  bool shouldRepaint(covariant _TouchpadCanvasPainter oldDelegate) {
    return oldDelegate.pointers != pointers ||
        oldDelegate.isStripActive != isStripActive ||
        oldDelegate.colorScheme != colorScheme;
  }
}
