import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../db/local_db.dart';

/// One vitrine somebody chose not to see any more (« Masquer cette
/// vitrine », batch 150): its address and its name as it was then, so the
/// list of hidden ones can name it without asking the server.
@immutable
class HiddenVitrine {
  const HiddenVitrine({required this.slug, required this.name, this.at});

  final String slug;
  final String name;
  final DateTime? at;

  Map<String, Object?> toJson() =>
      {'slug': slug, 'name': name, if (at != null) 'at': at!.toUtc().toIso8601String()};

  static HiddenVitrine? fromJson(Object? j) {
    if (j is! Map) return null;
    final slug = '${j['slug'] ?? ''}'.trim();
    if (slug.isEmpty) return null;
    final name = '${j['name'] ?? ''}'.trim();
    return HiddenVitrine(
      slug: slug,
      name: name.isEmpty ? slug : name,
      at: DateTime.tryParse('${j['at']}')?.toLocal(),
    );
  }
}

/// The vitrines hidden on this device (App Store guideline 1.2: a way to
/// block content one finds abusive). A hidden vitrine leaves the street —
/// the list, the map, « À la une », the search, the paid spots — and its
/// link says « Vous avez masqué cette vitrine » with the way back.
///
/// Kept in the device preferences (LocalDb), as the street's last look
/// is (street_cache.dart): no account needed, nothing sent anywhere. There
/// is no per-shopper place for it on the server (113's shopper_settings
/// holds the city, the payment and the news switch only), so it stays on
/// the phone — a new phone starts with nothing hidden.
///
/// Every read and write is quiet when the storage fails: the street still
/// shows, it simply forgets.
class HiddenVitrines {
  HiddenVitrines(this._db);

  final LocalDb _db;

  static const key = 'street.hidden';

  /// Ticks on every change on this device, so a page already open (the
  /// street under the vitrine, the profile) reads the list again.
  static final changes = ValueNotifier<int>(0);

  /// What was last read or written for each device store, kept in memory
  /// so a page opened after the first read knows at once, before any wait.
  static final _known = Expando<Set<String>>('hidden vitrines');

  /// The hidden slugs as last known in this run, or null before the first
  /// read: a page asks [slugs] meanwhile and never waits on it to draw.
  Set<String>? get known => _known[_db];

  Future<List<HiddenVitrine>> list() async {
    try {
      final raw = await _db.readPref(key);
      final json = raw == null ? null : jsonDecode(raw);
      final rows = json is List
          ? [for (final j in json) ?HiddenVitrine.fromJson(j)]
          : const <HiddenVitrine>[];
      final first = _known[_db] == null;
      _known[_db] = {for (final h in rows) h.slug};
      // The first read of the run (main.dart's): a page already drawn
      // hears it.
      if (first && rows.isNotEmpty) changes.value++;
      return rows;
    } catch (_) {
      return const [];
    }
  }

  Future<Set<String>> slugs() async => {for (final h in await list()) h.slug};

  Future<bool> contains(String slug) async => (await slugs()).contains(slug);

  /// Hides [slug]; [name] is how the list will call it. True once kept.
  Future<bool> hide(String slug, {required String name}) async {
    final now = [
      HiddenVitrine(slug: slug, name: name, at: DateTime.now()),
      for (final h in await list())
        if (h.slug != slug) h,
    ];
    return _write(now);
  }

  /// Shows [slug] again. True once kept.
  Future<bool> show(String slug) async =>
      _write([for (final h in await list()) if (h.slug != slug) h]);

  Future<bool> _write(List<HiddenVitrine> rows) async {
    try {
      await _db.writePref(
          key, rows.isEmpty ? null : jsonEncode([for (final h in rows) h.toJson()]));
      _known[_db] = {for (final h in rows) h.slug};
      changes.value++;
      return true;
    } catch (_) {
      return false;
    }
  }
}
