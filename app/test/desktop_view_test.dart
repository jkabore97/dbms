// The desktop view (160b): the app takes the whole window — no 1120-pixel
// column with paper either side; the street's grid widens to six vitrines a
// row on a monitor; a business's page stands at a reading width.
// DESKTOP_SHOTS=<dir> also writes screenshots.
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/storefront/directory_screen.dart';
import 'package:kaj_app/features/storefront/shop_style.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Shops extends StorefrontRepository {
  _Shops() : super(null);
  static const names = ['Apiculteur du Faso', 'Bic & Cie', 'Marché Vert', 'Baguettes Music', 'Jeanny Fashion',
    'Bling Bling', 'Agroalimentaire', 'Yalagré Élégance', 'Dev Studio', 'Chez Fatou', 'Le Café', 'Poulet Braisé'];
  @override
  bool get isConfigured => true;
  @override
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) async => [
        for (var i = 0; i < names.length; i++)
          DirectoryEntry(orgId: 'o$i', name: names[i], slug: 's$i', profile: 'retail'),
      ];
  @override
  Future<PublicShop?> shop(String slug) async => const PublicShop(orgId: 'o1', name: 'Boutique Awa', slug: 'boutique-awa', profile: 'retail', phone: '+22670000000',
      style: StorefrontStyle(coverKey: 'orgs/o1/cover.jpg'));
  @override
  Future<List<PublicItem>> items(String slug) async => [
        for (var i = 0; i < 14; i++) PublicItem(id: 'p$i', name: 'Article $i', price: 1000 + i * 250, inStock: true),
      ];
  @override
  Future<List<FeaturedItem>> featured({double? lat, double? lng}) async => const [];
  @override
  Future<Map<String, List<ShopPreview>>> previews(List<String> slugs) async => {
        for (final s in slugs) s: [ShopPreview(slug: s, productId: 'p$s', name: 'Article', price: 1500)],
      };
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  late LocalDb db;
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Size size, {bool vitrine = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => KajBackground(palette: kajPalette, child: child!),
      home: RepaintBoundary(
        key: const Key('screen'),
        child: vitrine
            ? StorefrontScreen(
                slug: 'boutique-awa',
                storefront: _Shops(),
                capture: CaptureRepository(null, db: db),
                session: SessionController(db: db, auth: AuthRepository(null), admin: AdminRepository(null), accounting: AccountingRepository(null)),
              )
            : DirectoryScreen(
                storefront: _Shops(),
                capture: CaptureRepository(null, db: db),
                session: SessionController(db: db, auth: AuthRepository(null), admin: AdminRepository(null), accounting: AccountingRepository(null)),
              ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  test('the street\'s columns follow the window: two on a phone, six on a monitor', () {
    expect([390, 700, 1000, 1300, 1920].map((w) => ShopStyle.columnsFor(w.toDouble())), [2, 3, 4, 5, 6]);
  });

  for (final size in const [Size(1920, 1080), Size(1366, 768), Size(390, 844)]) {
    testWidgets('the street at ${size.width.toInt()} px: the whole window, its header across it', (tester) async {
      await pump(tester, size);
      expect(tester.takeException(), isNull);
      final page = tester.getSize(find.byType(DirectoryScreen));
      expect(page.width, size.width, reason: 'no column with paper either side');
      final shots = Platform.environment['DESKTOP_SHOTS'];
      if (shots != null) {
        Directory(shots).createSync(recursive: true);
        await tester.runAsync(() async {
          final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('screen')));
          final img = await ro.toImage(pixelRatio: 1);
          final data = await img.toByteData(format: ImageByteFormat.png);
          File('$shots/street_${size.width.toInt()}.png').writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
    });
  }

  for (final size in const [Size(1920, 1080), Size(390, 844)]) {
    testWidgets('a vitrine at ${size.width.toInt()} px: the whole window', (tester) async {
      await pump(tester, size, vitrine: true);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(StorefrontScreen)).width, size.width);
      expect(find.byKey(const Key('shop-cover-side')), size.width >= 1100 ? findsOneWidget : findsNothing,
          reason: 'on a monitor the cover stands beside the band, on a phone above it');
      final shots = Platform.environment['DESKTOP_SHOTS'];
      if (shots != null) {
        Directory(shots).createSync(recursive: true);
        await tester.runAsync(() async {
          final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('screen')));
          final img = await ro.toImage(pixelRatio: 1);
          final data = await img.toByteData(format: ImageByteFormat.png);
          File('$shots/vitrine_${size.width.toInt()}.png').writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
    });
  }
}
