import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/platform_writes.dart';
import '../admin/spots.dart' show PlatformToday;
import 'created_businesses.dart';
import 'models.dart' show PlatformOverview;
import 'problem_reports.dart';

export '../admin/spots.dart' show PlatformToday;
export 'created_businesses.dart';
export 'models.dart' show PlatformOverview;
export 'problem_reports.dart';

/// Mara's command center, from the server (104, 105): « À faire », the one
/// search, several businesses at once, the journal and its « Annuler »,
/// the settings. Every function checks the platform on the server; the
/// screens are only drawn for a platform admin as a courtesy.
class CommandCenterRepository {
  CommandCenterRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError(
          'Cette version de l\'application a été compilée sans serveur.');
    }
    return client;
  }

  /// The counts « À faire » opens on (platform_todo, 105).
  Future<PlatformTodo> todo() async {
    final v = await _requireClient().rpc('platform_todo');
    final counts = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    // 136: the help requests (133's help_todo_counts) — late and open.
    // Without 133 (or on any failure) the two counters are simply not
    // there: « Aujourd'hui » is as batch 135 drew it.
    try {
      final h = await _requireClient().rpc('help_todo_counts');
      if (h is Map) counts.addAll(Map<String, dynamic>.from(h));
    } catch (_) {}
    // 139: spot payments the stores took that programmed nothing (the
    // spot gone, refused, no longer eligible) — to refund by hand. Only
    // where 139 is.
    try {
      final r = await _requireClient().rpc('spot_refunds_todo');
      if (r is Map) counts.addAll(Map<String, dynamic>.from(r));
    } catch (_) {}
    // 146 (batch 151): « À vérifier » — the fraud review queue's length.
    // Only where 146 is.
    try {
      final r = await _requireClient().rpc('review_todo_counts');
      if (r is Map) counts.addAll(Map<String, dynamic>.from(r));
    } catch (_) {}
    return PlatformTodo.fromJson(counts);
  }

  /// What needs Mara's look (146's platform_review_queue): businesses with
  /// many blocked or refused orders, couriers over the cash cap, large till
  /// gaps, and the counts of what already has its own place.
  Future<ReviewQueue> reviewQueue() async {
    final v = await _requireClient().rpc('platform_review_queue');
    return ReviewQueue.fromJson(v is Map ? Map<String, dynamic>.from(v) : const {});
  }

  /// Those payments, oldest first (139's platform_spot_refunds).
  Future<List<SpotRefundRow>> spotRefunds() async {
    final v = await _requireClient().rpc('platform_spot_refunds');
    return [
      for (final r in (v is List ? v : const []))
        if (r is Map) SpotRefundRow.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  /// One of them refunded in Play Console or by Apple (journaled).
  Future<void> spotRefundDone(String id) async {
    await _requireClient().rpc('platform_spot_refund_done', params: {'p_id': id});
  }

  /// « Activités créées » (111): the businesses people created, and the
  /// requests of before.
  Future<CreatedBusinesses> createdBusinesses({int limit = 200}) async {
    final v = await _requireClient()
        .rpc('platform_created_businesses', params: {'p_limit': limit});
    return CreatedBusinesses.fromJson(v is Map ? Map<String, dynamic>.from(v) : const {});
  }

  /// « Signalements » (113): the shoppers' reports, the open ones oldest
  /// first, or the handled ones.
  Future<List<ProblemReport>> reports({bool handled = false}) async {
    final v = await _requireClient().rpc('platform_reports',
        params: {'p_status': handled ? 'handled' : 'open'});
    return [
      for (final r in (v is List ? v : const []))
        if (r is Map) ProblemReport.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  /// One report closed, with an answer the person reads (113): the
  /// journal line's id, for « Annuler ».
  Future<String?> handleReport(String id, {String? answer}) async {
    final v = await _requireClient().rpc('platform_handle_report',
        params: {'p_id': id, 'p_answer': answer});
    return v as String?;
  }

  /// The rows behind one count (platform_todo_list, 105).
  Future<List<TodoRow>> todoList(String key) async {
    final v = await _requireClient()
        .rpc('platform_todo_list', params: {'p_key': key});
    return [
      for (final r in (v is List ? v : const []))
        if (r is Map) TodoRow.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  /// One search for the platform (platform_search, 105).
  Future<SearchResults> search(String query) async {
    final v = await _requireClient()
        .rpc('platform_search', params: {'p_q': query});
    return SearchResults.fromJson(
        v is Map ? Map<String, dynamic>.from(v) : const {});
  }

  /// One act for several businesses (platform_bulk, 105): 'cauris',
  /// 'unlock', 'message', 'archive'.
  Future<BulkResult> bulk(
      String action, List<String> orgIds, Map<String, Object?> args) async {
    final v = await _requireClient().rpc('platform_bulk', params: {
      'p_action': action,
      'p_orgs': orgIds,
      'p_args': args,
    });
    return BulkResult.fromJson(v is Map ? Map<String, dynamic>.from(v) : const {});
  }

  /// The journal, newest first (platform_actions_page, 104). The next page
  /// starts after the last line read: its time [before] and its id
  /// [beforeId] together, since several lines can share one moment.
  Future<List<JournalEntry>> journal(
      {String? orgId, int limit = 50, DateTime? before, String? beforeId}) async {
    final v = await _requireClient().rpc('platform_actions_page', params: {
      'p_org': orgId,
      'p_limit': limit,
      'p_before': before?.toUtc().toIso8601String(),
      'p_before_id': before == null ? null : beforeId,
    });
    return [
      for (final r in (v is List ? v : const []))
        if (r is Map) JournalEntry.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  /// « Annuler » (platform_undo, 104).
  Future<void> undo(String actionId) async {
    await _requireClient().rpc('platform_undo', params: {'p_action': actionId});
  }

  /// Every platform setting but the markers, with who changed it last
  /// (platform_settings_board, 105).
  Future<Map<String, SettingValue>> settings() async {
    final v = await _requireClient().rpc('platform_settings_board');
    return {
      if (v is Map)
        for (final e in v.entries)
          if (e.value is Map)
            '${e.key}': SettingValue.fromJson(Map<String, dynamic>.from(e.value as Map)),
    };
  }

  /// One setting changed (platform_set_setting, 105): the journal line's
  /// id, for « Annuler », or null when nothing changed.
  Future<String?> setSetting(String key, Object? value) =>
      writePlatformSetting(_requireClient(), key, value);

  /// The month's money, the growth and the health (072's platform_today):
  /// « Aujourd'hui »'s four numbers and « Argent »'s card (135). Null when
  /// the server has none to give.
  Future<PlatformToday?> today() async {
    final v = await _requireClient().rpc('platform_today');
    return v is Map ? PlatformToday.fromJson(Map<String, dynamic>.from(v)) : null;
  }

  /// The businesses in numbers (platform_overview): the active ones, the
  /// week's new ones, the ones on Pro today (135).
  Future<PlatformOverview?> overview() async {
    final v = await _requireClient().rpc('platform_overview');
    if (v is! List || v.isEmpty || v.first is! Map) return null;
    return PlatformOverview.fromRow(Map<String, dynamic>.from(v.first as Map));
  }

  /// « Aujourd'hui »'s new accounts and today's orders (132's
  /// platform_today_counts). Null when the server has none to give — a
  /// database without 132 among them: « Aujourd'hui » then draws the new
  /// businesses and the seven days' orders, as before 132.
  Future<TodayCounts?> todayCounts() async {
    try {
      final v = await _requireClient().rpc('platform_today_counts');
      return v is Map ? TodayCounts.fromJson(Map<String, dynamic>.from(v)) : null;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }
}

/// 132's counts: the accounts made in the last seven days and the seven
/// before; the orders placed today (since Ouagadougou's midnight) and on
/// the same day last week up to the same hour.
class TodayCounts {
  const TodayCounts({
    required this.accountsWeek,
    required this.accountsLastWeek,
    required this.ordersToday,
    required this.ordersLastWeek,
  });

  factory TodayCounts.fromJson(Map<String, dynamic> j) => TodayCounts(
        accountsWeek: _int(j['accounts_week']),
        accountsLastWeek: _int(j['accounts_last_week']),
        ordersToday: _int(j['orders_today']),
        ordersLastWeek: _int(j['orders_last_week']),
      );

  final int accountsWeek;
  final int accountsLastWeek;
  final int ordersToday;
  final int ordersLastWeek;
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
String? _text(Object? v) {
  final s = v?.toString();
  return s == null || s.trim().isEmpty ? null : s;
}

class PlatformTodo {
  const PlatformTodo(this.counts);

  factory PlatformTodo.fromJson(Map<String, dynamic> j) =>
      PlatformTodo({for (final e in j.entries) e.key: _int(e.value)});

  final Map<String, int> counts;

  int operator [](String key) => counts[key] ?? 0;

  /// What waits on the platform, « À faire »'s « À traiter » in one number.
  int get waiting =>
      this['new_7'] + this['pro_paid'] + this['spots_paid'] + this['spots_asked'] + this['spot_refunds'] +
      this['couriers'] + this['orders_stuck'] + this['payouts_failed'] + this['silent_30'] +
      this['features_lapsed'] + this['reports_open'] + this['help_late'] + this['help_open'] +
      this['review'];

  /// A counter this server has: the help's two (136) only where 133 is,
  /// every other one always.
  /// 139's spot refunds only where 139 is.
  bool has(String key) =>
      (!key.startsWith('help_') && key != 'spot_refunds' && key != 'review') ||
      counts.containsKey(key);

  /// One of « Aujourd'hui »'s fourteen counters (135): the spots are the
  /// paid ones and the asked ones together, as « À faire » drew them.
  int count(String key) =>
      key == 'spots' ? this['spots_paid'] + this['spots_asked'] : this[key];

  /// The counters that are not zero, the most urgent first (135).
  List<String> get waitingOrder => [
        for (final tier in todoUrgency)
          for (final k in tier)
            if (has(k) && count(k) > 0) k,
      ];

  /// The counters at zero, folded into one green line (135).
  List<String> get zeroKeys => [
        for (final tier in todoUrgency)
          for (final k in tier)
            if (has(k) && count(k) == 0) k,
      ];

  /// The urgent counters' total (135): stuck orders, reports, failed
  /// payouts, « J'ai payé » and spots to handle.
  int get urgent => [for (final k in todoUrgency.first) count(k)].fold(0, (a, b) => a + b);

  /// The bar's badge on « Aujourd'hui » (135 review): the lines « VOUS
  /// ATTEND · N » draws — the same number on the badge and on the page
  /// (the mockup's « 4 » on both), never a sum of their counts.
  int get badge => waitingOrder.length;
}

/// « Aujourd'hui »'s counters by urgency (135), most urgent first: what
/// is stuck or failed or reported and the « J'ai payé » to confirm; then
/// the couriers to validate and the new businesses to welcome; then the
/// businesses to call; then what ends within seven days. A shopper's
/// « Signaler un problème » is the report. 136: a Pro business's help
/// request — late (no answer for 30 open minutes) with the urgent ones,
/// the other open ones with the couriers and the new businesses; only on
/// a server with 133 ([PlatformTodo.has]).
const todoUrgency = <List<String>>[
  // 146: « À vérifier » (the fraud review queue) beside the reports.
  ['orders_stuck', 'help_late', 'reports_open', 'review', 'payouts_failed', 'pro_paid', 'spots', 'spot_refunds'],
  ['help_open', 'couriers', 'new_7'],
  ['silent_30', 'features_lapsed'],
  ['plans_ending', 'unlocks_ending', 'promos_ending', 'spots_ending', 'rules_ending'],
];

/// A spot's store payment that programmed nothing, to refund (139).
class SpotRefundRow {
  const SpotRefundRow({
    required this.id,
    required this.channel,
    this.externalId,
    this.orgName,
    this.kind,
    this.amount,
    this.currency,
    this.reason,
    this.at,
  });

  factory SpotRefundRow.fromJson(Map<String, dynamic> j) => SpotRefundRow(
        id: '${j['id']}',
        channel: '${j['channel'] ?? ''}',
        externalId: _text(j['external_id']),
        orgName: _text(j['org_name']),
        kind: _text(j['kind']),
        amount: _num(j['amount']),
        currency: _text(j['currency']),
        reason: _text(j['reason']),
        at: _date(j['created_at']),
      );

  final String id;

  /// 'google', 'apple' (or 'stripe' when its automatic refund failed).
  final String channel;

  /// The store's id: Google's order is found by it in Play Console,
  /// Apple's transaction in App Store Connect.
  final String? externalId;
  final String? orgName;
  final String? kind;
  final double? amount;
  final String? currency;

  /// spot_settle's: 'no spot', 'refused', 'vitrine', 'feature', 'article', 'product'.
  final String? reason;
  final DateTime? at;
}

/// One row behind a count: a business, and what is about it.
class TodoRow {
  const TodoRow({
    this.orgId,
    this.orgName,
    this.profile,
    this.kind,
    this.feature,
    this.points,
    this.amount,
    this.currency,
    this.status,
    this.customer,
    this.orderId,
    this.error,
    this.spot,
    this.state,
    this.gift = false,
    this.owner,
    this.city,
    this.byPerson = false,
    this.at,
  });

  factory TodoRow.fromJson(Map<String, dynamic> j) => TodoRow(
        orgId: _text(j['org_id']),
        orgName: _text(j['org_name']),
        profile: _text(j['profile']),
        kind: _text(j['kind']),
        feature: _text(j['feature']),
        points: j['points'] == null ? null : _int(j['points']),
        amount: _num(j['amount']),
        currency: _text(j['currency']),
        status: _text(j['status']),
        customer: _text(j['customer']),
        orderId: _text(j['order_id']),
        error: _text(j['error']),
        spot: _text(j['spot']),
        state: _text(j['state']),
        gift: j['gift'] == true,
        owner: _text(j['owner']),
        city: _text(j['city']),
        byPerson: j['by_person'] == true,
        at: _date(j['at']),
      );

  final String? orgId;
  final String? orgName;
  final String? profile;

  /// A kind's rule (rules_ending): 'retail', 'farm', 'association'.
  final String? kind;
  final String? feature;
  final int? points;
  final double? amount;
  final String? currency;
  final String? status;
  final String? customer;
  final String? orderId;
  final String? error;
  final String? spot;

  /// A rule's switch (rules_ending): 'visible' or 'hidden'.
  final String? state;
  final bool gift;

  /// A new business (new_7, 111): its owner, its town, and whether the
  /// person created it (else Mara did, or approved a request).
  final String? owner;
  final String? city;
  final bool byPerson;
  final DateTime? at;
}

class SearchResults {
  const SearchResults({
    this.businesses = const [],
    this.people = const [],
    this.orders = const [],
  });

  factory SearchResults.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> rows(Object? v) => [
          for (final r in (v is List ? v : const []))
            if (r is Map) Map<String, dynamic>.from(r),
        ];
    return SearchResults(
      businesses: [for (final r in rows(j['businesses'])) BusinessHit.fromJson(r)],
      people: [for (final r in rows(j['people'])) PersonHit.fromJson(r)],
      orders: [for (final r in rows(j['orders'])) OrderHit.fromJson(r)],
    );
  }

  final List<BusinessHit> businesses;
  final List<PersonHit> people;
  final List<OrderHit> orders;

  bool get isEmpty => businesses.isEmpty && people.isEmpty && orders.isEmpty;
}

class BusinessHit {
  const BusinessHit({
    required this.id,
    required this.name,
    this.slug,
    this.profile = 'retail',
    this.owner,
    this.ownerPhone,
    this.phone,
    this.archived = false,
  });

  factory BusinessHit.fromJson(Map<String, dynamic> j) => BusinessHit(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        slug: _text(j['slug']),
        profile: _text(j['profile']) ?? 'retail',
        owner: _text(j['owner']),
        ownerPhone: _text(j['owner_phone']),
        phone: _text(j['phone']),
        archived: j['archived'] == true,
      );

  final String id;
  final String name;
  final String? slug;
  final String profile;
  final String? owner;
  final String? ownerPhone;
  final String? phone;
  final bool archived;
}

class PersonHit {
  const PersonHit({
    required this.id,
    this.name,
    this.phone,
    this.email,
    this.platform = false,
    this.businesses = 0,
  });

  factory PersonHit.fromJson(Map<String, dynamic> j) => PersonHit(
        id: '${j['id']}',
        name: _text(j['name']),
        phone: _text(j['phone']),
        email: _text(j['email']),
        platform: j['platform'] == true,
        businesses: _int(j['businesses']),
      );

  final String id;
  final String? name;
  final String? phone;
  final String? email;
  final bool platform;
  final int businesses;

  String get label => name ?? email ?? phone ?? '—';
}

class OrderHit {
  const OrderHit({
    required this.id,
    required this.orgId,
    this.orgName,
    this.profile = 'retail',
    this.customer,
    this.phone,
    this.status = 'pending',
    this.fulfilment = 'pickup',
    this.total = 0,
    this.currency = 'XOF',
    this.at,
  });

  factory OrderHit.fromJson(Map<String, dynamic> j) => OrderHit(
        id: '${j['id']}',
        orgId: '${j['org_id']}',
        orgName: _text(j['org_name']),
        profile: _text(j['profile']) ?? 'retail',
        customer: _text(j['customer']),
        phone: _text(j['phone']),
        status: _text(j['status']) ?? 'pending',
        fulfilment: _text(j['fulfilment']) ?? 'pickup',
        total: _num(j['total']) ?? 0,
        currency: _text(j['currency']) ?? 'XOF',
        at: _date(j['at']),
      );

  final String id;
  final String orgId;
  final String? orgName;
  final String profile;
  final String? customer;
  final String? phone;
  final String status;
  final String fulfilment;
  final double total;
  final String currency;
  final DateTime? at;

  /// The first eight characters of its number, as it is searched.
  String get shortId => id.length > 8 ? id.substring(0, 8) : id;
}

class BulkResult {
  const BulkResult({this.done = 0, this.actions = const [], this.failed = const []});

  factory BulkResult.fromJson(Map<String, dynamic> j) => BulkResult(
        done: _int(j['done']),
        actions: [for (final a in (j['actions'] is List ? j['actions'] as List : const [])) '$a'],
        failed: [
          for (final f in (j['failed'] is List ? j['failed'] as List : const []))
            if (f is Map)
              (
                orgId: '${f['org_id']}',
                name: _text(f['name']),
                error: '${f['error'] ?? ''}',
              ),
        ],
      );

  final int done;

  /// One journal line per business done.
  final List<String> actions;
  final List<({String orgId, String? name, String error})> failed;
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.at,
    required this.kind,
    required this.summary,
    this.actor,
    this.orgId,
    this.orgName,
    this.before,
    this.after,
    this.undoable = false,
    this.undoneAt,
    this.undoneBy,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
        id: '${j['id']}',
        at: _date(j['at']) ?? DateTime.now(),
        kind: '${j['kind'] ?? ''}',
        summary: '${j['summary'] ?? ''}',
        actor: _text(j['actor_label']),
        orgId: _text(j['org_id']),
        orgName: _text(j['org_name']),
        before: j['before'] is Map ? Map<String, dynamic>.from(j['before'] as Map) : null,
        after: j['after'] is Map ? Map<String, dynamic>.from(j['after'] as Map) : null,
        undoable: j['undoable'] == true,
        undoneAt: _date(j['undone_at']),
        undoneBy: _text(j['undone_by_label']),
      );

  final String id;
  final DateTime at;
  final String kind;
  final String summary;
  final String? actor;
  final String? orgId;
  final String? orgName;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final bool undoable;
  final DateTime? undoneAt;
  final String? undoneBy;
}

class SettingValue {
  const SettingValue({this.value, this.updatedAt, this.changedBy});

  factory SettingValue.fromJson(Map<String, dynamic> j) => SettingValue(
        value: j['value'],
        updatedAt: _date(j['updated_at']),
        changedBy: _text(j['changed_by']),
      );

  /// As the database keeps it: a number, true/false, a text, a list.
  final Object? value;
  final DateTime? updatedAt;
  final String? changedBy;
}


/// Mara's review queue (146, batch 151).
class ReviewQueue {
  const ReviewQueue({
    this.businesses = const [],
    this.couriers = const [],
    this.tills = const [],
    this.reportsOpen = 0,
    this.couriersPending = 0,
    this.cashCap,
    this.tillGap,
  });

  factory ReviewQueue.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> rows(String k) => [
          for (final r in (j[k] is List ? j[k] as List : const []))
            if (r is Map) Map<String, dynamic>.from(r),
        ];
    double? n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    return ReviewQueue(
      businesses: [
        for (final r in rows('businesses'))
          ReviewBusiness(
            orgId: '${r['org_id']}',
            name: '${r['name'] ?? ''}',
            slug: r['slug'] as String?,
            profile: (r['profile'] as String?) ?? 'retail',
            blocks: (n(r['blocks_30']) ?? 0).round(),
            refused: (n(r['refused_7']) ?? 0).round(),
          ),
      ],
      couriers: [
        for (final r in rows('couriers'))
          ReviewCourier(
            userId: '${r['user_id']}',
            name: '${r['name'] ?? ''}',
            phone: r['phone'] as String?,
            currency: (r['currency'] as String?) ?? 'XOF',
            held: n(r['held']) ?? 0,
            cap: n(r['cap']) ?? 0,
          ),
      ],
      tills: [
        for (final r in rows('tills'))
          ReviewTill(
            orgId: '${r['org_id']}',
            name: '${r['name'] ?? ''}',
            day: DateTime.tryParse('${r['day']}'),
            gap: n(r['gap']) ?? 0,
            expected: n(r['expected']) ?? 0,
            counted: n(r['counted']) ?? 0,
            currency: (r['currency'] as String?) ?? 'XOF',
            closer: r['closer'] as String?,
          ),
      ],
      reportsOpen: (n(j['reports_open']) ?? 0).round(),
      couriersPending: (n(j['couriers_pending']) ?? 0).round(),
      cashCap: n(j['cash_cap']),
      tillGap: n(j['till_gap_review']),
    );
  }

  final List<ReviewBusiness> businesses;
  final List<ReviewCourier> couriers;
  final List<ReviewTill> tills;
  final int reportsOpen;
  final int couriersPending;
  final double? cashCap;
  final double? tillGap;

  bool get isEmpty => businesses.isEmpty && couriers.isEmpty && tills.isEmpty;
}

/// A business with 3 blocks in 30 days or 5 refused orders in 7.
class ReviewBusiness {
  const ReviewBusiness({
    required this.orgId,
    required this.name,
    this.slug,
    this.profile = 'retail',
    this.blocks = 0,
    this.refused = 0,
  });

  final String orgId;
  final String name;
  final String? slug;
  final String profile;
  final int blocks;
  final int refused;
}

/// A courier carrying more shops' cash than the cap.
class ReviewCourier {
  const ReviewCourier({
    required this.userId,
    required this.name,
    this.phone,
    this.currency = 'XOF',
    required this.held,
    required this.cap,
  });

  final String userId;
  final String name;
  final String? phone;
  final String currency;
  final double held;
  final double cap;
}

/// A till closed with a gap at least as large as till_gap_review.
class ReviewTill {
  const ReviewTill({
    required this.orgId,
    required this.name,
    this.day,
    required this.gap,
    required this.expected,
    required this.counted,
    this.currency = 'XOF',
    this.closer,
  });

  final String orgId;
  final String name;
  final DateTime? day;
  final double gap;
  final double expected;
  final double counted;
  final String currency;
  final String? closer;
}
