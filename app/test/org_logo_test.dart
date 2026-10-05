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

/// A shop's own logo (080): storefront() sends it inside the style for
/// every plan, it is no Pro dressing, and the window shows it beside the
/// name — only when there is one.
class _OneShop extends StorefrontRepository {
  _OneShop(this.style) : super(null);

  final StorefrontStyle style;

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => PublicShop(
    orgId: 'o1',
    name: 'Shop Style',
    slug: 'style',
    profile: 'retail',
    style: style,
  );

  @override
  Future<List<PublicItem>> items(String slug) async => const [
    PublicItem(id: 'p1', name: 'Gateau', price: 200, inStock: true),
  ];
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('the logo is read for a Free shop, and is no Pro dressing', () {
    final style = StorefrontStyle.fromJson({'logo_key': 'org/o1/logo.png'});
    expect(style.logoKey, 'org/o1/logo.png');
    expect(
      style.isEmpty,
      isTrue,
      reason: 'a Free shop with a logo still wears the common design',
    );
    expect(
      style.toJson(),
      isEmpty,
      reason: 'set_org_logo() sets it, never set_storefront_style()',
    );
  });

  group('the window', () {
    late LocalDb db;
    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    Future<void> pump(WidgetTester tester, StorefrontStyle style) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: StorefrontScreen(
            slug: 'style',
            storefront: _OneShop(style),
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

    testWidgets('shows the logo beside the name', (tester) async {
      await pump(tester, const StorefrontStyle(logoKey: 'org/o1/logo.png'));
      expect(find.byKey(const Key('shop-logo')), findsOneWidget);
      final logo = tester.getCenter(find.byKey(const Key('shop-logo')));
      final name = tester.getCenter(find.text('Shop Style').first);
      expect(logo.dx < name.dx, isTrue, reason: 'the logo leads the name');
    });

    testWidgets('no logo, no empty square', (tester) async {
      await pump(tester, StorefrontStyle.none);
      expect(find.byKey(const Key('shop-logo')), findsNothing);
      expect(find.text('Shop Style'), findsWidgets);
    });
  });
}
