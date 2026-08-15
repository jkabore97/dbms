import 'package:supabase_flutter/supabase_flutter.dart';

/// One ring of the bell.
class NotificationRow {
  const NotificationRow({
    required this.id,
    required this.kind,
    required this.message,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String kind;
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory NotificationRow.fromRow(Map<String, dynamic> r) => NotificationRow(
        id: r['id'] as String,
        kind: r['kind'] as String,
        message: r['message'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        readAt: r['read_at'] == null
            ? null
            : DateTime.parse(r['read_at'] as String),
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

  /// The most recent rings, newest first. Unread count is derived from the
  /// same fetch — one round trip feeds both the badge and the list.
  Future<List<NotificationRow>> recent({int limit = 50}) async {
    final rows = await _c
        .from('notifications')
        .select('id, kind, message, created_at, read_at')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
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
