import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/nav/business_cover.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/home/business_frame.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The owner's question (108): « Do I still have this bar when I open
/// articles or commandes or facture or any other feature? » — yes: one
/// frame around every page of the business, the place on screen selected,
/// a tap switches tool, back from a tool returns to the home, a sheet still
/// covers the bar, a deep link lands with its bar. For the shop, the farm
/// and the association alike.
class _Shop extends RetailRepository {
  _Shop(super.client);

  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();

  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) async => const [];

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [];

  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) async => 0;

  @override
  Future<int> pendingOrders(String orgId) async => 2;
}

const _shop = OrgSummary(
  id: 'org-1',
  name: 'Boutique Awa',
  slug: 'boutique-awa',
  profile: 'retail',
  roles: ['owner'],
  currency: 'XOF',
);
const _farm = OrgSummary(id: 'farm-1', name: 'Ferme Ignace', profile: 'farm', roles: ['owner']);
const _asso = OrgSummary(id: 'asso-1', name: 'Entraide', profile: 'association', roles: ['owner']);

/// A tool's page: its name in its own app bar, and a sheet to open.
Widget _tool(String name) => Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text('Page $name')),
        body: Center(
          child: FilledButton(
            key: Key('sheet-$name'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const SizedBox(height: 200, child: Center(child: Text('La feuille'))),
            ),
            child: const Text('Ouvrir la feuille'),
          ),
        ),
      ),
    );

/// Whether the page « saisie » holds input not saved (A4).
bool _dirty = false;

GoRouter _router(Widget Function() home, OrgSummary org, {String? at}) {
  final cover = BusinessCover();
  return GoRouter(
      initialLocation: at ?? '/o/${org.id}',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('La rue'))),
        ShellRoute(
          observers: [cover],
          builder: (context, state, child) =>
              BusinessFrame(org: org, location: state.uri.path, cover: cover, child: child),
          routes: [
            GoRoute(
              path: '/o/:orgId',
              builder: (_, _) => BusinessPage(child: home()),
              routes: [
                for (final r in const [
                  'produits', 'commandes', 'factures', 'compte', 'administration', 'equipe',
                  'stock', 'bandes', 'a-vendre', 'services', 'chemin', 'credits', 'production',
                  'photos', 'journal', 'rapports', 'notifications',
                ])
                  GoRoute(
                    path: r,
                    builder: (_, _) => BusinessPage(child: _tool(r)),
                    routes: [
                      GoRoute(path: ':id', builder: (_, s) => BusinessPage(child: _tool('$r ${s.pathParameters['id']}'))),
                    ],
                  ),
                // A page with input (a new invoice, a rubrique of the
                // settings): unsaved while [_dirty].
                GoRoute(
                  path: 'saisie',
                  builder: (_, _) =>
                      BusinessPage(child: UnsavedInput(isDirty: () => _dirty, child: _tool('saisie'))),
                ),
              ],
            ),
          ],
        ),
      ],
    );
}

Widget _app(GoRouter router) => MaterialApp.router(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      routerConfig: router,
    );

Future<void> _size(WidgetTester tester, double width, [double height = 844]) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

List<String> _labels(WidgetTester tester) => tester
    .widgetList<NavigationDestination>(find.byType(NavigationDestination))
    .map((d) => d.label)
    .toList();

String _selected(WidgetTester tester) {
  final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
  return _labels(tester)[bar.selectedIndex];
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  late SupabaseClient client;

  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
    client = SupabaseClient('https://example.supabase.co', 'sb_publishable_test');
  });

  tearDown(() async {
    await client.dispose();
    await db.close();
  });

  Widget shopHome() => StoreHomeScreen(
        org: _shop,
        retail: _Shop(client),
        invoicing: InvoicingRepository(client),
      );

  group('the shop', () {
    testWidgets('the bar stays on every tool, its place selected; a tap switches; back returns home',
        (tester) async {
      await _size(tester, 390);
      final router = _router(shopHome, _shop);
      await tester.pumpWidget(_app(router));
      await _settle(tester);

      expect(_labels(tester), ['Vente', 'Articles', 'Commandes', 'Factures', 'Plus']);
      expect(_selected(tester), 'Vente');
      // One bar: the home draws none of its own inside the frame.
      expect(find.byType(NavigationBar), findsOneWidget);

      await tester.tap(find.text('Articles'));
      await _settle(tester);
      expect(find.text('Page produits'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(_selected(tester), 'Articles');
      // The orders waiting still ride on Commandes, on another page.
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('2')),
          findsOneWidget);

      // Commandes from Articles: a switch, not a pile.
      await tester.tap(find.text('Commandes').last);
      await _settle(tester);
      expect(find.text('Page commandes'), findsOneWidget);
      expect(_selected(tester), 'Commandes');

      // Android's back: the home, and not out of the app.
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.text('Page commandes'), findsNothing);
      expect(router.state.uri.path, '/o/org-1');
      expect(_selected(tester), 'Vente');
    });

    testWidgets('a page from Plus is Plus\'s; Plus lists Administration; the home is underneath',
        (tester) async {
      await _size(tester, 390, 1400);
      final router = _router(shopHome, _shop);
      await tester.pumpWidget(_app(router));
      await _settle(tester);

      await tester.tap(find.text('Plus'));
      await _settle(tester);
      expect(find.widgetWithText(ListTile, 'Administration'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Administration'));
      await _settle(tester);
      expect(find.text('Page administration'), findsOneWidget);
      expect(_selected(tester), 'Plus');

      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(router.state.uri.path, '/o/org-1');
    });

    testWidgets('a deep link lands with its bar, the tool selected, the home under it',
        (tester) async {
      await _size(tester, 390);
      final router = _router(shopHome, _shop, at: '/o/org-1/factures/F-12');
      await tester.pumpWidget(_app(router));
      await _settle(tester);
      expect(find.text('Page factures F-12'), findsOneWidget);
      expect(_selected(tester), 'Factures');

      // Factures again, from an invoice: the place already selected —
      // nothing (A4), the invoice stays.
      await tester.tap(find.text('Factures'));
      await _settle(tester);
      expect(router.state.uri.path, '/o/org-1/factures/F-12');
      expect(find.text('Page factures F-12'), findsOneWidget);

      // Back walks the link's own stack: the list of invoices, then home.
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(router.state.uri.path, '/o/org-1/factures');
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(router.state.uri.path, '/o/org-1');
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('a sheet still covers the bar, to the foot of the screen', (tester) async {
      await _size(tester, 390);
      await tester.pumpWidget(_app(_router(shopHome, _shop, at: '/o/org-1/produits')));
      await _settle(tester);
      // The page stands above the bar, not under it.
      final bar = tester.getRect(find.byType(NavigationBar));
      expect(tester.getRect(find.byType(Scaffold).last).bottom, lessThanOrEqualTo(bar.top + 0.5));

      await tester.tap(find.byKey(const Key('sheet-produits')));
      await _settle(tester);
      expect(find.text('La feuille'), findsOneWidget);
      expect(tester.getRect(find.byType(BottomSheet)).bottom, 844);
      // A tap where the bar is closes the sheet; it does not change tool.
      await tester.tapAt(Offset(bar.center.dx, 300));
      await _settle(tester);
      expect(find.text('La feuille'), findsNothing);
      expect(find.text('Page produits'), findsOneWidget);
    });

    testWidgets('input not saved: the bar asks « Quitter sans enregistrer ? » — Rester stays, Quitter goes',
        (tester) async {
      await _size(tester, 390, 1400);
      _dirty = true;
      addTearDown(() => _dirty = false);
      final router = _router(shopHome, _shop, at: '/o/org-1/saisie');
      await tester.pumpWidget(_app(router));
      await _settle(tester);
      expect(find.text('Page saisie'), findsOneWidget);

      await tester.tap(find.text('Articles'));
      await _settle(tester);
      expect(find.text('Quitter sans enregistrer ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('unsaved-stay')));
      await _settle(tester);
      expect(router.state.uri.path, '/o/org-1/saisie');
      expect(find.text('Page saisie'), findsOneWidget);

      // From Plus too.
      await tester.tap(find.text('Plus'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Administration'));
      await _settle(tester);
      expect(find.text('Quitter sans enregistrer ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('unsaved-stay')));
      await _settle(tester);
      expect(router.state.uri.path, '/o/org-1/saisie');

      await tester.tap(find.text('Articles'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('unsaved-leave')));
      await _settle(tester);
      expect(find.text('Page produits'), findsOneWidget);

      // Nothing typed: no question.
      _dirty = false;
      router.go('/o/org-1/saisie');
      await _settle(tester);
      await tester.tap(find.text('Commandes'));
      await _settle(tester);
      expect(find.text('Quitter sans enregistrer ?'), findsNothing);
      expect(find.text('Page commandes'), findsOneWidget);
    });

    testWidgets('a page that is no place selects none; Plus opens in the business\'s colours',
        (tester) async {
      await _size(tester, 390, 1400);
      final router = _router(shopHome, _shop, at: '/o/org-1/notifications');
      await tester.pumpWidget(_app(router));
      await _settle(tester);
      expect(find.text('Page notifications'), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.indicatorColor, Colors.transparent, reason: 'no place shown selected');
      final first = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).first;
      expect((first.selectedIcon as dynamic).toString(), (first.icon as dynamic).toString());
      // A place's page: its indicator back.
      router.go('/o/org-1/produits');
      await _settle(tester);
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).indicatorColor, isNull);
      expect(_selected(tester), 'Articles');

      await tester.tap(find.text('Plus'));
      await _settle(tester);
      final business = Theme.of(tester.element(find.byType(NavigationBar))).colorScheme.primary;
      final sheet = Theme.of(tester.element(find.byType(BottomSheet))).colorScheme.primary;
      final app = Theme.of(tester.element(find.byType(Navigator).first)).colorScheme.primary;
      expect(sheet, business);
      expect(business, isNot(app), reason: 'the business has colours of its own');
    });

    testWidgets('on a computer the rail stands at the left of every page', (tester) async {
      await _size(tester, 1280, 800);
      await tester.pumpWidget(_app(_router(shopHome, _shop, at: '/o/org-1/commandes')));
      await _settle(tester);
      expect(find.byType(NavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 2);
      // A page that is no place: the rail selects none.
      GoRouter.of(tester.element(find.text('Page commandes'))).go('/o/org-1/notifications');
      await _settle(tester);
      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, isNull);
      GoRouter.of(tester.element(find.text('Page notifications'))).go('/o/org-1/commandes');
      await _settle(tester);
      expect(find.text('Page commandes'), findsOneWidget);
      // The page beside the rail, not under it.
      expect(tester.getRect(find.byType(Scaffold).last).left,
          greaterThanOrEqualTo(tester.getRect(find.byType(NavigationRail)).right));
    });
  });

  testWidgets('the farm: its bar on Stock, Bandes, Factures and the rest', (tester) async {
    await _size(tester, 390, 1400);
    final router = _router(
        () => FarmHomeScreen(db: db, org: _farm, invoicing: InvoicingRepository(client)), _farm);
    await tester.pumpWidget(_app(router));
    await _settle(tester);
    expect(_labels(tester), ['Accueil', 'Stock', 'Bandes', 'Factures', 'Plus']);
    await tester.tap(find.text('Bandes'));
    await _settle(tester);
    expect(find.text('Page bandes'), findsOneWidget);
    expect(_selected(tester), 'Bandes');
    await tester.tap(find.text('Plus'));
    await _settle(tester);
    expect(find.widgetWithText(ListTile, 'Administration'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'À vendre'));
    await _settle(tester);
    expect(find.text('Page a-vendre'), findsOneWidget);
    expect(_selected(tester), 'Plus');
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(router.state.uri.path, '/o/farm-1');
  });

  testWidgets('the association: its bar on Rapports, Factures and the rest', (tester) async {
    await _size(tester, 390, 1400);
    final router = _router(
        () => ChurchHomeScreen(
              db: db,
              orgId: _asso.id,
              orgName: _asso.name,
              org: _asso,
              invoicing: InvoicingRepository(client),
            ),
        _asso);
    await tester.pumpWidget(_app(router));
    await _settle(tester);
    expect(_labels(tester), ['Accueil', 'Factures', 'Plus']);
    await tester.tap(find.text('Factures'));
    await _settle(tester);
    expect(find.text('Page factures'), findsOneWidget);
    expect(_selected(tester), 'Factures');
    await tester.tap(find.text('Plus'));
    await _settle(tester);
    expect(find.widgetWithText(ListTile, 'Administration'), findsOneWidget);
  });

  testWidgets('no places yet (the first setup holds the home): no bar, the page is the screen',
      (tester) async {
    await _size(tester, 390);
    await tester.pumpWidget(_app(_router(() => const Scaffold(body: Text('Mise en route')), _shop,
        at: '/o/org-1/produits')));
    await _settle(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.getRect(find.byType(Scaffold).last).bottom, 844);
  });

  test('every page of a business is in the frame of the real router', () async {
    final db = await LocalDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    final router = buildRouter(SessionController(
      db: db,
      auth: AuthRepository(null),
      admin: AdminRepository(null),
      accounting: AccountingRepository(null),
    ));
    for (final path in [
      '/o/o1', '/o/o1/produits', '/o/o1/commandes', '/o/o1/factures', '/o/o1/factures/f1',
      '/o/o1/administration', '/o/o1/administration/parametres', '/o/o1/stock',
      '/o/o1/bandes', '/o/o1/rapports/semaine', '/o/o1/compte', '/o/o1/chemin',
    ]) {
      final match = router.configuration.findMatch(Uri.parse(path));
      expect(match.isEmpty, isFalse, reason: path);
      expect(match.matches.first.route, isA<ShellRoute>(), reason: '$path is in the frame');
    }
    // The street, sign-in and the center are not.
    for (final path in ['/vitrines', '/s/awa', Routes.signIn, Routes.picker]) {
      final match = router.configuration.findMatch(Uri.parse(path));
      expect(match.matches.first.route, isNot(isA<ShellRoute>()), reason: path);
    }
  });
}
