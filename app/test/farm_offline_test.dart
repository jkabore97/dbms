import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The M4 demo, driven through the screen: Ignace records a feed delivery with
/// no signal.
///
/// The farm module has one property everything else depends on, and it is not
/// an accounting property — it is that the recording works with no network at
/// all. Ignace is the user the offline architecture was built for. A screen
/// that needs signal is a screen he stops using in favour of the notebook that
/// always works, and then none of the rest of this matters.
///
/// So `FarmRepository` is deliberately absent from every test here. That is
/// exactly the state of a phone at the farm gate: the counts that need the
/// server cannot be computed, and everything Ignace does must still work.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  const org = OrgSummary(id: 'org-farm', name: 'Ferme Ignace', profile: 'farm');

  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  Future<void> flush(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
  }

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // No FarmRepository at all: this is the farm gate.
    await tester.pumpWidget(
      MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
        home: FarmHomeScreen(db: db, org: org)),
    );
    await flush(tester);
  }

  Future<void> tapKeys(WidgetTester tester, List<String> keys) async {
    for (final key in keys) {
      await tester.tap(find.widgetWithText(InkWell, key));
      await tester.pump();
    }
  }

  group('the home screen', () {
    testWidgets('leads with what the farm produced, not with money',
        (tester) async {
      await pumpHome(tester);

      // Egg collection was removed (eggs are ordinary stock now), so the
      // header leads with the flock figures — mortality tells you next week,
      // and the money, underneath, tells you last month.
      expect(find.text('œufs ramassés'), findsNothing);
      expect(find.text('Mortalité'), findsOneWidget);
      expect(find.text('Aliment sorti'), findsOneWidget);
      expect(find.text('Récolte'), findsOneWidget);
    });

    testWidgets('works with no repository at all', (tester) async {
      await pumpHome(tester);

      // No spinner stuck forever waiting on a server that is not there.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Ferme Ignace'), findsWidgets);
    });
  });

  group('a delivery with no signal', () {
    testWidgets('is counted, costed and queued', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byTooltip('Réception de stock'));
      await flush(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Quantité'),
        '20',
      );
      await tester.pump();

      // The item did not exist a moment ago. Typing its name is what creates
      // it, here and on the server.
      await tester.tap(find.text('Autre…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, "Nom de l'article"),
        'Aliment ponte',
      );
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      // 17 500 per sack.
      await tapKeys(tester, ['1', '7', '5', '0', '0']);

      await tester.tap(find.text('Enregistrer la réception'));
      await flush(tester);

      // The physical ledger.
      final events = await tester.runAsync(
        () => db.farmEventsForDay(org.id, DateTime.now()),
      );
      expect(events!.single['kind'], 'stock_in');
      expect(events.single['subject'], 'Aliment ponte');
      expect(events.single['quantity'], 20.0);
      expect(events.single['unit'], 'sac');

      // And the money one: 20 x 17 500. One delivery is one thing that
      // happened, so both rows carry the same client_uuid.
      final entries = await tester.runAsync(
        () => db.entriesForDay(org.id, DateTime.now()),
      );
      expect(entries!.single['amount'], 350000.0);
      expect(entries.single['direction'], 'out');
      expect(entries.single['category'], 'Aliment');
      expect(entries.single['client_uuid'], events.single['client_uuid']);

      // Waiting for a network that is not there.
      final pending = await tester.runAsync(() => db.pendingActions());
      expect(pending!.single['action'], 'receive_stock');

      final payload =
          jsonDecode(pending.single['payload'] as String) as Map<String, dynamic>;
      expect(payload['p_org_id'], org.id);
      expect(payload['p_item_name'], 'Aliment ponte');
      expect(payload['p_quantity'], 20.0);
      expect(payload['p_unit_cost'], 17500.0);
      expect(payload['p_unit'], 'sac');
      expect(payload['p_category'], 'Aliment');
      expect(payload.containsKey('p_client_uuid'), isTrue);
    });

    testWidgets('without a price is still a delivery', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byTooltip('Réception de stock'));
      await flush(tester);

      await tester.tap(find.text('Autre…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, "Nom de l'article"),
        'Sciure',
      );
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Quantité'), '6');
      await tester.pump();

      // The invoice is in the truck. The sacks are here.
      await tester.tap(find.text('Enregistrer la réception'));
      await flush(tester);

      final events = await tester.runAsync(
        () => db.farmEventsForDay(org.id, DateTime.now()),
      );
      expect(events!.single['quantity'], 6.0);

      // 009 posts no journal entry for a delivery with no price, so neither
      // does the device — an entry of zero would be a lie about the books.
      final entries = await tester.runAsync(
        () => db.entriesForDay(org.id, DateTime.now()),
      );
      expect(entries, isEmpty);
    });
  });

  testWidgets('feed distributed moves the count and not the money',
      (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byTooltip('Aliment distribué'));
    await flush(tester);

    await tester.tap(find.text('Autre…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, "Nom de l'article"),
      'Aliment ponte',
    );
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Quantité'), '3');
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await flush(tester);

    final events = await tester.runAsync(
      () => db.farmEventsForDay(org.id, DateTime.now()),
    );
    expect(events!.single['kind'], 'stock_out');

    // The money left when the sacks arrived. Expensing them again as they are
    // eaten would double the single largest cost on the farm.
    final entries = await tester.runAsync(
      () => db.entriesForDay(org.id, DateTime.now()),
    );
    expect(entries, isEmpty);

    final pending = await tester.runAsync(() => db.pendingActions());
    expect(pending!.single['action'], 'move_stock');
  });

  group('the device on its own', () {
    test('adds up its own day', () async {
      await db.receiveStock(
        orgId: org.id,
        itemName: 'Aliment ponte',
        quantity: 20,
        unitCost: 17500,
      );
      await db.moveStock(
        orgId: org.id,
        itemName: 'Aliment ponte',
        quantity: 3,
      );
      await db.recordEggs(orgId: org.id, eggCount: 380);
      await db.recordEggs(orgId: org.id, eggCount: 24, grade: 'fêlé');
      await db.recordFlockEvent(
        orgId: org.id,
        flockId: 'flock-1',
        batchCode: 'B-2026-01',
        kind: 'mortality',
        quantity: 7,
      );

      final day = await db.farmDay(org.id, DateTime.now());
      expect(day.eggs, 404);
      expect(day.deaths, 7);
      expect(day.feedUsed, 3);

      // Only the delivery touched money.
      final totals = await db.dayTotals(org.id, DateTime.now());
      expect(totals.moneyOut, 350000);
      expect(totals.moneyIn, 0);
    });

    test('offers the item names the server last reported', () async {
      await db.cacheFarmItems(org.id, [
        {
          'item_id': 'i1',
          'name': 'Aliment ponte',
          'unit': 'sac',
          'on_hand': 4.0,
          'reorder_level': 5.0,
          'below_reorder': true,
        },
        {
          'item_id': 'i2',
          'name': 'Vaccin Newcastle',
          'unit': 'dose',
          'on_hand': 500.0,
          'reorder_level': null,
          'below_reorder': false,
        },
      ]);

      // What is running out comes first: an item list is a list of things to
      // buy before it is a list of things you have.
      expect(
        (await db.farmItemNames(org.id)),
        ['Aliment ponte', 'Vaccin Newcastle'],
      );

      final cached = await db.cachedFarmItems(org.id);
      expect(cached.first['name'], 'Aliment ponte');
      expect(cached.first['below_reorder'], 1);
    });

    test('falls back to what it has recorded when nothing is cached',
        () async {
      await db.moveStock(orgId: org.id, itemName: 'Aliment ponte', quantity: 3);
      await db.moveStock(orgId: org.id, itemName: 'Aliment ponte', quantity: 3);
      await db.moveStock(orgId: org.id, itemName: 'Sciure', quantity: 1);

      // A phone that has never synced is still useful: the items somebody has
      // been using all week are the items they are about to use again.
      expect(
        await db.farmItemNames(org.id),
        ['Aliment ponte', 'Sciure'],
      );
    });

    test('a closed flock is not offered for recording', () async {
      await db.cacheFlocks(org.id, [
        {
          'flock_id': 'f1',
          'batch_code': 'B-2026-01',
          'alive': 490,
          'closed': false,
        },
        {
          'flock_id': 'f2',
          'batch_code': 'B-2025-08',
          'alive': 0,
          'closed': true,
        },
      ]);

      final open = await db.cachedFlocks(org.id);
      expect(open, hasLength(1));
      expect(open.single['batch_code'], 'B-2026-01');
      expect(open.single['alive'], 490);
    });
  });

  test('a flock event names the function 009 exposes', () async {
    await db.recordFlockEvent(
      orgId: org.id,
      flockId: 'flock-1',
      batchCode: 'B-2026-01',
      kind: 'mortality',
      quantity: 7,
      note: 'Chaleur',
    );

    final pending = await db.pendingActions();
    expect(pending.single['action'], 'record_flock_event');

    // SyncService posts this map verbatim as the RPC's arguments, so a key
    // renamed on one side and not the other fails at the server, on a phone,
    // days later.
    final payload =
        jsonDecode(pending.single['payload'] as String) as Map<String, dynamic>;
    expect(payload['p_flock_id'], 'flock-1');
    expect(payload['p_kind'], 'mortality');
    expect(payload['p_quantity'], 7.0);
    expect(payload['p_note'], 'Chaleur');
    expect(payload.containsKey('p_client_uuid'), isTrue);
  });
}
