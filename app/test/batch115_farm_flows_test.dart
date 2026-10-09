import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/farm/models.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/sync/sync_service.dart';
import 'package:kaj_app/features/farm/farm_animal_flows.dart';
import 'package:kaj_app/features/farm/farm_crop_flows.dart';
import 'package:kaj_app/features/farm/farm_flows.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The farm's six, one entry at a time (115, W4): « Réception »,
/// « Consommation » (and « Perte »), « Mortalité », « Ajouter des
/// animaux », « Ajouter une culture », « Récolte ». What the sheets they
/// replace guaranteed is checked on the flows: the stock and the flocks
/// recorded with no signal, through the outbox, drained to the same server
/// functions; the feed stopped on the phone past what is left (101); the
/// network said where it is needed.
class _Farm extends FarmRepository {
  _Farm({this.crops = const [], this.herdList = const [], this.oldServer = false,
      this.cropsFail = false})
      : super(null);

  /// No signal on the way to the plantings.
  bool cropsFail;

  final List<CropCycle> crops;
  final List<Herd> herdList;

  /// A server before 119: no p_to_stock.
  final bool oldServer;
  final calls = <String, Map<String, Object?>>{};

  @override
  bool get isConfigured => true;

  @override
  Future<List<CropCycle>> cropCycles(String orgId, {bool includeClosed = false}) async {
    if (cropsFail) throw const SocketException('Failed host lookup');
    return crops;
  }

  @override
  Future<List<Herd>> herds(String orgId, {bool includeClosed = false}) async => herdList;

  @override
  Future<List<Flock>> flocks(String orgId, {bool includeClosed = false}) async => [
        Flock.fromRow({
          'flock_id': 'fl-new',
          'batch_code': 'B-2026-10',
          'bird_count': 500,
          'alive': 500,
          'arrived_on': '2026-10-01',
        }),
      ];

  @override
  Future<String> openFlock({
    required String orgId,
    required String batchCode,
    required int birdCount,
    String? breed,
    String? entityId,
    DateTime? arrivedOn,
  }) async {
    calls['openFlock'] = {
      'code': batchCode,
      'count': birdCount,
      'breed': breed,
      'arrived': arrivedOn,
    };
    return 'fl-new';
  }

  @override
  Future<String> openHerd({
    required String orgId,
    required String species,
    required String label,
    required int headCount,
    String? breed,
    String? purpose,
    DateTime? arrivedOn,
  }) async {
    calls['openHerd'] = {
      'species': species,
      'label': label,
      'count': headCount,
      'arrived': arrivedOn,
    };
    return 'h-new';
  }

  @override
  Future<String> recordHerdEvent({
    required String orgId,
    required String herdId,
    required String kind,
    double quantity = 0,
    DateTime? occurredOn,
    String? note,
    String? clientUuid,
  }) async {
    calls['herdEvent'] = {'herd': herdId, 'kind': kind, 'q': quantity, 'note': note};
    return 'he-1';
  }

  @override
  Future<String> openCropCycle({
    required String orgId,
    required String crop,
    String? plotName,
    String? variety,
    DateTime? plantedOn,
    DateTime? expectedOn,
    double? expectedYield,
    String unit = 'kg',
  }) async {
    calls['openCrop'] = {
      'crop': crop,
      'plot': plotName,
      'planted': plantedOn,
      'expected': expectedOn,
      'unit': unit,
    };
    return 'cc-new';
  }

  @override
  Future<void> setPlotArea({
    required String cropCycleId,
    required double area,
    required String unit,
  }) async {
    calls['area'] = {'cycle': cropCycleId, 'area': area, 'unit': unit};
  }

  @override
  Future<String> recordHarvest({
    required String orgId,
    required String cropCycleId,
    required double quantity,
    String? unit,
    String grade = 'first',
    DateTime? harvestedOn,
    String? note,
    String? clientUuid,
    bool toStock = false,
  }) async {
    if (toStock && oldServer) {
      throw const PostgrestException(
          message: 'Could not find the function public.record_harvest', code: 'PGRST202');
    }
    calls['harvest'] = {
      'cycle': cropCycleId,
      'q': quantity,
      'unit': unit,
      'grade': grade,
      'stock': toStock,
      'uuid': clientUuid,
    };
    return 'hv-1';
  }
}

class _Shelf extends RetailRepository {
  _Shelf(this.items) : super(null);
  final List<Product> items;

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => items;
}

const _org = OrgSummary(id: 'f1', name: 'Ferme Ignace', profile: 'farm', roles: ['owner']);

Widget _app(void Function(BuildContext) open) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => open(context), child: const Text('Ouvrir')),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester, void Function(BuildContext) open) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
    addTearDown(() => tester.runAsync(db.close));
    await tester.pumpWidget(_app(open));
  }

  Future<void> openFlow(WidgetTester tester) async {
    await tester.tap(find.text('Ouvrir'));
    await settle(tester);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();
  }

  Future<void> option(WidgetTester tester, String value) async {
    final f = find.byKey(Key('flow-option-$value'));
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pump();
  }

  bool nextEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('flow-next'))).onPressed != null;

  Future<List<Map<String, Object?>>> outbox(WidgetTester tester) async =>
      (await tester.runAsync(() => db.pendingActions()))!;

  Map<String, dynamic> payload(Map<String, Object?> row) =>
      jsonDecode(row['payload'] as String) as Map<String, dynamic>;

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('flow-save')));
    await settle(tester);
  }

  group('Réception (offline, as before)', () {
    testWidgets('a new item, a price, the medicine account and the supplier — one row in the outbox',
        (tester) async {
      await start(tester, (c) => FarmStockFlow.receive(c, db: db, org: _org));
      await openFlow(tester);
      expect(find.text('Réception'), findsOneWidget);
      expect(nextEnabled(tester), isFalse, reason: 'nothing chosen yet');
      await option(tester, '__new__');
      await tester.enterText(find.byKey(const Key('farm-new-item')), 'Vaccin Newcastle');
      await tester.pump();
      await next(tester);
      await tester.enterText(find.byKey(const Key('farm-quantity')), '4');
      await tester.tap(find.byKey(const Key('farm-unit-dose')));
      await tester.pump();
      await next(tester);
      await tester.enterText(find.byKey(const Key('farm-price')), '2500');
      await tester.pump();
      expect(find.textContaining('10'), findsWidgets, reason: 'the total, 4 × 2 500');
      await next(tester);
      // Priced: which account it goes to, « Aliment » as 009 did by default.
      await option(tester, 'Vétérinaire');
      await next(tester);
      await tester.enterText(find.byKey(const Key('farm-supplier')), 'Dr Ouédraogo');
      await tester.pump();
      await next(tester);
      expect(find.byKey(const Key('flow-summary')), findsOneWidget);
      expect(find.text('Médicaments, vaccins'), findsOneWidget);
      expect(find.textContaining('sans connexion'), findsOneWidget);
      await save(tester);
      expect(find.byKey(const Key('flow-done')), findsOneWidget);
      expect(find.text('Vaccin Newcastle : 4 dose reçus'), findsOneWidget);

      final rows = await outbox(tester);
      expect(rows, hasLength(1));
      expect(rows.single['action'], 'receive_stock');
      final p = payload(rows.single);
      expect(p['p_item_name'], 'Vaccin Newcastle');
      expect(p['p_quantity'], 4);
      expect(p['p_unit_cost'], 2500);
      expect(p['p_unit'], 'dose');
      expect(p['p_category'], 'Vétérinaire');
      expect(p['p_memo'], 'Fournisseur : Dr Ouédraogo');
      final entries = await tester.runAsync(() => db.entriesForDay('f1', DateTime.now()));
      expect(entries!.single['amount'], 10000, reason: 'the money, on this phone too');
    });

    testWidgets('no price: no account asked, no money moved', (tester) async {
      await start(tester, (c) => FarmStockFlow.receive(c, db: db, org: _org));
      await tester.runAsync(() => db.cacheFarmItems('f1', [
            {'item_id': 'i1', 'name': 'Aliment ponte', 'unit': 'sac', 'on_hand': 2},
          ]));
      await openFlow(tester);
      expect(find.text('Il reste 2 sac'), findsOneWidget);
      await option(tester, 'Aliment ponte');
      await next(tester);
      expect(find.byKey(const Key('farm-unit-sac')), findsNothing,
          reason: 'a known item keeps its unit');
      await tester.enterText(find.byKey(const Key('farm-quantity')), '20');
      await tester.pump();
      await next(tester);
      await next(tester); // no price
      expect(find.byKey(const Key('flow-step-category')), findsNothing);
      expect(find.byKey(const Key('flow-step-supplier')), findsOneWidget);
      await next(tester);
      expect(find.text('Pas encore connu'), findsOneWidget);
      await save(tester);
      final p = payload((await outbox(tester)).single);
      expect(p['p_unit_cost'], isNull);
      expect(p['p_category'], 'Aliment');
      final entries = await tester.runAsync(() => db.entriesForDay('f1', DateTime.now()));
      expect(entries, isEmpty);
    });
  });

  group('Consommation and Perte (offline, as before)', () {
    testWidgets('given to one batch: the batch rides in the note, the outbox drains to move_stock',
        (tester) async {
      await start(tester, (c) => FarmStockFlow.use(c, db: db, org: _org));
      await tester.runAsync(() async {
        await db.cacheFarmItems('f1', [
          {'item_id': 'i1', 'name': 'Aliment', 'unit': 'sac', 'on_hand': 10},
        ]);
        await db.cacheFlocks('f1', [
          {'flock_id': 'fl1', 'batch_code': 'B-2026-01', 'alive': 480},
        ]);
      });
      await openFlow(tester);
      expect(find.text('Consommation'), findsOneWidget);
      await option(tester, 'Aliment');
      await next(tester);
      await tester.enterText(find.byKey(const Key('farm-quantity')), '2');
      await tester.pump();
      await next(tester);
      expect(find.byKey(const Key('flow-step-batch')), findsOneWidget);
      await option(tester, 'fl1');
      await next(tester);
      await next(tester); // no note
      await save(tester);
      expect(find.text('Aliment : 2 sac donnés'), findsOneWidget);

      final row = (await outbox(tester)).single;
      expect(row['action'], 'move_stock');
      expect(payload(row)['p_kind'], 'consumed');
      expect(payload(row)['p_memo'], 'Pour B-2026-01');

      // The same outbox drain as always: move_stock with the caller.
      final posted = <String, Map<String, dynamic>>{};
      // Made outside the fake clock: its auth refresh timer is real.
      final client = (await tester.runAsync(
          () async => SupabaseClient('https://example.supabase.co', 'anon-key')))!;
      final sync = SyncService(db, client,
          currentUserId: () => 'u1', post: (action, params) async {
        posted[action] = params;
        return 'srv-1';
      });
      await tester.runAsync(sync.syncNow);
      expect(posted['move_stock']!['p_item_name'], 'Aliment');
      expect(posted['move_stock']!['p_recorded_by'], 'u1');
      expect(await tester.runAsync(db.pendingCount), 0);
    });

    testWidgets('nothing received: nothing to give, and the delivery is one tap away',
        (tester) async {
      await start(tester, (c) => FarmStockFlow.use(c, db: db, org: _org));
      await openFlow(tester);
      expect(find.textContaining('Rien en stock'), findsOneWidget);
      expect(find.byKey(const Key('farm-receive-first')), findsOneWidget);
      expect(nextEnabled(tester), isFalse);
    });

    testWidgets('Perte: a cause, no batch asked', (tester) async {
      await start(tester, (c) => FarmStockFlow.use(c, db: db, org: _org, wasted: true));
      await tester.runAsync(() async {
        await db.cacheFarmItems('f1', [
          {'item_id': 'i1', 'name': 'Aliment', 'unit': 'sac', 'on_hand': 10},
        ]);
        await db.cacheFlocks('f1', [
          {'flock_id': 'fl1', 'batch_code': 'B-2026-01', 'alive': 480},
        ]);
      });
      await openFlow(tester);
      expect(find.text('Perte'), findsOneWidget);
      await option(tester, 'Aliment');
      await next(tester);
      await tester.enterText(find.byKey(const Key('farm-quantity')), '1');
      await tester.pump();
      await next(tester);
      expect(find.byKey(const Key('flow-step-note')), findsOneWidget,
          reason: 'no batch for a loss');
      await tester.tap(find.text('Mouillé'));
      await tester.pump();
      await next(tester);
      await save(tester);
      final p = payload((await outbox(tester)).single);
      expect(p['p_kind'], 'wasted');
      expect(p['p_memo'], 'Mouillé');
    });
  });

  group('Mortalité', () {
    testWidgets('one flock: no picking, a count, a cause — offline through record_flock_event',
        (tester) async {
      await start(tester, (c) => FarmAnimalFlow.event(c, db: db, org: _org));
      await tester.runAsync(() => db.cacheFlocks('f1', [
            {'flock_id': 'fl1', 'batch_code': 'B-2026-01', 'alive': 480},
          ]));
      await openFlow(tester);
      expect(find.text('Mortalité'), findsOneWidget);
      expect(find.byKey(const Key('flow-step-count')), findsOneWidget,
          reason: 'one batch, nothing to choose');
      expect(find.text('480 oiseaux au dernier point'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('farm-count')), '3');
      await tester.pump();
      await next(tester);
      await tester.tap(find.text('Chaleur'));
      await tester.pump();
      await next(tester);
      expect(find.textContaining('sans connexion'), findsOneWidget);
      await save(tester);
      expect(find.text('Mortalité : 3 oiseaux · B-2026-01'), findsOneWidget);
      final row = (await outbox(tester)).single;
      expect(row['action'], 'record_flock_event');
      expect(payload(row)['p_flock_id'], 'fl1');
      expect(payload(row)['p_kind'], 'mortality');
      expect(payload(row)['p_quantity'], 3);
      expect(payload(row)['p_note'], 'Chaleur');
      final day = await tester.runAsync(() => db.farmDay('f1', DateTime.now()));
      expect(day!.deaths, 3, reason: 'the home counts it at once');
    });

    testWidgets('a flock and a herd: which one; the herd is the server\'s and its count is held',
        (tester) async {
      final farm = _Farm(herdList: [
        Herd.fromRow({'id': 'h1', 'species': 'caprin', 'label': 'Chèvres', 'head_count': 12}),
      ]);
      await start(tester, (c) => FarmAnimalFlow.event(c, db: db, org: _org, farm: farm));
      await tester.runAsync(() => db.cacheFlocks('f1', [
            {'flock_id': 'fl1', 'batch_code': 'B-2026-01', 'alive': 480},
          ]));
      await openFlow(tester);
      expect(find.byKey(const Key('flow-step-group')), findsOneWidget);
      expect(nextEnabled(tester), isFalse);
      await option(tester, 'h1');
      await next(tester);
      await tester.enterText(find.byKey(const Key('farm-count')), '20');
      await tester.pump();
      expect(find.text('Il n\'y a que 12 têtes dans ce groupe.'), findsOneWidget);
      expect(nextEnabled(tester), isFalse);
      await tester.enterText(find.byKey(const Key('farm-count')), '2');
      await tester.pump();
      await next(tester);
      await next(tester);
      await save(tester);
      expect(farm.calls['herdEvent'], {'herd': 'h1', 'kind': 'mortality', 'q': 2.0, 'note': null});
      expect(await outbox(tester), isEmpty, reason: 'a herd is recorded on the server, as before');
    });

    testWidgets('no batch at all: it says where to open one', (tester) async {
      await start(tester, (c) => FarmAnimalFlow.event(c, db: db, org: _org));
      await openFlow(tester);
      expect(find.textContaining('Aucune bande enregistrée'), findsOneWidget);
      expect(nextEnabled(tester), isFalse);
    });

    testWidgets('from « Bandes »: the batch is known, what happened is asked', (tester) async {
      final flock = Flock.fromRow({
        'flock_id': 'fl1', 'batch_code': 'B-2026-01', 'bird_count': 500,
        'alive': 480, 'arrived_on': '2026-08-01',
      });
      await start(tester, (c) => FarmAnimalFlow.flockEvent(c, db: db, org: _org, flock: flock));
      await openFlow(tester);
      expect(find.byKey(const Key('flow-step-kind')), findsOneWidget);
      await option(tester, 'weight');
      await next(tester);
      expect(find.text('Quel poids ?'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('farm-count')), '1850');
      await tester.pump();
      await next(tester);
      await next(tester);
      await save(tester);
      final p = payload((await outbox(tester)).single);
      expect(p['p_kind'], 'weight');
      expect(p['p_quantity'], 1850);
    });
  });

  group('Ajouter des animaux', () {
    testWidgets('laying hens 8 weeks old: a flock, counted from 8 weeks back, the cost in the outbox',
        (tester) async {
      final farm = _Farm();
      await start(tester, (c) => FarmAnimalFlow.add(c, db: db, org: _org, farm: farm));
      await openFlow(tester);
      await option(tester, 'pondeuses');
      await next(tester);
      final now = DateTime.now();
      final code = 'B-${now.year}-${now.month.toString().padLeft(2, '0')}';
      expect(find.text(code), findsOneWidget, reason: 'a batch code filled in');
      await next(tester);
      await tester.enterText(find.byKey(const Key('farm-count')), '500');
      await tester.pump();
      await next(tester);
      await option(tester, 'age');
      await tester.enterText(find.byKey(const Key('farm-age')), '8');
      await tester.pump();
      await next(tester);
      await tester.enterText(find.byKey(const Key('farm-cost')), '750000');
      await tester.pump();
      await next(tester);
      expect(find.text('8 semaines'), findsOneWidget);
      expect(find.textContaining('Demande le réseau'), findsOneWidget);
      await save(tester);
      expect(find.byKey(const Key('flow-done')), findsOneWidget);

      final call = farm.calls['openFlock']!;
      expect(call['code'], code);
      expect(call['count'], 500);
      expect(call['breed'], 'Poules pondeuses');
      final today = DateUtils.dateOnly(now);
      expect(call['arrived'], today.subtract(const Duration(days: 56)));
      final row = (await outbox(tester)).single;
      expect(row['action'], 'record_entry');
      expect(payload(row)['p_amount'], 750000);
      expect(payload(row)['p_direction'], 'out');
      expect(payload(row)['p_category'], 'Achat d\'animaux');
      final cached = await tester.runAsync(() => db.cachedFlocks('f1'));
      expect(cached!.single['batch_code'], 'B-2026-10',
          reason: 'the new batch is offered offline by « Mortalité » at once');
    });

    testWidgets('goats that arrive today, nothing paid: a herd, no money', (tester) async {
      final farm = _Farm();
      await start(tester, (c) => FarmAnimalFlow.add(c, db: db, org: _org, farm: farm));
      await openFlow(tester);
      await option(tester, 'caprin');
      await next(tester);
      expect(find.text('Chèvres'), findsWidgets, reason: 'the species as a first name');
      await tester.enterText(find.byKey(const Key('farm-group-name')), 'Chèvres du bas-fond');
      await tester.pump();
      await next(tester);
      await tester.enterText(find.byKey(const Key('farm-count')), '12');
      await tester.pump();
      await next(tester);
      await option(tester, 'today');
      await next(tester);
      await next(tester);
      expect(find.text('Rien payé'), findsOneWidget);
      await save(tester);
      expect(farm.calls['openHerd'], {
        'species': 'caprin',
        'label': 'Chèvres du bas-fond',
        'count': 12,
        'arrived': DateUtils.dateOnly(DateTime.now()),
      });
      expect(await outbox(tester), isEmpty);
    });
  });

  testWidgets('Ajouter une culture: crop, new plot, its area, the sowing day, the unit',
      (tester) async {
    final farm = _Farm();
    await start(tester, (c) => FarmCropFlow.add(c, org: _org, farm: farm));
    await openFlow(tester);
    await option(tester, 'Tomate');
    await next(tester);
    await option(tester, '__new__');
    await tester.enterText(find.byKey(const Key('farm-plot-new')), 'Bas-fond 2');
    await tester.pump();
    await next(tester);
    await tester.enterText(find.byKey(const Key('farm-area')), '0,5');
    await tester.pump();
    await next(tester);
    await option(tester, 'yesterday');
    await next(tester);
    await tester.tap(find.byKey(const Key('farm-unit-panier')));
    await tester.pump();
    await next(tester);
    await option(tester, '2');
    await next(tester);
    expect(find.text('0.5 hectares'), findsOneWidget);
    await save(tester);
    expect(find.text('Tomate ajoutée · Bas-fond 2'), findsOneWidget);
    final yesterday = DateUtils.dateOnly(DateTime.now()).subtract(const Duration(days: 1));
    expect(farm.calls['openCrop'], {
      'crop': 'Tomate',
      'plot': 'Bas-fond 2',
      'planted': yesterday,
      'expected': DateTime(yesterday.year, yesterday.month + 2, yesterday.day),
      'unit': 'panier',
    });
    expect(farm.calls['area'], {'cycle': 'cc-new', 'area': 0.5, 'unit': 'ha'});
  });

  group('Récolte', () {
    final tomato = CropCycle.fromRow(
        {'id': 'c1', 'crop': 'Tomate', 'plot_name': 'Bas-fond 2', 'unit': 'kg'});
    final onion = CropCycle.fromRow({'id': 'c2', 'crop': 'Oignon', 'unit': 'kg'});

    testWidgets('with no signal: called Récolte, nothing to gather, no egg, nothing written',
        (tester) async {
      await start(tester, (c) => FarmCropFlow.harvest(c, org: _org));
      await openFlow(tester);
      expect(find.text('Récolte'), findsOneWidget);
      expect(find.text('Ramassage'), findsNothing);
      expect(find.textContaining('Rien à récolter'), findsOneWidget);
      expect(find.text('Œufs'), findsNothing);
      expect(nextEnabled(tester), isFalse);
      expect(await outbox(tester), isEmpty);
    });

    testWidgets('the plantings could not be read: « Récolte demande le réseau », never « Aucune culture »',
        (tester) async {
      final farm = _Farm(crops: [tomato], cropsFail: true);
      await start(tester, (c) => FarmCropFlow.harvest(c, org: _org, farm: farm));
      await openFlow(tester);
      expect(find.byKey(const Key('farm-harvest-offline')), findsOneWidget);
      expect(find.textContaining('Aucune culture en cours'), findsNothing);
      expect(nextEnabled(tester), isFalse);
      // The signal back: « Réessayer » lists them.
      farm.cropsFail = false;
      await tester.tap(find.byKey(const Key('farm-harvest-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('farm-harvest-offline')), findsNothing);
      expect(nextEnabled(tester), isTrue, reason: 'one planting: already chosen');
    });

    testWidgets('kept for sale: onto the article of that name, its unit asked', (tester) async {
      final farm = _Farm(crops: [tomato, onion]);
      final shelf = _Shelf([
        Product.fromRow({'id': 'p2', 'name': 'Oignon', 'sale_price': 9000, 'quantity': 2, 'unit': 'sac'}),
      ]);
      await start(tester, (c) => FarmCropFlow.harvest(c, org: _org, farm: farm, retail: shelf));
      await openFlow(tester);
      await option(tester, 'c2');
      await next(tester);
      await tester.enterText(find.byKey(const Key('farm-quantity')), '120');
      await tester.pump();
      await next(tester);
      await option(tester, 'second');
      await next(tester);
      await option(tester, 'stock');
      expect(find.textContaining('se vend par sac'), findsOneWidget);
      expect(nextEnabled(tester), isFalse, reason: 'how many sacks first');
      await tester.enterText(find.byKey(const Key('farm-converted')), '3');
      await tester.pump();
      await next(tester);
      expect(find.text('+3 sac sur « Oignon »'), findsOneWidget);
      await save(tester);
      expect(farm.calls['harvest']!['q'], 3);
      expect(farm.calls['harvest']!['unit'], 'sac');
      expect(farm.calls['harvest']!['grade'], 'second');
      expect(farm.calls['harvest']!['stock'], isTrue);
      expect(find.text('Ajoutés à « Oignon » dans À vendre.'), findsOneWidget);
    });

    testWidgets('sold now: a new article (no price yet), then « Enregistrer la vente » opens the sale',
        (tester) async {
      final farm = _Farm(crops: [tomato]);
      var sold = 0;
      await start(tester, (c) => FarmCropFlow.harvest(c,
          org: _org, farm: farm, retail: _Shelf(const []), onSell: () => sold++));
      await openFlow(tester);
      // One planting: already chosen.
      expect(nextEnabled(tester), isTrue);
      await next(tester);
      await tester.enterText(find.byKey(const Key('farm-quantity')), '30');
      await tester.pump();
      await next(tester);
      await next(tester);
      await option(tester, 'sold');
      await next(tester);
      expect(find.text('Nouvel article « Tomate », hors vitrine'), findsOneWidget);
      await save(tester);
      expect(farm.calls['harvest']!['stock'], isTrue);
      expect(find.textContaining('Mettez-lui un prix'), findsOneWidget);
      await tester.tap(find.byKey(const Key('farm-harvest-sell')));
      await tester.pumpAndSettle();
      expect(sold, 1);
    });

    testWidgets('for the house: nothing moves; a server before 119 still counts a stocked harvest',
        (tester) async {
      final farm = _Farm(crops: [tomato], oldServer: true);
      await start(tester, (c) => FarmCropFlow.harvest(c, org: _org, farm: farm, retail: _Shelf(const [])));
      await openFlow(tester);
      await next(tester);
      await tester.enterText(find.byKey(const Key('farm-quantity')), '5');
      await tester.pump();
      await next(tester);
      await next(tester);
      await option(tester, 'stock');
      await next(tester);
      await save(tester);
      expect(farm.calls['harvest']!['stock'], isFalse, reason: 'counted the 019 way');
      expect(find.textContaining('n\'a pas changé'), findsOneWidget);
    });
  });
}
