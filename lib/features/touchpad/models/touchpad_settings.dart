import 'dart:convert';

class TouchpadSettings {
  final double sensitivity;
  final bool acceleration;
  final double accelerationFactor;
  final double scrollSensitivity;
  final bool naturalScroll;
  final bool tapToClick;
  final bool doubleTapDrag;
  final bool twoFingerTapRightClick;
  final bool threeFingerTapMiddleClick;
  final bool hapticFeedback;
  final bool showScrollStrip;
  final bool showTouchPoints;

  const TouchpadSettings({
    this.sensitivity = 1.8,
    this.acceleration = true,
    this.accelerationFactor = 1.2,
    this.scrollSensitivity = 1.2,
    this.naturalScroll = true,
    this.tapToClick = true,
    this.doubleTapDrag = true,
    this.twoFingerTapRightClick = true,
    this.threeFingerTapMiddleClick = true,
    this.hapticFeedback = true,
    this.showScrollStrip = true,
    this.showTouchPoints = true,
  });

  TouchpadSettings copyWith({
    double? sensitivity,
    bool? acceleration,
    double? accelerationFactor,
    double? scrollSensitivity,
    bool? naturalScroll,
    bool? tapToClick,
    bool? doubleTapDrag,
    bool? twoFingerTapRightClick,
    bool? threeFingerTapMiddleClick,
    bool? hapticFeedback,
    bool? showScrollStrip,
    bool? showTouchPoints,
  }) {
    return TouchpadSettings(
      sensitivity: sensitivity ?? this.sensitivity,
      acceleration: acceleration ?? this.acceleration,
      accelerationFactor: accelerationFactor ?? this.accelerationFactor,
      scrollSensitivity: scrollSensitivity ?? this.scrollSensitivity,
      naturalScroll: naturalScroll ?? this.naturalScroll,
      tapToClick: tapToClick ?? this.tapToClick,
      doubleTapDrag: doubleTapDrag ?? this.doubleTapDrag,
      twoFingerTapRightClick:
          twoFingerTapRightClick ?? this.twoFingerTapRightClick,
      threeFingerTapMiddleClick:
          threeFingerTapMiddleClick ?? this.threeFingerTapMiddleClick,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      showScrollStrip: showScrollStrip ?? this.showScrollStrip,
      showTouchPoints: showTouchPoints ?? this.showTouchPoints,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sensitivity': sensitivity,
      'acceleration': acceleration,
      'accelerationFactor': accelerationFactor,
      'scrollSensitivity': scrollSensitivity,
      'naturalScroll': naturalScroll,
      'tapToClick': tapToClick,
      'doubleTapDrag': doubleTapDrag,
      'twoFingerTapRightClick': twoFingerTapRightClick,
      'threeFingerTapMiddleClick': threeFingerTapMiddleClick,
      'hapticFeedback': hapticFeedback,
      'showScrollStrip': showScrollStrip,
      'showTouchPoints': showTouchPoints,
    };
  }

  factory TouchpadSettings.fromMap(Map<String, dynamic> map) {
    return TouchpadSettings(
      sensitivity: (map['sensitivity'] as num?)?.toDouble() ?? 1.8,
      acceleration: map['acceleration'] as bool? ?? true,
      accelerationFactor:
          (map['accelerationFactor'] as num?)?.toDouble() ?? 1.2,
      scrollSensitivity:
          (map['scrollSensitivity'] as num?)?.toDouble() ?? 1.2,
      naturalScroll: map['naturalScroll'] as bool? ?? true,
      tapToClick: map['tapToClick'] as bool? ?? true,
      doubleTapDrag: map['doubleTapDrag'] as bool? ?? true,
      twoFingerTapRightClick: map['twoFingerTapRightClick'] as bool? ?? true,
      threeFingerTapMiddleClick:
          map['threeFingerTapMiddleClick'] as bool? ?? true,
      hapticFeedback: map['hapticFeedback'] as bool? ?? true,
      showScrollStrip: map['showScrollStrip'] as bool? ?? true,
      showTouchPoints: map['showTouchPoints'] as bool? ?? true,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory TouchpadSettings.fromJson(String source) =>
      TouchpadSettings.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
