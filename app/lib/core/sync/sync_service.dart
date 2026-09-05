import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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
  SyncService(
    this._db,
    this._supabase, {
    // Injected in tests so the outbox drain can be exercised without a live
    // Supabase client. Both default to the real client in the app.
    @visibleForTesting
    Future<dynamic> Function(String action, Map<String, dynamic> params)? post,
    @visibleForTesting this._currentUserId,
    this.rpcTimeout = const Duration(seconds: 20),
  })  : _postOverride = post;

  final LocalDb _db;
  final SupabaseClient _supabase;

  final Future<dynamic> Function(String, Map<String, dynamic>)? _postOverride;
  final String? Function()? _currentUserId;

  /// How long a single push may stall before it is treated as a failure and
  /// left in the outbox to retry. Without this a stalled socket — the reply
  /// that never comes, common on a market connection — hangs the drain loop
  /// forever: the pending await never returns, so `_running` never clears, and
  /// `if (_running) return` then turns every later sync into a silent no-op.
  /// One stalled push would wedge the sync until the app was restarted, and
  /// everything recorded offline in the meantime would sit unsent — an offline
  /// notebook the server never hears about. Bounded, a stall is just a retry.
  final Duration rpcTimeout;

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

  String? get _userId => _currentUserId != null
      ? _currentUserId()
      : _supabase.auth.currentUser?.id;

  /// One push to the server, bounded by [rpcTimeout] so it cannot hang the
  /// drain loop. A timeout surfaces as a TimeoutException, which the caller
  /// treats like any other failure: the row stays in the outbox to retry.
  Future<dynamic> _post(String action, Map<String, dynamic> params) {
    final call = _postOverride != null
        ? _postOverride(action, params)
        : _supabase.rpc(action, params: params);
    return call.timeout(rpcTimeout);
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
          final userId = _userId;
          if (userId == null) return; // Not signed in; try again later.

          if (action == 'reverse_entry') {
            // A reversal references the original by its client uuid, which the
            // server resolves to the real entry id.
            await _post('reverse_entry_by_client_uuid', {
              'p_org_id': row['org_id'],
              'p_original_client_uuid': payload['p_original_client_uuid'],
              'p_reversed_by': userId,
              'p_reason': payload['p_reason'],
            });
            await _db.markSynced(clientUuid);
          } else {
            final serverId =
                await _post(action, {...payload, 'p_recorded_by': userId});
            await _db.markSynced(clientUuid, serverId: serverId as String?);
          }
        } catch (e) {
          // Network down, server busy, a stalled socket past the timeout, or a
          // genuine rejection. Either way the row stays in the outbox. Only the
          // error is recorded.
          await _db.markFailed(clientUuid, e.toString());
        }
      }
    } finally {
      _running = false;
    }
  }
}
