import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/platform_writes.dart';

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
    return PlatformTodo.fromJson(v is Map ? Map<String, dynamic>.from(v) : const {});
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

  /// The journal, newest first (platform_actions_page, 104).
  Future<List<JournalEntry>> journal(
      {String? orgId, int limit = 50, DateTime? before}) async {
    final v = await _requireClient().rpc('platform_actions_page', params: {
      'p_org': orgId,
      'p_limit': limit,
      'p_before': before?.toUtc().toIso8601String(),
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
      this['applications'] + this['pro_paid'] + this['spots_paid'] + this['spots_asked'] +
      this['couriers'] + this['orders_stuck'] + this['payouts_failed'] + this['silent_30'];
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
