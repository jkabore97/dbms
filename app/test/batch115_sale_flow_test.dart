import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/sync/sync_service.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/retail/sale_flow.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// « Vente », one entry at a time (115, W1) — the shop's till and the
/// farm's. What the one-form sale sheet guaranteed is checked here on the
/// flow that replaced it: the stock rule (101, the audit's ELIM SHOP), Wave
/// (037/090), the carnet's credit (029), foreign currency (039), the till
/// with no signal (package 7) — and what is new: one question per screen,
/// RULE M, the customer or « client de passage », the receipt.
class _Till extends RetailRepository {
  _Till({this.merchant, this.rates = const [], super.outbox, this.offline = false})
      : super(null);

  final String? merchant;
  final List<CurrencyRate> rates;
  final bool offline;
  final calls = <Map<String, Object?>>[];
  String? confirmedSender;
  String? tenderCurrency;
  double? tenderAmount;

  @override
  Future<String?> waveMerchant(String orgId) async => merchant;

  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) async => rates;

  @override
  Future<Map<String, double>> freshStock(String orgId, List<String> ids) async =>
      const {};

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
    if (offline) {
      throw const SocketException('Failed host lookup: dkrtntrcbhuuouctfyug');
    }
    calls.add({
      'lines': [for (final l in lines) l.toJson()],
      'method': method,
      'note': note,
      'uuid': clientUuid,
      'customer': customerName,
    });
    return 'sale-${calls.length}';
  }

  @override
  Future<void> confirmWavePayment(
      {required String saleId, required String sender, String? reference}) async {
    confirmedSender = sender;
  }

  @override
  Future<void> attachSaleTender({
    required String saleId,
    required String currency,
    required double amount,
    required double rate,
  }) async {
    tenderCurrency = currency;
    tenderAmount = amount;
  }
}

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('flow-next')));
  await tester.pumpAndSettle();
}

bool _nextOn(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('flow-next'))).onPressed != null;

/// Picks [id] and sets its quantity, on the « Combien ? » step.
Future<void> _sell(WidgetTester tester, String id, String qty) async {
  await tester.tap(find.byKey(ValueKey('sale-pick-$id')));
  await tester.pumpAndSettle();
  await _next(tester);
  await tester.enterText(find.byKey(ValueKey('sale-qty-$id')), qty);
  await tester.pumpAndSettle();
}

Future<void> _typed(WidgetTester tester, String name, String price,
    {bool catalogue = false}) async {
  if (catalogue) {
    await tester.tap(find.byKey(const Key('sale-type-open')));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byKey(const Key('sale-typed-name')), name);
  await tester.enterText(find.byKey(const Key('sale-typed-price')), price);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('sale-typed-add')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('the steps', () {
    testWidgets('a cash sale: articles → combien → client → paiement → résumé → C\'est fait',
        (tester) async {
      await _phone(tester);
      final till = _Till();
      await tester.pumpWidget(_app(SaleFlow(
        orgId: 'o1',
        orgName: 'Boutique Awa',
        retail: till,
        store: MemoryFlowStore(),
        products: const [
          Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 5),
          Product(id: 'p2', name: 'Farine', salePrice: 600, quantity: 9, isIngredient: true),
        ],
      )));
      await tester.pumpAndSettle();

      expect(find.text('Quels articles ?'), findsOneWidget);
      expect(find.text('Choisissez les articles demandés par le client ici'), findsOneWidget);
      expect(find.text('Reste : 5'), findsOneWidget);
      expect(find.byKey(const ValueKey('sale-pick-p2')), findsNothing,
          reason: 'a production ingredient is not on the till');
      expect(_nextOn(tester), isFalse, reason: 'nothing in the basket yet');

      await _sell(tester, 'p1', '2');
      expect(find.text('Combien ?'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('sale-total'))).data,
          matches(RegExp(r'^900\s?FCFA$')));
      await _next(tester);

      expect(find.text('Pour quel client ?'), findsOneWidget);
      await _next(tester); // client de passage, the default
      expect(find.text('Comment le client paie ?'), findsOneWidget);
      await _next(tester); // Espèces
      expect(find.byKey(const Key('flow-summary')), findsOneWidget);
      expect(find.text('2 × Savon'), findsOneWidget);
      expect(find.text('Client de passage'), findsOneWidget);

      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(till.calls, hasLength(1));
      expect(till.calls.single['method'], 'cash');
      expect(till.calls.single['note'], isNull);
      expect((till.calls.single['lines'] as List).single,
          {'product_id': 'p1', 'name': 'Savon', 'quantity': 2.0, 'unit_price': 450.0});
      expect(find.text('Vente enregistrée'), findsOneWidget);
      expect(find.byKey(const Key('sale-share')), findsOneWidget);

      // « Nouvelle vente »: an empty basket — and another client_uuid.
      await tester.tap(find.byKey(const Key('sale-again')));
      await tester.pumpAndSettle();
      expect(find.text('Quels articles ?'), findsOneWidget);
      expect(_nextOn(tester), isFalse);
      await _sell(tester, 'p1', '1');
      await _next(tester);
      await _next(tester);
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(till.calls[1]['uuid'], isNot(till.calls[0]['uuid']));
    });

    testWidgets('a named customer goes on the sale\'s note; the receipt names it',
        (tester) async {
      await _phone(tester);
      final till = _Till();
      await tester.pumpWidget(_app(SaleFlow(
        orgId: 'o1',
        retail: till,
        store: MemoryFlowStore(),
        products: const [Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 5)],
      )));
      await tester.pumpAndSettle();
      await _sell(tester, 'p1', '1');
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-option-true')));
      await tester.pumpAndSettle();
      expect(_nextOn(tester), isFalse, reason: 'a known customer needs a name');
      await tester.enterText(find.byKey(const Key('sale-customer')), 'Awa');
      await tester.pumpAndSettle();
      await _next(tester);
      await _next(tester);
      expect(find.text('Awa'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(till.calls.single['note'], 'Client : Awa');
      expect(till.calls.single['customer'], isNull, reason: 'not a debt');
    });

    testWidgets('a name typed on the spot is sold too — the catalogue can be fixed later',
        (tester) async {
      await _phone(tester);
      final till = _Till();
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1', retail: till, store: MemoryFlowStore())));
      await tester.pumpAndSettle();
      // No catalogue: the fields are there at once.
      await _typed(tester, 'Tissu', '9000');
      await _next(tester);
      await _next(tester);
      await _next(tester);
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect((till.calls.single['lines'] as List).single,
          {'name': 'Tissu', 'quantity': 1.0, 'unit_price': 9000.0});
    });

    testWidgets('the farm: its produce', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'f1', retail: _Till(), farm: true, store: MemoryFlowStore(),
          products: const [Product(id: 'e', name: 'Œufs', salePrice: 2500, quantity: 40, unit: 'plateau')])));
      await tester.pumpAndSettle();
      expect(find.text('Quels produits ?'), findsOneWidget);
      expect(find.text('Choisissez les produits demandés par le client ici'), findsOneWidget);
    });
  });

  group('the stock never goes below zero (101)', () {
    Future<_Till> sell(WidgetTester tester, Product product, String qty) async {
      await _phone(tester);
      final till = _Till();
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1', retail: till, store: MemoryFlowStore(), products: [product])));
      await tester.pumpAndSettle();
      if (product.quantity <= 0 && !product.isService) return till;
      await _sell(tester, product.id, qty);
      return till;
    }

    testWidgets('past the shelf: said, and Suivant waits', (tester) async {
      final till = await sell(tester,
          const Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 2), '5');
      expect(find.text('Il ne reste que 2 Savon'), findsOneWidget);
      expect(_nextOn(tester), isFalse);
      expect(till.calls, isEmpty);
    });

    testWidgets('nothing on the shelf: the tile says so and cannot be picked',
        (tester) async {
      await sell(tester,
          const Product(id: 'p1', name: 'Pain', salePrice: 150, quantity: 0), '1');
      expect(find.text('Plus en stock'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sale-pick-p1')));
      await tester.pumpAndSettle();
      expect(_nextOn(tester), isFalse);
    });

    testWidgets('within stock: no word at all', (tester) async {
      await sell(tester,
          const Product(id: 'p1', name: 'Sucre', salePrice: 750, quantity: 9), '3');
      expect(find.textContaining('Il ne reste'), findsNothing);
      expect(_nextOn(tester), isTrue);
    });

    testWidgets('a service has no stock to run out of', (tester) async {
      await sell(tester,
          const Product(id: 'p1', name: 'Coiffure', salePrice: 2000, isService: true), '2');
      expect(find.textContaining('Reste'), findsNothing);
      expect(_nextOn(tester), isTrue);
    });

    testWidgets('a typed name the shop never received has nothing on the shelf',
        (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1', retail: _Till(), store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 2)])));
      await tester.pumpAndSettle();
      await _typed(tester, 'Bougie', '100', catalogue: true);
      await _next(tester);
      expect(find.text('Plus de Bougie en stock'), findsOneWidget);
    });
  });

  group('payment', () {
    testWidgets('RULE M: no mobile payment unless Mara allows it for this business',
        (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1', retail: _Till(merchant: '+22670000000'),
          store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 5)])));
      await tester.pumpAndSettle();
      await _sell(tester, 'p1', '1');
      await _next(tester);
      await _next(tester);
      expect(find.text('Espèces'), findsOneWidget);
      expect(find.text('Crédit'), findsOneWidget);
      expect(find.text('Mobile'), findsNothing);
      expect(find.text('Wave'), findsNothing);
      expect(find.text('Banque'), findsNothing);
    });

    testWidgets('allowed: Mobile; and Wave only with a handle', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1', retail: _Till(), allowWave: true, store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 5)])));
      await tester.pumpAndSettle();
      await _sell(tester, 'p1', '1');
      await _next(tester);
      await _next(tester);
      expect(find.text('Mobile'), findsOneWidget);
      expect(find.text('Wave'), findsNothing, reason: 'no handle');
    });

    testWidgets('no Crédit where the owner\'s dial says no', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1', retail: _Till(), canCredit: false, store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 5)])));
      await tester.pumpAndSettle();
      await _sell(tester, 'p1', '1');
      await _next(tester);
      await _next(tester);
      expect(find.text('Crédit'), findsNothing);
    });

    testWidgets('Wave: the QR, the sender, the confirmation — dismissed, nothing recorded',
        (tester) async {
      await _phone(tester);
      final till = _Till(merchant: '+22670000000');
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1', orgName: 'Boutique', retail: till, allowWave: true,
          store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Savon', salePrice: 500, quantity: 5)])));
      await tester.pumpAndSettle();
      await _sell(tester, 'p1', '1');
      await _next(tester);
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-option-wave')));
      await tester.pumpAndSettle();
      await _next(tester);
      expect(find.text('Payer avec Wave'), findsOneWidget);

      // Not pumpAndSettle while the sheet is up: the save button's spinner
      // turns behind it until the sheet answers.
      Future<void> frames() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.tap(find.byKey(const Key('flow-save')));
      await frames();
      expect(find.text('Paiement Wave'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(till.calls, isEmpty, reason: 'a QR shown is not a sale');
      expect(find.byKey(const Key('flow-summary')), findsOneWidget);

      await tester.tap(find.byKey(const Key('flow-save')));
      await frames();
      await tester.enterText(
          find.widgetWithText(TextField, 'Nom de l\'expéditeur Wave'), 'Awa Traoré');
      await frames();
      await tester.tap(find.text('Paiement reçu'));
      await tester.pumpAndSettle();
      expect(till.calls.single['method'], 'wave');
      expect(till.confirmedSender, 'Awa Traoré');
      expect(find.text('Paiement Wave reçu'), findsOneWidget);
      expect(find.text('Payé par : Awa Traoré'), findsOneWidget);
    });

    testWidgets('the carnet opens on Crédit: the customer by name, no « de passage »',
        (tester) async {
      await _phone(tester);
      final till = _Till();
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1', retail: till, initialMethod: 'credit', store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Riz', salePrice: 500, quantity: 5)])));
      await tester.pumpAndSettle();
      await _sell(tester, 'p1', '2');
      await _next(tester);
      expect(find.text('Client de passage'), findsNothing);
      expect(find.text('Nom du client'), findsOneWidget);
      expect(_nextOn(tester), isFalse);
      await tester.enterText(find.byKey(const Key('sale-customer')), 'Moussa');
      await tester.pumpAndSettle();
      await _next(tester);
      expect(find.textContaining('ira dans le carnet'), findsOneWidget);
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(till.calls.single['method'], 'credit');
      expect(till.calls.single['customer'], 'Moussa');
      expect(find.text('Vente à crédit enregistrée'), findsOneWidget);
    });

    testWidgets('Crédit chosen for a « client de passage »: the name is asked right there',
        (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1', retail: _Till(), store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Riz', salePrice: 500, quantity: 5)])));
      await tester.pumpAndSettle();
      await _sell(tester, 'p1', '1');
      await _next(tester);
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-option-credit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sale-customer')), findsOneWidget);
      expect(_nextOn(tester), isFalse);
    });

    testWidgets('paying in USD: what to collect, the tender stamped, both on « C\'est fait »',
        (tester) async {
      await _phone(tester);
      final till = _Till(rates: const [CurrencyRate(currency: 'USD', rate: 600)]);
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1', retail: till, store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Tissu', salePrice: 9000, quantity: 5)])));
      await tester.pumpAndSettle();
      await _sell(tester, 'p1', '1');
      await _next(tester);
      await _next(tester);
      expect(find.text('FCFA'), findsOneWidget);
      expect(find.text('À encaisser'), findsNothing);
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      expect(find.text('À encaisser'), findsOneWidget);
      expect(find.textContaining('15,00'), findsOneWidget);
      expect(find.text('1 USD = 600 F'), findsOneWidget);
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(till.tenderCurrency, 'USD');
      expect(till.tenderAmount, 15.0);
      expect(find.byKey(const Key('sale-done-tender')), findsOneWidget);
    });

    testWidgets('no rates (or only the home currency): no currency chips', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1', retail: _Till(rates: const [CurrencyRate(currency: 'XOF', rate: 1)]),
          store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Tissu', salePrice: 9000, quantity: 5)])));
      await tester.pumpAndSettle();
      await _sell(tester, 'p1', '1');
      await _next(tester);
      await _next(tester);
      expect(find.text('FCFA'), findsNothing);
      expect(find.text('USD'), findsNothing);
    });
  });

  group('no signal (package 7) — as before', () {
    testWidgets('the sale is kept on the phone with its uuid, then sent once',
        (tester) async {
      await _phone(tester);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      bool? closed;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => closed = await StepFlow.push(
                context,
                SaleFlow(
                  orgId: 'o1',
                  retail: _Till(outbox: db, offline: true),
                  store: MemoryFlowStore(),
                  products: const [Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 5)],
                )),
            child: const Text('Vendre'),
          ),
        ),
      )));
      await tester.tap(find.text('Vendre'));
      await tester.pumpAndSettle();
      await _sell(tester, 'p1', '1');
      await _next(tester);
      await _next(tester);
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sale-done-queued')), findsOneWidget);
      expect(await tester.runAsync(() => db.pendingSales('o1')), 1);
      await tester.tap(find.byKey(const Key('flow-finish')));
      await tester.pumpAndSettle();
      expect(closed, isTrue);

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
      expect(sent.single['p_client_uuid'], isNotEmpty);
      expect(sent.single.containsKey('p_recorded_by'), isFalse);
      expect((sent.single['p_lines'] as List).single['name'], 'Savon');
      await tester.runAsync(sync.syncNow);
      expect(sent, hasLength(1), reason: 'sent once, not again');
    });

    testWidgets('the till counts the sales still waiting on the phone (101)',
        (tester) async {
      await _phone(tester);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => db.queueSale(orgId: 'o1', clientUuid: 'w-1', params: {
            'p_org_id': 'o1',
            'p_lines': [
              {'product_id': 'p1', 'name': 'Savon', 'quantity': 1, 'unit_price': 450},
            ],
            'p_client_uuid': 'w-1',
          }));
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1', retail: _Till(outbox: db, offline: true), store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 2)])));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Reste : 1'), findsOneWidget,
          reason: 'the server shows 2, but 1 already waits on this phone');
      await _sell(tester, 'p1', '2');
      expect(find.text('Il ne reste que 1 Savon'), findsOneWidget);
    });

    testWidgets('a sale in a foreign currency is not kept offline: it needs the server',
        (tester) async {
      await _phone(tester);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      await tester.pumpWidget(_app(SaleFlow(
          orgId: 'o1',
          retail: _Till(outbox: db, offline: true,
              rates: const [CurrencyRate(currency: 'USD', rate: 600)]),
          store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Tissu', salePrice: 9000, quantity: 5)])));
      await tester.pumpAndSettle();
      await _sell(tester, 'p1', '1');
      await _next(tester);
      await _next(tester);
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('flow-error')), findsOneWidget);
      expect(await tester.runAsync(() => db.pendingSales('o1')), 0);
    });
  });

  testWidgets('interrupted mid-sale: the basket and its uuid come back — no double sale',
      (tester) async {
    await _phone(tester);
    final store = MemoryFlowStore();
    final till = _Till();
    Widget flow() => _app(SaleFlow(
        orgId: 'o1', retail: till, store: store,
        products: const [Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 5)]));
    await tester.pumpWidget(flow());
    await tester.pumpAndSettle();
    await _sell(tester, 'p1', '3');
    await _next(tester);
    final kept = store.values['step_flow:sale:o1']!;
    expect(kept, contains('"q":"3"'));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(flow());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flow-resumed')), findsOneWidget);
    expect(find.text('Pour quel client ?'), findsOneWidget);
    await _next(tester);
    await _next(tester);
    expect(find.text('3 × Savon'), findsOneWidget);
    await tester.tap(find.byKey(const Key('flow-save')));
    await tester.pumpAndSettle();
    expect(kept, contains(till.calls.single['uuid'] as String),
        reason: 'the uuid made before the interruption');
    expect(store.values.containsKey('step_flow:sale:o1'), isFalse);
  });

  testWidgets('English', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: SaleFlow(orgId: 'o1', retail: _Till(), store: MemoryFlowStore(),
          products: const [Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 5)]),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Which items?'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsOneWidget);
  });
}
