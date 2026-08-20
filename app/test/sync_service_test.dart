import 'dart:async';

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
}
