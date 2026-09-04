import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The shelf filter inside one shop: instant, accent-blind like the street's
/// search, offered only once the shelf is long enough to need it, and the
/// count always tells the truth about what is hidden. Plus the two links a
/// vitrine lives by: its public address, and the WhatsApp share.
class _OneShop extends StorefrontRepository {
  _OneShop(this.count) : super(null);

  final int count;

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
  Future<List<PublicItem>> items(String slug) async => [
        for (var i = 0; i < count; i++)
          PublicItem(
            id: 'p$i',
            name: i == 0 ? 'Café Touba' : 'Savon n°$i',
            price: 450,
            inStock: true,
          ),
      ];
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('the links', () {
    test('folding matches the street search: cafe finds Café', () {
      expect(foldSearchText('CAFÉ'), 'cafe');
      expect(foldSearchText('Un Îlot Où ça Sèche'), 'un ilot ou ca seche');
      expect(foldSearchText(''), '');
    });

    test('the public address falls back to the production site', () {
      // In a test there is no http origin to inherit.
      expect(publicShopUrl('boutique-awa'),
          'https://dbms.kabore-boss.workers.dev/s/boutique-awa');
    });

    test('the share link carries the text, encoded', () {
      final url = whatsappShareUrl('Découvrez Boutique Awa : https://x/s/a');
      expect(url, startsWith('https://wa.me/?text='));
      expect(url, isNot(contains(' ')));
      expect(Uri.parse(url).queryParameters['text'],
          'Découvrez Boutique Awa : https://x/s/a');
    });
  });

  group('the shelf filter', () {
    late LocalDb db;

    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });

    tearDown(() => db.close());

    Future<void> pumpShop(WidgetTester tester, {int count = 8}) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: StorefrontScreen(
          slug: 'boutique-awa',
          storefront: _OneShop(count),
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
      // The basket restore reads the real (async) device database, which
      // only advances in real time — alternate, the routing tests' way.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      // Let the entrance settle so every tile is fully placed.
      await tester.pump(const Duration(milliseconds: 800));
    }

    testWidgets('typing narrows the shelf, accent-blind, with a true count',
        (tester) async {
      await pumpShop(tester);
      expect(find.text('8 articles'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Chercher dans la boutique…'),
          'cafe');
      await tester.pump();
      expect(find.text('Café Touba'), findsOneWidget);
      expect(find.text('Savon n°1'), findsNothing);
      expect(find.text('1 sur 8'), findsOneWidget);
    });

    testWidgets('a shelf nobody stocks that way says so, and clears back',
        (tester) async {
      await pumpShop(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Chercher dans la boutique…'),
          'ordinateur');
      await tester.pump();
      expect(
        find.text(
            'Aucun article ne répond à « ordinateur » dans cette boutique.'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Effacer'));
      await tester.pump();
      expect(find.text('8 articles'), findsOneWidget);
      expect(find.text('Café Touba'), findsOneWidget);
    });

    testWidgets('a short shelf gets no filter — six articles is browsing',
        (tester) async {
      await pumpShop(tester, count: 5);
      expect(find.text('Chercher dans la boutique…'), findsNothing);
      expect(find.text('5 articles'), findsOneWidget);
    });

    testWidgets('the shop can always be passed along', (tester) async {
      await pumpShop(tester, count: 5);
      expect(find.text('Partager'), findsOneWidget);
    });

    testWidgets('the basket survives leaving and coming back',
        (tester) async {
      await pumpShop(tester, count: 5);
      expect(find.text('Commander'), findsNothing);

      // One savon in the basket: the bar appears, and the device remembers.
      await tester.tap(find.text('Savon n°1'));
      await tester.pump();
      expect(find.text('Commander'), findsOneWidget);
      // Let the write land on the real (async) database.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));

      // A refresh, a sign-in round-trip: a brand-new screen, same device.
      await tester.pumpWidget(const SizedBox());
      await pumpShop(tester, count: 5);
      expect(find.text('Commander'), findsOneWidget);
    });
  });
}
