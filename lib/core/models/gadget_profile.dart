import 'dart:convert';

import 'package:uuid/uuid.dart';

enum GadgetRoleType { mouse, keyboard, composite }

String gadgetRoleTypeToString(GadgetRoleType t) => switch (t) {
      GadgetRoleType.mouse => 'mouse',
      GadgetRoleType.keyboard => 'keyboard',
      GadgetRoleType.composite => 'composite',
    };

GadgetRoleType gadgetRoleTypeFromString(String s) => switch (s) {
      'mouse' => GadgetRoleType.mouse,
      'keyboard' => GadgetRoleType.keyboard,
      'composite' => GadgetRoleType.composite,
      _ => GadgetRoleType.mouse,
    };

class GadgetProfile {
  final String id;
  final String name;
  final String description;
  final GadgetRoleType roleType;

  /// USB identification (optional, defaults reasonable for Linux gadget).
  final int vendorId;
  final int productId;
  final String manufacturer;
  final String product;
  final String serialNumber;

  final bool activateOnOpen;

  const GadgetProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.roleType,
    required this.vendorId,
    required this.productId,
    required this.manufacturer,
    required this.product,
    required this.serialNumber,
    required this.activateOnOpen,
  });

  factory GadgetProfile.create({
    required String name,
    required GadgetRoleType roleType,
    String description = '',
  }) {
    const uuid = Uuid();
    return GadgetProfile(
      id: uuid.v4(),
      name: name.trim().isEmpty ? 'New Profile' : name.trim(),
      description: description,
      roleType: roleType,
      vendorId: 0x1d6b,
      productId: 0x0104,
      manufacturer: 'KaijinLab',
      product: 'GadgetFS',
      serialNumber: '0001',
      activateOnOpen: false,
    );
  }

  GadgetProfile copyWith({
    String? id,
    String? name,
    String? description,
    GadgetRoleType? roleType,
    int? vendorId,
    int? productId,
    String? manufacturer,
    String? product,
    String? serialNumber,
    bool? activateOnOpen,
  }) {
    return GadgetProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      roleType: roleType ?? this.roleType,
      vendorId: vendorId ?? this.vendorId,
      productId: productId ?? this.productId,
      manufacturer: manufacturer ?? this.manufacturer,
      product: product ?? this.product,
      serialNumber: serialNumber ?? this.serialNumber,
      activateOnOpen: activateOnOpen ?? this.activateOnOpen,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'roleType': gadgetRoleTypeToString(roleType),
        'vendorId': vendorId,
        'productId': productId,
        'manufacturer': manufacturer,
        'product': product,
        'serialNumber': serialNumber,
        'activateOnOpen': activateOnOpen,
      };

  factory GadgetProfile.fromJson(Map<String, dynamic> json) {
    return GadgetProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      roleType: gadgetRoleTypeFromString(json['roleType'] as String? ?? 'mouse'),
      vendorId: (json['vendorId'] as num?)?.toInt() ?? 0x1d6b,
      productId: (json['productId'] as num?)?.toInt() ?? 0x0104,
      manufacturer: json['manufacturer'] as String? ?? 'GadgetFS',
      product: json['product'] as String? ?? 'Gadget',
      serialNumber: json['serialNumber'] as String? ?? '0001',
      activateOnOpen: json['activateOnOpen'] as bool? ?? false,
    );
  }

  static List<GadgetProfile> decodeList(String raw) {
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(GadgetProfile.fromJson).toList(growable: false);
  }

  static String encodeList(List<GadgetProfile> profiles) {
    return jsonEncode(profiles.map((p) => p.toJson()).toList(growable: false));
  }
}
