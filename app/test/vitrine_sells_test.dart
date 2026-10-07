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
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A vitrine that sells (070).
///
/// The audit's screenshots: every article a grey box with an image icon, a
/// tap that dropped one in the basket without a word about the article,
/// rows with a band of white under each, and a directory of beige squares
/// carrying the shop's initial. Each test is one of those, fixed.
class _Shop extends StorefrontRepository {
  _Shop(this.goods) : super(null);

  final List<PublicItem> goods;

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => const PublicShop(
        orgId: 'o1',
        name: 'Boutique Awa',
        slug: 'boutique-awa',
        profile: 'retail',
        phone: '+22670000000',
      );

  @override
  Future<List<PublicItem>> items(String slug) async => goods;

  @override
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) async =>
      const [
        DirectoryEntry(
            orgId: 'o1', name: 'Boutique Awa', slug: 'boutique-awa', profile: 'retail'),
      ];

  @override
  Future<List<FeaturedItem>> featured() async => const [];

  @override
  Future<Map<String, List<ShopPreview>>> previews(List<String> slugs) async => {
        'boutique-awa': const [
          ShopPreview(slug: 'boutique-awa', productId: 'p1', name: 'Bissap', price: 150),
          ShopPreview(slug: 'boutique-awa', productId: 'p2', name: 'Chaussette', price: 700),
        ],
      };
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  SessionController session() => SessionController(
        db: db,
        auth: AuthRepository(null),
        admin: AdminRepository(null),
        accounting: AccountingRepository(null),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 800));
  }

  Future<void> pumpShop(WidgetTester tester, List<PublicItem> goods) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: StorefrontScreen(
        slug: 'boutique-awa',
        storefront: _Shop(goods),
        capture: CaptureRepository(null, db: db),
        session: session(),
      ),
    ));
    await settle(tester);
  }

  testWidgets('an article with no photo shows its name, not a grey box',
      (tester) async {
    await pumpShop(tester, const [
      PublicItem(id: 'p1', name: 'Bissap', price: 150, inStock: true),
    ]);
    expect(find.byType(NoPhotoPanel), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(
        find.descendant(
            of: find.byType(NoPhotoPanel), matching: find.text('Bissap')),
        findsOneWidget);
  });

  testWidgets('a tap opens the article; its button fills the basket',
      (tester) async {
    await pumpShop(tester, const [
      PublicItem(
          id: 'p1',
          name: 'Bissap',
          price: 150,
          inStock: true,
          description: 'Fait maison, servi frais.'),
    ]);
    await tester.tap(find.text('Bissap').last);
    await tester.pumpAndSettle();

    expect(find.byType(ArticleSheet), findsOneWidget);
    expect(find.text('En stock'), findsOneWidget);
    expect(find.text('Poser une question sur WhatsApp'), findsOneWidget);
    expect(find.text('Commander'), findsNothing,
        reason: 'opening the article puts nothing in the basket');

    await tester.tap(find.text('Ajouter au panier'));
    await tester.pumpAndSettle();
    expect(find.text('1 dans le panier'), findsOneWidget);
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('Commander'), findsOneWidget);
  });

  test('the WhatsApp question names the article', () {
    final url = whatsappUrl('+226 70 00 00 00',
        text: 'Bonjour, une question sur « Bissap »');
    expect(url, startsWith('https://wa.me/22670000000?text='));
    expect(Uri.decodeComponent(url!.split('text=').last), contains('Bissap'));
  });

  testWidgets('long names and descriptions fit their cells: no overflow',
      (tester) async {
    await pumpShop(tester, [
      for (var i = 0; i < 9; i++)
        PublicItem(
          id: 'p$i',
          name: 'Un article au nom vraiment très long numéro $i',
          price: 1000.0 + i,
          inStock: i.isEven,
          description: 'Deux lignes de description qui débordent largement '
              'de la place prévue pour elles sur un téléphone.',
        ),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a directory card shows what the shop sells', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: DirectoryScreen(
        storefront: _Shop(const []),
        capture: CaptureRepository(null, db: db),
        session: session(),
      ),
    ));
    await settle(tester);
    expect(find.text('Bissap'), findsOneWidget);
    expect(find.text('700 F'), findsOneWidget);
    expect(find.text('B'), findsNothing, reason: 'no initial on a beige square');
  });
}
