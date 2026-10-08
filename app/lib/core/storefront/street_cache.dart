import 'dart:convert';

import '../db/local_db.dart';

/// The street's last look, kept on the device: what the directory and the
/// vitrines this phone opened said the last time there was signal.
///
/// The owner asked for Mara to « load easily even the internet is bad ».
/// On a market's 3G a vitrine is four round trips after the app has
/// started — five seconds of skeleton every time, and with no signal at all
/// a page saying the network failed. With this the page shows what it
/// showed last time at once, and the fresh answer replaces it when it
/// comes; with no signal at all, the last look stays, said as such.
///
/// Only what the street shows anybody: the public answers of the
/// storefront functions (052–110), kept as the server sent them, so a
/// field added later is kept too. Nothing a shopper typed, nothing of an
/// account. Ordering still goes to the server, which checks the shelf and
/// the prices then (place_order) — a kept price is never what is charged.
///
/// Kept in the device preferences (LocalDb), the last [vitrines] vitrines
/// opened, the oldest dropped first.
class StreetCache {
  StreetCache(this._db, {this.vitrines = 12});

  final LocalDb _db;

  /// How many vitrines are kept.
  final int vitrines;

  static const _prefix = 'street.kept.';
  static const _indexKey = 'street.kept.vitrines';

  /// Keeps the server's [rows] under [key]. For a vitrine's keys
  /// (`storefront:<slug>`, `items:<slug>`) the slug joins the recent ones.
  Future<void> put(String key, Object? rows) async {
    try {
      await _db.writePref(
        '$_prefix$key',
        jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), 'rows': rows}),
      );
      final slug = _slugOf(key);
      if (slug != null) await _touch(slug);
    } catch (_) {
      // A phone that cannot keep the street still shows it online.
    }
  }

  /// What was kept under [key], or null.
  Future<KeptRows?> get(String key) async {
    try {
      final raw = await _db.readPref('$_prefix$key');
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final at = DateTime.tryParse('${json['at']}');
      return KeptRows(rows: json['rows'], at: at?.toLocal());
    } catch (_) {
      return null;
    }
  }

  static String? _slugOf(String key) {
    for (final p in const ['storefront:', 'items:']) {
      if (key.startsWith(p)) return key.substring(p.length);
    }
    return null;
  }

  Future<void> _touch(String slug) async {
    final raw = await _db.readPref(_indexKey);
    var recent = <String>[];
    try {
      if (raw != null) recent = List<String>.from(jsonDecode(raw) as List);
    } catch (_) {}
    recent
      ..remove(slug)
      ..insert(0, slug);
    while (recent.length > vitrines) {
      final gone = recent.removeLast();
      await _db.writePref('${_prefix}storefront:$gone', null);
      await _db.writePref('${_prefix}items:$gone', null);
    }
    await _db.writePref(_indexKey, jsonEncode(recent));
  }
}

/// One kept answer: the rows as the server sent them, and when.
class KeptRows {
  const KeptRows({required this.rows, this.at});

  final Object? rows;
  final DateTime? at;

  List<dynamic> get list => rows is List ? rows as List : const [];
}
