import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/sync/sync_service.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/retail/sale_flow.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The till's catalogue kept on the phone (the offline audit).
///
/// Before: the products were read from the server each time and kept
/// nowhere, so on an offline cold start the till — the shop's, and the
/// farm's « Vente » — had nothing to offer: every name typed by hand, and
/// no stock to stop the last soap being sold twice.

/// The server, as a shop's phone reaches it: [mode] 'up' answers the
/// catalogue, 'down' has no network at all, 'stall' takes the request and
/// never answers.
class _Server {
  String mode = 'up';
  var rows = <Map<String, Object?>>[];
  var photoKeys = <Map<String, Object?>>[];
  int productReads = 0;

  late final client = SupabaseClient(
    'https://example.supabase.co',
    'sb_publishable_test',
    httpClient: MockClient((r) async {
      if (mode == 'down') throw http.ClientException('Failed host lookup');
      if (mode == 'stall') return Completer<http.Response>().future;
      const json = {'content-type': 'application/json'};
      if (r.url.path == '/rest/v1/products') {
        productReads++;
        return http.Response(jsonEncode(rows), 200, headers: json, request: r);
      }
      if (r.url.path == '/rest/v1/rpc/product_photo_keys') {
        return http.Response(jsonEncode(photoKeys), 200, headers: json, request: r);
      }
      return http.Response('[]', 200, headers: json, request: r);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

/// The shop's phone with no network at all, as the screens meet it (the
/// HTTP client's own retry timers have no place in a widget test): every
/// question fails, a sale's with the socket's own error.
class _NoSignal extends RetailRepository {
  _NoSignal(LocalDb db) : super(null, outbox: db);

  @override
  bool get isConfigured => true;

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
      throw const SocketException('Failed host lookup');
}

Map<String, Object?> _row(String id, String name,
        {double qty = 0,
        double price = 0,
        bool service = false,
        bool tracked = true}) =>
    {
      'id': id,
      'name': name,
      'sale_price': price,
      'cost_price': 100,
      'quantity': qty,
      'is_ingredient': false,
      'is_published': false,
      'is_service': service,
      'stock_tracked': tracked,
      'unit': null,
    };

Future<void> _queue(LocalDb db, String org, String uuid,
    List<Map<String, Object?>> lines) {
  return db.queueSale(orgId: org, clientUuid: uuid, params: {
    'p_org_id': org,
    'p_lines': lines,
    'p_client_uuid': uuid,
  });
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('kept on the phone', () {
    late LocalDb db;
    setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
    tearDown(() => db.close());

    test('each read from the server is kept, per business, and replaces the last',
        () async {
      final server = _Server()
        ..rows = [_row('p1', 'Savon', qty: 4, price: 450), _row('p2', 'Riz', qty: 9)];
      final retail = RetailRepository(server.client, outbox: db);

      await retail.products('o1');
      var kept = await retail.keptProducts('o1');
      expect(kept.map((p) => p.name), ['Riz', 'Savon']);
      expect(kept.firstWhere((p) => p.id == 'p1').salePrice, 450);
      expect(await retail.keptProducts('o2'), isEmpty,
          reason: 'one business never sees another\'s shelf');

      // Retired on the server: gone here too.
      server.rows = [_row('p1', 'Savon', qty: 3, price: 450)];
      await retail.products('o1');
      kept = await retail.keptProducts('o1');
      expect(kept.single.quantity, 3);
      // Only the active list is the till's: the full one is not kept.
      server.rows = [_row('p1', 'Savon', qty: 3), _row('px', 'Ancien')];
      await retail.products('o1', activeOnly: false);
      expect((await retail.keptProducts('o1')).single.id, 'p1');
    });

    test('a stalled server: the till sells from the list it last read', () async {
      final server = _Server()..rows = [_row('p1', 'Savon', qty: 4)];
      final retail = RetailRepository(server.client, outbox: db);
      final first = await retail.tillProducts('o1');
      expect(first.fromDevice, isFalse);

      server.mode = 'stall';
      final shelf = await retail
          .tillProducts('o1', timeout: const Duration(milliseconds: 50))
          .timeout(const Duration(seconds: 5),
              onTimeout: () => fail('the till waited on the stalled server'));
      expect(shelf.fromDevice, isTrue);
      expect(shelf.products.single.name, 'Savon');

      // Nothing ever read: the server's failure, as before.
      await expectLater(
          retail.tillProducts('o2', timeout: const Duration(milliseconds: 50)),
          throwsA(isA<TimeoutException>()));
    });

    test('a sale sent after the list was read comes off it; one sent before does not',
        () async {
      await _queue(db, 'o1', 'before', [
        {'product_id': 'p1', 'name': 'Savon', 'quantity': 1, 'unit_price': 450},
      ]);
      await db.markSynced('before');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await db.cacheProducts('o1', [_row('p1', 'Savon', qty: 5)],
          askedAt: DateTime.now());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await _queue(db, 'o1', 'after', [
        {'product_id': 'p1', 'name': 'Savon', 'quantity': 2, 'unit_price': 450},
      ]);
      await _queue(db, 'o1', 'waiting', [
        {'product_id': 'p1', 'name': 'Savon', 'quantity': 1, 'unit_price': 450},
      ]);
      await db.markSynced('after');

      final kept = await db.cachedProducts('o1');
      expect(kept.single['quantity'], 3.0,
          reason: '5 read; 2 reached the server since; the waiting one is the till\'s to count');
      expect(await db.pendingSaleQuantities('o1'), {'p1': 1.0});
    });

    test('a sale the server took at once comes off the kept count', () async {
      await db.cacheProducts('o1', [
        _row('p1', 'Savon', qty: 5),
        _row('s1', 'Coupe', service: true),
        _row('t1', 'Entrée', tracked: false),
      ], askedAt: DateTime.now());
      await db.takeFromCachedProducts('o1', [
        {'product_id': 'p1', 'name': 'Savon', 'quantity': 2},
        {'name': 'savon ', 'quantity': 1},
        {'product_id': 's1', 'name': 'Coupe', 'quantity': 1},
        {'product_id': 't1', 'name': 'Entrée', 'quantity': 3},
      ]);
      final byId = {
        for (final r in await db.cachedProducts('o1')) r['id']: r['quantity'],
      };
      expect(byId, {'p1': 2.0, 's1': 0.0, 't1': 0.0});
    });

    test('the photo keys stay with their articles across a new read', () async {
      final server = _Server()
        ..rows = [_row('p1', 'Savon', qty: 4)]
        ..photoKeys = [
          {'product_id': 'p1', 'photo_key': 'o1/p1.jpg'},
        ];
      final retail = RetailRepository(server.client, outbox: db);
      await retail.products('o1');
      await retail.photoKeys('o1');
      await retail.products('o1');
      expect((await db.cachedProducts('o1')).single['photo_key'], 'o1/p1.jpg');
    });

    test('signing out clears the kept catalogue; the outbox and the device stay',
        () async {
      await db.saveIdentity(const LocalIdentity(userId: 'u1'));
      await db.cacheProducts('o1', [_row('p1', 'Savon', qty: 5)],
          askedAt: DateTime.now());
      await _queue(db, 'o1', 'c-1', [
        {'product_id': 'p1', 'name': 'Savon', 'quantity': 1, 'unit_price': 450},
      ]);
      await db.writePref('language', 'fr');
      await db.clearIdentity();
      expect(await db.cachedProducts('o1'), isEmpty);
      expect(await db.pendingSales('o1'), 1,
          reason: 'work already recorded is never deleted at sign-out');
      expect(await db.readPref('language'), 'fr');
    });
  });

  group('the till with no signal', () {
    Widget app(Widget home) => MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          home: home,
        );

    Future<void> flush(WidgetTester tester, {int rounds = 8}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pump();
    }

    testWidgets(
        'an offline cold start: the shop\'s till lists the kept catalogue and refuses '
        'more than is left after the sales waiting on the phone', (tester) async {
      tester.view.physicalSize = const Size(480, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() async {
        await db.cacheProducts('o1', [
          _row('p1', 'Savon', qty: 2, price: 450),
          _row('s1', 'Livraison', service: true, price: 1000),
          _row('t1', 'Ticket', tracked: false, price: 500),
        ], askedAt: DateTime.now());
        // Sold earlier today with no signal, still on the phone.
        await _queue(db, 'o1', 'c-1', [
          {'product_id': 'p1', 'name': 'Savon', 'quantity': 1, 'unit_price': 450},
        ]);
      });
      await tester.pumpWidget(app(StoreHomeScreen(
        org: const OrgSummary(
            id: 'o1', name: 'Boutique Esperance', profile: 'retail', roles: ['cashier']),
        retail: _NoSignal(db),
      )));
      await flush(tester);
      await tester.tap(find.byKey(const Key('home-new-sale')));
      await flush(tester);
      await tester.pumpAndSettle();

      expect(find.byType(SaleFlow), findsOneWidget);
      // Before: no tiles at all — every name typed by hand.
      expect(find.byKey(const ValueKey('sale-pick-p1')), findsOneWidget);
      expect(find.byKey(const Key('sale-from-device')), findsOneWidget);
      expect(find.text('Reste : 1'), findsOneWidget,
          reason: '2 kept, 1 already sold on this phone');

      // The untracked ticket and the service have no count to run out of.
      await tester.tap(find.byKey(const ValueKey('sale-pick-t1')));
      await tester.tap(find.byKey(const ValueKey('sale-pick-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('sale-qty-t1')), '40');
      await tester.enterText(find.byKey(const ValueKey('sale-qty-p1')), '2');
      await tester.pumpAndSettle();
      expect(find.text('Il ne reste que 1 Savon'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('sale-qty-p1')), '1');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sale-stock-short')), findsNothing,
          reason: 'an untracked article sells whatever its 0');
    });

    testWidgets('the last one sold offline cannot be sold again at the next sale',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => db.cacheProducts(
          'o1', [_row('p1', 'Savon', qty: 1, price: 450)],
          askedAt: DateTime.now()));
      final retail = _NoSignal(db);
      final shelf = (await tester.runAsync(() => retail.tillProducts('o1')))!;

      await tester.pumpWidget(app(SaleFlow(
          orgId: 'o1',
          retail: retail,
          store: MemoryFlowStore(),
          products: shelf.products,
          productsFromDevice: shelf.fromDevice)));
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('sale-pick-p1')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('flow-next')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('flow-save')));
      await flush(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sale-done-queued')), findsOneWidget);

      // « Nouvelle vente »: the same phone, the same shelf — now empty.
      await tester.tap(find.byKey(const Key('sale-again')));
      await flush(tester);
      await tester.pumpAndSettle();
      expect(find.text('Plus en stock'), findsOneWidget);
      final tile = tester.widget<InkWell>(find.byKey(const ValueKey('sale-pick-p1')));
      expect(tile.onTap, isNull);
    });

    testWidgets('the farm\'s « Vente » on a stalled line: the produce it last read',
        (tester) async {
      tester.view.physicalSize = const Size(480, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      const org = OrgSummary(id: 'f1', name: 'Ferme Ignace', profile: 'farm');
      await tester.runAsync(() => db.cacheProducts(
          'f1', [_row('e1', 'Plateau d\'œufs', qty: 6, price: 2500)],
          askedAt: DateTime.now()));
      final server = _Server()..mode = 'stall';

      await tester.pumpWidget(app(FarmHomeScreen(
          db: db, org: org, retail: RetailRepository(server.client, outbox: db))));
      await flush(tester);
      await tester.tap(find.byKey(const Key('farm-sell')));
      await tester.pump(const Duration(seconds: 13));
      await flush(tester);
      await tester.pumpAndSettle();

      expect(find.byType(SaleFlow), findsOneWidget);
      expect(find.byKey(const ValueKey('sale-pick-e1')), findsOneWidget,
          reason: 'before: the produce was typed by name');
      expect(
          find.text('Produits et stock de cet appareil seulement. Ils seront à jour au retour du réseau.'),
          findsOneWidget);
      expect(find.text('Reste : 6'), findsOneWidget);
    });

    testWidgets('online: no word about the device', (tester) async {
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      await tester.pumpWidget(app(SaleFlow(
          orgId: 'o1',
          retail: RetailRepository(null, outbox: db),
          store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Savon', quantity: 3)])));
      await flush(tester);
      expect(find.byKey(const Key('sale-from-device')), findsNothing);
    });
  });

  test('a queued sale drains: the kept count follows, without counting it twice',
      () async {
    final db = await LocalDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    await db.cacheProducts('o1', [_row('p1', 'Savon', qty: 3)],
        askedAt: DateTime.now());
    await _queue(db, 'o1', 'c-1', [
      {'product_id': 'p1', 'name': 'Savon', 'quantity': 2, 'unit_price': 450},
    ]);
    // Waiting: the kept count is the server's 3; the till takes the 2 off.
    expect((await db.cachedProducts('o1')).single['quantity'], 3.0);
    expect(await db.pendingSaleQuantities('o1'), {'p1': 2.0});

    final sync = SyncService(
      db,
      SupabaseClient('https://example.supabase.co', 'anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false)),
      currentUserId: () => 'u1',
      post: (action, params) async => 'sale-1',
    );
    await sync.syncNow();
    // Sent: the server has it, the kept list does not yet — taken off there.
    expect(await db.pendingSaleQuantities('o1'), isEmpty);
    expect((await db.cachedProducts('o1')).single['quantity'], 1.0);
  });
}
