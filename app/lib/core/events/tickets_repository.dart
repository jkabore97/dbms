import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/local_db.dart';

/// Ticket sales (161): the payment goes from the buyer to the organiser,
/// outside the app; Marakaj carries the ticket types, the requests, the
/// validation, one QR per ticket and the door. Every write is the
/// server's (event_ticket_decide, event_ticket_scan…) or bound by its
/// policies (the types, the sale's settings).
class TicketsRepository {
  // A named parameter cannot be private: keep is handed to _keep.
  // ignore: prefer_initializing_formals
  TicketsRepository(this._client, {LocalDb? keep}) : _keep = keep;

  final SupabaseClient? _client;

  /// Where the door's list and its scans without signal are kept: the
  /// phone's preferences, or memory alone (the tests, a phone with none).
  final LocalDb? _keep;
  final _memory = <String, String>{};

  Future<String?> _read(String key) async {
    try {
      if (_keep != null) return await _keep.readPref(key);
    } catch (_) {}
    return _memory[key];
  }

  Future<void> _write(String key, String? value) async {
    if (value == null) {
      _memory.remove(key);
    } else {
      _memory[key] = value;
    }
    try {
      await _keep?.writePref(key, value);
    } catch (_) {}
  }

  /// Whether this business may sell tickets (Marakaj Pro, or the
  /// platform's own while the switch is off). False when it cannot be asked.
  Future<bool> allowed(String orgId) async {
    try {
      return (await _require().rpc('event_tickets_ready', params: {'p_org': orgId})) == true;
    } catch (_) {
      return false;
    }
  }

  bool get isConfigured => _client != null;

  SupabaseClient _require() {
    final c = _client;
    if (c == null) throw StateError('Supabase is not configured in this build.');
    return c;
  }

  /// The event's sale as it stands.
  Future<TicketSettings> settings(String eventId) async {
    final c = _require();
    final row = await c
        .from('events')
        .select('tickets_on, pay_methods, pay_whatsapp, hold_hours, sales_close_at')
        .eq('id', eventId)
        .single();
    final types = await c.from('event_ticket_types').select().eq('event_id', eventId).order('sort').order('created_at');
    return TicketSettings.fromJson(Map<String, dynamic>.from(row),
        [for (final t in types) TicketType.fromJson(Map<String, dynamic>.from(t))]);
  }

  /// The sale turned on or off, where to pay, how long a request holds its
  /// places. Turning it on is Marakaj Pro's (the server says so).
  Future<void> saveSettings(String eventId, TicketSettings s) async {
    await _require().from('events').update({
      'tickets_on': s.on,
      'pay_methods': [for (final m in s.payMethods) m.toJson()],
      'pay_whatsapp': s.payWhatsapp?.trim().isEmpty ?? true ? null : s.payWhatsapp!.trim(),
      'hold_hours': s.holdHours,
      'sales_close_at': s.salesCloseAt?.toUtc().toIso8601String(),
    }).eq('id', eventId);
  }

  Future<void> saveType(String eventId, TicketType t) async {
    final row = {
      'event_id': eventId,
      'name': t.name.trim(),
      'price': t.price,
      'capacity': t.capacity,
      'sort': t.sort,
      'active': t.active,
    };
    if (t.id.isEmpty) {
      await _require().from('event_ticket_types').insert(row);
    } else {
      await _require().from('event_ticket_types').update(row).eq('id', t.id);
    }
  }

  /// A type nobody asked for goes; one already in a request stops selling.
  Future<void> removeType(TicketType t) async {
    try {
      await _require().from('event_ticket_types').delete().eq('id', t.id);
    } on PostgrestException {
      await _require().from('event_ticket_types').update({'active': false}).eq('id', t.id);
    }
  }

  /// The requests, newest first, with what each asks.
  Future<List<TicketRequest>> requests(String eventId) async {
    final rows = await _require()
        .from('event_ticket_requests')
        .select('*, event_ticket_lines(qty, unit_price, event_ticket_types(name))')
        .eq('event_id', eventId)
        .order('created_at', ascending: false);
    return [for (final r in rows) TicketRequest.fromJson(Map<String, dynamic>.from(r))];
  }

  /// Paid (the money seen on the organiser's own phone) or refused.
  Future<void> decide(String requestId, {required bool paid, String? note, String? method}) async {
    await _require().rpc('event_ticket_decide', params: {
      'p_id': requestId,
      'p_paid': paid,
      'p_note': note,
      'p_method': method,
    });
  }

  /// The door: a ticket valid once.
  Future<ScanResult> scan(String ticketId) async {
    final r = await _require().rpc('event_ticket_scan', params: {'p_id': ticketId});
    return ScanResult.fromJson(Map<String, dynamic>.from(r as Map));
  }

  /// Every ticket of the event, for a hall with no signal.
  Future<List<DoorTicket>> doorList(String eventId) async {
    final r = await _require().rpc('event_tickets_door', params: {'p_event': eventId});
    return [for (final t in (r as List)) DoorTicket.fromJson(Map<String, dynamic>.from(t as Map))];
  }

  /// Scans made with no signal, sent once back online. The ids the server
  /// found already used are returned.
  Future<List<String>> doorSync(String eventId, List<({String id, DateTime at})> scans) async {
    final r = await _require().rpc('event_tickets_door_sync', params: {
      'p_event': eventId,
      'p_scans': [for (final s in scans) {'id': s.id, 'at': s.at.toUtc().toIso8601String()}],
    });
    return [
      for (final x in (r as List))
        if ((x as Map)['applied'] != true) '${x['id']}',
    ];
  }

  /// The door's list kept on the phone, with when it was taken.
  Future<({List<DoorTicket> tickets, DateTime? at})?> keptDoor(String eventId) async {
    final raw = await _read('tickets.door.$eventId');
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map;
      return (
        tickets: [for (final t in (j['rows'] as List)) DoorTicket.fromJson(Map<String, dynamic>.from(t as Map))],
        at: DateTime.tryParse('${j['at']}')?.toLocal(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> keepDoor(String eventId, List<DoorTicket> tickets) => _write(
        'tickets.door.$eventId',
        jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), 'rows': [for (final t in tickets) t.toJson()]}),
      );

  /// The scans made without signal, waiting to be sent.
  Future<List<({String id, DateTime at})>> keptScans(String eventId) async {
    final raw = await _read('tickets.scans.$eventId');
    if (raw == null) return const [];
    try {
      return [
        for (final s in (jsonDecode(raw) as List))
          (id: '${(s as Map)['id']}', at: DateTime.tryParse('${s['at']}')?.toLocal() ?? DateTime.now()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> keepScans(String eventId, List<({String id, DateTime at})> scans) => _write(
        'tickets.scans.$eventId',
        scans.isEmpty ? null : jsonEncode([for (final s in scans) {'id': s.id, 'at': s.at.toUtc().toIso8601String()}]),
      );

  /// « Garder mes billets dans Marakaj ».
  Future<bool> claim(String requestId) async =>
      (await _require().rpc('event_ticket_claim', params: {'p_id': requestId})) == true;

  /// The signed-in person's tickets for events still to come.
  Future<List<MyTickets>> mine() async {
    final r = await _require().rpc('my_event_tickets');
    return [for (final t in (r as List? ?? const [])) MyTickets.fromJson(Map<String, dynamic>.from(t as Map))];
  }

  /// A ticket's id inside its QR (`https://marakaj.com/e/<slug>/billet/<id>`).
  static String? ticketIdFrom(String text) {
    final m = RegExp(r'/billet/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/?\s*$', caseSensitive: false)
        .firstMatch(text.trim());
    return m?.group(1)?.toLowerCase();
  }
}

/// Where the buyer pays: Orange Money, Moov Money, Wave or another.
class PayMethod {
  const PayMethod({required this.kind, required this.number, this.name});

  factory PayMethod.fromJson(Map<String, dynamic> j) =>
      PayMethod(kind: '${j['kind'] ?? 'orange'}', number: '${j['number'] ?? ''}', name: j['name'] as String?);

  final String kind;
  final String number;
  final String? name;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'number': number.trim(),
        if (name != null && name!.trim().isNotEmpty) 'name': name!.trim(),
      };

  static const kinds = {'orange': 'Orange Money', 'moov': 'Moov Money', 'wave': 'Wave', 'autre': 'Autre'};
}

class TicketType {
  const TicketType({
    this.id = '',
    required this.name,
    required this.price,
    this.capacity,
    this.sort = 0,
    this.active = true,
  });

  factory TicketType.fromJson(Map<String, dynamic> j) => TicketType(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        capacity: (j['capacity'] as num?)?.toInt(),
        sort: (j['sort'] as num?)?.toInt() ?? 0,
        active: (j['active'] as bool?) ?? true,
      );

  final String id;
  final String name;
  final double price;

  /// Null: no limit.
  final int? capacity;
  final int sort;
  final bool active;
}

class TicketSettings {
  const TicketSettings({
    required this.on,
    required this.payMethods,
    this.payWhatsapp,
    this.holdHours = 72,
    this.salesCloseAt,
    this.types = const [],
  });

  factory TicketSettings.fromJson(Map<String, dynamic> j, List<TicketType> types) => TicketSettings(
        on: (j['tickets_on'] as bool?) ?? false,
        payMethods: [
          for (final m in (j['pay_methods'] as List? ?? const [])) PayMethod.fromJson(Map<String, dynamic>.from(m as Map)),
        ],
        payWhatsapp: j['pay_whatsapp'] as String?,
        holdHours: (j['hold_hours'] as num?)?.toInt() ?? 72,
        salesCloseAt: j['sales_close_at'] == null ? null : DateTime.tryParse('${j['sales_close_at']}')?.toLocal(),
        types: types,
      );

  final bool on;
  final List<PayMethod> payMethods;
  final String? payWhatsapp;
  final int holdHours;
  final DateTime? salesCloseAt;
  final List<TicketType> types;

  TicketSettings copyWith({bool? on, List<PayMethod>? payMethods, String? payWhatsapp, int? holdHours, DateTime? salesCloseAt, bool clearClose = false}) =>
      TicketSettings(
        on: on ?? this.on,
        payMethods: payMethods ?? this.payMethods,
        payWhatsapp: payWhatsapp ?? this.payWhatsapp,
        holdHours: holdHours ?? this.holdHours,
        salesCloseAt: clearClose ? null : (salesCloseAt ?? this.salesCloseAt),
        types: types,
      );
}

class TicketRequest {
  const TicketRequest({
    required this.id,
    required this.ref,
    required this.name,
    required this.whatsapp,
    required this.status,
    required this.total,
    required this.currency,
    required this.holdUntil,
    required this.createdAt,
    this.txnRef,
    this.note,
    this.lines = const [],
  });

  factory TicketRequest.fromJson(Map<String, dynamic> j) {
    final hold = DateTime.tryParse('${j['hold_until']}')?.toLocal() ?? DateTime.now();
    final raw = '${j['status'] ?? 'pending'}';
    return TicketRequest(
      id: '${j['id']}',
      ref: '${j['ref'] ?? ''}',
      name: '${j['buyer_name'] ?? ''}',
      whatsapp: '${j['buyer_whatsapp'] ?? ''}',
      // An unpaid request past its hold is expired (its places back on sale).
      status: raw == 'pending' && hold.isBefore(DateTime.now()) ? 'expired' : raw,
      total: (j['total'] as num?)?.toDouble() ?? 0,
      currency: '${j['currency'] ?? 'XOF'}',
      holdUntil: hold,
      createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
      txnRef: j['txn_ref'] as String?,
      note: j['note'] as String?,
      lines: [
        for (final l in (j['event_ticket_lines'] as List? ?? const []))
          (
            name: '${((l as Map)['event_ticket_types'] as Map?)?['name'] ?? ''}',
            qty: (l['qty'] as num?)?.toInt() ?? 0,
          ),
      ],
    );
  }

  final String id;
  final String ref;
  final String name;
  final String whatsapp;

  /// pending, paid, refused, expired, refunded.
  final String status;
  final double total;
  final String currency;
  final DateTime holdUntil;
  final DateTime createdAt;
  final String? txnRef;
  final String? note;
  final List<({String name, int qty})> lines;

  int get count => lines.fold(0, (a, l) => a + l.qty);
}

class ScanResult {
  const ScanResult({required this.result, this.holder, this.type, this.usedAt});

  factory ScanResult.fromJson(Map<String, dynamic> j) => ScanResult(
        result: '${j['result'] ?? 'unknown'}',
        holder: j['holder'] as String?,
        type: j['type'] as String?,
        usedAt: j['used_at'] == null ? null : DateTime.tryParse('${j['used_at']}')?.toLocal(),
      );

  /// valid, used, void, unknown.
  final String result;
  final String? holder;
  final String? type;
  final DateTime? usedAt;
}

class DoorTicket {
  const DoorTicket({required this.id, required this.holder, required this.type, required this.status});

  factory DoorTicket.fromJson(Map<String, dynamic> j) =>
      DoorTicket(id: '${j['id']}', holder: '${j['holder'] ?? ''}', type: '${j['type'] ?? ''}', status: '${j['status'] ?? 'valid'}');

  final String id;
  final String holder;
  final String type;
  final String status;

  Map<String, dynamic> toJson() => {'id': id, 'holder': holder, 'type': type, 'status': status};

  DoorTicket used() => DoorTicket(id: id, holder: holder, type: type, status: 'used');
}

/// One request the signed-in person keeps (my_event_tickets).
class MyTickets {
  const MyTickets({
    required this.requestId,
    required this.slug,
    required this.title,
    required this.status,
    required this.tickets,
    this.startsAt,
    this.place,
    this.dateFr,
    this.ref = '',
  });

  factory MyTickets.fromJson(Map<String, dynamic> j) => MyTickets(
        requestId: '${j['id']}',
        slug: '${j['slug'] ?? ''}',
        title: '${j['title'] ?? ''}',
        status: '${j['status'] ?? 'pending'}',
        ref: '${j['ref'] ?? ''}',
        startsAt: j['starts_at'] == null ? null : DateTime.tryParse('${j['starts_at']}')?.toLocal(),
        place: j['place'] as String?,
        dateFr: j['date_fr'] as String?,
        tickets: [
          for (final t in (j['tickets'] as List? ?? const []))
            (id: '${(t as Map)['id']}', type: '${t['type'] ?? ''}', holder: '${t['holder'] ?? ''}', status: '${t['status'] ?? 'valid'}'),
        ],
      );

  final String requestId;
  final String slug;
  final String title;
  final String status;
  final String ref;
  final DateTime? startsAt;
  final String? place;
  final String? dateFr;
  final List<({String id, String type, String holder, String status})> tickets;

  Map<String, dynamic> toJson() => {
        'id': requestId,
        'slug': slug,
        'title': title,
        'status': status,
        'ref': ref,
        'starts_at': startsAt?.toUtc().toIso8601String(),
        'place': place,
        'date_fr': dateFr,
        'tickets': [for (final t in tickets) {'id': t.id, 'type': t.type, 'holder': t.holder, 'status': t.status}],
      };

  /// What the QR of a ticket carries.
  String qrOf(String ticketId) => 'https://marakaj.com/e/$slug/billet/$ticketId';
}
