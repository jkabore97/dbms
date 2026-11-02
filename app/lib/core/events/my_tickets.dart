import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/local_db.dart';
import 'browser_tickets_stub.dart' if (dart.library.js_interop) 'browser_tickets_web.dart';
import 'tickets_repository.dart';

/// The buyer's tickets on this phone (ticket sales, part 4): the requests
/// kept here — « Garder mes billets dans Marakaj », or those this browser
/// booked on marakaj.com — and, signed in, those of the account. Their
/// last look is kept, so the QR codes open at the door with no signal.
///
/// No account is needed: a request's id is its key, as on the ticket page
/// the buyer was sent (event_ticket_status, open to the street).
class MyTicketsStore {
  MyTicketsStore(this._client, this._db);

  final SupabaseClient? _client;
  final LocalDb? _db;

  /// Whether the last [refresh] reached the server.
  bool reached = false;

  static const _idsKey = 'tickets.ids';
  static const _keptKey = 'tickets.kept';

  Future<List<String>> _ids() async {
    final ids = <String>{};
    try {
      final raw = await _db?.readPref(_idsKey);
      if (raw != null) ids.addAll([for (final x in jsonDecode(raw) as List) '$x']);
    } catch (_) {}
    ids.addAll(browserTicketIds());
    return ids.toList();
  }

  /// A request kept on this phone, and on the account when signed in.
  Future<void> keep(String requestId) async {
    final ids = {...await _ids(), requestId.toLowerCase()};
    try {
      await _db?.writePref(_idsKey, jsonEncode(ids.toList()));
    } catch (_) {}
    final c = _client;
    if (c != null && c.auth.currentUser != null) {
      try {
        await c.rpc('event_ticket_claim', params: {'p_id': requestId});
      } catch (_) {}
    }
  }

  /// The last look, with no network: what [refresh] saw.
  Future<List<MyTickets>> kept({DateTime? now}) async {
    try {
      final raw = await _db?.readPref(_keptKey);
      if (raw == null) return const [];
      return _upcoming([for (final x in jsonDecode(raw) as List) MyTickets.fromJson(Map<String, dynamic>.from(x as Map))], now);
    } catch (_) {
      return const [];
    }
  }

  /// Asked again: each kept request, and the account's. A request the
  /// server cannot be asked about keeps its last look.
  Future<List<MyTickets>> refresh({DateTime? now}) async {
    final c = _client;
    reached = false;
    if (c == null) return kept(now: now);
    final old = {for (final t in await kept(now: now)) t.requestId: t};
    final found = <String, MyTickets>{};
    var got = false;
    for (final id in await _ids()) {
      try {
        final r = await c.rpc('event_ticket_status', params: {'p_id': id});
        got = true;
        if (r is Map) found[id] = MyTickets.fromJson(Map<String, dynamic>.from(r));
      } catch (_) {
        if (old[id] != null) found[id] = old[id]!;
      }
    }
    if (c.auth.currentUser != null) {
      try {
        final r = await c.rpc('my_event_tickets');
        got = true;
        for (final x in (r as List? ?? const [])) {
          final t = MyTickets.fromJson(Map<String, dynamic>.from(x as Map));
          found[t.requestId] = t;
        }
      } catch (_) {}
    }
    reached = got;
    if (!got && found.isEmpty) return old.values.toList();
    final list = _upcoming(found.values.toList(), now);
    try {
      await _db?.writePref(_keptKey, jsonEncode([for (final t in list) t.toJson()]));
    } catch (_) {}
    return list;
  }

  /// Still to come (or the day just past), waiting or paid; soonest first.
  static List<MyTickets> _upcoming(List<MyTickets> all, DateTime? now) {
    final t = (now ?? DateTime.now()).subtract(const Duration(days: 1));
    final list = [
      for (final x in all)
        if ((x.status == 'paid' || x.status == 'pending') && (x.startsAt == null || x.startsAt!.isAfter(t))) x,
    ]..sort((a, b) => (a.startsAt ?? DateTime(9999)).compareTo(b.startsAt ?? DateTime(9999)));
    return list;
  }
}
