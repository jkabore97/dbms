import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaj_app/core/nav/back_first.dart';
import 'package:kaj_app/core/nav/parent_route.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/features/account/legal_screens.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Batch 122, builder P2 — the owner: « Every page has a return button and
/// clicking the back button returns to the previous page instead of
/// quitting the app. » Android's back from a page with nothing under it
/// (opened with `go`: the bar, a link, a ring) goes to its logical parent;
/// from a root it asks « Quitter Mara ? » once, never closing silently.
/// Back still closes what is open first (114).

/// A page: its name, and what Flutter or [parentBack] puts in its AppBar.
Widget _page(String name) => Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(leading: parentBack(context), title: Text('Page $name')),
        body: TextButton(
          key: const Key('open-sheet'),
          onPressed: () => showModalBottomSheet<void>(
              context: context, builder: (_) => const SizedBox(height: 120, child: Text('La feuille'))),
          child: const Text('Feuille'),
        ),
      ),
    );

/// The app's addresses as the router nests them (router.dart): the street,
/// a vitrine, the shopper's account and its pages, the courier's pages,
/// the picker, the legal pages, a business and its tools.
GoRouter _router(String at) => GoRouter(
      initialLocation: at,
      observers: [BackFirst.instance.watch()],
      routes: [
        GoRoute(path: Routes.directory, builder: (_, _) => _page('vitrines')),
        GoRoute(path: '/s/:slug', builder: (_, s) => _page('vitrine ${s.pathParameters['slug']}')),
        GoRoute(path: Routes.myOrders, builder: (_, _) => _page('commandes')),
        GoRoute(path: Routes.picker, builder: (_, _) => _page('entreprises')),
        GoRoute(path: Routes.privacy, builder: (_, _) => const PrivacyScreen()),
        GoRoute(path: Routes.language, builder: (_, _) => _page('langue')),
        GoRoute(
          path: Routes.shopperProfile,
          builder: (_, _) => _page('compte'),
          routes: [GoRoute(path: 'adresses', builder: (_, _) => _page('adresses'))],
        ),
        GoRoute(path: Routes.courier, builder: (_, _) => _page('livreur')),
        GoRoute(path: Routes.courierNotifications, builder: (_, _) => _page('livreur notifications')),
        GoRoute(path: '${Routes.courier}/course/:id', builder: (_, _) => _page('course')),
        ShellRoute(
          builder: (_, _, child) => child,
          routes: [
            GoRoute(
              path: '/o/:orgId',
              builder: (_, _) => _page('accueil'),
              routes: [
                GoRoute(
                  path: 'factures',
                  builder: (_, _) => _page('factures'),
                  routes: [GoRoute(path: ':invoiceId', builder: (_, _) => _page('facture'))],
                ),
                GoRoute(
                  path: 'administration',
                  builder: (_, _) => _page('administration'),
                  routes: [GoRoute(path: 'parametres', builder: (_, _) => _page('parametres'))],
                ),
                GoRoute(path: 'produits', builder: (_, _) => _page('produits')),
              ],
            ),
          ],
        ),
      ],
    );

class _Engine {
  _Engine(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') phonePops++;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  int phonePops = 0;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

/// Android's back.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

void main() {
  /// The app at [at], reached with `go`: nothing under it.
  Future<GoRouter> open(WidgetTester tester, String at, {int businesses = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = _router(Routes.directory);
    final back = BackFirst.instance;
    back.attach(router, businesses: () => businesses);
    addTearDown(() => back.detach(router));
    await tester.pumpWidget(MaterialApp.router(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      routerConfig: router,
      scaffoldMessengerKey: back.messenger,
      onNavigationNotification: back.onNavigationNotification,
    ));
    await _settle(tester);
    router.go(at);
    await _settle(tester);
    return router;
  }

  String path(GoRouter r) => r.state.uri.path;

  group('the parent of a page, from its address', () {
    final known = {
      '/vitrines', '/mon-compte', '/mon-compte/adresses', '/livreur', '/livreur/notifications', '/console',
      '/console/entreprises', '/console/livreurs', '/demandes', '/o/x', '/o/x/factures', '/o/x/administration',
      '/o/x/administration/parametres', '/o/x/rapports', '/o/x/rapports/semaine', '/entreprises',
    };
    String? parent(String at, {int businesses = 1}) =>
        parentRoute(at, exists: known.contains, businesses: businesses);

    test('a business\'s tools → the page above, up to the home; the home → the picker only with several', () {
      expect(parent('/o/x/factures/inv-9'), '/o/x/factures');
      expect(parent('/o/x/administration/parametres'), '/o/x/administration');
      expect(parent('/o/x/administration'), '/o/x');
      expect(parent('/o/x/rapports/semaine'), '/o/x/rapports');
      expect(parent('/o/x/stock'), '/o/x');
      expect(parent('/o/x'), isNull, reason: 'one business: a root');
      expect(parent('/o/x', businesses: 2), Routes.picker);
      expect(parent('/o/x/', businesses: 2), Routes.picker, reason: 'a trailing slash is the same page');
    });

    test('the street side: the street is the root; everything else leads back to it', () {
      expect(parent(Routes.directory), isNull);
      expect(parent('/s/boutique-awa'), Routes.directory);
      expect(parent(Routes.myOrders), Routes.directory);
      expect(parent(Routes.shopperProfile), Routes.directory);
      expect(parent('/mon-compte/adresses'), '/mon-compte');
      expect(parent('/livreur/notifications'), '/livreur');
      expect(parent('/livreur/course/c1'), '/livreur', reason: '/livreur/course is not a page');
      expect(parent(Routes.courier), Routes.directory);
      expect(parent(Routes.privacy), Routes.directory);
      expect(parent('/paiement/p1'), Routes.directory);
      expect(parent(Routes.picker), isNull, reason: 'never back onto the street from the picker');
      expect(parent(Routes.signIn), Routes.directory);
    });

    test('the center, creation, the gates', () {
      expect(parent('/console/entreprises/o1'), '/console/entreprises');
      expect(parent('/console/livreurs/dossier/u1'), '/console/livreurs');
      expect(parent('/console/entreprises'), '/console');
      expect(parent('/demandes/formulaire'), '/demandes');
      expect(parent('/demandes'), '/console');
      expect(parent(Routes.createBusiness, businesses: 1), Routes.picker);
      expect(parent(Routes.createBusiness, businesses: 0), Routes.directory);
      for (final gate in ['/', Routes.splash, Routes.pin, Routes.twoStep]) {
        expect(parent(gate), isNull, reason: gate);
      }
    });
  });

  group('Android\'s back from a page with nothing under it', () {
    testWidgets('six deep pages, each reached with go: back lands on the parent, never out of the app',
        (tester) async {
      final engine = _Engine(tester);
      for (final (from, to) in const [
        ('/o/org-1/factures/inv-9', '/o/org-1/factures'),
        ('/o/org-1/administration/parametres', '/o/org-1/administration'),
        ('/o/org-1/produits', '/o/org-1'),
        ('/s/boutique-awa', '/vitrines'),
        ('/mes-commandes', '/vitrines'),
        ('/mon-compte/adresses', '/mon-compte'),
        ('/livreur/notifications', '/livreur'),
        ('/livreur/course/c1', '/livreur'),
        ('/langue', '/vitrines'),
      ]) {
        final router = await open(tester, from);
        expect(path(router), from);
        await _back(tester);
        expect(path(router), to, reason: 'back from $from');
        expect(engine.phonePops, 0, reason: from);
        expect(find.byKey(const Key('leave-mara')), findsNothing, reason: from);
      }
    });

    testWidgets('a chain: the shopper\'s addresses → Mon compte → the street → « Quitter Mara ? »', (tester) async {
      final engine = _Engine(tester);
      final router = await open(tester, '/mon-compte/adresses');
      await _back(tester);
      expect(path(router), '/mon-compte');
      await _back(tester);
      expect(path(router), '/vitrines');
      await _back(tester);
      expect(find.text('Quitter Mara ?'), findsOneWidget);
      expect(engine.phonePops, 0);
    });

    testWidgets('the home of the only business: back asks « Quitter Mara ? » — « Rester » stays, a second back '
        'closes the question, « Quitter » leaves', (tester) async {
      final engine = _Engine(tester);
      final router = await open(tester, '/o/org-1');
      await _back(tester);
      expect(find.byKey(const Key('leave-mara')), findsOneWidget);
      expect(find.text('Rester'), findsOneWidget);
      expect(find.text('Quitter'), findsOneWidget);
      expect(engine.phonePops, 0, reason: 'never out without the question');

      await tester.tap(find.byKey(const Key('leave-stay')));
      await _settle(tester);
      expect(find.byKey(const Key('leave-mara')), findsNothing);
      expect(path(router), '/o/org-1');
      expect(engine.phonePops, 0);

      await _back(tester);
      expect(find.byKey(const Key('leave-mara')), findsOneWidget);
      await _back(tester);
      expect(find.byKey(const Key('leave-mara')), findsNothing, reason: 'back closes the question like any pop-up');
      expect(engine.phonePops, 0);

      await _back(tester);
      await tester.tap(find.byKey(const Key('leave-quit')));
      await _settle(tester);
      expect(engine.phonePops, 1, reason: '« Quitter »: the phone closes the app');
    });

    testWidgets('the home, with several businesses: back goes to the picker', (tester) async {
      final engine = _Engine(tester);
      final router = await open(tester, '/o/org-1', businesses: 2);
      await _back(tester);
      expect(path(router), Routes.picker);
      expect(engine.phonePops, 0);
    });

    testWidgets('back still closes an open sheet first (114), then goes to the parent', (tester) async {
      final router = await open(tester, '/mes-commandes');
      await tester.tap(find.byKey(const Key('open-sheet')));
      await _settle(tester);
      expect(find.text('La feuille'), findsOneWidget);
      await _back(tester);
      expect(find.text('La feuille'), findsNothing);
      expect(path(router), '/mes-commandes');
      await _back(tester);
      expect(path(router), '/vitrines');
    });
  });

  group('the AppBar\'s back arrow', () {
    testWidgets('a page reached with go gets an arrow to its parent; a pushed page keeps Flutter\'s own; '
        'the street (a root) has none', (tester) async {
      _Engine(tester);
      final router = await open(tester, Routes.privacy);
      expect(find.text('Politique de confidentialité'), findsOneWidget);
      expect(find.byKey(const Key('parent-back')), findsOneWidget, reason: 'the real legal page');
      await tester.tap(find.byKey(const Key('parent-back')));
      await _settle(tester);
      expect(path(router), '/vitrines');
      expect(find.byKey(const Key('parent-back')), findsNothing, reason: 'the street is a root');
      expect(find.byType(BackButton), findsNothing);

      router.push('/mes-commandes');
      await _settle(tester);
      expect(find.byKey(const Key('parent-back')), findsNothing);
      expect(find.byType(BackButton), findsOneWidget, reason: 'pushed: Flutter\'s arrow pops');
      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect(path(router), '/vitrines');

      router.go('/o/org-1/produits');
      await _settle(tester);
      expect(find.byType(BackButton), findsOneWidget, reason: 'a tool: the home is under it');
      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect(path(router), '/o/org-1');
      expect(find.byType(BackButton), findsNothing, reason: 'the only business\'s home: a root');
    });
  });
}
