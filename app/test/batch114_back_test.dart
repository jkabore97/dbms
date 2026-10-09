import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/whatsapp_phone.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/nav/back_first.dart';
import 'package:kaj_app/core/nav/business_cover.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/onboarding/business_creation.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/center/command_center_shell.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/home/business_frame.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/features/setup/create_my_business_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient, User;

/// The owner (114): « Please make the back button close the pop up first
/// in the all app. » — Android's back, and the browser's, close what is
/// open (a sheet, a dialog, a menu, a date picker, a snackbar with an
/// action, the Plus sheet) before leaving the page: on a business's tool
/// page (shop, farm, association), the vitrine's basket, the command
/// center, a step of « Créer mon activité ». One mechanism: BackFirst.

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
  Future<int> pendingOrders(String orgId) async => 0;
}

const _shop = OrgSummary(
    id: 'org-1', name: 'Boutique Awa', slug: 'boutique-awa', profile: 'retail', roles: ['owner'], currency: 'XOF');
const _farm = OrgSummary(id: 'farm-1', name: 'Ferme Ignace', profile: 'farm', roles: ['owner']);
const _asso = OrgSummary(id: 'asso-1', name: 'Entraide', profile: 'association', roles: ['owner']);

/// A tool's page and everything that opens over one.
Widget _tool(String name) => Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text('Page $name'), actions: [
          PopupMenuButton<int>(
            key: const Key('menu'),
            itemBuilder: (_) => const [PopupMenuItem(value: 1, child: Text('Un choix'))],
          ),
        ]),
        body: ListView(children: [
          TextButton(
            key: const Key('open-sheet'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (sheet) => SizedBox(
                height: 200,
                child: Column(children: [
                  const Text('La feuille'),
                  TextButton(
                    key: const Key('sheet-dialog'),
                    onPressed: () => showDialog<void>(
                        context: sheet,
                        builder: (_) => const AlertDialog(content: Text('Sûr ?'))),
                    child: const Text('Une question'),
                  ),
                ]),
              ),
            ),
            child: const Text('Feuille'),
          ),
          TextButton(
            key: const Key('open-dialog'),
            onPressed: () => showDialog<void>(
                context: context, builder: (_) => const AlertDialog(content: Text('Le dialogue'))),
            child: const Text('Dialogue'),
          ),
          TextButton(
            key: const Key('open-date'),
            onPressed: () => showDatePicker(
                context: context,
                initialDate: DateTime(2026, 10, 8),
                firstDate: DateTime(2026),
                lastDate: DateTime(2027),
                helpText: 'Le jour'),
            child: const Text('Date'),
          ),
          TextButton(
            key: const Key('open-snack'),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Article retiré.'),
                duration: const Duration(minutes: 5),
                action: SnackBarAction(label: 'Annuler', onPressed: () {}))),
            child: const Text('Message'),
          ),
        ]),
      ),
    );

GoRouter _business(Widget Function() home, OrgSummary org, BackFirst back, {String? at}) {
  final cover = BusinessCover();
  return GoRouter(
    initialLocation: at ?? '/o/${org.id}',
    observers: [back.watch()],
    routes: [
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
                'produits', 'commandes', 'factures', 'compte', 'administration', 'equipe', 'stock',
                'bandes', 'a-vendre', 'services', 'chemin', 'credits', 'production', 'photos',
                'journal', 'rapports', 'notifications',
              ])
                GoRoute(path: r, builder: (_, _) => BusinessPage(child: _tool(r))),
            ],
          ),
        ],
      ),
    ],
  );
}

/// The app's MaterialApp.router as main.dart draws it: the snackbars on
/// BackFirst's messenger, the back always the app's.
Widget _app(GoRouter router, BackFirst back) => MaterialApp.router(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      routerConfig: router,
      scaffoldMessengerKey: back.messenger,
      onNavigationNotification: back.onNavigationNotification,
    );

void _size(WidgetTester tester, [double width = 390, double height = 1400]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

/// What the app tells the engine: the back taken or not, a pop handed to
/// the phone, an address put in the browser's history.
class _Engine {
  _Engine(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.setFrameworkHandlesBack') handlesBack.add(call.arguments as bool);
      if (call.method == 'SystemNavigator.pop') phonePops++;
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
      if (call.method == 'routeInformationUpdated') {
        addresses.add('${(call.arguments as Map)['uri'] ?? (call.arguments as Map)['location']}');
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(SystemChannels.navigation, null);
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  final handlesBack = <bool>[];
  final addresses = <String>[];
  int phonePops = 0;
}

/// The browser's back: the address it went to, handed to the app.
Future<void> _browserBack(WidgetTester tester, String to) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(
        MethodCall('pushRouteInformation', {'location': to, 'state': null})),
    (_) {},
  );
}

/// Android's back.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
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

  Widget shopHome() =>
      StoreHomeScreen(org: _shop, retail: _Shop(client), invoicing: InvoicingRepository(client));
  Widget farmHome() => FarmHomeScreen(db: db, org: _farm, invoicing: InvoicingRepository(client));
  Widget assoHome() => ChurchHomeScreen(
      db: db, orgId: _asso.id, orgName: _asso.name, org: _asso, invoicing: InvoicingRepository(client));

  /// [home] at a tool page, [back] wired as main.dart wires it.
  Future<(GoRouter, BackFirst)> openTool(WidgetTester tester, Widget Function() home, OrgSummary org,
      String tool) async {
    _size(tester);
    late BackFirst back;
    final router = _business(home, org, back = BackFirst(), at: '/o/${org.id}');
    back.attach(router);
    addTearDown(() => back.detach(router));
    await tester.pumpWidget(_app(router, back));
    await _settle(tester);
    router.push('/o/${org.id}/$tool');
    await _settle(tester);
    expect(find.text('Page $tool'), findsOneWidget);
    return (router, back);
  }

  group('a business\'s tool page', () {
    testWidgets('the shop: back closes the sheet, the dialog, the menu, the date picker, the message, '
        'the Plus sheet — each before the page; then back goes home', (tester) async {
      final (router, back) = await openTool(tester, shopHome, _shop, 'produits');

      Future<void> openThenBack(String key, String shown) async {
        await tester.tap(find.byKey(Key(key)));
        await _settle(tester);
        expect(find.text(shown), findsOneWidget, reason: '$key open');
        expect(back.popupOpen, key != 'open-snack');
        await _back(tester);
        expect(find.text(shown), findsNothing, reason: 'back closed $key');
        expect(find.text('Page produits'), findsOneWidget, reason: 'and the page stays');
        expect(router.state.uri.path, '/o/org-1/produits');
      }

      await openThenBack('open-sheet', 'La feuille');
      await openThenBack('open-dialog', 'Le dialogue');
      await openThenBack('menu', 'Un choix');
      await openThenBack('open-date', 'Le jour');
      await openThenBack('open-snack', 'Article retiré.');

      // The Plus sheet of the business's bar.
      await tester.tap(find.text('Plus'));
      await _settle(tester);
      expect(find.widgetWithText(ListTile, 'Administration'), findsOneWidget);
      await _back(tester);
      expect(find.widgetWithText(ListTile, 'Administration'), findsNothing);
      expect(find.text('Page produits'), findsOneWidget);

      // A dialog asked from a sheet, answered: back still closes the sheet.
      await tester.tap(find.byKey(const Key('open-sheet')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('sheet-dialog')));
      await _settle(tester);
      await _back(tester);
      expect(find.text('Sûr ?'), findsNothing);
      expect(find.text('La feuille'), findsOneWidget, reason: 'one back, one thing closed');
      await _back(tester);
      expect(find.text('La feuille'), findsNothing);
      expect(find.text('Page produits'), findsOneWidget);

      // Nothing open: back leaves the page for the home, as before.
      await _back(tester);
      expect(router.state.uri.path, '/o/org-1');
    });

    testWidgets('the farm (À vendre) and the association (Factures): the Plus sheet and a sheet first',
        (tester) async {
      for (final (home, org, tool) in [
        (farmHome, _farm, 'a-vendre'),
        (assoHome, _asso, 'factures'),
      ]) {
        final (router, _) = await openTool(tester, home, org, tool);
        await tester.tap(find.text('Plus'));
        await _settle(tester);
        expect(find.widgetWithText(ListTile, 'Administration'), findsOneWidget, reason: org.profile);
        await _back(tester);
        expect(find.widgetWithText(ListTile, 'Administration'), findsNothing, reason: org.profile);
        await tester.tap(find.byKey(const Key('open-sheet')));
        await _settle(tester);
        await _back(tester);
        expect(find.text('La feuille'), findsNothing, reason: org.profile);
        expect(router.state.uri.path, '/o/${org.id}/$tool', reason: org.profile);
        await _back(tester);
        expect(router.state.uri.path, '/o/${org.id}', reason: org.profile);
      }
    });

    testWidgets('Android: the app keeps the back while a sheet is open under a dialog just closed '
        '(before 114 the router\'s navigator said « nothing to pop » and back left the app)',
        (tester) async {
      _size(tester);
      final engine = _Engine(tester);
      final back = BackFirst();
      final router = _business(shopHome, _shop, back);
      back.attach(router);
      addTearDown(() => back.detach(router));
      await tester.pumpWidget(_app(router, back));
      await _settle(tester);

      // A sheet on the home (the frame's navigator), a dialog from it (the
      // router's), the dialog answered.
      showModalBottomSheet<void>(
          context: tester.element(find.byType(StoreHomeScreen)),
          builder: (_) => const SizedBox(height: 120, child: Text('La vente')));
      await _settle(tester);
      showDialog<void>(
          context: tester.element(find.text('La vente')),
          builder: (_) => const AlertDialog(content: Text('Sûr ?')));
      await _settle(tester);
      Navigator.of(tester.element(find.text('Sûr ?'))).pop();
      await _settle(tester);
      expect(find.text('La vente'), findsOneWidget);
      expect(engine.handlesBack, isNotEmpty);
      expect(engine.handlesBack.toSet(), {true}, reason: 'the back stays the app\'s');

      await _back(tester);
      expect(find.text('La vente'), findsNothing);
      expect(engine.phonePops, 0, reason: 'the sheet closed, the app stayed');

      // On the home with nothing open (the only business): « Quitter
      // Mara ? » first (122), then the phone's back, out.
      await _back(tester);
      expect(engine.phonePops, 0);
      expect(find.text('Quitter Mara ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('leave-quit')));
      await _settle(tester);
      expect(engine.phonePops, 1);
    });

    testWidgets('the web: the browser\'s back closes the sheet and keeps the page\'s address; '
        'with nothing open it goes back as before', (tester) async {
      final engine = _Engine(tester);
      final (router, back) = await openTool(tester, shopHome, _shop, 'produits');
      back.browserHistory = true;
      // The page by its own address, as the bar opens it.
      router.go('/o/org-1/produits');
      await _settle(tester);

      await tester.tap(find.byKey(const Key('open-sheet')));
      await _settle(tester);
      await _browserBack(tester, '/o/org-1');
      await _settle(tester);
      expect(find.text('La feuille'), findsNothing);
      expect(find.text('Page produits'), findsOneWidget);
      expect(router.state.uri.path, '/o/org-1/produits');
      expect(engine.addresses.last, '/o/org-1/produits', reason: 'the page\'s address back in the history');

      await tester.tap(find.byKey(const Key('open-snack')));
      await _settle(tester);
      await _browserBack(tester, '/o/org-1');
      await _settle(tester);
      expect(find.text('Article retiré.'), findsNothing);
      expect(router.state.uri.path, '/o/org-1/produits');

      await _browserBack(tester, '/o/org-1');
      await _settle(tester);
      expect(router.state.uri.path, '/o/org-1');
    });
  });

  testWidgets('a step flow open inside the business frame: the browser\'s back is the previous step, '
      'the address kept; from the first step it closes the flow (batch 115)', (tester) async {
    final engine = _Engine(tester);
    _size(tester);
    final back = BackFirst()..browserHistory = true;
    Widget flow() => StepFlow(
          title: 'Dépense',
          store: MemoryFlowStore(),
          steps: [
            for (final n in [1, 2, 3])
              FlowStep(id: 's$n', title: 'Question $n', builder: (_) => Text('Réponse $n')),
          ],
          summary: (_) => const Text('Résumé'),
          onSave: () async => true,
          done: (_) => const Text('Fait'),
        );
    final router = _business(
        () => Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('open-flow'),
                  onPressed: () => StepFlow.push(context, flow()),
                  child: const Text('Accueil'),
                ),
              ),
            ),
        _shop,
        back);
    back.attach(router);
    addTearDown(() => back.detach(router));
    await tester.pumpWidget(_app(router, back));
    await _settle(tester);
    router.go('/o/org-1/produits');
    await _settle(tester);
    router.go('/o/org-1');
    await _settle(tester);
    await tester.tap(find.byKey(const Key('open-flow')));
    await _settle(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('flow-next')));
      await _settle(tester);
    }
    expect(find.text('Question 3'), findsOneWidget);
    // The business's bar is behind the flow (108's cover), the flow on top.
    expect(find.byType(StepFlow), findsOneWidget);

    await _browserBack(tester, '/o/org-1/produits');
    await _settle(tester);
    expect(find.text('Question 2'), findsOneWidget, reason: 'the previous step, not the previous page');
    expect(router.state.uri.path, '/o/org-1');
    expect(engine.addresses.last, '/o/org-1', reason: 'the page\'s address back in the history');

    await _browserBack(tester, '/o/org-1/produits');
    await _settle(tester);
    expect(find.text('Question 1'), findsOneWidget);

    // From the first step: the flow closes (nothing typed), the page stays.
    await _browserBack(tester, '/o/org-1/produits');
    await _settle(tester);
    expect(find.byType(StepFlow), findsNothing);
    expect(find.text('Accueil'), findsOneWidget);
    expect(router.state.uri.path, '/o/org-1');

    // Nothing open any more: the browser's back goes back as before.
    await _browserBack(tester, '/o/org-1/produits');
    await _settle(tester);
    expect(router.state.uri.path, '/o/org-1/produits');
  });

  testWidgets('the vitrine: back closes the basket (« Votre commande ») and the vitrine stays', (tester) async {
    _size(tester, 390, 844);
    final server = _Server()
      ..live = true
      ..user = _awa;
    final session = SessionController(
        db: db, auth: server, admin: _Admin(), accounting: AccountingRepository(null));
    await tester.runAsync(session.resolveOrgs);
    await tester.runAsync(() => db.writePref('street_basket_boutique-awa', jsonEncode({'p1': 2})));
    final back = BackFirst();
    final router = GoRouter(
      initialLocation: Routes.directory,
      observers: [back.watch()],
      routes: [
        GoRoute(path: Routes.directory, builder: (_, _) => const Scaffold(body: Text('La rue'))),
        GoRoute(
          path: '/s/:slug',
          builder: (_, state) => StorefrontScreen(
            slug: state.pathParameters['slug']!,
            storefront: _Window(),
            capture: CaptureRepository(null, db: db),
            session: session,
            whatsApp: _Phone(),
          ),
        ),
      ],
    );
    back.attach(router);
    addTearDown(() => back.detach(router));
    await tester.pumpWidget(_app(router, back));
    await _settle(tester);
    router.push(Routes.storefront('boutique-awa'));
    await _settle(tester);
    final order = find.widgetWithText(FilledButton, 'Commander').first;
    await tester.ensureVisible(order);
    await tester.pump();
    await tester.tap(order);
    await _settle(tester);
    expect(find.text('Votre commande'), findsOneWidget);

    await _back(tester);
    expect(find.text('Votre commande'), findsNothing);
    expect(router.state.uri.path, '/s/boutique-awa', reason: 'the vitrine stays');
    expect(find.text('La rue'), findsNothing);
    await _back(tester);
    expect(find.text('La rue'), findsOneWidget, reason: 'then back leaves it, as before');
  });

  testWidgets('the command center: back closes a dialog and its « Plus » sheet, the section stays',
      (tester) async {
    _size(tester, 390, 900);
    final back = BackFirst();
    final router = GoRouter(
      initialLocation: Routes.consoleBusinesses,
      observers: [back.watch()],
      routes: [
        ShellRoute(
          builder: (_, _, child) => CommandCenterShell(
              center: CommandCenterRepository(null), platformAdmin: true, child: child),
          routes: [
            for (final p in [Routes.console, Routes.consoleBusinesses, Routes.consoleJournal])
              GoRoute(path: p, builder: (_, _) => _tool(p)),
          ],
        ),
      ],
    );
    back.attach(router);
    addTearDown(() => back.detach(router));
    await tester.pumpWidget(_app(router, back));
    await _settle(tester);
    final page = 'Page ${Routes.consoleBusinesses}';
    expect(find.text(page), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-dialog')));
    await _settle(tester);
    await _back(tester);
    expect(find.text('Le dialogue'), findsNothing);
    expect(find.text(page), findsOneWidget);

    await tester.tap(find.text('Plus'));
    await _settle(tester);
    expect(find.byKey(const Key('center-more-journal')), findsOneWidget);
    await _back(tester);
    expect(find.byKey(const Key('center-more-journal')), findsNothing);
    expect(find.text(page), findsOneWidget);
    expect(router.state.uri.path, Routes.consoleBusinesses);
  });

  testWidgets('« Créer mon activité »: on the phone step back closes the currency list, then steps back',
      (tester) async {
    _size(tester);
    final back = BackFirst();
    final router = GoRouter(
      initialLocation: Routes.createBusiness,
      observers: [back.watch()],
      routes: [
        GoRoute(
          path: Routes.createBusiness,
          builder: (_, _) => CreateMyBusinessScreen(
              api: _Api(), drafts: _Drafts(), whatsApp: _Phone(), onCreated: (_) async => true),
        ),
      ],
    );
    back.attach(router);
    addTearDown(() => back.detach(router));
    await tester.pumpWidget(_app(router, back));
    await _settle(tester);

    Future<void> next() async {
      await tester.tap(find.byKey(const Key('create-next')));
      await _settle(tester);
    }

    await tester.tap(find.byKey(const Key('create-kind-retail')));
    await _settle(tester);
    await next();
    await tester.enterText(find.byKey(const Key('create-name')), 'Chez Awa');
    await _settle(tester);
    await next();
    await tester.tap(find.byKey(const Key('create-activity-alimentation')));
    await tester.enterText(find.byKey(const Key('create-about')), 'Riz et huile au détail');
    await _settle(tester);
    await next();
    await tester.tap(find.text('Ouagadougou'));
    await tester.enterText(find.byKey(const Key('create-area')), 'Dapoya');
    await _settle(tester);
    await next();
    expect(find.text('5 / 6'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await _settle(tester);
    expect(find.text('EUR — Euro'), findsWidgets, reason: 'the list is open');
    await _back(tester);
    expect(find.text('EUR — Euro'), findsNothing, reason: 'back closed the list');
    expect(find.text('5 / 6'), findsOneWidget, reason: 'on the same step');
    await _back(tester);
    expect(find.text('4 / 6'), findsOneWidget, reason: 'then back steps back, as before');
  });
}

// ---------------------------------------------------------------- fakes

class _Server extends AuthRepository {
  _Server() : super(null);
  bool live = false;
  User? user;
  @override
  bool get isConfigured => true;
  @override
  bool get hasLiveSession => live;
  @override
  User? get currentUser => user;
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

class _Window extends StorefrontRepository {
  _Window() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<PublicShop?> shop(String slug) async =>
      PublicShop(orgId: 'o1', name: 'Boutique Awa', slug: slug, profile: 'retail');
  @override
  Future<List<PublicItem>> items(String slug) async =>
      const [PublicItem(id: 'p1', name: 'Savon', price: 500, inStock: true)];
}

class _Phone implements WhatsAppPhone {
  @override
  Future<OrderPhoneGate?> gate() async => null;
  @override
  Future<void> sendCode(String e164) async {}
  @override
  Future<void> confirm(String e164, String code) async {}
}

class _Api implements BusinessCreation {
  @override
  Future<BusinessStart> start() async => const BusinessStart();
  @override
  Future<AddressCheck> checkAddress(String slug) async => AddressCheck(slug: slug);
  @override
  Future<String> create({
    required String profile,
    required String name,
    required String slug,
    required String activity,
    required String about,
    required String city,
    required String area,
    required String phone,
    required String currency,
    Map<String, Object?>? answers,
  }) async =>
      'org-new';
}

class _Drafts implements DraftStore {
  BusinessDraft? kept;
  @override
  Future<BusinessDraft?> read() async => kept;
  @override
  Future<void> write(BusinessDraft? draft) async => kept = draft;
}

const _awa = User(
  id: 'awa-1',
  appMetadata: {'provider': 'google'},
  userMetadata: {'full_name': 'Awa Ouédraogo'},
  aud: 'authenticated',
  email: 'awa@example.com',
  createdAt: '2026-10-08T00:00:00Z',
);
