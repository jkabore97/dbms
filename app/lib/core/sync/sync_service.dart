import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/local_db.dart';

/// Drains the outbox to the server whenever there's a connection.
///
/// This is safe to run at any time, repeatedly, in any order, because every
/// server function takes the device-generated `client_uuid` and returns the
/// existing row if it has already seen it. A retry after a dropped connection
/// cannot double-post an offering — that guarantee lives in the database
/// (see `record_contribution` in 002_church_profile.sql), not in this file.
class SyncService {
  SyncService(this._db, this._supabase);

  final LocalDb _db;
  final SupabaseClient _supabase;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodicTimer;
  bool _running = false;

  /// Sync when the connection returns, and periodically as a fallback.
  void start() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) unawaited(syncNow());
    });

    _periodicTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(syncNow()),
    );

    unawaited(syncNow());
  }

  void dispose() {
    _connectivitySub?.cancel();
    _periodicTimer?.cancel();
  }

  /// Attempts to push every pending action. Failures are left in the outbox
  /// to be retried later — nothing is dropped, nothing is lost.
  Future<void> syncNow() async {
    if (_running) return;
    _running = true;

    try {
      final pending = await _db.pendingActions();

      for (final row in pending) {
        final clientUuid = row['client_uuid'] as String;
        final action = row['action'] as String;
        final payload =
            jsonDecode(row['payload'] as String) as Map<String, dynamic>;

        try {
          final userId = _supabase.auth.currentUser?.id;
          if (userId == null) return; // Not signed in; try again later.

          if (action == 'reverse_entry') {
            // A reversal references the original by its client uuid, which the
            // server resolves to the real entry id.
            await _supabase.rpc('reverse_entry_by_client_uuid', params: {
              'p_org_id': row['org_id'],
              'p_original_client_uuid': payload['p_original_client_uuid'],
              'p_reversed_by': userId,
              'p_reason': payload['p_reason'],
            });
            await _db.markSynced(clientUuid);
          } else {
            final serverId = await _supabase.rpc(
              action,
              params: {...payload, 'p_recorded_by': userId},
            );
            await _db.markSynced(clientUuid, serverId: serverId as String?);
          }
        } catch (e) {
          // Network down, server busy, or a genuine rejection. Either way the
          // row stays in the outbox. Only the error is recorded.
          await _db.markFailed(clientUuid, e.toString());
        }
      }
    } finally {
      _running = false;
    }
  }
}
