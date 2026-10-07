import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';

import 'push_client.dart';

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

  bool get isUnread => readAt == null;

  factory NotificationRow.fromRow(Map<String, dynamic> r) => NotificationRow(
        id: r['id'] as String,
        kind: r['kind'] as String,
        message: brandText(r['message'] as String),
        createdAt: DateTime.parse(r['created_at'] as String),
        readAt: r['read_at'] == null
            ? null
            : DateTime.parse(r['read_at'] as String),
        orgId: r['org_id'] as String?,
        params: r['params'] is Map
            ? Map<String, dynamic>.from(r['params'] as Map)
            : const {},
      );
}

/// The bell, server side. Rows are written by triggers in 030 and RLS
/// scopes every query to the signed-in recipient, so this repository never
/// names a user: whoever holds the session reads their own bell and
/// nobody else's.
class NotificationsRepository {
  NotificationsRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  SupabaseClient get _c {
    final c = _client;
    if (c == null) {
      throw StateError(
          "Cette version de l'application a été compilée sans serveur.");
    }
    return c;
  }

  /// This browser said yes to push (060): its address goes under the
  /// signed-in account, where the push Worker will find it.
  Future<void> savePushSubscription(PushSubscriptionInfo sub) async {
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

  /// The most recent rings, newest first. Unread count is derived from the
  /// same fetch — one round trip feeds both the badge and the list.
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

  /// Marks everything read. Called when the list opens: a bell that stays
  /// red after being looked at trains people to ignore it.
  Future<void> markAllRead() async {
    await _c
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .filter('read_at', 'is', null);
  }
}
