import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// The super admin's window onto the server: what people have been doing, and
/// what the database actually holds.
///
/// Everything here is gated server-side on `is_org_admin()` — the functions in
/// 008 check it themselves and return nothing rather than raising, so a
/// non-admin who somehow reached these screens sees empty lists rather than an
/// error that would tell them something exists.
///
/// Nothing is cached. A log read from a week-old copy would be the one screen
/// in the app where being out of date is actively misleading: it is consulted
/// precisely when somebody suspects a change was made, and an answer of "no
/// changes" that means "no changes as of last Tuesday" is worse than no answer.
class ConsoleRepository {
  ConsoleRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  // ----------------------------------------------------------------
  // The activity log
  // ----------------------------------------------------------------

  /// One page of the log, newest first.
  ///
  /// [before] is the id of the oldest row already on screen. Keyset paging
  /// rather than an offset, because the log grows at the top while somebody is
  /// reading down it and an offset would show them the same row twice.
  Future<List<AuditEvent>> log(
    String orgId, {
    int limit = 50,
    int? before,
    String? table,
    String? actorId,
    String? action,
  }) async {
    final client = _requireClient();
    final rows = await client.rpc('audit_log_page', params: {
      'p_org_id': orgId,
      'p_limit': limit,
      if (before != null) 'p_before': before,
      if (table != null) 'p_table': table,
      if (actorId != null) 'p_actor': actorId,
      if (action != null) 'p_action': action,
    }) as List<dynamic>;

    return rows
        .map((r) => AuditEvent.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Who has appeared in the log, busiest-recently first. Reading a log
  /// usually starts with "who has been doing things", not with a date.
  Future<List<AuditActor>> actors(String orgId) async {
    final client = _requireClient();
    final rows = await client.rpc(
      'audit_log_actors',
      params: {'p_org_id': orgId},
    ) as List<dynamic>;

    return rows
        .map((r) => AuditActor.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // ----------------------------------------------------------------
  // The database
  // ----------------------------------------------------------------

  /// Every table that holds anything belonging to this business, what it is
  /// for, how many rows of it are theirs, and when it last moved.
  Future<List<DatabaseTable>> databaseOverview(String orgId) async {
    final client = _requireClient();
    final rows = await client.rpc(
      'org_database_overview',
      params: {'p_org_id': orgId},
    ) as List<dynamic>;

    return rows
        .map((r) => DatabaseTable.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// What one table is made of. Structure only — this never returns a row of
  /// anybody's data, and 008 refuses any table outside the app's own.
  Future<List<TableColumn>> tableColumns(String orgId, String table) async {
    final client = _requireClient();
    final rows = await client.rpc('org_table_columns', params: {
      'p_org_id': orgId,
      'p_table': table,
    }) as List<dynamic>;

    return rows
        .map((r) => TableColumn.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError(
        "Cette version de l'application a été compilée sans serveur. "
        'Reconstruisez-la avec SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY.',
      );
    }
    return client;
  }
}
