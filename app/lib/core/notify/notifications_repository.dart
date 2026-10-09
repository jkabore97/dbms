import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';

import 'bell.dart';
import 'push_client.dart';

/// Whose list a bell is (115): one business's, the person's purchases, their
/// deliveries, or the platform's. The account's own rows (a new device, a
/// test, a verified phone) belong to none and are shown in every list.
class NotifyScope {
  const NotifyScope._(this.name, [this.orgId]);

  /// A business: the rows written for those who answer for it.
  const NotifyScope.org(String orgId) : this._('shop', orgId);

  static const customer = NotifyScope._('customer');
  static const courier = NotifyScope._('courier');
  static const platform = NotifyScope._('platform');

  /// The server's word for it (notifications.scope, 115).
  final String name;
  final String? orgId;

  /// Whether a row is in this list.
  bool holds(NotificationRow n) =>
      n.scope == 'me' || (n.scope == name && (orgId == null || n.orgId == orgId));

  @override
  bool operator ==(Object other) =>
      other is NotifyScope && other.name == name && other.orgId == orgId;

  @override
  int get hashCode => Object.hash(name, orgId);
}

/// One ring of the bell.
class NotificationRow {
  const NotificationRow({
    required this.id,
    required this.kind,
    required this.message,
    required this.createdAt,
    this.readAt,
    this.orgId,
    this.params = const {},
    this.scope = '',
  });

  final String id;
  final String kind;

  /// The server's line, in French — what the push said, and what is shown
  /// when the app has nothing better (a row from before 099, a French phone).
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;

  /// The business it is about; null for the platform's and the person's own
  /// (a new device, a courier's decision).
  final String? orgId;

  /// The event's facts (099): ids, names, amounts, and `to` — 'shop',
  /// 'customer' or 'courier' — whom it was written for. Empty on older rows.
  final Map<String, dynamic> params;

  /// Whose list it is in (115): 'shop', 'customer', 'courier', 'platform'
  /// or 'me'. Read from the server, or said here the server's way for a
  /// database before 115.
  final String scope;

  bool get isUnread => readAt == null;

  factory NotificationRow.fromRow(Map<String, dynamic> r) {
    final kind = r['kind'] as String;
    final orgId = r['org_id'] as String?;
    final params = r['params'] is Map
        ? Map<String, dynamic>.from(r['params'] as Map)
        : const <String, dynamic>{};
    return NotificationRow(
      id: r['id'] as String,
      kind: kind,
      message: brandText(r['message'] as String),
      createdAt: DateTime.parse(r['created_at'] as String),
      readAt: r['read_at'] == null ? null : DateTime.parse(r['read_at'] as String),
      orgId: orgId,
      params: params,
      scope: (r['scope'] as String?) ?? scopeOf(kind, orgId, params),
    );
  }

  /// 115's notification_scope(), for rows read from a database before it.
  static String scopeOf(String kind, String? orgId, Map<String, dynamic> params) {
    final to = params['to'];
    if (to == 'platform') return 'platform';
    if (orgId == null &&
        (kind == 'org_application' || kind == 'courier_application' || kind.startsWith('spot_'))) {
      return 'platform';
    }
    if (to == 'courier') return 'courier';
    if (to == null &&
        (kind.startsWith('courier_') || kind == 'delivery_available' || kind == 'delivery_cancelled')) {
      return 'courier';
    }
    if (to == 'customer') return 'customer';
    if (to == null &&
        const {
          'order_accepted', 'order_ready', 'order_picked_up', 'order_refused',
          'order_cancelled', 'order_courier', 'order_in_transit',
        }.contains(kind)) {
      return 'customer';
    }
    if (to == 'me') return 'me';
    return orgId != null ? 'shop' : 'me';
  }
}

/// The unread number of each list (notification_counts, 115).
class NotificationCounts {
  const NotificationCounts({
    this.orgs = const {},
    this.customer = 0,
    this.courier = 0,
    this.platform = 0,
    this.me = 0,
  });

  final Map<String, int> orgs;
  final int customer;
  final int courier;
  final int platform;

  /// The account's own rows, counted in every bell.
  final int me;

  static const none = NotificationCounts();

  /// What one bell shows.
  int of(NotifyScope scope) =>
      me +
      switch (scope.name) {
        'shop' => orgs[scope.orgId] ?? 0,
        'customer' => customer,
        'courier' => courier,
        'platform' => platform,
        _ => 0,
      };

  factory NotificationCounts.fromJson(Map<String, dynamic> j) {
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    final orgs = j['orgs'] is Map ? Map<String, dynamic>.from(j['orgs'] as Map) : const {};
    return NotificationCounts(
      orgs: {for (final e in orgs.entries) e.key: n(e.value)},
      customer: n(j['customer']),
      courier: n(j['courier']),
      platform: n(j['platform']),
      me: n(j['me']),
    );
  }

  /// The same numbers from rows, for a database before 115.
  factory NotificationCounts.fromRows(Iterable<NotificationRow> rows) {
    final orgs = <String, int>{};
    var customer = 0, courier = 0, platform = 0, me = 0;
    for (final r in rows.where((r) => r.isUnread)) {
      switch (r.scope) {
        case 'shop':
          orgs[r.orgId!] = (orgs[r.orgId!] ?? 0) + 1;
        case 'customer':
          customer++;
        case 'courier':
          courier++;
        case 'platform':
          platform++;
        default:
          me++;
      }
    }
    return NotificationCounts(
        orgs: orgs, customer: customer, courier: courier, platform: platform, me: me);
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationCounts &&
      other.customer == customer &&
      other.courier == courier &&
      other.platform == platform &&
      other.me == me &&
      other.orgs.length == orgs.length &&
      orgs.entries.every((e) => other.orgs[e.key] == e.value);

  @override
  int get hashCode => Object.hash(customer, courier, platform, me, orgs.length);
}

/// One switch of the person's (115's notification_types).
class NotificationPref {
  const NotificationPref({
    required this.type,
    required this.audience,
    required this.label,
    required this.enabled,
  });

  final String type;

  /// 'customer', 'courier' or 'shop': whose switches it is among.
  final String audience;

  /// The server's French name for it.
  final String label;
  final bool enabled;
}

/// The bell, server side. Rows are written by triggers in 030 and RLS
/// scopes every query to the signed-in recipient, so this repository never
/// names a user: whoever holds the session reads their own bell and
/// nobody else's.
class NotificationsRepository {
  NotificationsRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  /// The one live keeper of the counts, shared by every bell and every
  /// bar of the app (bell.dart).
  late final Bell bell = Bell(this);

  SupabaseClient get _c {
    final c = _client;
    if (c == null) {
      throw StateError(
          "Cette version de l'application a été compilée sans serveur.");
    }
    return c;
  }

  /// The signed-in person, or null.
  String? get me => _client?.auth.currentUser?.id;

  /// This browser said yes to push (060): its address goes under the
  /// signed-in account, where the push Worker will find it.
  Future<void> savePushSubscription(PushSubscriptionInfo sub) async {
    if (sub.fcmToken != null) {
      await _c.rpc('save_fcm_token', params: {
        'p_token': sub.fcmToken,
        'p_label': sub.userAgent,
      });
      return;
    }
    await _c.rpc('save_push_subscription', params: {
      'p_endpoint': sub.endpoint,
      'p_p256dh': sub.p256dh,
      'p_auth': sub.auth,
      'p_user_agent': sub.userAgent,
    });
  }

  /// This browser said no again.
  Future<void> removePushSubscription(String endpoint) async {
    await _c.rpc('remove_push_subscription', params: {'p_endpoint': endpoint});
  }

  /// Whether this device's address is in the person's book (the bug of
  /// before 115: a browser that had said yes but whose row was never
  /// written was never offered again, and never rang).
  Future<bool> hasPushSubscription(String endpoint) async {
    final rows = await _c
        .from('push_subscriptions')
        .select('endpoint')
        .eq('endpoint', endpoint)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// The most recent rings, newest first, of every list.
  ///
  /// The business and the facts (099) come with each row; a database before
  /// 099 has no params column, and then the rows come without them rather
  /// than the bell going silent.
  Future<List<NotificationRow>> recent({int limit = 50}) async {
    Future<List<dynamic>> read(String columns) => _c
        .from('notifications')
        .select(columns)
        .order('created_at', ascending: false)
        .limit(limit);
    List<dynamic> rows;
    try {
      rows = await read('id, kind, message, created_at, read_at, org_id, params');
    } on PostgrestException catch (e) {
      if (e.code != '42703' && e.code != 'PGRST204') rethrow;
      rows = await read('id, kind, message, created_at, read_at, org_id');
    }
    return rows
        .map((r) => NotificationRow.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// One list's rings, newest first (115): this business's, my purchases,
  /// my deliveries or the platform's — with the account's own in each. A
  /// database before 115 has no scope column; the rows are then sorted here,
  /// from the recent ones.
  Future<List<NotificationRow>> inScope(NotifyScope scope, {int limit = 50}) async {
    final list = scope.orgId == null
        ? 'scope.eq.me,scope.eq.${scope.name}'
        : 'scope.eq.me,and(scope.eq.shop,org_id.eq.${scope.orgId})';
    try {
      final rows = await _c
          .from('notifications')
          .select('id, kind, message, created_at, read_at, org_id, params, scope')
          .or(list)
          .order('created_at', ascending: false)
          .limit(limit);
      return [
        for (final r in rows) NotificationRow.fromRow(Map<String, dynamic>.from(r as Map)),
      ];
    } on PostgrestException catch (e) {
      if (e.code != '42703' && e.code != 'PGRST204' && e.code != 'PGRST100') rethrow;
      return (await recent(limit: limit * 2)).where(scope.holds).take(limit).toList();
    }
  }

  /// Marks read exactly these rows — the ones a list showed — and nothing
  /// else (before 115 opening one business's list cleared every list).
  Future<void> markRead(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await _c
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .inFilter('id', list)
        .filter('read_at', 'is', null);
  }

  /// The unread number of every list (115). Before 115 the numbers are
  /// counted from the recent rows, the way the bell always did.
  Future<NotificationCounts> counts() async {
    try {
      final v = await _c.rpc('notification_counts');
      return v is Map
          ? NotificationCounts.fromJson(Map<String, dynamic>.from(v))
          : NotificationCounts.none;
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
      return NotificationCounts.fromRows(await recent());
    }
  }

  /// What asks for action in one business, for its bar (home_counts, 115):
  /// orders, bookings, articles, invoices, credit, invitations, supplies,
  /// livestock. Empty before 115 or for somebody not of the business.
  Future<Map<String, int>> homeCounts(String orgId) async {
    try {
      final v = await _c.rpc('home_counts', params: {'p_org': orgId});
      if (v is! Map) return const {};
      return {
        for (final e in v.entries)
          '${e.key}': e.value is num ? (e.value as num).toInt() : 0,
      };
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
      return const {};
    }
  }

  /// Calls [onChange] whenever a row of the signed-in person's bell is
  /// written or read (115: Realtime, under the table's own security — a
  /// phone hears only its own rows). Returns the way to stop listening.
  void Function() watch(String userId, void Function() onChange) {
    final client = _client;
    if (client == null) return () {};
    final channel = client
        .channel('bell-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: userId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return () => client.removeChannel(channel);
  }

  /// The person's switches (115), the catalog's defaults where they never
  /// moved one. Empty before 115.
  Future<List<NotificationPref>> prefs() async {
    try {
      final rows = await _c.rpc('my_notification_prefs');
      return [
        for (final r in (rows as List? ?? const []))
          NotificationPref(
            type: (r as Map)['type'] as String,
            audience: r['audience'] as String,
            label: r['label'] as String,
            enabled: r['enabled'] == true,
          ),
      ];
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
      return const [];
    }
  }

  /// One switch moved. Off writes nothing: no bell row, so no push either.
  Future<void> setPref(String type, bool enabled) async {
    await _c.rpc('set_notification_pref', params: {'p_type': type, 'p_enabled': enabled});
  }

  /// « M'envoyer une notification test » (115): rings the caller's own
  /// devices; answers how many browsers and phones they have, and — to the
  /// platform — whether the database webhook that wakes the Worker exists.
  Future<({int web, int android, bool? webhook})> sendTest() async {
    final v = Map<String, dynamic>.from(await _c.rpc('send_test_notification') as Map);
    int n(Object? x) => x is num ? x.toInt() : 0;
    return (
      web: n(v['web']),
      android: n(v['android']),
      webhook: v['webhook'] as bool?,
    );
  }
}
