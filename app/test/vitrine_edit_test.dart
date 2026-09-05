import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/retail/products_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The vitrine from the shop's side, after the owner's report: the switch
/// said "off" for an article already in the window (the row never read
/// is_published), there was no description to write, and no visible way
/// from the stock list to the window at all — only a long press nobody
/// discovers. Now the row carries a storefront button that opens the same
/// sheet, the switch reflects the row, and the description travels from the
/// sheet to the street.
class _Shelf extends RetailRepository {
  _Shelf({this.published = true, this.description}) : super(null);

  final bool published;
  final String? description;

  /// What the sheet asked to save, verbatim.
  final saved = <Map<String, Object?>>[];

  @override
  Future<List<Product>> products(String orgId,
          {bool activeOnly = true}) async =>
      [
        Product(
          id: 'p1',
          name: 'Gateau',
          costPrice: 1200,
          salePrice: 2500,
          quantity: 4,
          isPublished: published,
          description: description,
        ),
      ];

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
  }) async {
    saved.add({
      'id': productId,
      'is_published': isPublished,
      'description': description,
    });
  }
}

class _OneShop extends StorefrontRepository {
  _OneShop(this.shelf) : super(null);

  final List<PublicItem> shelf;

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => const PublicShop(
        orgId: 'o1',
        name: 'Pâtisserie Esperance',
        slug: 'esperance',
        profile: 'retail',
      );

  @override
  Future<List<PublicItem>> items(String slug) async => shelf;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('the rows', () {
    test('a product reads its description, and blank reads null', () {
      final told = Product.fromRow({
        'id': 'p1',
        'name': 'Gateau',
        'is_published': true,
        'description': 'Gâteau au chocolat, 8 parts.',
      });
      expect(told.isPublished, isTrue);
      expect(told.description, 'Gâteau au chocolat, 8 parts.');

      final blank = Product.fromRow(
          {'id': 'p2', 'name': 'Pagne', 'description': '   '});
      expect(blank.description, isNull);
      // Absent before 064: an app ahead of its database reads "nothing".
      expect(Product.fromRow({'id': 'p3', 'name': 'Lait'}).description,
          isNull);
    });

    test('the street row carries the description the same way', () {
      final item = PublicItem.fromRow({
        'id': 'p1',
        'name': 'Gateau',
        'sale_price': '2500.00',
        'in_stock': true,
        'photo_key': null,
        'description': 'Gâteau au chocolat, 8 parts.',
      });
      expect(item.hasDescription, isTrue);
      expect(item.description, 'Gâteau au chocolat, 8 parts.');

      final bare = PublicItem.fromRow({
        'id': 'p2',
        'name': 'Pagne',
        'sale_price': 6000,
        'in_stock': true,
        'photo_key': null,
      });
      expect(bare.hasDescription, isFalse);
    });
  });

  group('the edit sheet', () {
    late LocalDb db;

    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });

    tearDown(() => db.close());

    const org = OrgSummary(id: 'org-1', name: 'Boutique Awa', profile: 'retail');

    Future<void> pumpShelf(WidgetTester tester, _Shelf shelf) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ProductsScreen(
          org: org,
          retail: shelf,
          capture: CaptureRepository(null, db: db),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    Future<void> openSheetFromRow(WidgetTester tester) async {
      // The visible door: a tap on the row's storefront button, not the
      // long press nobody finds.
      await tester.tap(find.byTooltip('Sur la vitrine — modifier'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
    }

    testWidgets('an article already in the window shows a filled door',
        (tester) async {
      await pumpShelf(tester, _Shelf(published: true));
      expect(find.byTooltip('Sur la vitrine — modifier'), findsOneWidget);
      expect(find.byTooltip('Mettre sur la vitrine'), findsNothing);
      expect(find.byIcon(Icons.storefront), findsOneWidget);
    });

    testWidgets('an article not yet in the window shows the outlined door',
        (tester) async {
      await pumpShelf(tester, _Shelf(published: false));
      expect(find.byTooltip('Mettre sur la vitrine'), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    });

    testWidgets('the switch tells the truth about an article in the window',
        (tester) async {
      // The report: "even when the item is already in vitrine the button
      // is not activated" — the stock list never selected is_published, so
      // every sheet opened on "off" and Enregistrer quietly unpublished.
      await pumpShelf(tester,
          _Shelf(published: true, description: 'Gâteau au chocolat, 8 parts.'));
      await openSheetFromRow(tester);

      final toggle = tester.widget<SwitchListTile>(find.widgetWithText(
          SwitchListTile, 'Afficher sur la vitrine en ligne'));
      expect(toggle.value, isTrue);
      expect(find.text('Gâteau au chocolat, 8 parts.'), findsOneWidget);
    });

    testWidgets('the description is written from the sheet and saved with it',
        (tester) async {
      final shelf = _Shelf(published: true);
      await pumpShelf(tester, shelf);
      await openSheetFromRow(tester);

      final field = find.widgetWithText(
          TextField, 'Description pour la vitrine (facultatif)');
      expect(field, findsOneWidget);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Gâteau au chocolat, 8 parts.');
      await tester.pump();

      final save = find.widgetWithText(FilledButton, 'Enregistrer');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump();

      expect(shelf.saved, hasLength(1));
      expect(shelf.saved.single['id'], 'p1');
      expect(shelf.saved.single['is_published'], isTrue);
      expect(
          shelf.saved.single['description'], 'Gâteau au chocolat, 8 parts.');
    });

    testWidgets('an untouched description is not sent at all',
        (tester) async {
      // The app deploys before the owner pastes 064; until then the column
      // does not exist and a price edit must still save.
      final shelf = _Shelf(published: true, description: 'Huit parts.');
      await pumpShelf(tester, shelf);
      await openSheetFromRow(tester);

      final save = find.widgetWithText(FilledButton, 'Enregistrer');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump();

      expect(shelf.saved, hasLength(1));
      expect(shelf.saved.single['description'], isNull);
      expect(shelf.saved.single['is_published'], isTrue);
    });
  });

  group('the vitrine', () {
    late LocalDb db;

    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });

    tearDown(() => db.close());

    testWidgets('a described article says its two lines under the price',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: StorefrontScreen(
          slug: 'esperance',
          storefront: _OneShop(const [
            PublicItem(
              id: 'p1',
              name: 'Gateau',
              price: 2500,
              inStock: true,
              description: 'Gâteau au chocolat, 8 parts. Commander la veille.',
            ),
            PublicItem(id: 'p2', name: 'Pagne', price: 6000, inStock: true),
          ]),
          capture: CaptureRepository(null, db: db),
          session: SessionController(
            db: db,
            auth: AuthRepository(null),
            admin: AdminRepository(null),
            accounting: AccountingRepository(null),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 800));

      expect(
        find.text('Gâteau au chocolat, 8 parts. Commander la veille.'),
        findsOneWidget,
      );
      // No overflow: the grid cell grew for the two extra lines.
      expect(tester.takeException(), isNull);
      // A screen reader hears it with the name and the price.
      final handle = tester.ensureSemantics();
      final node = tester.getSemantics(find.bySemanticsLabel(
          RegExp(r'Gateau, .*Gâteau au chocolat, 8 parts\. Commander la veille\.')));
      expect(node, isNotNull);
      handle.dispose();
    });
  });
}
