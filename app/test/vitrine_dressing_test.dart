import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/vitrine_plus_card.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Every vitrine dresses itself; Pro arranges it (093): the hours line is
/// written from the days, the street draws the chosen layout and the open
/// banner, and the preview follows the form.
class _OneShop extends StorefrontRepository {
  _OneShop(this.style) : super(null);

  final StorefrontStyle style;

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => PublicShop(
    orgId: 'o1',
    name: 'Maquis Awa',
    slug: 'maquis-awa',
    profile: 'retail',
    style: style,
  );

  @override
  Future<List<PublicItem>> items(String slug) async => const [
    PublicItem(id: 'p1', name: 'Riz gras', price: 1000, inStock: true),
    PublicItem(id: 'p2', name: 'Poulet braisé', price: 3500, inStock: true),
    PublicItem(id: 'p3', name: 'Bissap', price: 300, inStock: false),
  ];
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('the hours line', () {
    test('runs of days, single days and every day', () {
      const week = VitrineSchedule(
        days: [1, 2, 3, 4, 5, 6],
        open: '08:00',
        close: '19:00',
      );
      expect(week.label(), 'Lun–Sam 8h–19h');
      expect(week.label('en'), 'Mon–Sat 8:00–19:00');
      expect(
        const VitrineSchedule(
          days: [1, 3, 4, 5],
          open: '07:30',
          close: '18:00',
        ).label(),
        'Lun, Mer–Ven 7h30–18h',
      );
      expect(
        const VitrineSchedule(
          days: [6, 7],
          open: '18:00',
          close: '02:00',
        ).label(),
        'Sam, Dim 18h–2h',
      );
      expect(
        const VitrineSchedule(
          days: [1, 2, 3, 4, 5, 6, 7],
          open: '06:00',
          close: '22:00',
        ).label(),
        'Tous les jours 6h–22h',
      );
    });

    test('reads and writes what the server keeps; a bad one is nothing', () {
      final style = StorefrontStyle.fromJson({
        'layout': 'list',
        'schedule': {
          'days': [5, 1],
          'open': '08:00',
          'close': '12:00',
        },
        'open_now': true,
      });
      expect(style.layout, VitrineLayout.list);
      expect(style.schedule!.days, [1, 5]);
      expect(style.openNow, isTrue);
      expect(style.toJson()['layout'], 'list');
      expect(
        StorefrontStyle.fromJson({'layout': 'mosaic'}).layout,
        VitrineLayout.grid,
      );
      expect(
        StorefrontStyle.fromJson({
          'schedule': {'days': [], 'open': '08:00', 'close': '12:00'},
        }).schedule,
        isNull,
      );
      expect(StorefrontStyle.fromJson({'open_now': true}).isEmpty, isTrue);
    });
  });

  group('the street', () {
    late LocalDb db;

    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });

    tearDown(() => db.close());

    Future<void> open(WidgetTester tester, StorefrontStyle style) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: StorefrontScreen(
            slug: 'maquis-awa',
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

    testWidgets('a menu, its hours from the days, and « Ouvert maintenant »', (
      tester,
    ) async {
      await open(
        tester,
        const StorefrontStyle(
          layout: VitrineLayout.menu,
          schedule: VitrineSchedule(
            days: [1, 2, 3, 4, 5, 6],
            open: '11:00',
            close: '23:00',
          ),
          openNow: true,
        ),
      );
      expect(find.byKey(const Key('shelf-menu')), findsOneWidget);
      expect(find.text('Riz gras'), findsOneWidget);
      expect(find.text('Lun–Sam 11h–23h'), findsOneWidget);
      expect(find.text('Ouvert maintenant'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a list, and « Fermé »', (tester) async {
      await open(
        tester,
        const StorefrontStyle(layout: VitrineLayout.list, openNow: false),
      );
      expect(find.byKey(const Key('shelf-list')), findsOneWidget);
      expect(find.text('Fermé'), findsOneWidget);
      expect(find.text('Épuisé'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a Free window: the grid, no banner', (tester) async {
      await open(tester, const StorefrontStyle(tagline: 'Le goût du quartier'));
      expect(find.byKey(const Key('shelf-list')), findsNothing);
      expect(find.byKey(const Key('shelf-menu')), findsNothing);
      expect(find.byKey(const Key('shop-open')), findsNothing);
      expect(find.text('Le goût du quartier'), findsOneWidget);
    });
  });

  testWidgets('the preview follows the form', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget preview(StorefrontStyle style) => MaterialApp(
      home: Scaffold(
        body: VitrinePreview(
          name: 'Maquis Awa',
          style: style,
          items: const [
            Product(id: 'p1', name: 'Riz gras', salePrice: 1000),
            Product(id: 'p2', name: 'Bissap', salePrice: 300),
          ],
          openNow: true,
        ),
      ),
    );
    await tester.pumpWidget(
      preview(
        const StorefrontStyle(
          tagline: 'Le goût du quartier',
          layout: VitrineLayout.menu,
        ),
      ),
    );
    expect(find.byKey(const Key('preview-tagline')), findsOneWidget);
    expect(find.text('Ouvert maintenant'), findsOneWidget);
    expect(find.text('1000 F'), findsOneWidget);
    await tester.pumpWidget(
      preview(const StorefrontStyle(layout: VitrineLayout.list)),
    );
    expect(find.byKey(const Key('preview-tagline')), findsNothing);
    expect(find.byIcon(Icons.add_circle), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
