import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';

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
  _Farm({this.crops = const [], this.herdList = const [], this.oldServer = false})
      : super(null);

  final List<CropCycle> crops;
  final List<Herd> herdList;

  /// A server before 119: no p_to_stock.
  final bool oldServer;
  final calls = <String, Map<String, Object?>>{};

  @override
  bool get isConfigured => true;

  @override
  Future<List<CropCycle>> cropCycles(String orgId, {bool includeClosed = false}) async =>
      crops;

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


// ---- throwaway screenshot helpers (corrector) ----
const _shotDir = '/tmp/claude-0/-home-user-dbms/6b841e07-559f-5c6e-8be9-8db87f01d3f1/scratchpad/shots';
bool _fontsLoaded = false;
Future<void> _shotFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('/opt/flutter/bin/cache/artifacts/material_fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf', 'Roboto-Light.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}
Future<void> _shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await expectLater(find.byWidgetPredicate((w) => w is MaterialApp).first, matchesGoldenFile('$_shotDir/$name.png'));
}

const _org = OrgSummary(id: 'f1', name: 'Ferme Ignace', profile: 'farm', roles: ['owner']);

Widget _app(void Function(BuildContext) open) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: kajTheme(kajPalette),
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
  Future<void> start(WidgetTester tester, void Function(BuildContext) open, {double w = 390}) async {
    await tester.runAsync(_shotFonts);
    tester.view.physicalSize = Size(w, 844);
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
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('flow-save')));
    await settle(tester);
  }

  Future<void> receive(WidgetTester tester, double w) async {
    await start(tester, (c) => FarmStockFlow.receive(c, db: db, org: _org), w: w);
    await tester.runAsync(() => db.cacheFarmItems('f1', [
          {'item_id': 'i1', 'name': 'Aliment ponte', 'unit': 'sac', 'on_hand': 2, 'below_reorder': true},
          {'item_id': 'i2', 'name': 'Vaccin Newcastle', 'unit': 'dose', 'on_hand': 40},
          {'item_id': 'i3', 'name': 'Sciure', 'unit': 'sac', 'on_hand': 6},
        ]));
    await openFlow(tester);
  }

  testWidgets('receive', (tester) async {
    await receive(tester, 390);
    await _shot(tester, 'b115_W4_receive_item');
    await option(tester, 'Aliment ponte');
    await next(tester);
    await tester.enterText(find.byKey(const Key('farm-quantity')), '20');
    await tester.pump();
    await next(tester);
    await tester.enterText(find.byKey(const Key('farm-price')), '14500');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await _shot(tester, 'b115_W4_receive_price');
    await next(tester);
    await _shot(tester, 'b115_W4_receive_category');
    await next(tester);
    await tester.enterText(find.byKey(const Key('farm-supplier')), 'SODEPAL');
    await next(tester);
    await _shot(tester, 'b115_W4_receive_summary');
    await save(tester);
    await _shot(tester, 'b115_W4_receive_done');
  });

  testWidgets('receive wide', (tester) async {
    await receive(tester, 1280);
    await _shot(tester, 'b115_W4_receive_item_1280');
  });

  testWidgets('use', (tester) async {
    await start(tester, (c) => FarmStockFlow.use(c, db: db, org: _org));
    await tester.runAsync(() async {
      await db.cacheFarmItems('f1', [
        {'item_id': 'i1', 'name': 'Aliment ponte', 'unit': 'sac', 'on_hand': 3},
      ]);
      await db.cacheFlocks('f1', [
        {'flock_id': 'fl1', 'batch_code': 'B-2026-01', 'alive': 480},
        {'flock_id': 'fl2', 'batch_code': 'B-2026-07', 'alive': 300},
      ]);
    });
    await openFlow(tester);
    await option(tester, 'Aliment ponte');
    await next(tester);
    await tester.enterText(find.byKey(const Key('farm-quantity')), '5');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await _shot(tester, 'b115_W4_use_short');
    await tester.enterText(find.byKey(const Key('farm-quantity')), '2');
    await tester.pump();
    await next(tester);
    await option(tester, 'fl2');
    await _shot(tester, 'b115_W4_use_batch');
    await next(tester);
    await next(tester);
    await _shot(tester, 'b115_W4_use_summary');
  });

  testWidgets('waste empty', (tester) async {
    await start(tester, (c) => FarmStockFlow.use(c, db: db, org: _org, wasted: true));
    await openFlow(tester);
    await _shot(tester, 'b115_W4_waste_empty');
  });

  testWidgets('mortality', (tester) async {
    final farm = _Farm(herdList: [
      Herd.fromRow({'id': 'h1', 'species': 'caprin', 'label': 'Chèvres du bas-fond', 'head_count': 12}),
    ]);
    await start(tester, (c) => FarmAnimalFlow.event(c, db: db, org: _org, farm: farm));
    await tester.runAsync(() => db.cacheFlocks('f1', [
          {'flock_id': 'fl1', 'batch_code': 'B-2026-01', 'alive': 480},
        ]));
    await openFlow(tester);
    await _shot(tester, 'b115_W4_mortality_group');
    await option(tester, 'fl1');
    await next(tester);
    await tester.enterText(find.byKey(const Key('farm-count')), '3');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await _shot(tester, 'b115_W4_mortality_count');
    await next(tester);
    await tester.tap(find.text('Chaleur'));
    await tester.pump();
    await _shot(tester, 'b115_W4_mortality_cause');
    await next(tester);
    await _shot(tester, 'b115_W4_mortality_summary');
    await save(tester);
    await _shot(tester, 'b115_W4_mortality_done');
  });

  testWidgets('animals', (tester) async {
    final farm = _Farm();
    await start(tester, (c) => FarmAnimalFlow.add(c, db: db, org: _org, farm: farm));
    await openFlow(tester);
    await _shot(tester, 'b115_W4_animals_species');
    await option(tester, 'pondeuses');
    await next(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await _shot(tester, 'b115_W4_animals_name');
    await next(tester);
    await tester.enterText(find.byKey(const Key('farm-count')), '500');
    await tester.pump();
    await next(tester);
    await option(tester, 'age');
    await tester.enterText(find.byKey(const Key('farm-age')), '8');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await _shot(tester, 'b115_W4_animals_when');
    await next(tester);
    await tester.enterText(find.byKey(const Key('farm-cost')), '750000');
    await next(tester);
    await _shot(tester, 'b115_W4_animals_summary');
    await save(tester);
    await _shot(tester, 'b115_W4_animals_done');
  });

  testWidgets('crop', (tester) async {
    final farm = _Farm(crops: [
      CropCycle.fromRow({'id': 'c0', 'crop': 'Oignon', 'plot_name': 'Bas-fond 2', 'unit': 'kg'}),
    ]);
    await start(tester, (c) => FarmCropFlow.add(c, org: _org, farm: farm));
    await openFlow(tester);
    await _shot(tester, 'b115_W4_crop_crop');
    await option(tester, 'Tomate');
    await next(tester);
    await option(tester, 'Bas-fond 2');
    await _shot(tester, 'b115_W4_crop_plot');
    await next(tester);
    await tester.enterText(find.byKey(const Key('farm-area')), '0,5');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await _shot(tester, 'b115_W4_crop_area');
    await next(tester);
    await _shot(tester, 'b115_W4_crop_sown');
    await next(tester);
    await _shot(tester, 'b115_W4_crop_unit');
    await next(tester);
    await option(tester, '3');
    await next(tester);
    await _shot(tester, 'b115_W4_crop_summary');
  });

  testWidgets('harvest', (tester) async {
    final farm = _Farm(crops: [
      CropCycle.fromRow({'id': 'c1', 'crop': 'Tomate', 'plot_name': 'Bas-fond 2', 'variety': 'Mongal', 'unit': 'kg'}),
      CropCycle.fromRow({'id': 'c2', 'crop': 'Oignon', 'unit': 'kg'}),
    ]);
    final shelf = _Shelf([
      Product.fromRow({'id': 'p2', 'name': 'Oignon', 'sale_price': 9000, 'quantity': 2, 'unit': 'sac'}),
    ]);
    await start(tester, (c) => FarmCropFlow.harvest(c, org: _org, farm: farm, retail: shelf, onSell: () {}));
    await openFlow(tester);
    await _shot(tester, 'b115_W4_harvest_crop');
    await option(tester, 'c2');
    await next(tester);
    await tester.enterText(find.byKey(const Key('farm-quantity')), '120');
    await tester.pump();
    await next(tester);
    await _shot(tester, 'b115_W4_harvest_grade');
    await next(tester);
    await option(tester, 'sold');
    await tester.enterText(find.byKey(const Key('farm-converted')), '3');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await _shot(tester, 'b115_W4_harvest_dest');
    await next(tester);
    await _shot(tester, 'b115_W4_harvest_summary');
    await save(tester);
    await _shot(tester, 'b115_W4_harvest_done');
  });

  testWidgets('harvest offline', (tester) async {
    await start(tester, (c) => FarmCropFlow.harvest(c, org: _org));
    await openFlow(tester);
    await _shot(tester, 'b115_W4_harvest_offline');
  });
}
