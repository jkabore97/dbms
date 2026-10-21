import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/animal_sales.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/farm/models.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/sync/sync_service.dart';
import 'package:kaj_app/features/common/refused_notice.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/farm/farm_animal_flows.dart';
import 'package:kaj_app/features/farm/farm_corrections.dart';
import 'package:kaj_app/features/farm/for_sale_screen.dart';
import 'package:kaj_app/features/retail/sale_flow.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 150 — an animal sold once, counted once: the farm's « Vente » sells its
/// groups of animals beside its products (one operation, sell_animals),
/// « Vendus vivants » takes the money there, an « À vendre » article can
/// follow a group, the sale waits on the phone with no signal and is sent
/// once. A shop's till is the one it was.
///
/// `B150_SHOTS=<dir>` also writes the screenshots (390 × 844, and 320 px at
/// text ×1.3; French and English).

const _flock = AnimalForSale(
  kind: 'flock',
  groupId: 'fl-1',
  label: 'B-2026-07',
  detail: 'Poulets de chair',
  alive: 90,
  productId: 'p-chicken',
  productName: 'Poulets de chair — B-2026-07',
  salePrice: 3500,
  unit: 'tête',
);
const _herd = AnimalForSale(
  kind: 'herd',
  groupId: 'hd-1',
  label: 'Chèvres du bas-fond',
  detail: 'caprin',
  alive: 10,
);
const _products = [
  Product(id: 'p-eggs', name: 'Œufs', salePrice: 2500, quantity: 48, unit: 'plateau'),
  // Follows the batch: sold through its tile, never listed twice.
  Product(id: 'p-chicken', name: 'Poulets de chair — B-2026-07', salePrice: 3500, quantity: 90),
];
const _farm = OrgSummary(id: 'f1', name: 'Ferme Kossi', profile: 'farm', roles: ['owner']);

class _Till extends RetailRepository {
  _Till({super.outbox, this.offline = false, this.shelf})
      : super(null);

  final bool offline;
  final AnimalShelf? shelf;
  final sales = <Map<String, Object?>>[];
  final animalSales = <Map<String, Object?>>[];
  final links = <Map<String, Object?>>[];
  final updates = <Map<String, Object?>>[];

  @override
  Future<String?> waveMerchant(String orgId) async => null;

  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) async => const [];

  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {};

  @override
  Future<({List<Product> products, bool fromDevice})> tillProducts(String orgId,
          {Duration timeout = const Duration(seconds: 12)}) async =>
      (products: _products, fromDevice: false);

  @override
  Future<AnimalShelf?> animalsForSale(String orgId,
          {Duration timeout = const Duration(seconds: 12)}) async =>
      shelf;

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
  }) async {
    if (offline) throw const SocketException('Failed host lookup: example.supabase.co');
    sales.add({'lines': [for (final l in lines) l.toJson()], 'method': method});
    return 'sale-${sales.length}';
  }

  @override
  Future<String> recordAnimalSale({
    required String orgId,
    required List<SaleLineDraft> lines,
    required String clientUuid,
    String method = 'cash',
    String? note,
    String? customerName,
    String? customerPhone,
    Map<String, String> groups = const {},
  }) async {
    if (offline) throw const SocketException('Failed host lookup: example.supabase.co');
    animalSales.add({
      'lines': [for (final l in lines) l.toJson()],
      'method': method,
      'uuid': clientUuid,
      'customer': customerName,
      'groups': groups,
    });
    return 'animal-sale-${animalSales.length}';
  }

  @override
  Future<double> linkProductAnimals(String productId, {String? flockId, String? herdId}) async {
    links.add({'product': productId, 'flock': flockId, 'herd': herdId});
    return flockId != null ? 90 : 0;
  }

  @override
  Future<void> updateProduct(String productId,
      {String? name,
      double? salePrice,
      double? costPrice,
      DateTime? expiresOn,
      double? lowStockAt,
      bool? isActive,
      bool? isIngredient,
      bool? isPublished,
      String? description,
      String? unit,
      DateTime? availableFrom,
      bool clearAvailableFrom = false,
      double? quantity,
      bool? isService,
      bool? priceFrom,
      bool? stockTracked}) async {
    updates.add({'product': productId, 'quantity': quantity, 'tracked': stockTracked, 'at': links.length});
  }
}

class _Farm extends FarmRepository {
  _Farm(this.rows) : super(null);
  final List<Map<String, dynamic>> rows;
  @override
  Future<List<Map<String, dynamic>>> flockEvents(String flockId) async => rows;
}

Widget _shot(Widget child) => RepaintBoundary(key: const Key('shot'), child: child);

Widget _app(Widget home, {String lang = 'fr'}) => MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      builder: (context, child) => _shot(child!),
      home: home,
    );

Future<void> _size(WidgetTester tester, double w, double h, {double text = 1}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('flow-next')));
  await tester.pumpAndSettle();
}

bool _nextOn(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('flow-next'))).onPressed != null;

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('flow-save')));
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

SaleFlow _till(_Till till, {FlowStore? store, String? initialAnimal}) => SaleFlow(
      orgId: 'f1',
      orgName: 'Ferme Kossi',
      retail: till,
      store: store ?? MemoryFlowStore(),
      products: _products,
      farm: true,
      animals: const [_flock, _herd],
      initialAnimal: initialAnimal,
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
  });

  group('the arithmetic', () {
    test('a total splits into lines that add up to it, to the franc', () {
      expect(splitTotal(3, 100000, 'XOF'),
          [(quantity: 2.0, unitPrice: 33333.0), (quantity: 1.0, unitPrice: 33334.0)]);
      expect(splitTotal(10, 35000, 'XOF'), [(quantity: 10.0, unitPrice: 3500.0)]);
      final eur = splitTotal(3, 100, 'EUR');
      expect(eur.fold<double>(0, (s, l) => s + l.quantity * l.unitPrice), closeTo(100, 1e-9));
      expect(eur.first.unitPrice, 33.33);
    });

    test('a group line carries its group; a shop line is what it always was', () {
      expect(const SaleLineDraft(flockId: 'fl-1', name: 'x', quantity: 2, unitPrice: 5).toJson(),
          {'flock_id': 'fl-1', 'name': 'x', 'quantity': 2.0, 'unit_price': 5.0});
      expect(const SaleLineDraft(productId: 'p1', name: 'Savon', quantity: 1, unitPrice: 450).toJson(),
          {'product_id': 'p1', 'name': 'Savon', 'quantity': 1.0, 'unit_price': 450.0});
    });

    test('150\'s sentences with a name, in English', () {
      expect(animalsText('en', '« B-2026-07 » est clôturé : ces animaux ne se vendent plus'),
          '“B-2026-07” is closed: these animals are no longer for sale');
      expect(animalsText('fr', '« B-2026-07 » est clôturé : ces animaux ne se vendent plus'),
          '« B-2026-07 » est clôturé : ces animaux ne se vendent plus');
      expect(animalsText('en', 'Il ne reste que 3 Savon'), isNull);
      expect(translate('en', 'Ces animaux ne sont pas dans cette ferme'),
          'These animals are not on this farm');
    });
  });

  group('the till sells the batch', () {
    testWidgets('a group beside the products; the article that follows it is not listed twice; one sell_animals',
        (tester) async {
      await _size(tester, 390, 1400);
      final till = _Till();
      await tester.pumpWidget(_app(_till(till)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sale-animals-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('sale-animal-flock:fl-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('sale-animal-herd:hd-1')), findsOneWidget);
      expect(find.text('90 vivants'), findsOneWidget);
      expect(find.text('10 têtes'), findsOneWidget);
      expect(find.byKey(const ValueKey('sale-pick-p-eggs')), findsOneWidget);
      expect(find.byKey(const ValueKey('sale-pick-p-chicken')), findsNothing,
          reason: 'the batch is sold through its own tile');

      await tester.tap(find.byKey(const ValueKey('sale-animal-flock:fl-1')));
      await tester.pumpAndSettle();
      await _next(tester);
      expect(find.text('B-2026-07 · 90 vivants'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('sale-qty-flock:fl-1')), '10');
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('sale-total'))).data,
          matches(RegExp(r'^35\s000\s?FCFA$')));
      await _next(tester);
      await _next(tester);
      await _next(tester);
      await _save(tester);

      expect(till.sales, isEmpty, reason: 'not record_sale: sell_animals, one operation');
      expect(till.animalSales, hasLength(1));
      expect(till.animalSales.single['lines'], [
        {'flock_id': 'fl-1', 'name': 'Poulets de chair — B-2026-07', 'quantity': 10.0, 'unit_price': 3500.0},
      ]);
      expect(till.animalSales.single['groups'], {'fl-1': 'B-2026-07'});
      expect(find.text('Vente enregistrée'), findsOneWidget);
    });

    testWidgets('a herd sold for a total: exact lines, the price remembered for next time', (tester) async {
      await _size(tester, 390, 1400);
      final till = _Till();
      final store = MemoryFlowStore();
      await tester.pumpWidget(_app(_till(till, store: store)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sale-animal-herd:hd-1')));
      await tester.pumpAndSettle();
      await _next(tester);
      await tester.tap(find.byKey(const ValueKey('sale-by-total-herd:hd-1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('sale-qty-herd:hd-1')), '3');
      await tester.enterText(find.byKey(const ValueKey('sale-price-herd:hd-1')), '100000');
      await tester.pumpAndSettle();
      expect(find.text('Prix total'), findsWidgets);
      expect(tester.widget<Text>(find.byKey(const Key('sale-total'))).data,
          matches(RegExp(r'^100\s000\s?FCFA$')));
      await _next(tester);
      await _next(tester);
      await _next(tester);
      await _save(tester);
      expect(till.animalSales.single['lines'], [
        {'herd_id': 'hd-1', 'name': 'Chèvres du bas-fond', 'quantity': 2.0, 'unit_price': 33333.0},
        {'herd_id': 'hd-1', 'name': 'Chèvres du bas-fond', 'quantity': 1.0, 'unit_price': 33334.0},
      ]);
      final kept = jsonDecode(store.values['animal_prices:f1']!) as Map;
      expect(kept['herd:hd-1'], {'p': 100000.0, 't': true});

      // The next sale of the herd opens on that price, by the total.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(_till(_Till(), store: store)));
      await tester.pumpAndSettle();
      expect(find.textContaining('le lot'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sale-animal-herd:hd-1')));
      await tester.pumpAndSettle();
      await _next(tester);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('sale-price-herd:hd-1'))).controller!.text,
          '100000');
    });

    testWidgets('more than a herd has is refused; more than a batch\'s last count is warned', (tester) async {
      await _size(tester, 390, 1400);
      await tester.pumpWidget(_app(_till(_Till())));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sale-animal-herd:hd-1')));
      await tester.tap(find.byKey(const ValueKey('sale-animal-flock:fl-1')));
      await tester.pumpAndSettle();
      await _next(tester);
      await tester.enterText(find.byKey(const ValueKey('sale-qty-herd:hd-1')), '11');
      await tester.enterText(find.byKey(const ValueKey('sale-price-herd:hd-1')), '45000');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sale-stock-short')), findsOneWidget);
      expect(find.text('Il ne reste que 10 Chèvres du bas-fond'), findsOneWidget);
      expect(_nextOn(tester), isFalse);
      await tester.enterText(find.byKey(const ValueKey('sale-qty-herd:hd-1')), '2');
      await tester.enterText(find.byKey(const ValueKey('sale-qty-flock:fl-1')), '95');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sale-stock-short')), findsNothing);
      expect(find.byKey(const ValueKey('sale-animal-warning-flock:fl-1')), findsOneWidget);
      expect(_nextOn(tester), isTrue, reason: 'a batch is warned, never refused here (009 checks)');
    });

    testWidgets('a shop\'s till: no animals, record_sale as always', (tester) async {
      await _size(tester, 390, 1400);
      final till = _Till();
      await tester.pumpWidget(_app(SaleFlow(
        orgId: 's1',
        retail: till,
        store: MemoryFlowStore(),
        products: const [Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 5)],
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sale-animals-title')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sale-pick-p1')));
      await tester.pumpAndSettle();
      await _next(tester);
      await _next(tester);
      await _next(tester);
      await _next(tester);
      await _save(tester);
      expect(till.animalSales, isEmpty);
      expect(till.sales.single['lines'], [
        {'product_id': 'p1', 'name': 'Savon', 'quantity': 1.0, 'unit_price': 450.0},
      ]);
    });
  });

  group('no signal', () {
    testWidgets('the same single operation is kept, sent once with its uuid, the day lists it', (tester) async {
      await _size(tester, 390, 1400);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      await tester.pumpWidget(_app(_till(_Till(outbox: db, offline: true))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sale-animal-flock:fl-1')));
      await tester.tap(find.byKey(const ValueKey('sale-pick-p-eggs')));
      await tester.pumpAndSettle();
      await _next(tester);
      await tester.enterText(find.byKey(const ValueKey('sale-qty-flock:fl-1')), '10');
      await tester.pumpAndSettle();
      await _next(tester);
      await _next(tester);
      await _next(tester);
      await _save(tester);
      expect(find.byKey(const Key('sale-done-queued')), findsOneWidget);

      expect(await tester.runAsync(() => db.pendingSales('f1')), 1);
      final waiting = (await tester.runAsync(() => db.pendingSaleQuantities('f1')))!;
      expect(waiting['flock:fl-1'], 10, reason: 'the till takes it off the batch while it waits');
      expect(waiting['p-eggs'], 1);
      final day = (await tester.runAsync(() => db.farmEventsForDay('f1', DateTime.now())))!;
      expect(day.single['kind'], 'sold');
      expect(day.single['subject'], 'B-2026-07');
      expect(day.single['quantity'], 10);

      final sent = <(String, Map<String, dynamic>)>[];
      final sync = SyncService(
        db,
        SupabaseClient('https://example.supabase.co', 'anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false)),
        currentUserId: () => 'u1',
        post: (action, params) async {
          sent.add((action, params));
          return 'sale-1';
        },
      );
      await tester.runAsync(sync.syncNow);
      expect(sent.single.$1, 'sell_animals');
      expect(sent.single.$2['p_recorded_by'], 'u1');
      expect(sent.single.$2['p_client_uuid'], isNotEmpty);
      expect(sent.single.$2['p_lines'], [
        {'flock_id': 'fl-1', 'name': 'Poulets de chair — B-2026-07', 'quantity': 10.0, 'unit_price': 3500.0},
        {'product_id': 'p-eggs', 'name': 'Œufs', 'quantity': 1.0, 'unit_price': 2500.0},
      ]);
      await tester.runAsync(sync.syncNow);
      expect(sent, hasLength(1), reason: 'sent once, not again');
      expect(await tester.runAsync(() => db.pendingSales('f1')), 0);
    });

    test('the list kept on the phone is read less the sales sent since it was heard', () async {
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      // As the server last answered, an hour ago.
      await db.writePref('${LocalDb.personalPrefPrefix}animals_for_sale:f1', jsonEncode({
        'at': DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(),
        'rows': [_flock.toRow(), _herd.toRow()],
      }));
      // No server here (offline): the kept list, at once.
      final repo = RetailRepository(null, outbox: db);
      var shelf = (await repo.animalsForSale('f1'))!;
      expect(shelf.fromDevice, isTrue);
      expect(shelf.animals.map((a) => a.alive), [90, 10]);
      // A sale of 4 goats kept, then sent: the server had not counted it.
      await repo.queueAnimalSale(
        orgId: 'f1',
        clientUuid: 'c-2',
        lines: const [SaleLineDraft(herdId: 'hd-1', name: 'Chèvres du bas-fond', quantity: 4, unitPrice: 45000)],
      );
      expect((await db.pendingSaleQuantities('f1'))['herd:hd-1'], 4,
          reason: 'while it waits, the till takes it off itself');
      await db.markSynced('c-2');
      shelf = (await repo.animalsForSale('f1'))!;
      expect(shelf.animals.map((a) => a.alive), [90, 6]);
      expect(await db.pendingSaleQuantities('f1'), isEmpty, reason: 'never counted twice');
    });

    test('refused for good (MA001): set aside, off the day\'s list, read as a sale', () async {
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      final till = _Till(outbox: db);
      await till.queueAnimalSale(
        orgId: 'f1',
        clientUuid: 'c-1',
        lines: const [SaleLineDraft(herdId: 'hd-1', name: 'Chèvres du bas-fond', quantity: 11, unitPrice: 45000)],
        groups: const {'hd-1': 'Chèvres du bas-fond'},
      );
      final sync = SyncService(
        db,
        SupabaseClient('https://example.supabase.co', 'anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false)),
        currentUserId: () => 'u1',
        post: (action, params) async =>
            throw const PostgrestException(message: 'Il ne reste que 10 Chèvres du bas-fond', code: 'MA001'),
      );
      await sync.syncNow();
      final refused = await db.refusedActions('f1');
      expect(refused, hasLength(1));
      final a = RefusedAction.fromRow(refused.single);
      expect(a.isSale, isTrue);
      expect(a.what, '11 × Chèvres du bas-fond');
      expect(a.shortfall, (name: 'Chèvres du bas-fond', missing: 1.0));
      expect(await db.farmEventsForDay('f1', DateTime.now()), isEmpty);
      expect(await db.pendingSales('f1'), 0);
    });
  });

  group('« Vendus vivants »', () {
    Flock flock() => Flock(
        id: 'fl-1', batchCode: 'B-2026-07', arrivedOn: DateTime(2026, 9, 1), ageDays: 50,
        started: 100, alive: 90, died: 0, sold: 10, eggs7d: 0, layRate: 0, breed: 'Poulets de chair');

    testWidgets('with 150: the sale at the till, the batch in the basket; « Sortis sans vente » stays',
        (tester) async {
      await _size(tester, 390, 1400);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      final till = _Till(outbox: db, shelf: const AnimalShelf([_flock, _herd]));
      bool? closed;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => closed = await FarmAnimalFlow.flockEvent(context,
                db: db, org: _farm, flock: flock(), retail: till),
            child: const Text('Saisir'),
          ),
        ),
      )));
      await tester.tap(find.text('Saisir'));
      await tester.pumpAndSettle();
      expect(find.text('Vendus vivants'), findsOneWidget);
      expect(find.text('Sortis sans vente'), findsOneWidget);
      expect(find.text('Donnés, mangés à la maison : sans argent.'), findsOneWidget);

      await tester.tap(find.text('Vendus vivants'));
      await tester.pumpAndSettle();
      expect(find.text('Vente'), findsOneWidget);
      // Straight on « Combien ? » for the batch: it is in the basket.
      await _next(tester);
      expect(find.byKey(const ValueKey('sale-line-flock:fl-1')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('sale-qty-flock:fl-1')), '4');
      await tester.pumpAndSettle();
      await _next(tester);
      await _next(tester);
      await _next(tester);
      await _save(tester);
      expect(till.animalSales.single['lines'], [
        {'flock_id': 'fl-1', 'name': 'Poulets de chair — B-2026-07', 'quantity': 4.0, 'unit_price': 3500.0},
      ]);
      await tester.tap(find.byKey(const Key('flow-finish')));
      await tester.pumpAndSettle();
      expect(closed, isTrue, reason: 'the event flow closes with the sale');
      expect(await tester.runAsync(() => db.pendingCount()), 0,
          reason: 'no second record: no count-only event was queued');
    });

    testWidgets('« Sortis sans vente »: the count only, said on the event', (tester) async {
      await _size(tester, 390, 1400);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      final till = _Till(outbox: db, shelf: const AnimalShelf([_flock]));
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => FarmAnimalFlow.flockEvent(context,
                db: db, org: _farm, flock: flock(), retail: till),
            child: const Text('Saisir'),
          ),
        ),
      )));
      await tester.tap(find.text('Saisir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sortis sans vente'));
      await tester.pumpAndSettle();
      await _next(tester);
      expect(find.text('Combien sont sortis sans vente ?'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('farm-count')), '2');
      await tester.pumpAndSettle();
      await _next(tester);
      await _next(tester);
      await _save(tester);
      final rows = (await tester.runAsync(() => db.pendingActions()))!;
      expect(rows.single['action'], 'record_flock_event');
      final payload = jsonDecode(rows.single['payload'] as String) as Map;
      expect(payload['p_kind'], 'sold');
      expect(payload['p_quantity'], 2);
      expect(payload['p_note'], 'Sans vente');
      expect(till.animalSales, isEmpty);
    });

    testWidgets('before 150: « Vendus vivants » is the count it always was', (tester) async {
      await _size(tester, 390, 1400);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => FarmAnimalFlow.flockEvent(context,
                db: db, org: _farm, flock: flock(), retail: _Till(outbox: db)),
            child: const Text('Saisir'),
          ),
        ),
      )));
      await tester.tap(find.text('Saisir'));
      await tester.pumpAndSettle();
      expect(find.text('Sortis sans vente'), findsNothing);
      await tester.tap(find.text('Vendus vivants'));
      await tester.pumpAndSettle();
      await _next(tester);
      expect(find.text('Combien sont vendus ?'), findsOneWidget);
    });
  });

  group('« À vendre » follows a batch', () {
    testWidgets('chosen: no count of its own to type; saved without one, then linked', (tester) async {
      await _size(tester, 390, 1600);
      final till = _Till();
      await tester.pumpWidget(_app(Scaffold(
        body: ForSaleSheet(
          org: _farm,
          retail: till,
          product: const Product(id: 'p-broiler', name: 'Poulet de chair', salePrice: 3500, quantity: 30, unit: 'tête'),
          groups: const [
            _flock, // followed by another article: not offered
            AnimalForSale(kind: 'flock', groupId: 'fl-2', label: 'B-2026-08', alive: 40),
            _herd,
          ],
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Suit des animaux'), findsOneWidget);
      expect(find.byKey(const ValueKey('for-sale-follow-flock:fl-1')), findsNothing);
      expect(find.byKey(const Key('for-sale-quantity')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('for-sale-follow-flock:fl-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('for-sale-quantity')), findsNothing);
      expect(find.text('40 à vendre : les vivants de la bande « B-2026-08 ».'), findsOneWidget);
      expect(find.text('Son stock à lui (30) est remplacé par ce nombre.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('for-sale-save')));
      await tester.tap(find.byKey(const Key('for-sale-save')));
      await tester.pumpAndSettle();
      expect(till.updates.single['quantity'], isNull, reason: 'the batch is the count');
      expect(till.updates.single['at'], 0, reason: 'saved first, then linked');
      expect(till.links.single, {'product': 'p-broiler', 'flock': 'fl-2', 'herd': null});
    });

    testWidgets('unfollowed: unlinked first, then its own count', (tester) async {
      await _size(tester, 390, 1600);
      final till = _Till();
      await tester.pumpWidget(_app(Scaffold(
        body: ForSaleSheet(
          org: _farm,
          retail: till,
          product: _products[1],
          groups: const [_flock],
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('for-sale-follow-count')), findsOneWidget);
      await tester.tap(find.byKey(const Key('for-sale-follow-none')));
      await tester.pumpAndSettle();
      expect(find.text('Les animaux restent dans leur groupe ; cet article repart de zéro.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('for-sale-save')));
      await tester.tap(find.byKey(const Key('for-sale-save')));
      await tester.pumpAndSettle();
      expect(till.links.single, {'product': 'p-chicken', 'flock': null, 'herd': null});
      expect(till.updates.single['at'], 1, reason: 'unlinked before its count is written');
      expect(till.updates.single['quantity'], 0);
    });
  });

  testWidgets('corrections: a sale\'s event is read, not edited; a give-back reads « Rendus »', (tester) async {
    await _size(tester, 390, 1000);
    await tester.pumpWidget(_app(Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showFarmCorrections(context,
              title: 'B-2026-07',
              farm: _Farm([
                {'id': 'e1', 'kind': 'sold', 'quantity': 10, 'note': 'Vente — Poulets', 'occurred_at': '2026-10-20T08:00:00Z', 'product_id': 'p-chicken'},
                {'id': 'e2', 'kind': 'sold', 'quantity': -3, 'note': 'Rendus — Poulets', 'occurred_at': '2026-10-20T09:00:00Z', 'product_id': 'p-chicken'},
                {'id': 'e3', 'kind': 'mortality', 'quantity': 2, 'note': null, 'occurred_at': '2026-10-20T10:00:00Z', 'product_id': null},
              ]),
              kind: FarmEntryKind.flock,
              subjectId: 'fl-1',
              canWrite: true),
          child: const Text('Corriger'),
        ),
      ),
    )));
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(find.text('Vendus · 10'), findsOneWidget);
    expect(find.text('Rendus · 3'), findsOneWidget);
    expect(find.text('Mortalité · 2'), findsOneWidget);
    final sale = tester.widget<ListTile>(find.byKey(const ValueKey('farm-entry-e1')));
    final death = tester.widget<ListTile>(find.byKey(const ValueKey('farm-entry-e3')));
    expect(sale.onLongPress, isNull, reason: 'corrected through its sale');
    expect(death.onLongPress, isNotNull);
  });

  // -------------------------------------------------------------------------
  // Screenshots (B150_SHOTS=<dir>)
  // -------------------------------------------------------------------------
  final shots = Platform.environment['B150_SHOTS'];
  group('screenshots', () {
    Future<void> realFonts() async {
      var dir = File(Platform.resolvedExecutable).parent;
      for (var i = 0; i < 6 && !Directory('${dir.path}/material_fonts').existsSync(); i++) {
        dir = dir.parent;
      }
      final fonts = Directory('${dir.path}/material_fonts');
      if (!fonts.existsSync()) return;
      final loader = FontLoader('Roboto');
      for (final f in const ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
        final file = File('${fonts.path}/$f');
        if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
      }
      await loader.load();
      final icons = File('${fonts.path}/MaterialIcons-Regular.otf');
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer))))
            .load();
      }
    }

    Future<void> shoot(WidgetTester tester, String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')).first);
        final img = await ro.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    final sizes = [('390', 390.0, 844.0, 1.0), ('320x1.3', 320.0, 640.0, 1.3)];
    for (final lang in ['fr', 'en']) {
      for (final (tag, w, h, text) in sizes) {
        testWidgets('$lang $tag', (tester) async {
          Directory(shots!).createSync(recursive: true);
          await tester.runAsync(realFonts);
          await _size(tester, w, h, text: text);
          final p = '${lang}_${tag}_';
          final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
          addTearDown(() => tester.runAsync(db.close));

          // The till: animals beside the products.
          final till = _Till(outbox: db, shelf: const AnimalShelf([_flock, _herd]));
          await tester.pumpWidget(_app(_till(till), lang: lang));
          await shoot(tester, '${p}01_till_animals');
          await tester.tap(find.byKey(const ValueKey('sale-animal-herd:hd-1')));
          await tester.pumpAndSettle();
          await _next(tester);
          await tester.tap(find.byKey(const ValueKey('sale-by-total-herd:hd-1')));
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const ValueKey('sale-qty-herd:hd-1')), '3');
          await tester.enterText(find.byKey(const ValueKey('sale-price-herd:hd-1')), '100000');
          await tester.pumpAndSettle();
          FocusManager.instance.primaryFocus?.unfocus();
          await shoot(tester, '${p}02_till_how_many_total');
          await _next(tester);
          await _next(tester);
          await _next(tester);
          await shoot(tester, '${p}03_till_summary');
          await _save(tester);
          await shoot(tester, '${p}04_till_done');

          // « Vendus vivants » on a batch.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_app(Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => FarmAnimalFlow.flockEvent(context,
                    db: db,
                    org: _farm,
                    retail: till,
                    flock: Flock(
                        id: 'fl-1', batchCode: 'B-2026-07', arrivedOn: DateTime(2026, 9, 1), ageDays: 50,
                        started: 100, alive: 90, died: 0, sold: 10, eggs7d: 0, layRate: 0)),
                child: const Text('Saisir'),
              ),
            ),
          ), lang: lang));
          await tester.tap(find.text('Saisir'));
          await tester.pumpAndSettle();
          await shoot(tester, '${p}05_event_kinds');

          // « À vendre »: the article follows a batch.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_app(Scaffold(
            body: ForSaleSheet(
              org: _farm,
              retail: till,
              product: const Product(id: 'p-broiler', name: 'Poulet de chair', salePrice: 3500, quantity: 30, unit: 'tête'),
              groups: const [AnimalForSale(kind: 'flock', groupId: 'fl-2', label: 'B-2026-08', alive: 40), _herd],
            ),
          ), lang: lang));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('for-sale-follow-flock:fl-2')));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(find.byKey(const Key('for-sale-follow-count')), 200,
              scrollable: find.byType(Scrollable).first);
          await shoot(tester, '${p}06_for_sale_follows');
        });
      }
    }
  }, skip: shots == null ? 'B150_SHOTS=<dir> writes the screenshots' : null);
}
