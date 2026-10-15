import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The offline/online seam: the outbox drain must survive a stalled push.
///
/// A push that stalls — the socket open, the reply never coming — used to hang
/// the drain loop forever, because the pending await never returned, `_running`
/// never cleared, and every later sync then early-returned on `if (_running)`.
/// One stall wedged the sync until the app restarted, and everything recorded
/// offline in the meantime sat unsent. Bounded by a timeout, a stall is just a
/// row left to retry, and the very next sync still drains it.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  // Never used: every network call and the user id are injected below. Built
  // lazily and without a connection, purely to satisfy the constructor.
  final dummy = SupabaseClient('https://example.supabase.co', 'anon-key');

  test('a stalled push does not wedge the sync; the next one drains it',
      () async {
    await db.recordEntry(
      orgId: 'org-1',
      amount: 2000,
      direction: 'in',
      label: 'Offrande',
    );
    expect(await db.pendingCount(), 1);

    var stall = true;
    final sync = SyncService(
      db,
      dummy,
      currentUserId: () => 'user-1',
      rpcTimeout: const Duration(milliseconds: 50),
      post: (action, params) {
        // A socket that never answers, then — once the connection "returns" —
        // a normal success carrying a server id.
        if (stall) return Completer<dynamic>().future;
        return Future<dynamic>.value('server-id-123');
      },
    );

    // The stalled push must not hang the loop: syncNow has to return.
    await sync.syncNow().timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('syncNow hung on a stalled push'),
        );
    expect(await db.pendingCount(), 1,
        reason: 'a stalled push must leave the row to retry, not drop it');

    // The connection returns. The SAME service — proving _running was not left
    // stuck — drains the outbox on the next sweep.
    stall = false;
    await sync.syncNow();
    expect(await db.pendingCount(), 0,
        reason: 'the sync was wedged: a later sweep could not drain the row');
  });

  test('recorded with no signal — an expense, a contribution, a farm\'s day — sent once the network is back, once',
      () async {
    // The shop's expense, the association's contribution, the farm's
    // delivery, feed and deaths: all on the phone, none sent.
    await db.recordEntry(
        orgId: 'shop', amount: 5000, direction: 'out', label: 'Loyer');
    await db.recordEntry(
        orgId: 'asso', amount: 2000, direction: 'in', label: 'Cotisation — Awa');
    await db.receiveStock(
        orgId: 'farm', itemName: 'Aliment ponte', quantity: 20, unitCost: 17500);
    await db.moveStock(
        orgId: 'farm', itemName: 'Aliment ponte', quantity: 2, kind: 'consumed');
    await db.recordFlockEvent(
        orgId: 'farm',
        flockId: 'flock-1',
        batchCode: 'B1',
        kind: 'mortality',
        quantity: 3);
    expect(await db.pendingCount(), 5);

    var online = false;
    final sent = <String, int>{};
    final sync = SyncService(
      db,
      dummy,
      currentUserId: () => 'user-1',
      post: (action, params) async {
        if (!online) throw const SocketException('Failed host lookup');
        final uuid = params['p_client_uuid'] as String;
        sent[uuid] = (sent[uuid] ?? 0) + 1;
        expect(params['p_recorded_by'], 'user-1');
        return 'server-$uuid';
      },
    );

    // Still no signal: nothing is lost, everything waits.
    await sync.syncNow();
    expect(await db.pendingCount(), 5);

    online = true;
    await sync.syncNow();
    expect(await db.pendingCount(), 0);
    expect(sent, hasLength(5));
    // A later sweep (the connection flapping, the five-minute timer) does
    // not send any of them again.
    await sync.syncNow();
    expect(sent.values, everyElement(1));
  });
}
