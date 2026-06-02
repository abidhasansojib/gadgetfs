class GadgetStatus {
  final bool rootAvailable;
  final bool supportAvailable;
  final List<String> udcList;
  final String state; // IDLE | ACTIVATING | ACTIVE | ERROR
  final String? activeProfileId;
  final String? message;

  const GadgetStatus({
    required this.rootAvailable,
    required this.supportAvailable,
    required this.udcList,
    required this.state,
    required this.activeProfileId,
    required this.message,
  });

  bool get isActive => state == 'ACTIVE';
  bool get isIdle => state == 'IDLE';

  factory GadgetStatus.fromMap(Map<dynamic, dynamic> map) {
    return GadgetStatus(
      rootAvailable: map['rootAvailable'] as bool? ?? false,
      supportAvailable: map['supportAvailable'] as bool? ?? false,
      udcList: (map['udcList'] as List? ?? const []).map((e) => e.toString()).toList(),
      state: map['state']?.toString() ?? 'IDLE',
      activeProfileId: map['activeProfileId']?.toString(),
      message: map['message']?.toString(),
    );
  }

  /// Backwards-compatible alias used by the platform API.
  factory GadgetStatus.fromJson(Map<dynamic, dynamic> json) => GadgetStatus.fromMap(json);

  /// Default initial status.
  static GadgetStatus initial() => empty;

  static const empty = GadgetStatus(
    rootAvailable: false,
    supportAvailable: false,
    udcList: [],
    state: 'IDLE',
    activeProfileId: null,
    message: null,
  );

  /// JSON-serializable representation (handy for diagnostics export).
  Map<String, dynamic> toJson() => <String, dynamic>{
        'rootAvailable': rootAvailable,
        'supportAvailable': supportAvailable,
        'udcList': udcList,
        'state': state,
        'activeProfileId': activeProfileId,
        'message': message,
      };
}
