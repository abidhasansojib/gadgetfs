enum RoleType {
  mouse,
  keyboard,
  composite,
}

extension RoleTypeX on RoleType {
  String get label {
    switch (this) {
      case RoleType.mouse:
        return 'Mouse';
      case RoleType.keyboard:
        return 'Keyboard';
      case RoleType.composite:
        return 'Composite (Keyboard + Mouse)';
    }
  }

  String get id => name;

  static RoleType fromId(String id) {
    return RoleType.values.firstWhere(
      (e) => e.name == id,
      orElse: () => RoleType.mouse,
    );
  }
}
