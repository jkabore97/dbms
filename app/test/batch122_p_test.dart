import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/analytics/analytics_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/credit/credit_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/l10n/locale_controller.dart';
import 'package:kaj_app/core/nav/app_scope.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/orders/orders.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/shopper/shopper_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/theme/scroll_hint.dart';
import 'package:kaj_app/core/tontine/tontine_repository.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/home/home_nav.dart';
import 'package:kaj_app/features/orders/my_orders_screen.dart';
import 'package:kaj_app/features/retail/sale_flow.dart';
import 'package:kaj_app/features/shopper/shopper_profile_screen.dart';
import 'package:kaj_app/features/storefront/directory_screen.dart';
import 'package:kaj_app/features/storefront/shop_style.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/// Batch 122, builder P — the owner's words:
///  P1 « The footer is really a footer at the bottom everywhere. »
///  P3 « an animated arrow showing the list continues at the bottom …
///     Make sure it disappears when the bottom is reached. »
///  P4 « In vente, display the article's picture if there is any. »
/// (P2, the back, is test/batch122_p_back_test.dart.)

const _awa = User(
  id: 'awa-1',
  appMetadata: {'provider': 'google'},
  userMetadata: {'full_name': 'Awa Ouédraogo'},
  aud: 'authenticated',
  email: 'awa@example.com',
  createdAt: '2026-10-08T00:00:00Z',
);

class _Server extends AuthRepository {
  _Server() : super(null);
  @override
  bool get isConfigured => true;
  @override
  bool get hasLiveSession => true;
  @override
  User? get currentUser => _awa;
  @override
  Future<List<OrgSummary>> fetchOrgs() async => const [];
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<bool> isPlatformAdmin() async => false;
  @override
  Future<int> claimMyInvitations() async => 0;
  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;
}

class _Shopper extends ShopperRepository {
  _Shopper() : super(null);
  @override
  bool get isConfigured => true;
  @override
  String? get picture => null;
  @override
  Future<ShopperProfile> profile() async =>
      const ShopperProfile(name: 'Awa Ouédraogo', phone: '+22670113005', follows: 2, ordersOpen: 0);
  @override
  Future<List<FollowedVitrine>> follows() async => const [];
}

class _Orders extends StorefrontRepository {
  _Orders(this.orders) : super(null);
  final List<CustomerOrder> orders;
  @override
  bool get isConfigured => true;
  @override
  Future<List<CustomerOrder>> myOrders() async => orders;
}

class _Street extends StorefrontRepository {
  _Street(this.entries) : super(null);
  final List<DirectoryEntry> entries;
  @override
  bool get isConfigured => true;
  @override
  Future<KeptStreet?> keptStreet() async => null;
  @override
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) async => entries;
  @override
  Future<List<FeaturedItem>> featured() async => const [];
  @override
  Future<Set<String>> spotlights() async => const {};
  @override
  Future<Set<String>> showcaseSlugs() async => const {};
  @override
  Future<Map<String, List<ShopPreview>>> previews(List<String> slugs) async => const {};
  @override
  Future<void> recordSeen(List<String> productIds) async {}
}

CustomerOrder _order(String id) => CustomerOrder(
      id: id,
      shopName: 'Boutique Awa',
      shopSlug: 'boutique-awa',
      status: 'picked_up',
      fulfilment: 'pickup',
      total: 1000,
      currency: 'XOF',
      createdAt: DateTime(2026, 10, 1, 10),
      lines: const [OrderLine(name: 'Savon', unitPrice: 500, quantity: 2)],
    );

/// A 1 × 1 PNG: an article's photograph as the uploads Worker sends it.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _Photos extends CaptureRepository {
  _Photos(LocalDb db, {this.offline = false}) : super(null, db: db);
  final bool offline;
  final asked = <String>[];
  @override
  bool get isConfigured => true;
  @override
  Future<Uint8List> objectBytes(String key) async {
    asked.add(key);
    if (offline) throw const CaptureException('Pas de réseau');
    return _png;
  }
}

class _Till extends RetailRepository {
  _Till() : super(null);
  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {'p1': 'org-1/products/p1.jpg'};
  @override
  Future<String?> waveMerchant(String orgId) async => null;
  @override
  Future<Map<String, double>> freshStock(String orgId, List<String> ids) async => const {};
}

void _size(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Widget _material(Widget home, {bool reduced = false}) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      builder: (context, child) => reduced
          ? MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!)
          : child!,
      home: home,
    );

Widget _lines(int n, {ScrollController? controller, void Function(int)? onTap}) => ListView(
      controller: controller,
      children: [
        for (var i = 0; i < n; i++)
          ListTile(key: ValueKey('line-$i'), title: Text('Ligne $i'), onTap: () => onTap?.call(i)),
      ],
    );

final _hint = find.byKey(const Key('scroll-hint'));

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  Future<SessionController> shopper(WidgetTester tester) async {
    final s = SessionController(db: db, auth: _Server(), admin: _Admin(), accounting: AccountingRepository(null));
    await tester.runAsync(s.resolveOrgs);
    return s;
  }

  /// The app's scope around a little router at [at], as batch 113's tests.
  Future<GoRouter> pump(WidgetTester tester, SessionController session,
      {required String at, required List<RouteBase> routes}) async {
    final stub = [
      for (final p in [Routes.myOrders, Routes.becomeCourier, Routes.directory, Routes.shopperProfile, '/s/:slug'])
        if (!routes.any((r) => r is GoRoute && r.path == p))
          GoRoute(path: p, builder: (_, state) => Scaffold(body: Text('page ${state.uri}'))),
    ];
    final router = GoRouter(initialLocation: at, routes: [...routes, ...stub]);
    await tester.pumpWidget(AppScope(
      session: session,
      localeController: LocaleController(db),
      db: db,
      auth: session.auth,
      admin: session.admin,
      reports: ReportsRepository(null),
      accounting: AccountingRepository(null),
      console: ConsoleRepository(null),
      farm: FarmRepository(null),
      invoicing: InvoicingRepository(null),
      retail: RetailRepository(null),
      staff: StaffRepository(null),
      capture: CaptureRepository(null, db: db),
      onboarding: OnboardingRepository(null),
      credit: CreditRepository(null),
      tontine: TontineRepository(null),
      production: ProductionRepository(null),
      notify: NotificationsRepository(null),
      analytics: AnalyticsRepository(null),
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
      ),
    ));
    await _settle(tester);
    return router;
  }

  Future<void> toTheEnd(WidgetTester tester) async {
    final scroll = find.byType(Scrollable).first;
    for (var i = 0; i < 30; i++) {
      await tester.drag(scroll, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _settle(tester);
  }

  group('P1 — the footer is at the foot of the page', () {
    testWidgets('« Mes commandes » with one order (390 × 844): the footer\'s bottom is the page\'s bottom',
        (tester) async {
      _size(tester);
      await pump(tester, await shopper(tester), at: Routes.myOrders, routes: [
        GoRoute(path: Routes.myOrders, builder: (_, _) => MyOrdersScreen(storefront: _Orders([_order('o1')]))),
      ]);
      expect(find.text('2 × Savon'), findsOneWidget);
      final footer = tester.getRect(find.byType(ShopFooter));
      expect(footer.bottom, 844, reason: 'the footer sits on the bottom edge, nothing white under it');
      final band = tester.getRect(find.byKey(const Key('shop-footer')));
      expect(band.bottom, 844 - 24, reason: 'the band, then its own small margin, then the edge');
      final card = tester.getRect(find.text('2 × Savon'));
      expect(band.top, greaterThan(card.bottom + 200), reason: 'the room is above the footer, not below it');
      expect(_hint, findsNothing, reason: 'everything fits: no arrow');
    });

    testWidgets('the street with no vitrine yet — its hero and map fill a 390 × 844 phone, so on a taller '
        'phone (390 × 1400) and a computer (1280 × 1000): the footer\'s bottom is the page\'s bottom',
        (tester) async {
      final session = await shopper(tester);
      for (final size in const [Size(390, 1400), Size(1280, 1000)]) {
        _size(tester, size);
        await pump(tester, session, at: Routes.directory, routes: [
          GoRoute(
            path: Routes.directory,
            builder: (_, _) => DirectoryScreen(
                storefront: _Street(const []), capture: CaptureRepository(null, db: db), session: session),
          ),
        ]);
        expect(find.text('Aucune vitrine ouverte pour le moment.'), findsOneWidget);
        expect(tester.getRect(find.byType(ShopFooter)).bottom, size.height, reason: '$size');
        expect(tester.getRect(find.byKey(const Key('shop-footer'))).bottom, size.height - 24, reason: '$size');
        expect(find.byKey(const Key('footer-become-courier')), findsOneWidget);
      }
    });

    testWidgets('long pages: the footer comes after the content — twelve orders, and the street', (tester) async {
      _size(tester);
      final session = await shopper(tester);
      await pump(tester, session, at: Routes.myOrders, routes: [
        GoRoute(
          path: Routes.myOrders,
          builder: (_, _) => MyOrdersScreen(storefront: _Orders([for (var i = 0; i < 12; i++) _order('o$i')])),
        ),
      ]);
      expect(find.byType(ShopFooter), findsNothing, reason: 'below the fold while the orders fill the screen');
      expect(_hint, findsOneWidget, reason: 'and the arrow says there is more');
      await toTheEnd(tester);
      final footer = tester.getRect(find.byType(ShopFooter));
      final last = tester.getRect(find.text('2 × Savon').last);
      expect(footer.top, greaterThanOrEqualTo(last.bottom), reason: 'after the last order');
      final pos = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(pos.pixels, pos.maxScrollExtent);
      expect(footer.bottom, closeTo(844, 0.5));
      expect(_hint, findsNothing, reason: 'the end is reached: the arrow is gone');

      await pump(tester, session, at: Routes.directory, routes: [
        GoRoute(
          path: Routes.directory,
          builder: (_, _) => DirectoryScreen(
            storefront: _Street([
              for (var i = 0; i < 6; i++)
                DirectoryEntry(orgId: 'o$i', name: 'Boutique $i', slug: 'boutique-$i', profile: 'retail'),
            ]),
            capture: CaptureRepository(null, db: db),
            session: session,
          ),
        ),
      ]);
      expect(_hint, findsOneWidget);
      await toTheEnd(tester);
      expect(tester.getRect(find.byType(ShopFooter)).top,
          greaterThanOrEqualTo(tester.getRect(find.text('Boutique 5')).bottom));
      expect(_hint, findsNothing);
    });

    testWidgets('« Mon compte » (pull to refresh kept): the footer after the sign-out button', (tester) async {
      _size(tester);
      await pump(tester, await shopper(tester), at: Routes.shopperProfile, routes: [
        GoRoute(path: Routes.shopperProfile, builder: (_, _) => ShopperProfileScreen(shopper: _Shopper())),
      ]);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      await toTheEnd(tester);
      expect(tester.getRect(find.byType(ShopFooter)).top,
          greaterThanOrEqualTo(tester.getRect(find.byKey(const Key('shopper-sign-out'))).bottom));
    });
  });

  group('P3 — the arrow that says the list goes on', () {
    testWidgets('shown while there is more below, gone at the bottom, back when scrolled up; never takes a tap',
        (tester) async {
      _size(tester);
      final tapped = <int>[];
      await tester.pumpWidget(_material(Scaffold(body: ScrollHint(child: _lines(40, onTap: tapped.add)))));
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget);
      expect(find.ancestor(of: _hint, matching: find.byType(IgnorePointer)), findsWidgets);
      final arrow = tester.getCenter(_hint);
      expect(arrow.dx, closeTo(195, 1), reason: 'bottom centre');
      expect(arrow.dy, greaterThan(844 - 60));
      // A tap on the arrow reaches the line under it.
      await tester.tapAt(arrow);
      await tester.pumpAndSettle();
      expect(tapped, hasLength(1));

      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(_hint, findsNothing, reason: 'the bottom is reached');

      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget, reason: 'more below again');
    });

    testWidgets('within 24 px of the end counts as the end; nothing at all when everything fits', (tester) async {
      _size(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_material(Scaffold(body: ScrollHint(child: _lines(40, controller: controller)))));
      await tester.pumpAndSettle();
      controller.jumpTo(controller.position.maxScrollExtent - 20);
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
      controller.jumpTo(controller.position.maxScrollExtent - 60);
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget);

      await tester.pumpWidget(_material(Scaffold(body: ScrollHint(child: _lines(3)))));
      await tester.pumpAndSettle();
      expect(_hint, findsNothing, reason: 'three lines fit');
    });

    testWidgets('it bounces, a few times only; held still for reduced motion', (tester) async {
      _size(tester);
      await tester.pumpWidget(_material(Scaffold(body: ScrollHint(child: _lines(40)))));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.descendant(of: _hint, matching: find.byType(Transform)), findsOneWidget);
      double drop() => tester
          .widget<Transform>(find.descendant(of: _hint, matching: find.byType(Transform)))
          .transform
          .getTranslation()
          .y;
      expect(drop(), 0);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      expect(drop(), greaterThan(2), reason: 'moving down and back');
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget, reason: 'the bounce ends; the arrow stays');

      await tester.pumpWidget(_material(Scaffold(body: ScrollHint(child: _lines(40))), reduced: true));
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget);
      expect(find.descendant(of: _hint, matching: find.byType(Transform)), findsNothing, reason: 'static arrow');
    });

    testWidgets('a page with a nested shrink-wrapped grid: the page\'s list speaks, not the grid', (tester) async {
      _size(tester);
      await tester.pumpWidget(_material(Scaffold(
        body: ScrollHint(
          child: ListView(children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [for (var i = 0; i < 4; i++) Text('Case $i')],
            ),
            for (var i = 0; i < 30; i++) ListTile(title: Text('Ligne $i')),
          ]),
        ),
      )));
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget);
    });

    testWidgets('a short page pushed over a long one under one wrapper: no arrow; back on the long one, the arrow',
        (tester) async {
      // A business's pages share one ScrollHint above their navigator
      // (business_frame): the long page stays mounted under the short one.
      _size(tester);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_material(Scaffold(
        body: ScrollHint(
          child: Navigator(
            key: nav,
            onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => Material(child: _lines(40))),
          ),
        ),
      )));
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget, reason: 'the long page');

      // A short page with no list at all: it sends no notification.
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Material(child: Column(children: [Text('Une ligne')]))));
      await tester.pumpAndSettle();
      expect(find.text('Une ligne'), findsOneWidget);
      expect(_hint, findsNothing, reason: 'the long page is under the short one');

      // A short page with a list that fits.
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget, reason: 'the long page is on top again');
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => Material(child: _lines(3))));
      await tester.pumpAndSettle();
      expect(_hint, findsNothing, reason: 'three lines fit; the long page below does not count');

      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget);
    });

    testWidgets('the Plus sheet: the arrow while tools are below, gone at the last one', (tester) async {
      _size(tester, const Size(390, 640));
      late BuildContext ctx;
      await tester.pumpWidget(_material(Builder(builder: (context) {
        ctx = context;
        return const Scaffold(body: SizedBox());
      })));
      HomeNav.showMore(ctx, [
        for (var i = 0; i < 14; i++) HomeDestination(icon: Icons.inventory_2_outlined, label: 'Outil $i', onTap: () {}),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Outil 0'), findsOneWidget);
      expect(_hint, findsOneWidget);
      final sheet = tester.getRect(find.byType(BottomSheet));
      expect(sheet.contains(tester.getCenter(_hint)), isTrue, reason: 'on the sheet, at its foot');
      await tester.drag(find.text('Outil 3'), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('Outil 13'), findsOneWidget);
      expect(_hint, findsNothing);

      Navigator.of(ctx).pop();
      await tester.pumpAndSettle();
      HomeNav.showMore(ctx, [
        for (var i = 0; i < 3; i++) HomeDestination(icon: Icons.inventory_2_outlined, label: 'Outil $i', onTap: () {}),
      ]);
      await tester.pumpAndSettle();
      expect(_hint, findsNothing, reason: 'three tools fit');
    });

    testWidgets('a step of a StepFlow that goes on below: one arrow (the step\'s), gone at the end', (tester) async {
      _size(tester, const Size(390, 640));
      await tester.pumpWidget(_material(StepFlow(
        title: 'Essai',
        store: MemoryFlowStore(),
        steps: [
          FlowStep(
              id: 'a',
              title: 'Une longue question',
              builder: (_) => Column(children: [for (var i = 0; i < 30; i++) Text('Choix $i')])),
        ],
        summary: (_) => const Text('Résumé'),
        onSave: () async => true,
        done: (_) => const Text('Fait'),
      )));
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget);
      await tester.drag(find.text('Choix 3'), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
    });
  });

  group('P4 — « Vente » shows the article\'s picture', () {
    Widget sale(CaptureRepository photos) => _material(SaleFlow(
          orgId: 'org-1',
          orgName: 'Boutique Awa',
          retail: _Till(),
          capture: photos,
          store: MemoryFlowStore(),
          products: const [
            Product(id: 'p1', name: 'Yaourt', salePrice: 350, quantity: 10),
            Product(id: 'p2', name: 'Sucre', salePrice: 900, quantity: 4),
          ],
        ));

    testWidgets('an article with a photo shows it (the Articles list\'s source); one without, as before; '
        'name, price and « Reste » still read', (tester) async {
      _size(tester);
      final photos = _Photos(db);
      await tester.pumpWidget(sale(photos));
      await _settle(tester);
      expect(find.byKey(const ValueKey('sale-photo-p1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('sale-photo-p1')), matching: find.byType(Image)),
          findsOneWidget);
      expect(photos.asked, ['org-1/products/p1.jpg']);
      expect(find.byKey(const ValueKey('sale-photo-p2')), findsNothing, reason: 'no photo: the tile as before');
      final tile = find.byKey(const ValueKey('sale-pick-p1'));
      expect(find.descendant(of: tile, matching: find.text('Yaourt')), findsOneWidget);
      expect(find.descendant(of: tile, matching: find.text('Reste : 10')), findsOneWidget);
      expect(find.descendant(of: tile, matching: find.textContaining('350')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow in the tile');
      // Still picked with a tap.
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.descendant(of: tile, matching: find.byIcon(Icons.check_circle)), findsOneWidget);
    });

    testWidgets('no signal: the letter on the tile, never a broken image', (tester) async {
      _size(tester);
      await tester.pumpWidget(sale(_Photos(db, offline: true)));
      await _settle(tester);
      final square = find.byKey(const ValueKey('sale-photo-p1'));
      expect(find.descendant(of: square, matching: find.byType(Image)), findsNothing);
      expect(find.descendant(of: square, matching: find.text('Y')), findsOneWidget);
    });
  });
}
