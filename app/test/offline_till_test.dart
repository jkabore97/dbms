import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/errors.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/sync/sync_service.dart';
import 'package:kaj_app/features/retail/sale_sheet.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The till that works with no signal (package 7).
///
/// The audit: farm and association entries waited on the phone and went
/// later, but a shop sale went straight to the server and failed with an
/// error offline — the busiest screen was the one that broke when the
/// network dropped.
class _NoSignal extends RetailRepository {
  _NoSignal(LocalDb db) : super(null, outbox: db);

  @override
  Future<String> recordSale({
    required String orgId,
    required List<SaleLineDraft> lines,
    String method = 'cash',
    String? note,
    String? clientUuid,
    String? deviceId,
    String? customerName,
    String? customerPhone,
  }) async =>
      throw const SocketException('Failed host lookup: dkrtntrcbhuuouctfyug');
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('only the transport counts as offline, never a refusal', () {
    expect(isOffline(const SocketException('Failed host lookup')), isTrue);
    expect(isOffline(const PostgrestException(message: 'Stock insuffisant')),
        isFalse);
  });

  testWidgets('a sale with no signal is kept on the phone, then sent once',
      (tester) async {
    tester.view.physicalSize = const Size(600, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = (await tester
        .runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
    addTearDown(() => tester.runAsync(db.close));

    bool? closed;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              closed = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SaleSheet(
                  orgId: 'o1',
                  retail: _NoSignal(db),
                  products: const [
                    Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 0),
                  ],
                ),
              );
            },
            child: const Text('Vendre'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Vendre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Savon'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter au panier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer la vente'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(closed, isTrue, reason: 'the sheet closes as if the sale went');
    expect(find.textContaining('vente gardée sur le téléphone'), findsOneWidget);
    expect(await tester.runAsync(() => db.pendingSales('o1')), 1);

    // The network returns: the sync sends it as record_sale, with its own
    // uuid and no p_recorded_by (record_sale takes its seller from the token).
    final sent = <Map<String, dynamic>>[];
    final sync = SyncService(
      db,
      SupabaseClient('https://example.supabase.co', 'anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false)),
      currentUserId: () => 'u1',
      post: (action, params) async {
        expect(action, 'record_sale');
        sent.add(params);
        return 'sale-1';
      },
    );
    await tester.runAsync(sync.syncNow);
    expect(sent.single['p_org_id'], 'o1');
    expect(sent.single['p_client_uuid'], isNotEmpty);
    expect(sent.single.containsKey('p_recorded_by'), isFalse);
    expect((sent.single['p_lines'] as List).single['name'], 'Savon');
    expect(await tester.runAsync(() => db.pendingSales('o1')), 0);

    await tester.runAsync(sync.syncNow);
    expect(sent, hasLength(1), reason: 'sent once, not again');
    // The snackbar's own clock, and the sheet's, run out before the end.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
