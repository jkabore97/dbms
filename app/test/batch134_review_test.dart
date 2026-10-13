// Batch 134's review: what the supervisor found and fixed.
//
//   1. « Suivre le stock » (131): an article whose stock is not followed is
//      never « Rupture », and the article form asks — off by default for an
//      association, on for a shop, not asked on a database before 131;
//   2. a notification's address lands on its place for each kind (the bell
//      → notificationTarget → the folded address the router draws);
//   3. Argent's « Dépenses »: a next page that fails (no signal) is not
//      asked again once a frame;
//   4. « Vous êtes ici pour… »: going back is « plus tard », answered once;
//   5. the home's two acts stand one above the other when their words would
//      not fit side by side (320 px, text at 1.3) — never « Nouvelle … ».

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/accounting/models.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/invoicing/models.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/shopper/shopper_repository.dart';
import 'package:kaj_app/features/accounting/journal_screen.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/features/retail/article_flow.dart';
import 'package:kaj_app/features/retail/stock_attention.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/features/shopper/arrival_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _shop = OrgSummary(id: 'r1', name: 'Jersey Bakery', profile: 'retail', roles: ['owner']);
const _farm = OrgSummary(id: 'f1', name: 'Ferme Wend', profile: 'farm', roles: ['owner']);
const _assoc = OrgSummary(id: 'a1', name: 'Centre ELIM', profile: 'association', roles: ['owner']);

/// The shelf as the article form writes to it.
class _Shelf extends RetailRepository {
  _Shelf({this.missing = false}) : super(null);

  /// A database before 131.
  final bool missing;
  final log = <String>[];
  final updates = <Map<String, Object?>>[];

  @override
  bool get isConfigured => true;
  @override
  bool get stockTrackingMissing => missing;
  @override
  set stockTrackingMissing(bool v) {}
  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [];
  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {};
  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();
  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) async => const [];
  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) async => 0;
  @override
  Future<int> pendingOrders(String orgId) async => 0;
  @override
  Future<int> pendingSales(String orgId) async => 0;
  @override
  Future<List<Map<String, Object?>>> refusedSales(String orgId) async => const [];

  @override
  Future<String> ensureProduct({
    required String orgId,
    required String name,
    double? salePrice,
    double? costPrice,
    String? barcode,
    DateTime? expiresOn,
    bool isService = false,
  }) async {
    log.add('ensure $name');
    return 'new-1';
  }

  @override
  Future<void> receive({
    required String orgId,
    required String productId,
    required double quantity,
    double? unitCost,
    DateTime? expiresOn,
    String method = 'cash',
    String? clientUuid,
  }) async =>
      log.add('receive $quantity');

  @override
  Future<void> updateProduct(
    String productId, {
    String? name,
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
    bool? stockTracked,
  }) async =>
      updates.add({'quantity': quantity, 'tracked': stockTracked, 'low': lowStockAt});
}

class _Bills extends InvoicingRepository {
  _Bills() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<List<InvoiceSummary>> list(String orgId, {bool includePaid = true, int limit = 200}) async =>
      const [];
  @override
  Future<BillingDetails> billingDetails(String orgId) async => const BillingDetails();
}

/// The books with no signal after the first page.
class _Offline extends AccountingRepository {
  _Offline() : super(null);
  int calls = 0;
  @override
  bool get isConfigured => true;
  @override
  Future<List<JournalRow>> journal(String orgId,
      {DateTime? from, DateTime? to, int limit = 100, int offset = 0}) async {
    calls++;
    if (offset > 0) throw Exception('Failed host lookup');
    // A full page of sales, none of them an expense.
    return [
      for (var i = 0; i < limit; i++)
        JournalRow(
          entryId: 'e$i',
          occurredAt: DateTime(2026, 10, 1),
          label: 'Vente',
          amount: 1000,
          direction: 'in',
          reversed: false,
          isReversal: false,
          recordedBy: 'Awa',
        ),
    ];
  }
}

class _Shopper extends ShopperRepository {
  _Shopper() : super(null);
  final answers = <String>[];
  @override
  Future<bool> arrivalPending() async => true;
  @override
  Future<void> answerArrival(String intent) async => answers.add(intent);
}

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

Future<void> _phone(WidgetTester tester, {double width = 390, double height = 1000}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('1. « Suivre le stock »', () {
    test('a row says it; a database before 131 reads every article followed', () {
      final off = Product.fromRow(const {'id': 'p', 'name': 'Entrée', 'quantity': 0, 'stock_tracked': false});
      final old = Product.fromRow(const {'id': 'q', 'name': 'Savon', 'quantity': 0});
      expect(off.stockTracked, isFalse);
      expect(off.counted, isFalse);
      expect(old.stockTracked, isTrue, reason: 'no column: followed, as before');
    });

    testWidgets('not followed: never « Rupture », never « bas »; followed at zero still is', (tester) async {
      const items = [
        Product(id: 'a', name: 'Entrée concert', quantity: 0, lowStockAt: 3, stockTracked: false),
        Product(id: 'b', name: 'Livre', quantity: 0),
        Product(id: 'c', name: 'T-shirt', quantity: 2, lowStockAt: 3),
      ];
      expect(stockFlagged(items).map((p) => p.name), ['Livre', 'T-shirt']);
      expect(items.first.isLow, isFalse);
      await tester.pumpWidget(_app(Builder(builder: (context) {
        expect(stockChip(context, items[0]), isNull);
        expect(stockChip(context, items[1]), 'Rupture');
        return const SizedBox();
      })));
    });

    Future<void> addOne(WidgetTester tester, _Shelf shelf, OrgSummary org,
        {required void Function() atQuantity}) async {
      await _phone(tester, height: 1200);
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => ArticleFlow.open(context,
                org: org, retail: shelf, forSale: org.isAssociation, store: MemoryFlowStore()),
            child: const Text('Ouvrir'),
          ),
        ),
      )));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('article-name')), 'Entrée concert');
      await tester.pump();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('article-price')), '2500');
      await tester.pump();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      // The shop's buying price (optional): on to the count.
      while (find.byKey(const Key('article-cost')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('flow-next')));
        await tester.pumpAndSettle();
      }
      atQuantity();
      for (var i = 0; i < 10 && find.byKey(const Key('flow-save')).evaluate().isEmpty; i++) {
        await tester.tap(find.byKey(const Key('flow-next')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('an association: off by default — no count asked, nothing received, saved « not followed »',
        (tester) async {
      final shelf = _Shelf();
      await addOne(tester, shelf, _assoc, atQuantity: () {
        final sw = tester.widget<SwitchListTile>(find.byKey(const Key('article-tracked')));
        expect(sw.value, isFalse);
        expect(find.byKey(const Key('article-quantity')), findsNothing);
      });
      expect(shelf.log.where((l) => l.startsWith('receive')), isEmpty);
      expect(shelf.updates.first['tracked'], isFalse);
      expect(shelf.updates.first['quantity'], isNull);
    });

    testWidgets('a shop: on by default, the count asked; the column left to its default', (tester) async {
      final shelf = _Shelf();
      await addOne(tester, shelf, _shop, atQuantity: () {
        final sw = tester.widget<SwitchListTile>(find.byKey(const Key('article-tracked')));
        expect(sw.value, isTrue);
        expect(find.byKey(const Key('article-quantity')), findsOneWidget);
      });
      expect(shelf.updates.first['tracked'], isNull);
    });

    testWidgets('a database before 131: no switch, the count asked as before', (tester) async {
      final shelf = _Shelf(missing: true);
      await addOne(tester, shelf, _assoc, atQuantity: () {
        expect(find.byKey(const Key('article-tracked')), findsNothing);
        expect(find.byKey(const Key('article-quantity')), findsOneWidget);
      });
      expect(shelf.updates.first['tracked'], isNull, reason: 'no column to write');
    });
  });

  group('2. a notification lands on its place, for each kind', () {
    NotificationRow row(String org, String kind, [Map<String, dynamic> p = const {}]) => NotificationRow(
        id: 'n', kind: kind, message: '', createdAt: DateTime(2026, 10, 13), orgId: org, params: p);
    String? landing(OrgSummary org, String kind, [Map<String, dynamic> p = const {}]) {
      final to = notificationTarget(row(org.id, kind, p),
          isAdminOf: (_) => true, profileOf: (_) => org.profile)!;
      return foldedAddress(Uri.parse(to), org) ?? to;
    }

    test('the shop', () {
      expect(landing(_shop, 'new_order'), Routes.inside('r1', 'commandes'));
      expect(landing(_shop, 'low_stock', {'name': 'Savon'}),
          '${Routes.inside('r1', 'catalogue')}?q=Savon&partie=articles');
      expect(landing(_shop, 'debt_settled'), '${Routes.inside('r1', 'argent')}?partie=credit');
      expect(landing(_shop, 'debt_settled', {'customer_id': 'c1'}), Routes.inside('r1', 'credits/c1'));
    });

    test('the farm', () {
      expect(landing(_farm, 'new_order', {'order_id': 'o9', 'booking': true, 'at': '2026-10-14T10:00:00Z'}),
          '${Routes.inside('f1', 'ventes')}?commande=o9&partie=commandes');
      expect(landing(_farm, 'new_order'), '${Routes.inside('f1', 'ventes')}?partie=commandes');
      expect(landing(_farm, 'low_stock', {'name': 'Œufs'}), '${Routes.inside('f1', 'ventes')}?partie=a-vendre');
      expect(landing(_farm, 'debt_settled'), Routes.inside('f1', 'credits'), reason: 'its own page, from Ventes');
    });

    test('the association', () {
      expect(landing(_assoc, 'new_order'), Routes.inside('a1', 'commandes'), reason: 'its Demandes');
      expect(landing(_assoc, 'low_stock', {'name': 'Livre'}),
          '${Routes.inside('a1', 'catalogue')}?q=Livre&partie=articles');
      expect(landing(_assoc, 'debt_settled'), Routes.inside('a1', 'credits'), reason: 'from Compte');
    });
  });

  testWidgets('3. « Dépenses » with no signal: the next page is not asked again once a frame', (tester) async {
    await _phone(tester);
    final books = _Offline();
    await tester.pumpWidget(_app(JournalScreen(accounting: books, org: _shop, direction: 'out')));
    await _settle(tester);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _settle(tester);
    // The first page, and one next page that failed: not thirty.
    expect(books.calls, 2);
  });

  testWidgets('4. « Vous êtes ici pour… »: back is « plus tard », answered once', (tester) async {
    await _phone(tester);
    final me = _Shopper();
    await tester.pumpWidget(_app(Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => ArrivalScreen(shopper: me))),
          child: const Text('Marché'),
        ),
      ),
    )));
    await tester.tap(find.text('Marché'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('arrival')), findsOneWidget);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('arrival')), findsNothing);
    expect(me.answers, ['later']);
  });

  group('5. the home\'s two acts', () {
    Future<(Rect, Rect)> acts(WidgetTester tester, double width, double scale) async {
      await _phone(tester, width: width, height: 900);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: StoreHomeScreen(org: _shop, retail: _Shelf(), invoicing: _Bills()),
      ));
      await _settle(tester);
      return (
        tester.getRect(find.byKey(const Key('home-new-sale'))),
        tester.getRect(find.byKey(const Key('home-expense'))),
      );
    }

    testWidgets('side by side on a 390 px phone', (tester) async {
      final (sale, expense) = await acts(tester, 390, 1.0);
      expect(sale.top, expense.top);
      expect(sale.right, lessThan(expense.left));
    });

    testWidgets('one above the other at 320 px and text at 1.3, each its whole width', (tester) async {
      final (sale, expense) = await acts(tester, 320, 1.3);
      expect(expense.top, greaterThan(sale.bottom));
      expect(sale.width, expense.width);
      expect(tester.takeException(), isNull);
    });
  });
}
