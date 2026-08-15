import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/home/home_router.dart';
import 'package:kaj_app/features/retail/sale_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The store module, at the two points where it can silently do the wrong
/// thing: routing a shop somewhere else, and selling the same goods twice.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('the basket', () {
    test('adds up what is in it', () {
      const lines = [
        SaleLineDraft(name: 'Sucre 1kg', quantity: 3, unitPrice: 750),
        SaleLineDraft(name: 'Lait', quantity: 2, unitPrice: 1000),
      ];
      final total = lines.fold<double>(0, (sum, l) => sum + l.lineTotal);
      expect(total, 4250);
    });

    test('a line with no product still carries its name', () {
      // Selling something that was never entered is the point: the server
      // creates the product from the name rather than refusing the sale.
      const line = SaleLineDraft(name: 'Savon', quantity: 1, unitPrice: 500);
      final json = line.toJson();

      expect(json.containsKey('product_id'), isFalse);
      expect(json['name'], 'Savon');
      expect(json['quantity'], 1);
    });
  });

  group('a product', () {
    test('reports its margin and whether it is running low', () {
      const product = Product(
        id: 'p1',
        name: 'Sucre 1kg',
        costPrice: 500,
        salePrice: 750,
        quantity: 2,
        lowStockAt: 5,
      );

      expect(product.margin, 250);
      expect(product.isLow, isTrue);
    });

    test('reads the numbers Postgres sends as strings', () {
      // numeric columns arrive as strings over PostgREST often enough that
      // parsing them wrongly would show a shop zero stock it actually has.
      final product = Product.fromRow({
        'id': 'p1',
        'name': 'Lait',
        'cost_price': '700.00',
        'sale_price': '1000.00',
        'quantity': '12.000',
        'expires_on': '2026-09-01',
        'low_stock_at': null,
      });

      expect(product.costPrice, 700);
      expect(product.quantity, 12);
      expect(product.expiresOn, DateTime(2026, 9, 1));
      expect(product.isLow, isFalse);
    });
  });

  test('an expiring product knows when it is already too late', () {
    final gone = ExpiringProduct.fromRow({
      'product_id': 'p1',
      'name': 'Lait',
      'quantity': '4',
      'expires_on': '2026-08-01',
      'days_left': -3,
      'value_at_risk': '2800.00',
    });

    expect(gone.isExpired, isTrue);
    expect(gone.valueAtRisk, 2800);
  });

  group('the home router', () {
    late LocalDb db;

    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    testWidgets('a retail business opens the store, not the placeholder',
        (tester) async {
      // This is the regression that sent every shop to a "module coming"
      // screen: 'retail' had no case in the switch.
      const org = OrgSummary(id: 'org-3', name: 'Boutique Esperance',
          profile: 'retail');

      await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
        home: homeScreenFor(
          db: db,
          org: org,
          retail: RetailRepository(null),
        ),
      ));
      await tester.pump();

      expect(find.text('Boutique Esperance'), findsOneWidget);
      // The placeholder's label for a shop. Its absence is the assertion.
      expect(find.text('Commerce'), findsNothing);
    });

    testWidgets('a profile this build has never heard of still opens something',
        (tester) async {
      const org = OrgSummary(id: 'org-4', name: 'Quelque chose',
          profile: 'something-invented-next-year');

      await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
        home: homeScreenFor(db: db, org: org),
      ));
      await tester.pump();

      expect(find.text('Quelque chose'), findsWidgets);
    });
  });

  testWidgets('the sale button is dead until the basket has something in it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Scaffold(
        body: SaleSheet(orgId: 'org-3', retail: RetailRepository(null)),
      ),
    ));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Enregistrer la vente'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}
