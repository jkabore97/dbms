import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/admin/team.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/core/credit/credit_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/farm/models.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/invoicing/models.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/orders/orders.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/admin/team_screen.dart';
import 'package:kaj_app/features/credit/credit_book_screen.dart';
import 'package:kaj_app/features/farm/flocks_screen.dart';
import 'package:kaj_app/features/farm/for_sale_screen.dart';
import 'package:kaj_app/features/farm/stock_screen.dart';
import 'package:kaj_app/features/invoicing/invoices_screen.dart';
import 'package:kaj_app/features/orders/shop_orders_screen.dart';
import 'package:kaj_app/features/retail/article_flow.dart';
import 'package:kaj_app/features/retail/products_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Batch 122, Q2: a red number on the bar is explained on top of the page
/// it opens — the reason in plain words, the items, the button that fixes
/// each — the items are marked in the list, and the number is said to stay
/// until the reason is gone.

class _Retail extends RetailRepository {
  _Retail({this.shelf = const [], this.orders = const []}) : super(null);
  final List<Product> shelf;
  final List<ShopOrder> orders;

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => shelf;
  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {};
  @override
  Future<List<ShopOrder>> shopOrders(String orgId) async => orders;
  @override
  Future<Map<String, OrderClock>> orderClocks(String orgId) async => const {};
  @override
  Future<List<CashOwed>> cashOwed(String orgId) async => const [];
}

class _Invoicing extends InvoicingRepository {
  _Invoicing(this.rows) : super(null);
  final List<InvoiceSummary> rows;
  @override
  bool get isConfigured => true;
  @override
  Future<List<InvoiceSummary>> list(String orgId, {bool includePaid = true, int limit = 200}) async =>
      rows;
  @override
  Future<BillingDetails> billingDetails(String orgId) async =>
      const BillingDetails(email: 'a@b.bf', taxId: 'IFU', footer: 'Merci');
}

class _Credit extends CreditRepository {
  _Credit() : super(null);
  @override
  Future<List<DebtorRow>> debtors(String orgId) async => const [
        DebtorRow(customerId: 'c1', name: 'Awa', totalOwed: 5000),
        DebtorRow(customerId: 'c2', name: 'Issa', totalOwed: 2000),
      ];
  @override
  Future<List<DebtDate>> dueDates(String orgId) async => [
        (debtId: 'd1', customerId: 'c1', dueOn: DateTime.now().subtract(const Duration(days: 5))),
        (debtId: 'd2', customerId: 'c1', dueOn: DateTime.now().subtract(const Duration(days: 2))),
        (debtId: 'd3', customerId: 'c2', dueOn: DateTime.now().add(const Duration(days: 9))),
      ];
}

class _Farm extends FarmRepository {
  _Farm() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<List<StockItem>> stockOnHand(String orgId) async => const [
        StockItem(id: 'i1', name: 'Aliment ponte', unit: 'sac', onHand: 1, reorderLevel: 5, belowReorder: true),
        StockItem(id: 'i2', name: 'Vaccin', unit: 'dose', onHand: 0, reorderLevel: 10, belowReorder: true),
        StockItem(id: 'i3', name: 'Sciure', unit: 'sac', onHand: 30, reorderLevel: 5, belowReorder: false),
      ];
  @override
  Future<List<Flock>> flocks(String orgId, {bool includeClosed = false}) async => [
        for (final (id, code) in [('f1', 'B-01'), ('f2', 'B-02')])
          Flock.fromRow({
            'flock_id': id,
            'batch_code': code,
            'bird_count': 500,
            'alive': 480,
            'arrived_on': '2026-09-01',
          }),
      ];
  @override
  Future<Set<String>> flocksWrittenToday(List<String> flockIds) async => {'f2'};
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<TeamOverview?> teamOverview(String orgId) async => TeamOverview(
        seats: const TeamSeats(free: 1, used: 1, open: false),
        members: const [
          TeamMember(userId: 'u0', name: 'Patronne', roles: ['owner'], isOwner: true, membershipIds: ['m0']),
        ],
        invitations: [
          const TeamInvite(id: 'inv1', code: 'K7P-4QX', name: 'Moussa'),
          TeamInvite(
              id: 'inv2', code: 'OLD-0000', name: 'Ancien',
              expiresAt: DateTime.now().subtract(const Duration(days: 1))),
        ],
      );
}

const _shop = OrgSummary(id: 'o1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);
const _farm = OrgSummary(id: 'o2', name: 'Ferme Issa', profile: 'farm', roles: ['owner']);
const _assoc = OrgSummary(id: 'o3', name: 'Entraide', profile: 'association', roles: ['owner']);

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

const _farine = Product(id: 'p1', name: 'Farine', salePrice: 500, quantity: 0);
const _sucre = Product(id: 'p2', name: 'Sucre', salePrice: 600, quantity: 2, lowStockAt: 5);
const _riz = Product(id: 'p3', name: 'Riz', salePrice: 400, quantity: 20, lowStockAt: 5);

ShopOrder _order(String id, String who, {bool service = false}) => ShopOrder(
      id: id,
      customerName: who,
      status: 'pending',
      fulfilment: 'pickup',
      total: 3500,
      currency: 'XOF',
      createdAt: DateTime(2026, 10, 8, 9),
      lines: [OrderLine(name: 'Savon', unitPrice: 3500, quantity: 1, isService: service)],
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('Articles (shop) and À vendre (farm)', () {
    testWidgets('one at zero: the reason, the chip, « Ajouter du stock » on it', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(ProductsScreen(org: _shop, retail: _Retail(shelf: const [_farine, _riz]))));
      await tester.pumpAndSettle();
      expect(find.text('1 article en rupture de stock : Farine'), findsOneWidget);
      expect(find.byKey(const Key('attention-stays')), findsOneWidget);
      expect(find.textContaining('ouvrir cette page ne l\'efface pas'), findsOneWidget);
      // Marked in the list too, and only the one at zero.
      expect(find.byKey(const Key('product-chip-p1')), findsOneWidget);
      expect(find.byKey(const Key('product-chip-p3')), findsNothing);
      expect(find.byKey(const Key('product-restock-p1')), findsOneWidget);
      expect(find.byKey(const Key('product-restock-p3')), findsNothing);
      // The banner's button: the existing entry, opened on Farine.
      await tester.tap(find.byKey(const Key('attention-action-p1')));
      await tester.pumpAndSettle();
      expect(tester.widget<ArticleFlow>(find.byType(ArticleFlow)).initialName, 'Farine');
    });

    testWidgets('the row\'s own button opens the same entry', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(ProductsScreen(org: _shop, retail: _Retail(shelf: const [_farine]))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('product-restock-p1')));
      await tester.pumpAndSettle();
      expect(tester.widget<ArticleFlow>(find.byType(ArticleFlow)).initialName, 'Farine');
    });

    testWidgets('zero and low together; nothing when all is well', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(ProductsScreen(org: _shop, retail: _Retail(shelf: const [_farine, _sucre, _riz]))));
      await tester.pumpAndSettle();
      expect(find.text('2 articles à réapprovisionner : Farine, Sucre'), findsOneWidget);
      expect(find.text('Rupture'), findsWidgets);
      expect(find.text('Bientôt épuisé'), findsWidgets);

      await tester.pumpWidget(_app(ProductsScreen(
          key: const ValueKey('well'), org: _shop, retail: _Retail(shelf: const [_riz]))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attention-banner')), findsNothing);
    });

    testWidgets('only low: « presque épuisé »', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(ProductsScreen(org: _shop, retail: _Retail(shelf: const [_sucre]))));
      await tester.pumpAndSettle();
      expect(find.text('1 article presque épuisé : Sucre'), findsOneWidget);
      expect(find.text('Reste 2 (alerte à 5)'), findsOneWidget);
    });

    testWidgets('farm, À vendre: the same reason and button', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(ForSaleScreen(org: _farm, retail: _Retail(shelf: const [_farine, _riz]))));
      await tester.pumpAndSettle();
      expect(find.text('1 article en rupture de stock : Farine'), findsOneWidget);
      expect(find.textContaining('« À vendre »'), findsOneWidget);
      expect(find.byKey(const Key('product-chip-p1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('product-restock-p1')));
      await tester.pumpAndSettle();
      final flow = tester.widget<ArticleFlow>(find.byType(ArticleFlow));
      expect(flow.initialName, 'Farine');
      expect(flow.forSale, isTrue);
    });
  });

  group('Commandes / Demandes', () {
    testWidgets('shop: « 2 commandes attendent votre réponse », each with Répondre', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(ShopOrdersScreen(
          org: _shop, retail: _Retail(orders: [_order('a', 'Fati'), _order('b', 'Ali')]))));
      await tester.pumpAndSettle();
      expect(find.text('2 commandes attendent votre réponse'), findsOneWidget);
      expect(find.byKey(const Key('attention-action-a')), findsOneWidget);
      expect(find.byKey(const Key('order-waiting-a')), findsOneWidget);
      await tester.tap(find.byKey(const Key('attention-action-a')));
      await tester.pumpAndSettle();
      expect(find.text('Fati commande'), findsOneWidget);
    });

    for (final org in [_farm, _assoc]) {
      testWidgets('${org.profile}: the same, in its words', (tester) async {
        await _phone(tester);
        await tester.pumpWidget(_app(ShopOrdersScreen(
            org: org, retail: _Retail(orders: [_order('a', 'Fati', service: true)]))));
        await tester.pumpAndSettle();
        expect(
            find.text(org == _assoc
                ? '1 demande attend votre réponse'
                : '1 réservation attend votre réponse'),
            findsOneWidget);
      });
    }
  });

  testWidgets('Factures: the late ones, named, each with Voir — all three kinds', (tester) async {
    await _phone(tester);
    final rows = [
      InvoiceSummary(id: 'i1', number: 'F-001', customerName: 'Hôtel Lumière', issuedOn: DateTime(2026, 9, 1),
          total: 10000, paid: 0, outstanding: 10000, cancelled: false, daysOverdue: 8),
      InvoiceSummary(id: 'i2', number: 'F-002', customerName: 'Maquis', issuedOn: DateTime(2026, 9, 1),
          total: 5000, paid: 5000, outstanding: 0, cancelled: false, daysOverdue: 0),
      InvoiceSummary(id: 'i3', number: 'F-003', customerName: 'Annulé', issuedOn: DateTime(2026, 9, 1),
          total: 5000, paid: 0, outstanding: 5000, cancelled: true, daysOverdue: 30),
    ];
    for (final org in [_shop, _farm, _assoc]) {
      await tester.pumpWidget(
          _app(InvoicesScreen(key: ValueKey(org.id), org: org, invoicing: _Invoicing(rows))));
      await tester.pumpAndSettle();
      expect(find.text('1 facture en retard de paiement : Hôtel Lumière'), findsOneWidget, reason: org.profile);
      expect(find.byKey(const Key('invoice-late-i1')), findsOneWidget, reason: org.profile);
      expect(find.byKey(const Key('invoice-late-i3')), findsNothing, reason: 'cancelled is not counted');
      expect(find.byKey(const Key('attention-action-i1')), findsOneWidget);
    }
  });

  testWidgets('Carnet: debts past their date, counted as the bar counts them', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(CreditBookScreen(org: _farm, credit: _Credit(), retail: _Retail())));
    await tester.pumpAndSettle();
    expect(find.text('2 crédits ont dépassé leur date de remboursement : Awa'), findsOneWidget);
    expect(find.byKey(const Key('credit-late-c1')), findsOneWidget);
    expect(find.byKey(const Key('credit-late-c2')), findsNothing);
    expect(find.byKey(const Key('attention-action-c1')), findsOneWidget);
  });

  group('the farm\'s own tools', () {
    late LocalDb db;

    // The phone's own store answers outside the test's clock.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester) async {
      await _phone(tester);
      db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
    }

    testWidgets('Stock: the supplies under their threshold, each with its Réception', (tester) async {
      await open(tester);
      await tester.pumpWidget(_app(StockScreen(db: db, org: _farm, farm: _Farm())));
      await settle(tester);
      expect(find.text('2 fournitures sous leur seuil : Aliment ponte, Vaccin'), findsOneWidget);
      expect(find.byKey(const Key('stock-chip-i1')), findsOneWidget);
      expect(find.byKey(const Key('stock-chip-i3')), findsNothing);
      await tester.tap(find.byKey(const Key('attention-action-i2')));
      await settle(tester);
      // « Réception », already on Vaccin: the first question is answered.
      expect(find.text('Réception'), findsWidgets);
      final next = find.byKey(const Key('flow-next'));
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    });

    testWidgets('Bandes: the batches with nothing written today', (tester) async {
      await open(tester);
      await tester.pumpWidget(_app(FlocksScreen(db: db, org: _farm, farm: _Farm())));
      await settle(tester);
      expect(find.text('1 bande sans saisie aujourd\'hui : B-01'), findsOneWidget);
      expect(find.byKey(const Key('flock-quiet-f1')), findsOneWidget);
      expect(find.byKey(const Key('flock-quiet-f2')), findsNothing);
      expect(find.byKey(const Key('attention-action-f1')), findsOneWidget);
    });
  });

  testWidgets('Équipe: invitations out, not the expired one — all three kinds', (tester) async {
    await _phone(tester);
    for (final org in [_shop, _farm, _assoc]) {
      await tester.pumpWidget(_app(TeamScreen(
          key: ValueKey(org.id), org: org, admin: _Admin(), onboarding: OnboardingRepository(null))));
      await tester.pumpAndSettle();
      expect(find.text('1 invitation pas encore acceptée : Moussa'), findsOneWidget, reason: org.profile);
      expect(find.byKey(const Key('attention-item-inv2')), findsNothing);
      expect(find.byKey(const Key('attention-action-inv1')), findsOneWidget);
    }
  });
}
