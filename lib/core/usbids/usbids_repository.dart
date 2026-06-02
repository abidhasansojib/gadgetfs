import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'usbids_models.dart';

class UsbIdsRepository {
  static const String assetPath = 'assets/db/usbids.sqlite';
  static const String dbFileName = 'usbids.sqlite';

  Database? _db;

  String fmtVidHex(int vid) => vid.toRadixString(16).padLeft(4, '0').toUpperCase();
  String fmtPidHex(int pid) => pid.toRadixString(16).padLeft(4, '0').toUpperCase();

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, dbFileName);

    final exists = await databaseExists(dbPath);
    if (!exists) {
      await _copyAssetDbTo(dbPath);
    }

    _db = await openDatabase(dbPath, readOnly: true);
    return _db!;
  }

  Future<void> _copyAssetDbTo(String dbPath) async {
    // Ensure parent dir exists.
    await Directory(p.dirname(dbPath)).create(recursive: true);

    // Load bundled asset bytes.
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    // Write to db path.
    final file = File(dbPath);
    if (await file.exists()) {
      // If something existed but sqflite didn't recognize it, replace.
      await file.delete();
    }
    await file.writeAsBytes(bytes, flush: true);
  }

  /// Search vendors by name OR by numeric VID (hex/dec).
  Future<List<UsbVendor>> searchVendors(String query, {int limit = 50}) async {
    final db = await _open();

    final q = query.trim();
    final parsed = _parseAnyNumber(q);
    final like = '%${_escapeLike(q)}%';

    final whereParts = <String>[];
    final args = <Object?>[];

    if (q.isNotEmpty) {
      whereParts.add("(name LIKE ? ESCAPE '\\')");
      args.add(like);
    }
    if (parsed != null) {
      whereParts.add('(vid = ?)');
      args.add(parsed);
    }

    final where = whereParts.isEmpty ? null : whereParts.join(' OR ');

    final rows = await db.query(
      'vendors',
      columns: ['vid', 'name'],
      where: where,
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );

    return rows
        .map(
          (r) => UsbVendor(
            vid: (r['vid'] as int),
            name: (r['name'] as String),
          ),
        )
        .toList(growable: false);
  }

  /// List/search products for a specific vendor.
  /// Query matches product name OR PID (hex/dec).
  Future<List<UsbProduct>> searchProductsForVendor({
    required int vid,
    String query = '',
    int limit = 100,
  }) async {
    final db = await _open();

    final q = query.trim();
    final like = '%${_escapeLike(q)}%';
    final parsed = _parseAnyNumber(q);

    final whereParts = <String>['vid = ?'];
    final args = <Object?>[vid];

    if (q.isNotEmpty) {
      whereParts.add("(name LIKE ? ESCAPE '\\' OR pid = ?)");
      args.add(like);
      args.add(parsed ?? -1);
    }

    final rows = await db.query(
      'products',
      columns: ['vid', 'pid', 'name'],
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );

    return rows
        .map(
          (r) => UsbProduct(
            vid: (r['vid'] as int),
            pid: (r['pid'] as int),
            name: (r['name'] as String),
          ),
        )
        .toList(growable: false);
  }

  /// Global search by product name (and optionally vendor name) OR numeric VID/PID.
  /// Returns hits with vendor+product names and vid/pid.
  Future<List<UsbProductHit>> searchProductsGlobal(String query, {int limit = 50}) async {
    final db = await _open();

    final q = query.trim();
    if (q.isEmpty) return const [];

    final vidPid = _parseVidPidPair(q);
    final parsed = _parseAnyNumber(q);

    // If user typed "1d6b:0104" -> exact match.
    if (vidPid != null) {
      final rows = await db.rawQuery(
        '''
SELECT p.vid as vid, p.pid as pid, v.name as vendor_name, p.name as product_name
FROM products p
JOIN vendors v ON v.vid = p.vid
WHERE p.vid = ? AND p.pid = ?
LIMIT ?
''',
        [vidPid.$1, vidPid.$2, limit],
      );

      return rows
          .map(
            (r) => UsbProductHit(
              vid: r['vid'] as int,
              pid: r['pid'] as int,
              vendorName: r['vendor_name'] as String,
              productName: r['product_name'] as String,
            ),
          )
          .toList(growable: false);
    }

    final like = '%${_escapeLike(q)}%';

    final args = <Object?>[];
    final whereParts = <String>[];

    // Name matches
    whereParts.add("(p.name LIKE ? ESCAPE '\\' OR v.name LIKE ? ESCAPE '\\')");
    args.add(like);
    args.add(like);

    // Numeric matches (if user typed a number or hex)
    if (parsed != null) {
      whereParts.add('(p.pid = ? OR p.vid = ?)');
      args.add(parsed);
      args.add(parsed);
    }

    args.add(limit);

    final rows = await db.rawQuery(
      '''
SELECT p.vid as vid, p.pid as pid, v.name as vendor_name, p.name as product_name
FROM products p
JOIN vendors v ON v.vid = p.vid
WHERE ${whereParts.join(' OR ')}
ORDER BY v.name COLLATE NOCASE ASC, p.name COLLATE NOCASE ASC
LIMIT ?
''',
      args,
    );

    return rows
        .map(
          (r) => UsbProductHit(
            vid: r['vid'] as int,
            pid: r['pid'] as int,
            vendorName: r['vendor_name'] as String,
            productName: r['product_name'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<String?> lookupVendorName(int vid) async {
    final db = await _open();
    final rows = await db.query(
      'vendors',
      columns: ['name'],
      where: 'vid = ?',
      whereArgs: [vid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['name'] as String?;
  }

  Future<String?> lookupProductName(int vid, int pid) async {
    final db = await _open();
    final rows = await db.query(
      'products',
      columns: ['name'],
      where: 'vid = ? AND pid = ?',
      whereArgs: [vid, pid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['name'] as String?;
  }

  /* ---------- helpers ---------- */

  int? _parseAnyNumber(String input) {
    final t = input.trim().toLowerCase();
    if (t.isEmpty) return null;

    // Try "0x1234"
    if (t.startsWith('0x')) {
      final h = t.substring(2);
      if (RegExp(r'^[0-9a-f]{1,8}$').hasMatch(h)) {
        return int.tryParse(h, radix: 16);
      }
      return null;
    }

    // Try pure hex (<= 8 chars) but only if it contains a-f to avoid ambiguity with decimal-only strings.
    if (RegExp(r'^[0-9a-f]{1,8}$').hasMatch(t) && RegExp(r'[a-f]').hasMatch(t)) {
      return int.tryParse(t, radix: 16);
    }

    // Try decimal
    if (RegExp(r'^\d+$').hasMatch(t)) {
      return int.tryParse(t);
    }

    return null;
    }

  (int, int)? _parseVidPidPair(String input) {
    final t = input.trim().toLowerCase();
    if (t.isEmpty) return null;

    // Accept "0x1d6b:0x0104" or "1d6b:0104" or "7531/260"
    final parts = t.split(RegExp(r'[:/ ]+')).where((e) => e.isNotEmpty).toList();
    if (parts.length != 2) return null;

    final a = _parseAnyNumber(parts[0]);
    final b = _parseAnyNumber(parts[1]);
    if (a == null || b == null) return null;

    // Keep only low 16 bits for safety (VID/PID are 16-bit)
    return (a & 0xFFFF, b & 0xFFFF);
  }

  String _escapeLike(String s) {
    // Escape LIKE wildcards with backslash for SQLITE: % and _
    // Also escape backslash itself.
    return s.replaceAll('\\', '\\\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
  }
}
