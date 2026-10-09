import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/errors.dart';
import 'package:kaj_app/core/retail/stock_rule.dart';
import 'package:kaj_app/features/common/refused_notice.dart';
import 'package:kaj_app/core/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The till that works with no signal (package 7).
///
/// The audit: farm and association entries waited on the phone and went
/// later, but a shop sale went straight to the server and failed with an
/// error offline — the busiest screen was the one that broke when the
/// network dropped.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('only the transport counts as offline, never a refusal', () {
    expect(isOffline(const SocketException('Failed host lookup')), isTrue);
    expect(isOffline(const PostgrestException(message: 'Il ne reste que 2 Savon')),
        isFalse);
  });

  test('a queued sale the server refuses for stock stops, is kept for the owner, and goes when read (101)',
      () async {
    final db = await LocalDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    await db.queueSale(orgId: 'o1', clientUuid: 'c-1', params: {
      'p_org_id': 'o1',
      'p_lines': [
        {'product_id': 'p1', 'name': 'Savon', 'quantity': 3, 'unit_price': 450},
      ],
      'p_client_uuid': 'c-1',
    });
    await db.queueSale(orgId: 'o1', clientUuid: 'c-2', params: {
      'p_org_id': 'o1',
      'p_lines': [
        {'product_id': 'p2', 'name': 'Riz', 'quantity': 1, 'unit_price': 500},
      ],
      'p_client_uuid': 'c-2',
    });
    var calls = 0;
    final sync = SyncService(
      db,
      SupabaseClient('https://example.supabase.co', 'anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false)),
      currentUserId: () => 'u1',
      post: (action, params) async {
        calls++;
        if (params['p_client_uuid'] == 'c-1') {
          throw const PostgrestException(
              message: 'Il ne reste que 2 Savon', code: 'P0001');
        }
        // Any other failure keeps the row for a retry, as before.
        throw const SocketException('Failed host lookup');
      },
    );
    await sync.syncNow();
    expect(calls, 2);
    final refused = await db.refusedActions('o1');
    expect(refused.single['client_uuid'], 'c-1');
    expect(refused.single['last_error'], 'Il ne reste que 2 Savon');
    expect(await db.pendingSales('o1'), 1, reason: 'the refused one is no longer waiting');

    await sync.syncNow();
    expect(calls, 3, reason: 'the refused sale is not sent again; the other is retried');

    final notice = RefusedAction.fromRow(refused.single);
    expect(notice.what, '3 × Savon');
    expect(stockShortText('en', notice.reason), 'Only 2 Savon left');

    await db.dismissRefused('c-1');
    expect(await db.refusedActions('o1'), isEmpty);
    expect(await db.pendingSales('o1'), 1);
  });

  testWidgets('the refused sale is said on the home, and put away with « Compris »',
      (tester) async {
    RefusedAction? put;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RefusedNotice(
          actions: const [
            RefusedAction(
                clientUuid: 'c-1',
                action: 'record_sale',
                what: '3 × Savon',
                reason: 'Il ne reste que 2 Savon'),
          ],
          onDismiss: (a) => put = a,
        ),
      ),
    ));
    expect(find.text('Vente refusée : rien n\'a été enregistré'), findsOneWidget);
    expect(find.text('3 × Savon'), findsOneWidget);
    expect(find.text('Il ne reste que 2 Savon'), findsOneWidget);
    await tester.tap(find.text('Compris'));
    expect(put?.clientUuid, 'c-1');
  });

  test('a refusal is known by its code first, MA001, whatever its words (101)',
      () async {
    final db = await LocalDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    await db.queueSale(orgId: 'o1', clientUuid: 'c-9', params: {
      'p_org_id': 'o1',
      'p_lines': [
        {'product_id': 'p1', 'name': 'Savon', 'quantity': 4, 'unit_price': 450},
      ],
      'p_client_uuid': 'c-9',
    });
    final sync = SyncService(
      db,
      SupabaseClient('https://example.supabase.co', 'anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false)),
      currentUserId: () => 'u1',
      post: (action, params) async => throw const PostgrestException(
          message: 'Only 1 left (a later wording)', code: stockRefusalCode),
    );
    await sync.syncNow();
    expect((await db.refusedActions('o1')).single['client_uuid'], 'c-9');
  });

  test('« Corriger le stock » sends the same sale again; waiting sales count against the shelf',
      () async {
    final db = await LocalDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    for (final (id, q) in [('c-1', 2), ('c-2', 1)]) {
      await db.queueSale(orgId: 'o1', clientUuid: id, params: {
        'p_org_id': 'o1',
        'p_lines': [
          {'product_id': 'p1', 'name': 'Savon', 'quantity': q, 'unit_price': 450},
          {'name': 'Bougie', 'quantity': 1, 'unit_price': 100},
        ],
        'p_client_uuid': id,
      });
    }
    expect(await db.pendingSaleQuantities('o1'),
        {'p1': 3.0, 'name:bougie': 2.0});
    await db.markRefused('c-1', 'Il ne reste que 1 Savon');
    expect(await db.pendingSaleQuantities('o1'), {'p1': 1.0, 'name:bougie': 1.0},
        reason: 'a refused sale takes nothing');
    final notice = RefusedAction.fromRow((await db.refusedActions('o1')).single);
    expect(notice.shortfall, (name: 'Savon', missing: 1.0));
    await db.requeueRefused('c-1');
    expect(await db.refusedActions('o1'), isEmpty);
    expect(await db.pendingSales('o1'), 2, reason: 'the same sale, waiting again');
  });

  testWidgets('the refused sale offers « Corriger le stock puis refaire la vente »',
      (tester) async {
    RefusedAction? fixed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RefusedNotice(
          actions: const [
            RefusedAction(
                clientUuid: 'c-1',
                action: 'record_sale',
                what: '3 × Savon',
                reason: 'Il ne reste que 2 Savon',
                lines: {'Savon': 3}),
          ],
          onDismiss: (_) {},
          onFix: (a) => fixed = a,
        ),
      ),
    ));
    await tester.tap(find.text('Corriger le stock puis refaire la vente'));
    expect(fixed?.shortfall, (name: 'Savon', missing: 1.0));
    expect(find.text('Compris'), findsOneWidget);
  });
}
