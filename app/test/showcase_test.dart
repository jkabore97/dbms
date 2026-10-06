import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/showcase_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The vitrines d'exemple (094): their photos come from the site, the
/// window says « Pas à proximité » and refuses the order before any
/// sign-in, and the console lists them and hides one.
class _Shop extends StorefrontRepository {
  _Shop({this.showcase = true}) : super(null);

  final bool showcase;

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => const PublicShop(
    orgId: 'o1',
    name: 'Tony Pizza',
    slug: 'tony-pizza',
    profile: 'retail',
  );

  @override
  Future<List<PublicItem>> items(String slug) async => const [
    PublicItem(id: 'p0', name: 'Coca', price: 500, inStock: true),
    PublicItem(
      id: 'p1',
      name: 'Pizza pepperoni',
      price: 6500,
      inStock: true,
      photoKey: 'showcase/tony-pizza/pizza-pepperoni.jpg',
    ),
  ];

  @override
  Future<Set<String>> showcaseSlugs() async =>
      showcase ? {'tony-pizza'} : const {};
}

class _Admin extends AdminRepository {
  _Admin() : super(null);

  final visible = <String, bool>{};

  @override
  Future<List<Showcase>> showcases() async => [
    Showcase(
      orgId: 'o1',
      name: 'Tony Pizza',
      slug: 'tony-pizza',
      items: 14,
      photos: 14,
      visible: visible['o1'] ?? true,
    ),
    const Showcase(
      orgId: 'o2',
      name: 'Bob Electronics',
      slug: 'bob-electronics',
      items: 13,
    ),
  ];

  @override
  Future<void> setShowcaseVisible(String orgId, bool on) async =>
      visible[orgId] = on;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'a showcase photo is read from the site, not the uploads Worker',
    () async {
      expect(
        CaptureRepository.isShowcaseKey('showcase/tony-pizza/a.jpg'),
        isTrue,
      );
      expect(CaptureRepository.isShowcaseKey('org/o1/a.jpg'), isFalse);
      expect(
        CaptureRepository.showcaseUrl(
          'showcase/tony-pizza/a.jpg',
          base: Uri.parse('https://dbms.kabore-boss.workers.dev/s/x'),
        ).toString(),
        'https://dbms.kabore-boss.workers.dev/showcase/tony-pizza/a.jpg',
      );
      expect(
        CaptureRepository.showcaseUrl(
          'showcase/a/b.jpg',
          base: Uri.parse('file:///app'),
        ).toString(),
        'https://marakaj.com/showcase/a/b.jpg',
      );

      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      final asked = <Uri>[];
      final capture = CaptureRepository(
        null,
        db: db,
        httpClient: MockClient((request) async {
          asked.add(request.url);
          return http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
        }),
      );
      final bytes = await capture.publicObjectBytes(
        'showcase/tony-pizza/a.jpg',
      );
      expect(bytes, [1, 2, 3]);
      // No token, no uploads address, and still a photo.
      expect(await capture.objectBytes('showcase/tony-pizza/a.jpg'), [1, 2, 3]);
      expect(asked.single.path, '/showcase/tony-pizza/a.jpg');
    },
  );

  group('the window', () {
    late LocalDb db;
    setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
    tearDown(() => db.close());

    Future<void> open(WidgetTester tester, _Shop shop) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: StorefrontScreen(
            slug: 'tony-pizza',
            storefront: shop,
            capture: CaptureRepository(null, db: db),
            session: SessionController(
              db: db,
              auth: AuthRepository(null),
              admin: AdminRepository(null),
              accounting: AccountingRepository(null),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 800));
    }

    testWidgets('says « Pas à proximité » and refuses the order', (
      tester,
    ) async {
      await open(tester, _Shop());
      expect(find.byKey(const Key('shop-far')), findsOneWidget);
      // The photographed article first, though it came second (095).
      expect(
          tester.getTopLeft(find.text('Pizza pepperoni').last).dx <
              tester.getTopLeft(find.text('Coca').last).dx,
          isTrue);
      await tester.tap(
        find.bySemanticsLabel('Ajouter un Pizza pepperoni au panier'),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Commander').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('showcase-far')), findsOneWidget);
      expect(find.textContaining('vitrine d\'exemple'), findsOneWidget);
    });

    testWidgets('a real shop has no such badge', (tester) async {
      await open(tester, _Shop(showcase: false));
      expect(find.byKey(const Key('shop-far')), findsNothing);
    });
  });

  testWidgets('the console lists them and hides one', (tester) async {
    final admin = _Admin();
    await tester.pumpWidget(MaterialApp(home: ShowcaseScreen(admin: admin)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Tony Pizza'), findsOneWidget);
    expect(find.text('Bob Electronics'), findsOneWidget);
    expect(find.textContaining('14 articles · 14 avec photo'), findsOneWidget);
    // Fewer than seven: the button to make the missing ones.
    expect(find.byKey(const Key('showcase-seed')), findsOneWidget);
    await tester.tap(find.byKey(const Key('showcase-visible-tony-pizza')));
    await tester.pump();
    await tester.pump();
    expect(admin.visible['o1'], isFalse);
  });
}
