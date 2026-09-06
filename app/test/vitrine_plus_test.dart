import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/vitrine_plus_card.dart';
import 'package:kaj_app/features/storefront/shop_style.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A Pro shop dresses its window (068): the style travels from the form to
/// the street, the street orders the shelf by it, the colour is readable
/// whatever the shop picked, and a Free owner meets the door to pay.
class _OneShop extends StorefrontRepository {
  _OneShop(this.style) : super(null);

  final StorefrontStyle style;

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => PublicShop(
        orgId: 'o1',
        name: 'Boutique Awa',
        slug: 'boutique-awa',
        profile: 'retail',
        address: 'Marché de Gounghin',
        style: style,
      );

  @override
  Future<List<PublicItem>> items(String slug) async => const [
        PublicItem(id: 'p1', name: 'Sucre', price: 750, inStock: true),
        PublicItem(id: 'p2', name: 'Pagne', price: 6000, inStock: true),
        PublicItem(id: 'p3', name: 'Gâteau', price: 2500, inStock: false),
        PublicItem(id: 'p4', name: 'Savon', price: 450, inStock: true),
      ];
}

class _Admin extends AdminRepository {
  _Admin({this.style = StorefrontStyle.none, this.refuse = false})
      : super(null);

  final StorefrontStyle style;
  final bool refuse;
  final saved = <StorefrontStyle>[];

  @override
  Future<StorefrontStyle> storefrontStyle(String orgId) async => style;

  @override
  Future<void> setStorefrontStyle(String orgId, StorefrontStyle style) async {
    if (refuse) {
      throw const PostgrestException(
          message: 'Kaj Pro : la vitrine personnalisée fait partie de Kaj Pro.',
          code: 'P0001');
    }
    saved.add(style);
  }
}

class _Shelf extends RetailRepository {
  _Shelf() : super(null);

  @override
  Future<List<Product>> products(String orgId,
          {bool activeOnly = true}) async =>
      const [
        Product(id: 'p1', name: 'Sucre', isPublished: true),
        Product(id: 'p2', name: 'Pagne', isPublished: true),
        Product(id: 'p9', name: 'Caché', isPublished: false),
      ];
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('the style', () {
    test('reads what storefront() sends and writes what the server takes',
        () {
      final style = StorefrontStyle.fromJson({
        'tagline': ' Depuis 1998 ',
        'hours': 'Lun–Sam 8h–19h',
        'accent': '#B1541A',
        'cover_key': 'org/o1/devanture.jpg',
        'pinned': ['p2', 'p1'],
        'hide_out_of_stock': true,
        'font': 'ignored',
      });
      expect(style.tagline, 'Depuis 1998');
      expect(style.hours, 'Lun–Sam 8h–19h');
      expect(style.accent, const Color(0xFFB1541A));
      expect(style.coverKey, 'org/o1/devanture.jpg');
      expect(style.pinned, ['p2', 'p1']);
      expect(style.hideOutOfStock, isTrue);
      expect(style.toJson(), {
        'tagline': 'Depuis 1998',
        'hours': 'Lun–Sam 8h–19h',
        'accent': '#B1541A',
        'cover_key': 'org/o1/devanture.jpg',
        'pinned': ['p2', 'p1'],
        'hide_out_of_stock': true,
      });
      // The common design: nothing, and nothing sent.
      expect(StorefrontStyle.fromJson(null).isEmpty, isTrue);
      expect(StorefrontStyle.fromJson({'accent': 'orange'}).accent, isNull);
      expect(StorefrontStyle.none.toJson(), isEmpty);
    });

    test('a shop row before 068, or a Free shop, reads the common design',
        () {
      final shop = PublicShop.fromRow({
        'org_id': 'o1',
        'name': 'Boutique',
        'slug': 'boutique',
        'profile': 'retail',
      });
      expect(shop.style.isEmpty, isTrue);
      final free = PublicShop.fromRow({
        'org_id': 'o1',
        'name': 'Boutique',
        'slug': 'boutique',
        'profile': 'retail',
        'style': <String, dynamic>{},
      });
      expect(free.style.isEmpty, isTrue);
    });

    test('orders the shelf: pinned first in their order, épuisé left off',
        () {
      const items = [
        PublicItem(id: 'p1', name: 'Sucre', price: 750, inStock: true),
        PublicItem(id: 'p2', name: 'Pagne', price: 6000, inStock: true),
        PublicItem(id: 'p3', name: 'Gâteau', price: 2500, inStock: false),
        PublicItem(id: 'p4', name: 'Savon', price: 450, inStock: true),
      ];
      final arranged = const StorefrontStyle(
              pinned: ['p4', 'p2'], hideOutOfStock: true)
          .arrange(items);
      expect(arranged.map((i) => i.id), ['p4', 'p2', 'p1']);
      // A pin for an article no longer in the window is simply skipped.
      expect(
          const StorefrontStyle(pinned: ['gone', 'p1'])
              .arrange(items)
              .map((i) => i.id),
          ['p1', 'p2', 'p3', 'p4']);
      expect(StorefrontStyle.none.arrange(items), items);
    });

    test('the button colour always carries readable text', () {
      expect(ShopStyle.onAccent(const Color(0xFF1F5FA8)), ShopStyle.paper);
      expect(ShopStyle.onAccent(const Color(0xFFFFE082)), ShopStyle.ink);
    });
  });

  group('the street', () {
    late LocalDb db;

    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });

    tearDown(() => db.close());

    testWidgets('shows the tagline, the hours and the pinned order',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: StorefrontScreen(
          slug: 'boutique-awa',
          storefront: _OneShop(const StorefrontStyle(
            tagline: 'Pagnes et gâteaux depuis 1998',
            hours: 'Lun–Sam 8h–19h',
            accent: Color(0xFFB1541A),
            pinned: ['p4'],
            hideOutOfStock: true,
          )),
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

      expect(find.text('Pagnes et gâteaux depuis 1998'), findsOneWidget);
      expect(find.text('Lun–Sam 8h–19h'), findsOneWidget);
      // Épuisé left off, and the count says what is on the shelf.
      expect(find.text('Gâteau'), findsNothing);
      expect(find.text('3 articles'), findsOneWidget);
      // Savon first: pinned.
      final savon = tester.getTopLeft(find.text('Savon'));
      final sucre = tester.getTopLeft(find.text('Sucre'));
      expect(savon.dy <= sucre.dy && savon.dx <= sucre.dx, isTrue,
          reason: 'the pinned article comes first on the shelf');
      // The accent reaches the page's theme, and so every filled button.
      final theme = Theme.of(tester.element(find.text('Partager')));
      expect(theme.colorScheme.primary, const Color(0xFFB1541A));
      expect(
          theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
          const Color(0xFFB1541A));
    });
  });

  group('the form', () {
    testWidgets('prefills what was written and saves what was changed',
        (tester) async {
      final admin = _Admin(
          style: const StorefrontStyle(tagline: 'Depuis 1998', pinned: ['p2']));
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VitrinePlusCard(
                orgId: 'org-1', admin: admin, retail: _Shelf()),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.widgetWithText(TextField, 'Depuis 1998'), findsOneWidget);
      expect(find.text('Articles en tête (1/6)'), findsOneWidget);
      // Only published articles are offered.
      expect(find.text('Caché'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextField, 'Horaires'), 'Lun–Sam 8h–19h');
      await tester.tap(find.bySemanticsLabel('Couleur #2E7D5B'));
      await tester.tap(find.text('Sucre'));
      await tester.pump();
      expect(find.text('Articles en tête (2/6)'), findsOneWidget);

      final save = find.text('Enregistrer la vitrine');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump();

      expect(admin.saved, hasLength(1));
      expect(admin.saved.single.toJson(), {
        'tagline': 'Depuis 1998',
        'hours': 'Lun–Sam 8h–19h',
        'accent': '#2E7D5B',
        'pinned': ['p2', 'p1'],
      });
      expect(find.textContaining('Vitrine enregistrée'), findsOneWidget);
    });

    testWidgets('a refusal for the plan is shown in the server\'s words',
        (tester) async {
      final admin = _Admin(refuse: true);
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VitrinePlusCard(orgId: 'org-1', admin: admin),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      final save = find.text('Enregistrer la vitrine');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Kaj Pro :'), findsOneWidget);
      expect(admin.saved, isEmpty);
    });
  });
}
