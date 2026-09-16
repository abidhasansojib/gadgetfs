import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/backend/gadget_backend.dart';

class TouchpadController extends ChangeNotifier {
  final GadgetBackend backend;

  TouchpadController({required this.backend});

  int _buttons = 0;
  bool _dragLock = false;

  int _accumDx = 0;
  int _accumDy = 0;
  int _accumWheel = 0;
  bool _isFlushing = false;
  bool _disposed = false;

  bool _isAutomatedTestRunning = false;
  String? _activeTestName;
  bool _cancelTestRequested = false;

  int get buttons => _buttons;
  bool get dragLock => _dragLock;
  int get effectiveButtons => _buttons | (_dragLock ? 1 : 0);
  bool get isLeftPressed => (effectiveButtons & 0x01) != 0;
  bool get isRightPressed => (effectiveButtons & 0x02) != 0;
  bool get isMiddlePressed => (effectiveButtons & 0x04) != 0;
  bool get isAutomatedTestRunning => _isAutomatedTestRunning;
  String? get activeTestName => _activeTestName;

  /// Accumulate relative delta and trigger non-blocking flush loop.
  void sendDelta({int dx = 0, int dy = 0, int wheel = 0}) {
    if (_disposed) return;
    _accumDx += dx;
    _accumDy += dy;
    _accumWheel += wheel;

    if (!_isFlushing) {
      _isFlushing = true;
      unawaited(_runFlushLoop());
    }
  }

  Future<void> _runFlushLoop() async {
    while (!_disposed &&
        (_accumDx != 0 || _accumDy != 0 || _accumWheel != 0)) {
      final sendDx = _accumDx.clamp(-127, 127);
      final sendDy = _accumDy.clamp(-127, 127);
      final sendWheel = _accumWheel.clamp(-127, 127);

      _accumDx -= sendDx;
      _accumDy -= sendDy;
      _accumWheel -= sendWheel;

      final currentBtns = effectiveButtons;

      try {
        await backend.testMouseMove(
          dx: sendDx,
          dy: sendDy,
          wheel: sendWheel,
          buttons: currentBtns,
        );
      } catch (_) {
        // Suppress failure during continuous movement; reported by status if inactive
      }

      if (_accumDx != 0 || _accumDy != 0 || _accumWheel != 0) {
        // Yield to prevent IPC flooding when handling large backlogs
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    _isFlushing = false;
  }

  /// Explicitly set button state (mask: 1=Left, 2=Right, 4=Middle).
  Future<void> setButton(int mask, bool down) async {
    if (_disposed) return;
    if (down) {
      _buttons |= mask;
    } else {
      _buttons &= ~mask;
    }
    notifyListeners();

    try {
      await backend.testMouseMove(
        dx: 0,
        dy: 0,
        wheel: 0,
        buttons: effectiveButtons,
      );
    } catch (_) {}
  }

  /// Toggle drag lock (locks Left Click active).
  Future<void> toggleDragLock() async {
    if (_disposed) return;
    _dragLock = !_dragLock;
    notifyListeners();

    try {
      await backend.testMouseMove(
        dx: 0,
        dy: 0,
        wheel: 0,
        buttons: effectiveButtons,
      );
    } catch (_) {}
  }

  /// Tap a button (down -> delay -> up).
  Future<void> tapButton(int mask, {int durationMs = 40}) async {
    if (_disposed) return;
    await setButton(mask, true);
    await Future<void>.delayed(Duration(milliseconds: durationMs));
    if (_disposed) return;
    await setButton(mask, false);
  }

  Future<void> leftClick() => tapButton(1);
  Future<void> rightClick() => tapButton(2);
  Future<void> middleClick() => tapButton(4);

  Future<void> doubleClick() async {
    if (_disposed) return;
    await leftClick();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (_disposed) return;
    await leftClick();
  }

  /// Send immediate discrete relative nudge.
  Future<void> nudge(int dx, int dy) async {
    if (_disposed) return;
    try {
      await backend.testMouseMove(
        dx: dx.clamp(-127, 127),
        dy: dy.clamp(-127, 127),
        wheel: 0,
        buttons: effectiveButtons,
      );
    } catch (_) {}
  }

  /// Send immediate discrete wheel scroll.
  Future<void> scroll(int wheel) async {
    if (_disposed) return;
    try {
      await backend.testMouseMove(
        dx: 0,
        dy: 0,
        wheel: wheel.clamp(-127, 127),
        buttons: effectiveButtons,
      );
    } catch (_) {}
  }

  /// Cancel any currently active automated test.
  void cancelAutomatedTest() {
    _cancelTestRequested = true;
  }

  /// Automated Circle Test: draws an orbital path to test host tracking.
  Future<void> runCircleTest({int radius = 60, int steps = 48}) async {
    if (_isAutomatedTestRunning || _disposed) return;
    _isAutomatedTestRunning = true;
    _activeTestName = 'Circle';
    _cancelTestRequested = false;
    notifyListeners();

    try {
      double lastX = radius.toDouble();
      double lastY = 0;
      for (int i = 1; i <= steps; i++) {
        if (_cancelTestRequested || _disposed) break;
        final angle = (2 * math.pi * i) / steps;
        final curX = radius * math.cos(angle);
        final curY = radius * math.sin(angle);

        final dx = (curX - lastX).round();
        final dy = (curY - lastY).round();
        lastX = curX;
        lastY = curY;

        await backend.testMouseMove(
          dx: dx,
          dy: dy,
          wheel: 0,
          buttons: effectiveButtons,
        );
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    } catch (_) {
    } finally {
      _isAutomatedTestRunning = false;
      _activeTestName = null;
      _cancelTestRequested = false;
      notifyListeners();
    }
  }

  /// Automated Square Test: moves right, down, left, up.
  Future<void> runSquareTest({int side = 80, int segments = 8}) async {
    if (_isAutomatedTestRunning || _disposed) return;
    _isAutomatedTestRunning = true;
    _activeTestName = 'Square';
    _cancelTestRequested = false;
    notifyListeners();

    final step = side ~/ segments;
    try {
      final directions = [
        Offset(step.toDouble(), 0), // Right
        Offset(0, step.toDouble()), // Down
        Offset(-step.toDouble(), 0), // Left
        Offset(0, -step.toDouble()), // Up
      ];

      for (final dir in directions) {
        for (int i = 0; i < segments; i++) {
          if (_cancelTestRequested || _disposed) break;
          await backend.testMouseMove(
            dx: dir.dx.toInt(),
            dy: dir.dy.toInt(),
            wheel: 0,
            buttons: effectiveButtons,
          );
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        if (_cancelTestRequested || _disposed) break;
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    } catch (_) {
    } finally {
      _isAutomatedTestRunning = false;
      _activeTestName = null;
      _cancelTestRequested = false;
      notifyListeners();
    }
  }

  /// Automated Jiggle Test: quick back-and-forth shake.
  Future<void> runJiggleTest({int iterations = 6, int amplitude = 40}) async {
    if (_isAutomatedTestRunning || _disposed) return;
    _isAutomatedTestRunning = true;
    _activeTestName = 'Jiggle';
    _cancelTestRequested = false;
    notifyListeners();

    try {
      for (int i = 0; i < iterations; i++) {
        if (_cancelTestRequested || _disposed) break;
        final dir = (i % 2 == 0) ? amplitude : -amplitude;
        await backend.testMouseMove(
          dx: dir,
          dy: 0,
          wheel: 0,
          buttons: effectiveButtons,
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    } catch (_) {
    } finally {
      _isAutomatedTestRunning = false;
      _activeTestName = null;
      _cancelTestRequested = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTestRequested = true;
    super.dispose();
  }
}
