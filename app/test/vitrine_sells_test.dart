import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/vitrine_checklist_card.dart';
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

class _Admin extends AdminRepository {
  _Admin(this.list) : super(null);

  VitrineChecklist list;

  @override
  Future<VitrineChecklist?> vitrineChecklist(String orgId) async => list;
}

class _Retail extends RetailRepository {
  _Retail() : super(null);

  int published = 0;

  @override
  Future<int> publishAll(String orgId) async {
    published++;
    return 57;
  }
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

  group('the checklist', () {
    test('scores six steps and names what is missing', () {
      const list = VitrineChecklist(
          open: true, published: 0, unpublished: 57, withPhoto: 0, phone: true);
      expect(list.score, 17);
      expect(list.steps.where((s) => !s.done).first.label,
          'Des articles sur la vitrine');
      const full = VitrineChecklist(
          open: true,
          published: 7,
          withPhoto: 3,
          blurb: true,
          address: true,
          phone: true,
          pin: true);
      expect(full.score, 100);
    });

    testWidgets('Tout publier publishes the waiting articles', (tester) async {
      final retail = _Retail();
      final admin = _Admin(const VitrineChecklist(open: true, unpublished: 57));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VitrineChecklistCard(
                orgId: 'o1', admin: admin, retail: retail),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('0 %'), findsOneWidget);
      expect(find.text('Remplissez votre vitrine'), findsOneWidget);
      expect(find.byKey(const Key('vitrine-step-0')), findsOneWidget);
      expect(find.textContaining("n'apparaît pas dans l'annuaire"),
          findsOneWidget);

      admin.list = const VitrineChecklist(open: true, published: 57);
      await tester.tap(find.text('Tout publier (57)'));
      await tester.pump();
      await tester.pump();
      expect(retail.published, 1);
      expect(find.text('57 articles publiés sur la vitrine.'), findsOneWidget);
      expect(find.text('Tout publier (57)'), findsNothing);
    });
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
