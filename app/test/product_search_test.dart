import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/storefront/directory_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The search across every window (059), from the shopper's side of the
/// glass: typing a word turns the street into results from several shops,
/// each naming its shop and how far it is; too short a word turns it back;
/// and an answer nobody has is said in words, echoing what was asked.
///
/// The repository is a fake on purpose — what the server returns for which
/// query is proven in SQL (test_product_search.sql); what this proves is
/// that the page asks, waits out the debounce, and shows what came back.
class _SearchableStreet extends StorefrontRepository {
  _SearchableStreet() : super(null);

  final List<String> asked = [];

  @override
  bool get isConfigured => true;

  @override
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) async =>
      const [
        DirectoryEntry(
          orgId: 'o1',
          name: 'Boutique Awa',
          slug: 'boutique-awa',
          profile: 'retail',
        ),
      ];

  @override
  Future<List<FeaturedItem>> featured() async => const [];

  @override
  Future<List<ProductHit>> searchProducts(String query,
      {double? lat, double? lng}) async {
    asked.add(query);
    if (!query.toLowerCase().contains('savon')) return const [];
    return const [
      ProductHit(
        id: 'p1',
        name: 'Savon Citec',
        price: 450,
        inStock: true,
        shopName: 'Boutique Awa',
        shopSlug: 'boutique-awa',
        distanceKm: 1.2,
      ),
      ProductHit(
        id: 'p2',
        name: 'Savon noir',
        price: 500,
        inStock: false,
        shopName: 'Boutique Binta',
        shopSlug: 'boutique-binta',
      ),
    ];
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ProductHit.fromRow', () {
    test('reads numbers whether PostgREST sends them as num or string', () {
      final h = ProductHit.fromRow({
        'id': 'p1',
        'name': 'Savon Citec',
        'sale_price': '450',
        'in_stock': true,
        'photo_key': null,
        'shop_name': 'Boutique Awa',
        'shop_slug': 'boutique-awa',
        'currency': 'XOF',
        'shop_lat': '12.3714',
        'shop_lng': -1.5197,
        'distance_km': '1.25',
      });
      expect(h.price, closeTo(450, 1e-9));
      expect(h.inStock, isTrue);
      expect(h.shopLat, closeTo(12.3714, 1e-9));
      expect(h.shopLng, closeTo(-1.5197, 1e-9));
      expect(h.distanceKm, closeTo(1.25, 1e-9));
    });

    test('a hit with no pin and no distance stays whole', () {
      final h = ProductHit.fromRow({
        'id': 'p2',
        'name': 'Savon noir',
        'sale_price': 500,
        'in_stock': false,
        'shop_name': 'Boutique Binta',
        'shop_slug': 'boutique-binta',
      });
      expect(h.inStock, isFalse);
      expect(h.shopLat, isNull);
      expect(h.distanceKm, isNull);
      expect(h.currency, 'XOF');
    });
  });

  group('the search on the street', () {
    late LocalDb db;
    late _SearchableStreet street;

    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
      street = _SearchableStreet();
    });

    tearDown(() => db.close());

    Future<void> pumpStreet(WidgetTester tester) async {
      // Tall enough that the hero, the results and the shop list are all in
      // the viewport at once — a ListView builds nothing below the fold.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final session = SessionController(
        db: db,
        auth: AuthRepository(null),
        admin: AdminRepository(null),
        accounting: AccountingRepository(null),
      );
      await tester.pumpWidget(MaterialApp(
        home: DirectoryScreen(
          storefront: street,
          capture: CaptureRepository(null, db: db),
          session: session,
        ),
      ));
      // Let the directory load land.
      await tester.pump();
      await tester.pump();
    }

    testWidgets('typing a word turns the street into results',
        (tester) async {
      await pumpStreet(tester);
      expect(find.text('TOUTES LES VITRINES'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'savon');
      // One keystroke burst, one question: the debounce waits out the typing.
      await tester.pump(const Duration(milliseconds: 349));
      expect(street.asked, isEmpty);
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();

      expect(street.asked, ['savon']);
      expect(find.text('RÉSULTATS'), findsOneWidget);
      expect(find.text('Savon Citec'), findsOneWidget);
      expect(find.text('Boutique Awa · 1.2 km'), findsOneWidget);
      // Out of stock is said on the price line, and the shop still named.
      expect(find.textContaining('Épuisé'), findsOneWidget);
      expect(find.text('Boutique Binta'), findsOneWidget);
      // The street itself has stepped aside.
      expect(find.text('TOUTES LES VITRINES'), findsNothing);
    });

    testWidgets('an empty answer is said in words, echoing the query',
        (tester) async {
      await pumpStreet(tester);
      await tester.enterText(find.byType(TextField), 'ordinateur');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(
        find.text(
            'Aucun article ne répond à « ordinateur ». Essayez un autre mot.'),
        findsOneWidget,
      );
    });

    testWidgets('one letter is browsing: the street comes back',
        (tester) async {
      await pumpStreet(tester);
      await tester.enterText(find.byType(TextField), 'savon');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('RÉSULTATS'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 's');
      await tester.pump();
      expect(find.text('RÉSULTATS'), findsNothing);
      expect(find.text('TOUTES LES VITRINES'), findsOneWidget);
      // And no second question went out for it.
      await tester.pump(const Duration(milliseconds: 400));
      expect(street.asked, ['savon']);
    });
  });
}
