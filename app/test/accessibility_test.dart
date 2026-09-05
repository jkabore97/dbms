import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/format/money.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/theme/motion.dart';
import 'package:kaj_app/features/storefront/directory_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The street, read aloud and read still.
///
/// A shopper with a screen reader hears each tile as one button that says
/// the article, its price, whether there is any, and the shop — not four
/// unrelated texts and an unlabelled tap. The stepper on a basketed tile is
/// two buttons that say which article they add or remove, each big enough
/// for a thumb. And a device asked for less motion gets the same page,
/// arriving still: no fade to wait out, no tile that grows under a pointer.
class _Street extends StorefrontRepository {
  _Street() : super(null);

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
          address: 'Rood Woko',
          lat: 12.3714,
          lng: -1.5197,
          distanceKm: 1.2,
        ),
      ];

  @override
  Future<List<FeaturedItem>> featured() async => const [
        FeaturedItem(
          id: 'f1',
          name: 'Pagne wax',
          price: 6500,
          inStock: true,
          shopName: 'Boutique Awa',
          shopSlug: 'boutique-awa',
        ),
      ];

  @override
  Future<List<ProductHit>> searchProducts(String query,
          {double? lat, double? lng}) async =>
      const [
        ProductHit(
          id: 'p1',
          name: 'Savon noir',
          price: 500,
          inStock: false,
          shopName: 'Boutique Binta',
          shopSlug: 'boutique-binta',
          distanceKm: 2.4,
        ),
      ];
}

class _OneShop extends StorefrontRepository {
  _OneShop() : super(null);

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => const PublicShop(
        orgId: 'o1',
        name: 'Boutique Awa',
        slug: 'boutique-awa',
        profile: 'retail',
      );

  @override
  Future<List<PublicItem>> items(String slug) async => const [
        PublicItem(id: 'p1', name: 'Café Touba', price: 450, inStock: true),
        PublicItem(id: 'p2', name: 'Savon', price: 300, inStock: false),
      ];
}

/// What a screen reader would say of one node, and whether it offers a tap.
/// Only that — not the focus flags this Flutter adds or withholds depending
/// on how the node was built.
void expectReads(
  SemanticsNode node, {
  required String label,
  required bool button,
  String? hint,
}) {
  final data = node.getSemanticsData();
  expect(data.label, label);
  if (hint != null) expect(data.hint, hint);
  expect(node.flagsCollection.isButton, button);
  expect(data.hasAction(SemanticsAction.tap), button);
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

  String f(num n) => moneyFormat('XOF').format(n);

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('the street, read aloud', () {
    testWidgets('a shop tile and a featured tile are one labelled button each',
        (tester) async {
      final handle = tester.ensureSemantics();
      tall(tester);
      await tester.pumpWidget(MaterialApp(
        home: DirectoryScreen(
          storefront: _Street(),
          capture: CaptureRepository(null, db: db),
          session: session(),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expectReads(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Boutique Awa'))),
        button: true,
        label: 'Boutique Awa, Boutique, Rood Woko, à 1.2 km',
        hint: 'Ouvrir la vitrine',
      );
      expectReads(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Pagne wax'))),
        button: true,
        label: 'Pagne wax, ${f(6500)}, chez Boutique Awa, à la une',
      );
      // The name, the price and the shop are not read a second time as
      // loose texts under the button.
      expect(find.bySemanticsLabel('Pagne wax'), findsNothing);
      handle.dispose();
    });

    testWidgets('a search hit says épuisé and how far the shop is',
        (tester) async {
      final handle = tester.ensureSemantics();
      tall(tester);
      await tester.pumpWidget(MaterialApp(
        home: DirectoryScreen(
          storefront: _Street(),
          capture: CaptureRepository(null, db: db),
          session: session(),
        ),
      ));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'savon');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expectReads(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Savon noir'))),
        button: true,
        label: 'Savon noir, ${f(500)}, épuisé, chez Boutique Binta, à 2.4 km',
        hint: 'Ouvrir la vitrine',
      );
      handle.dispose();
    });
  });

  group('the shelf, read aloud', () {
    Future<void> pumpShop(WidgetTester tester) async {
      tall(tester);
      await tester.pumpWidget(MaterialApp(
        home: StorefrontScreen(
          slug: 'boutique-awa',
          storefront: _OneShop(),
          capture: CaptureRepository(null, db: db),
          session: session(),
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
    }

    testWidgets(
        'an article is one button that offers the basket; épuisé is not',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpShop(tester);

      expectReads(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Café Touba'))),
        button: true,
        label: 'Café Touba, ${f(450)}',
        hint: 'Ajouter au panier',
      );
      expectReads(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Savon'))),
        button: false,
        label: 'Savon, ${f(300)}, épuisé',
      );
      handle.dispose();
    });

    testWidgets('the stepper is two named buttons, each 40 px a side',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpShop(tester);

      await tester.tap(find.text('Café Touba'));
      await tester.pump();

      expectReads(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Café Touba'))),
        button: true,
        label: 'Café Touba, ${f(450)}, 1 dans le panier',
      );
      final add = find.bySemanticsLabel('Ajouter un Café Touba');
      final remove = find.bySemanticsLabel('Retirer un Café Touba');
      expect(add, findsOneWidget);
      expect(remove, findsOneWidget);
      expect(tester.getSize(add), const Size(40, 40));
      expect(tester.getSize(remove), const Size(40, 40));

      await tester.tap(add);
      await tester.pump();
      expect(find.bySemanticsLabel('Café Touba, ${f(450)}, 2 dans le panier'),
          findsOneWidget);
      await tester.tap(remove);
      await tester.tap(remove);
      await tester.pump();
      expect(find.bySemanticsLabel('Café Touba, ${f(450)}'), findsOneWidget);
      expect(add, findsNothing);
      // Every tap also wrote the basket to the real (async) device database;
      // let the last write land before the database is closed.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      handle.dispose();
    });
  });

  group('less motion, asked for', () {
    Widget still(Widget child) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(home: Center(child: child)),
        );

    testWidgets('a reveal is already there: no fade, no wait',
        (tester) async {
      await tester.pumpWidget(still(const Reveal(
        delay: Duration(milliseconds: 300),
        child: Text('bonjour'),
      )));
      expect(find.text('bonjour'), findsOneWidget);
      expect(find.byType(AnimatedOpacity), findsNothing);
    });

    testWidgets('a lift stays flat under the pointer', (tester) async {
      await tester.pumpWidget(
          still(const Lift(child: SizedBox(width: 100, height: 100))));
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SizedBox)));
      await tester.pump();
      expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
    });

    testWidgets('a page arrives without the fade', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: ThemeData(
            pageTransitionsTheme: const PageTransitionsTheme(builders: {
              TargetPlatform.android: PaperPageTransitionsBuilder(),
              TargetPlatform.linux: PaperPageTransitionsBuilder(),
            }),
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const Text('deuxième page')),
              ),
              child: const Text('aller'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aller'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('deuxième page'), findsOneWidget);
      expect(find.byType(FadeTransition), findsNothing);
    });
  });

  group('a reveal is readable while still invisible', () {
    testWidgets('the semantics are there before the fade lands',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Reveal(
          delay: Duration(milliseconds: 300),
          child: Text('bonjour'),
        ),
      ));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      expect(find.bySemanticsLabel('bonjour'), findsOneWidget);
      handle.dispose();
    });
  });
}
