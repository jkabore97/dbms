// Batch 134: the business bars folded, an association's Catalogue, and
// « Créer mon activité » easy to find (the owner's approved mockups,
// scratchpad/nav_mockups).
//
//   1. three bars, five places at most, always a word, in an order that
//      never moves — the shop's Vente · Catalogue · Commandes · Argent ·
//      Plus, the farm's Accueil · Bandes · Stock · Ventes · Plus, the
//      association's Accueil · Journal · Rapports · Catalogue · Plus — on
//      the first frame as when the home has said them; Plus under its
//      headings; the acts (a sale, an expense) big buttons on the home;
//      the dial still closes the bar up; an observer only watches; the
//      rail on a wide screen;
//   2. Catalogue: Articles | Services in one tab, one ＋ that asks « un
//      article ou un service ? »; an association's articles simple;
//   3. Argent: four numbers, Factures | Dépenses | Crédit, and Factures'
//      lock exactly as it was;
//   4. the old addresses (a bell's `produits?q=…`, `factures`, `credits`,
//      the farm's `commandes`) land in the right tab and section, and the
//      bar shows that place on the pages under it;
//   5. the market: « ＋ Vendre sur Mara » / « Ma boutique » worded, the
//      helmet in the account menu, « Créer mon activité » there too, the
//      invite card (closed for good on the device, gone for a member),
//      and « Vous êtes ici pour… » once.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/org_access.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/accounting/models.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/analytics/analytics_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/credit/credit_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/invoicing/models.dart';
import 'package:kaj_app/core/l10n/locale_controller.dart';
import 'package:kaj_app/core/nav/app_scope.dart';
import 'package:kaj_app/core/nav/business_cover.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/shopper/shopper_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/tontine/tontine_repository.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/home/business_frame.dart';
import 'package:kaj_app/features/home/home_nav.dart';
import 'package:kaj_app/features/money/money_screen.dart';
import 'package:kaj_app/features/retail/catalogue_screen.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/features/shopper/arrival_screen.dart';
import 'package:kaj_app/features/storefront/directory_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

// ---------------------------------------------------------------------------
// The businesses
// ---------------------------------------------------------------------------

const _shop = OrgSummary(
    id: '13400000-0000-0000-0000-0000000000a1',
    name: 'Jersey Bakery',
    slug: 'jersey-bakery',
    profile: 'retail',
    roles: ['owner']);
const _farm = OrgSummary(
    id: '13400000-0000-0000-0000-0000000000a2',
    name: 'Ferme Wend',
    slug: 'ferme-wend',
    profile: 'farm',
    roles: ['owner']);
const _assoc = OrgSummary(
    id: '13400000-0000-0000-0000-0000000000a3',
    name: 'Centre ELIM',
    slug: 'centre-elim',
    profile: 'association',
    roles: ['owner']);

class _Shelf extends RetailRepository {
  _Shelf([this.items = const []]) : super(null);

  final List<Product> items;

  @override
  bool get isConfigured => true;
  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();
  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) async => const [];
  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => List.of(items);
  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {};
  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) async => 0;
  @override
  Future<int> pendingOrders(String orgId) async => 0;
  @override
  Future<int> pendingSales(String orgId) async => 0;
  @override
  Future<List<Map<String, Object?>>> refusedSales(String orgId) async => const [];
}

class _Bills extends InvoicingRepository {
  _Bills([this.invoices = const []]) : super(null);
  final List<InvoiceSummary> invoices;
  @override
  bool get isConfigured => true;
  @override
  Future<List<InvoiceSummary>> list(String orgId, {bool includePaid = true, int limit = 200}) async =>
      invoices;
  @override
  Future<BillingDetails> billingDetails(String orgId) async => const BillingDetails();
}

class _Books extends AccountingRepository {
  _Books() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<List<StatementLine>> incomeStatement(String orgId, {DateTime? from, DateTime? to}) async => const [
        StatementLine(section: 'total', code: '1', name: 'Produits', amount: 612000),
        StatementLine(section: 'total', code: '2', name: 'Charges', amount: 148500),
      ];
  @override
  Future<List<JournalRow>> journal(String orgId,
          {DateTime? from, DateTime? to, int limit = 100, int offset = 0}) async =>
      const [];
}

class _Carnet extends CreditRepository {
  _Carnet() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<List<DebtorRow>> debtors(String orgId) async =>
      const [DebtorRow(customerId: 'c1', name: 'Awa', totalOwed: 35000)];
  @override
  Future<List<DebtDate>> dueDates(String orgId) async => const [];
}

/// The server as the session reads it: these locks on Le Chemin.
class _Admin extends AdminRepository {
  _Admin({this.locks = const {}}) : super(null);
  final Map<String, bool> locks;
  @override
  Future<bool> isPlatformAdmin() async => false;
  @override
  Future<int> claimMyInvitations() async => 0;
  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;
  @override
  Future<FeatureStates?> featureStates(String orgId) async => FeatureStates.fromJson({
        'plan': 'free',
        'progress': {'locks': locks},
      });
  @override
  Future<Map<String, String>> featureRulesForTier(String orgId, String tier) async => const {};
}

class _Server extends AuthRepository {
  _Server(this.orgs) : super(null);
  final List<OrgSummary> orgs;
  @override
  bool get isConfigured => true;
  @override
  bool get hasLiveSession => true;
  @override
  User? get currentUser => const User(
        id: 'awa-134',
        appMetadata: {'provider': 'email'},
        userMetadata: {'full_name': 'Awa'},
        aud: 'authenticated',
        email: 'awa134@example.com',
        createdAt: '2026-10-12T00:00:00Z',
      );
  @override
  Future<List<OrgSummary>> fetchOrgs() async => orgs;
}

class _Shopper extends ShopperRepository {
  _Shopper({this.pending = true}) : super(null);
  bool pending;
  final answers = <String>[];
  int asked = 0;
  @override
  Future<bool> arrivalPending() async {
    asked++;
    return pending;
  }

  @override
  Future<void> answerArrival(String intent) async {
    answers.add(intent);
    pending = false;
  }
}

class _Street extends StorefrontRepository {
  _Street() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<KeptStreet?> keptStreet() async => null;
  @override
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) async => const [
        DirectoryEntry(orgId: 'o1', name: 'Tony Pizza', slug: 'tony-pizza', profile: 'retail'),
      ];
  @override
  Future<List<FeaturedItem>> featured({double? lat, double? lng}) async => const [];
  @override
  Future<Set<String>> spotlights({double? lat, double? lng}) async => const {};
  @override
  Future<Set<String>> showcaseSlugs() async => const {};
  @override
  Future<Map<String, List<ShopPreview>>> previews(List<String> slugs) async => const {};
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _phone(WidgetTester tester, {double width = 390, double height = 844}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home, {Locale locale = const Locale('fr')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

List<String> _bar(WidgetTester tester) => tester
    .widgetList<NavigationDestination>(find.byType(NavigationDestination))
    .map((d) => d.label)
    .toList();

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Plus: its lines, in order, and the headings drawn.
Future<(List<String>, List<String>)> _plus(WidgetTester tester) async {
  await tester.tap(find.text('Plus'));
  await tester.pumpAndSettle();
  final lines = tester
      .widgetList<ListTile>(find.byType(ListTile))
      .map((t) => (t.title as Text).data ?? '')
      .toList();
  final headings = [
    for (final g in PlusGroup.values)
      if (find.byKey(Key('plus-heading-${g.name}')).evaluate().isNotEmpty) g.name,
  ];
  return (lines, headings);
}

Widget _home(OrgSummary org, LocalDb db, {OrgAccess access = OrgAccess.allEdit}) => switch (org.profile) {
      'retail' => StoreHomeScreen(org: org, retail: _Shelf(), invoicing: _Bills(), access: access),
      'farm' => FarmHomeScreen(db: db, org: org, retail: _Shelf(), invoicing: _Bills(), access: access),
      _ => ChurchHomeScreen(
          db: db,
          orgId: org.id,
          orgName: org.name,
          org: org,
          reports: ReportsRepository(null),
          invoicing: _Bills(),
          retail: _Shelf(),
          onHistory: () {},
          access: access,
        ),
    };

/// A business's frame around its home and a few pages, as the router has
/// it, at [at].
GoRouter _business(Widget Function() home, OrgSummary org, SessionController session,
    {String? at}) {
  final cover = BusinessCover();
  return GoRouter(initialLocation: at ?? '/o/${org.id}', routes: [
    ShellRoute(
      observers: [cover],
      builder: (context, state, child) =>
          BusinessFrame(org: org, location: state.uri.path, cover: cover, session: session, child: child),
      routes: [
        GoRoute(
          path: '/o/:orgId',
          builder: (_, _) => BusinessPage(child: home()),
          routes: [
            for (final r in const [
              'catalogue', 'argent', 'ventes', 'commandes', 'bandes', 'stock', 'journal', 'rapports',
              'compte', 'equipe', 'administration', 'chemin', 'photos', 'credits', 'services',
            ])
              GoRoute(path: r, builder: (_, _) => BusinessPage(child: Scaffold(appBar: AppBar(title: Text('Page $r'))))),
            GoRoute(
              path: 'factures',
              builder: (_, _) => const BusinessPage(child: Scaffold(body: Text('Page factures'))),
              routes: [
                GoRoute(
                    path: ':id',
                    builder: (_, state) =>
                        BusinessPage(child: Scaffold(body: Text('Facture ${state.pathParameters['id']}')))),
              ],
            ),
          ],
        ),
      ],
    ),
  ]);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
  });

  late LocalDb db;
  setUp(() async {
    BusinessNav.forgetKnown();
    forgetStreetArrival();
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  SessionController session0({List<OrgSummary> orgs = const [], Map<String, bool> locks = const {}}) =>
      SessionController(
        db: db,
        auth: _Server(orgs),
        admin: _Admin(locks: locks),
        accounting: AccountingRepository(null),
      );

  Widget scoped(SessionController s, Widget child) => AppScope(
        session: s,
        localeController: LocaleController(db),
        db: db,
        auth: s.auth,
        admin: s.admin,
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
        child: child,
      );

  // -------------------------------------------------------------------------
  group('1. three bars, in an order that never moves', () {
    for (final (org, places) in [
      (_shop, ['Vente', 'Catalogue', 'Commandes', 'Argent', 'Plus']),
      (_farm, ['Accueil', 'Bandes', 'Stock', 'Ventes', 'Plus']),
      (_assoc, ['Accueil', 'Journal', 'Rapports', 'Catalogue', 'Plus']),
    ]) {
      testWidgets('${org.profile}: ${places.join(' · ')}', (tester) async {
        await _phone(tester);
        await tester.pumpWidget(_app(_home(org, db)));
        await _settle(tester);
        expect(_bar(tester), places);
        expect(_bar(tester).length, lessThanOrEqualTo(HomeNav.maxSlots));
      });

      testWidgets('${org.profile}: the same on the very first frame, and after', (tester) async {
        await _phone(tester);
        final s = session0(orgs: [org]);
        await tester.pumpWidget(_app(const SizedBox()));
        await tester.pumpWidget(MaterialApp.router(
          locale: const Locale('fr'),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          routerConfig: _business(() => _home(org, db), org, s),
        ));
        expect(_bar(tester), places, reason: 'the first frame (HomeNav.defaultsFor)');
        await _settle(tester);
        await tester.pumpAndSettle();
        expect(_bar(tester), places, reason: 'the home\'s own places');
        s.dispose();
      });
    }

    testWidgets('the shop: Plus under MA VITRINE, MON ÉQUIPE, MOI; the acts are buttons on the home',
        (tester) async {
      await _phone(tester, height: 1400);
      await tester.pumpWidget(_app(_home(_shop, db)));
      await _settle(tester);
      expect(find.byKey(const Key('home-new-sale')), findsOneWidget);
      expect(find.text('Nouvelle vente'), findsOneWidget);
      expect(find.byKey(const Key('home-expense')), findsOneWidget);
      final (lines, headings) = await _plus(tester);
      expect(lines, ['Voir ma vitrine', 'Mon chemin', 'Production', 'Équipe', 'Administration', 'Compte', 'Voir le marché']);
      expect(headings, ['vitrine', 'team', 'me']);
      expect(lines, isNot(contains('Dépense')), reason: 'an act, not a place');
      expect(lines, isNot(contains('Mes services')), reason: 'in Catalogue now');
    });

    testWidgets('the farm: « Dépense » on Accueil; Plus without À vendre, Commandes or the carnet',
        (tester) async {
      await _phone(tester, height: 1400);
      await tester.pumpWidget(_app(_home(_farm, db)));
      await _settle(tester);
      expect(find.byKey(const Key('home-expense')), findsOneWidget);
      final (lines, headings) = await _plus(tester);
      expect(lines, ['Voir ma vitrine', 'Mes services', 'Mon chemin', 'Production', 'Administration', 'Compte']);
      expect(headings, ['vitrine', 'team', 'me']);
    });

    testWidgets('the association: Factures under Plus (OUTILS); « Recette » and « Dépense » stay',
        (tester) async {
      await _phone(tester, height: 1400);
      await tester.pumpWidget(_app(_home(_assoc, db)));
      await _settle(tester);
      expect(find.text('Recette'), findsOneWidget);
      expect(find.text('Dépense'), findsOneWidget);
      final (lines, headings) = await _plus(tester);
      expect(lines.first, 'Factures');
      expect(lines, containsAllInOrder(['Factures', 'Voir ma vitrine', 'Administration', 'Compte']));
      expect(headings, ['tools', 'vitrine', 'team', 'me']);
    });

    testWidgets('the dial: a place hidden is not drawn, and the bar closes up', (tester) async {
      await _phone(tester);
      const clerk = OrgSummary(id: 'c1', name: 'Jersey Bakery', profile: 'retail', roles: ['employee']);
      await tester.pumpWidget(_app(_home(clerk, db,
          access: const OrgAccess.forTier({'products': 'hidden', 'orders': 'hidden'}))));
      await _settle(tester);
      expect(_bar(tester), ['Vente', 'Argent', 'Plus']);
      await tester.pumpWidget(_app(_home(_assoc, db,
          access: const OrgAccess.forTier({'products': 'hidden', 'reports': 'hidden'}))));
      await _settle(tester);
      expect(_bar(tester), ['Accueil', 'Plus']);
    });

    testWidgets('an observer (a trainer) watches: the bar, no sale or expense to make', (tester) async {
      await _phone(tester);
      const watcher = OrgSummary(id: 'w1', name: 'Jersey Bakery', profile: 'retail', roles: ['observer']);
      await tester.pumpWidget(_app(_home(watcher, db)));
      await _settle(tester);
      expect(_bar(tester), ['Vente', 'Catalogue', 'Commandes', 'Argent', 'Plus']);
      expect(find.byKey(const Key('home-new-sale')), findsNothing);
      expect(find.byKey(const Key('home-expense')), findsNothing);
      const farmWatcher = OrgSummary(id: 'w2', name: 'Ferme', profile: 'farm', roles: ['observer']);
      await tester.pumpWidget(_app(_home(farmWatcher, db)));
      await _settle(tester);
      expect(find.byKey(const Key('home-expense')), findsNothing);
    });

    testWidgets('a wide screen: the same places in the rail', (tester) async {
      await _phone(tester, width: 1200, height: 900);
      final s = session0(orgs: [_shop]);
      await tester.pumpWidget(MaterialApp.router(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        routerConfig: _business(() => _home(_shop, db), _shop, s),
      ));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('business-rail')), findsOneWidget);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect([for (final d in rail.destinations) (d.label as Text).data],
          ['Vente', 'Catalogue', 'Commandes', 'Argent', 'Plus']);
      s.dispose();
    });

    testWidgets('English: the same order, in English', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(_home(_shop, db), locale: const Locale('en')));
      await _settle(tester);
      expect(_bar(tester), ['Sale', 'Catalogue', 'Orders', 'Money', 'More']);
    });
  });

  // -------------------------------------------------------------------------
  group('2. Catalogue: articles and services, one tab, one ＋', () {
    const items = [
      Product(id: 'p1', name: 'Brownies', salePrice: 1500, quantity: 2, isPublished: true),
      Product(id: 's1', name: 'Gâteau sur commande', salePrice: 10000, isService: true, isPublished: true),
    ];

    testWidgets('the shop: Articles first; the switch opens Services; the ＋ asks which', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(CatalogueScreen(org: _shop, retail: _Shelf(items))));
      await _settle(tester);
      expect(find.widgetWithText(AppBar, 'Catalogue'), findsOneWidget);
      expect(find.text('Articles · 1'), findsOneWidget);
      expect(find.text('Services · 1'), findsOneWidget);
      expect(find.text('Brownies'), findsWidgets);
      expect(find.text('Gâteau sur commande'), findsNothing);
      // One ＋: the screens' own add buttons are not drawn twice.
      expect(find.byKey(const Key('products-add')), findsNothing);

      await tester.tap(find.byKey(const Key('section-services')));
      await _settle(tester);
      expect(find.text('Gâteau sur commande'), findsOneWidget);
      expect(find.text('Brownies'), findsNothing);
      expect(find.byKey(const Key('services-add')), findsNothing);

      await tester.tap(find.byKey(const Key('catalogue-add')));
      await tester.pumpAndSettle();
      expect(find.text('Un article ou un service ?'), findsOneWidget);
      expect(find.byKey(const Key('catalogue-add-article')), findsOneWidget);
      expect(find.byKey(const Key('catalogue-add-service')), findsOneWidget);
    });

    testWidgets('opened on its section from the address (?partie=services)', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
          _app(CatalogueScreen(org: _shop, retail: _Shelf(items), initialPart: 'services')));
      await _settle(tester);
      expect(find.text('Gâteau sur commande'), findsOneWidget);
    });

    testWidgets('services hidden by Mara: Articles alone, the ＋ goes straight to an article', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(CatalogueScreen(
          org: _shop, retail: _Shelf(items), access: const OrgAccess.admin(hidden: {'services'}))));
      await _settle(tester);
      expect(find.byKey(const Key('section-services')), findsNothing);
      expect(find.text('Brownies'), findsWidgets);
    });

    testWidgets('an association: simple articles (a t-shirt, a ticket) beside its services', (tester) async {
      await _phone(tester);
      const assocItems = [
        Product(id: 'a1', name: 'T-shirt ELIM', salePrice: 3000, quantity: 5, unit: 'pièce', isPublished: true),
        Product(id: 'a2', name: 'Adhésion annuelle', salePrice: 5000, isService: true, isPublished: true),
      ];
      await tester.pumpWidget(_app(CatalogueScreen(org: _assoc, retail: _Shelf(assocItems))));
      await _settle(tester);
      expect(find.text('T-shirt ELIM'), findsOneWidget);
      expect(find.textContaining('Livres, t-shirts, billets'), findsOneWidget);
      // No barcode, no buying price, no till: none of the shop's tools.
      expect(find.byTooltip('Scanner un code-barres'), findsNothing);
      await tester.tap(find.byKey(const Key('section-services')));
      await _settle(tester);
      expect(find.text('Adhésion annuelle'), findsOneWidget);
      await tester.tap(find.byKey(const Key('catalogue-add')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Un livre, un t-shirt, un billet'), findsOneWidget);
    });

    testWidgets('an observer reads the catalogue, and is offered no ＋', (tester) async {
      await _phone(tester);
      const watcher = OrgSummary(id: 'w3', name: 'Centre', profile: 'association', roles: ['observer']);
      await tester.pumpWidget(_app(CatalogueScreen(org: watcher, retail: _Shelf(items))));
      await _settle(tester);
      expect(find.byKey(const Key('catalogue-add')), findsNothing);
      expect(find.text('Brownies'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('3. Argent: four numbers, three sections, Factures\' lock as it was', () {
    Future<SessionController> withLocks(WidgetTester tester, Map<String, bool> locks) async {
      final s = session0(orgs: [_shop], locks: locks);
      await tester.runAsync(() async {
        await s.resolveOrgs();
        await s.reloadFeatures(_shop.id);
      });
      return s;
    }

    Widget money(SessionController s, {String? part}) => scoped(
        s,
        _app(MoneyScreen(
          org: _shop,
          invoicing: _Bills(),
          credit: _Carnet(),
          retail: _Shelf(),
          accounting: _Books(),
          db: db,
          initialPart: part,
        )));

    testWidgets('open: the numbers, then Factures', (tester) async {
      await _phone(tester);
      final s = await withLocks(tester, const {});
      await tester.pumpWidget(money(s));
      await _settle(tester);
      expect(find.widgetWithText(AppBar, 'Argent'), findsOneWidget);
      expect(find.byKey(const Key('money-numbers')), findsOneWidget);
      for (final label in ['Entré', 'Sorti', 'On me doit', 'Factures impayées']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.textContaining('612'), findsOneWidget);
      expect(find.textContaining('35'), findsWidgets);
      expect(find.text('Aucune facture pour le moment.'), findsOneWidget, reason: 'Factures first');
      await tester.tap(find.byKey(const Key('section-depenses')));
      await _settle(tester);
      expect(find.byKey(const Key('expenses-add')), findsOneWidget);
      await tester.tap(find.byKey(const Key('section-credit')));
      await _settle(tester);
      expect(find.text('Awa'), findsOneWidget);
      s.dispose();
    });

    testWidgets('locked: opens on Dépenses; Factures shows the lock, « lecture seule » opens it',
        (tester) async {
      await _phone(tester);
      final s = await withLocks(tester, const {'invoices': true});
      await tester.pumpWidget(money(s));
      await _settle(tester);
      expect(find.text('Aucune facture pour le moment.'), findsNothing);
      expect(find.byKey(const Key('expenses-add')), findsOneWidget, reason: 'Dépenses');

      await tester.tap(find.byKey(const Key('section-factures')));
      await _settle(tester);
      expect(find.byKey(const Key('path-sheet')), findsOneWidget, reason: 'the lock, as the bar\'s Factures had it');
      await tester.tap(find.byKey(const Key('path-view')));
      await _settle(tester);
      expect(find.text('Aucune facture pour le moment.'), findsOneWidget, reason: 'read, lecture seule');
      s.dispose();
    });

    testWidgets('locked, closed without reading: Argent stays where it was', (tester) async {
      await _phone(tester);
      final s = await withLocks(tester, const {'invoices': true});
      await tester.pumpWidget(money(s));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('section-factures')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('sheet-close')));
      await _settle(tester);
      expect(find.byKey(const Key('expenses-add')), findsOneWidget);
      s.dispose();
    });

    testWidgets('the old address (factures) opens Factures even locked, as it always did', (tester) async {
      await _phone(tester);
      final s = await withLocks(tester, const {'invoices': true});
      await tester.pumpWidget(money(s, part: 'factures'));
      await _settle(tester);
      expect(find.text('Aucune facture pour le moment.'), findsOneWidget);
      s.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('4. the old addresses land in the right tab and section', () {
    Uri u(String s) => Uri.parse(s);
    test('each kind\'s old page, folded', () {
      final shop = _shop.id, farm = _farm.id, assoc = _assoc.id;
      expect(foldedAddress(u('/o/$shop/produits?q=Savon'), _shop), '/o/$shop/catalogue?q=Savon&partie=articles');
      expect(foldedAddress(u('/o/$shop/services'), _shop), '/o/$shop/catalogue?partie=services');
      expect(foldedAddress(u('/o/$shop/factures'), _shop), '/o/$shop/argent?partie=factures');
      expect(foldedAddress(u('/o/$shop/factures/f-31'), _shop), isNull, reason: 'an invoice stays a page');
      expect(foldedAddress(u('/o/$shop/credits'), _shop), '/o/$shop/argent?partie=credit');
      expect(foldedAddress(u('/o/$shop/credits/c1'), _shop), isNull);
      expect(foldedAddress(u('/o/$shop/commandes?commande=9'), _shop), isNull, reason: 'a place of its own');
      expect(foldedAddress(u('/o/$farm/commandes?commande=9'), _farm), '/o/$farm/ventes?commande=9&partie=commandes');
      expect(foldedAddress(u('/o/$farm/a-vendre'), _farm), '/o/$farm/ventes?partie=a-vendre');
      expect(foldedAddress(u('/o/$farm/produits'), _farm), '/o/$farm/ventes?partie=a-vendre');
      expect(foldedAddress(u('/o/$farm/factures'), _farm), '/o/$farm/ventes?partie=factures');
      expect(foldedAddress(u('/o/$farm/services'), _farm), isNull, reason: 'the farm\'s services stay under Plus');
      expect(foldedAddress(u('/o/$farm/credits'), _farm), isNull, reason: 'opened from Ventes');
      expect(foldedAddress(u('/o/$assoc/services'), _assoc), '/o/$assoc/catalogue?partie=services');
      expect(foldedAddress(u('/o/$assoc/produits'), _assoc), '/o/$assoc/catalogue?partie=articles');
      expect(foldedAddress(u('/o/$assoc/factures'), _assoc), isNull, reason: 'under Plus, a page');
      expect(foldedAddress(u('/o/$shop/factures'), null), isNull, reason: 'a business not read yet stays put');
    });

    testWidgets('the bar shows Argent on an invoice, Catalogue on the old services page', (tester) async {
      await _phone(tester);
      final s = session0(orgs: [_shop]);
      Future<int?> selectedAt(String at) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp.router(
          locale: const Locale('fr'),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          routerConfig: _business(() => _home(_shop, db), _shop, s, at: at),
        ));
        await _settle(tester);
        await tester.pumpAndSettle();
        return tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;
      }

      expect(await selectedAt('/o/${_shop.id}/factures/f-31'), 3, reason: 'Argent');
      expect(await selectedAt('/o/${_shop.id}/services'), 1, reason: 'Catalogue');
      expect(await selectedAt('/o/${_shop.id}/argent'), 3);
      s.dispose();
    });

    testWidgets('the farm: Ventes on its orders and invoices', (tester) async {
      await _phone(tester);
      final s = session0(orgs: [_farm]);
      await tester.pumpWidget(MaterialApp.router(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        routerConfig: _business(() => _home(_farm, db), _farm, s, at: '/o/${_farm.id}/commandes'),
      ));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 3);
      s.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('5. « Créer mon activité » easy to find', () {
    Future<GoRouter> street(WidgetTester tester, SessionController s, {_Shopper? shopper}) async {
      await _phone(tester, height: 1400);
      final router = GoRouter(initialLocation: Routes.directory, routes: [
        GoRoute(
          path: Routes.directory,
          builder: (_, _) => DirectoryScreen(
            storefront: _Street(),
            capture: CaptureRepository(null, db: db),
            session: s,
            shopper: shopper,
          ),
        ),
        for (final p in [Routes.createBusiness, Routes.courier, Routes.becomeCourier, Routes.join,
          Routes.signIn, Routes.myOrders, Routes.shopperProfile, Routes.picker])
          GoRoute(path: p, builder: (_, state) => Scaffold(body: Text('page ${state.uri.path}'))),
        GoRoute(path: Routes.arrival, builder: (_, _) => ArrivalScreen(shopper: shopper ?? _Shopper())),
        GoRoute(path: '/o/:id', builder: (_, state) => Scaffold(body: Text('page ${state.uri.path}'))),
      ]);
      await tester.pumpWidget(scoped(
          s,
          MaterialApp.router(
            routerConfig: router,
            locale: const Locale('fr'),
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
          )));
      await _settle(tester);
      return router;
    }

    Future<SessionController> noBusiness(WidgetTester tester) async {
      final s = session0();
      await tester.runAsync(s.resolveOrgs);
      expect(s.phase, SessionPhase.noOrg);
      return s;
    }

    testWidgets('no business: « ＋ Vendre sur Mara », worded, straight to the form', (tester) async {
      final s = await noBusiness(tester);
      await street(tester, s, shopper: _Shopper(pending: false));
      expect(find.byKey(const Key('street-sell')), findsOneWidget);
      expect(find.text('Vendre sur Mara'), findsOneWidget);
      // No bare picture left: no add-business icon, no helmet in the header.
      expect(find.byIcon(Icons.add_business_outlined), findsNothing);
      expect(find.byIcon(Icons.sports_motorsports_outlined), findsNothing);
      await tester.tap(find.byKey(const Key('street-sell')));
      await _settle(tester);
      expect(find.text('page ${Routes.createBusiness}'), findsOneWidget);
      s.dispose();
    });

    testWidgets('the account menu: « Créer mon activité » and « Espace livreur »', (tester) async {
      final s = await noBusiness(tester);
      await street(tester, s, shopper: _Shopper(pending: false));
      await tester.tap(find.byKey(const Key('street-account')));
      await tester.pumpAndSettle();
      expect(find.text('Créer mon activité'), findsWidgets);
      expect(find.text('Espace livreur'), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu-create-business')));
      await _settle(tester);
      expect(find.text('page ${Routes.createBusiness}'), findsOneWidget,
          reason: 'the form, not the join-or-create page');
      s.dispose();
    });

    testWidgets('a member: « Ma boutique » worded; the helmet in the menu; no invite', (tester) async {
      final s = session0(orgs: [_shop]);
      await tester.runAsync(s.resolveOrgs);
      expect(s.phase, isNot(SessionPhase.noOrg));
      await street(tester, s, shopper: _Shopper(pending: false));
      expect(find.byKey(const Key('street-my-business')), findsOneWidget);
      expect(find.text('Ma boutique'), findsOneWidget);
      expect(find.byKey(const Key('street-invite')), findsNothing);
      expect(find.byKey(const Key('street-sell')), findsNothing);
      await tester.tap(find.byKey(const Key('street-account')));
      await tester.pumpAndSettle();
      expect(find.text('Espace livreur'), findsOneWidget);
      expect(find.byKey(const Key('menu-create-business')), findsNothing);
      s.dispose();
    });

    testWidgets('a farmer reads « Ma ferme », an association « Mon association »', (tester) async {
      for (final (org, word) in [(_farm, 'Ma ferme'), (_assoc, 'Mon association')]) {
        final s = session0(orgs: [org]);
        await tester.runAsync(s.resolveOrgs);
        await street(tester, s, shopper: _Shopper(pending: false));
        expect(find.text(word), findsOneWidget);
        s.dispose();
      }
    });

    testWidgets('the invite card: at the top of the list, straight to the form, closed for good', (tester) async {
      final s = await noBusiness(tester);
      final router = await street(tester, s, shopper: _Shopper(pending: false));
      expect(find.byKey(const Key('street-invite')), findsOneWidget);
      expect(find.text('GRATUIT · 3 MINUTES'), findsOneWidget);
      expect(find.text('Vous vendez, élevez ou gérez une association ?'), findsOneWidget);
      for (final chip in ['Boutique', 'Ferme', 'Association']) {
        expect(find.descendant(of: find.byKey(const Key('street-invite')), matching: find.text(chip)),
            findsOneWidget);
      }
      // Above the shops.
      expect(tester.getRect(find.byKey(const Key('street-invite'))).top,
          lessThan(tester.getRect(find.text('Tony Pizza')).top));
      await tester.tap(find.byKey(const Key('street-invite-create')));
      await _settle(tester);
      expect(find.text('page ${Routes.createBusiness}'), findsOneWidget);

      router.go(Routes.directory);
      await _settle(tester);
      await tester.tap(find.byKey(const Key('street-invite-close')));
      await _settle(tester);
      expect(find.byKey(const Key('street-invite')), findsNothing);
      expect(await tester.runAsync(() => db.readPref('street_invite_closed')), '1');
      // The next visit on this device: still closed.
      await tester.pumpWidget(const SizedBox());
      await street(tester, s, shopper: _Shopper(pending: false));
      expect(find.byKey(const Key('street-invite')), findsNothing);
      s.dispose();
    });

    testWidgets('signed out: the card too; « Créer mon activité » goes by sign-in to the form', (tester) async {
      await tester.runAsync(db.clearIdentity);
      final s = SessionController(
        db: db,
        auth: AuthRepository(null),
        admin: AdminRepository(null),
        accounting: AccountingRepository(null),
      );
      await tester.runAsync(s.boot);
      expect(s.phase, SessionPhase.signedOut);
      await street(tester, s);
      expect(find.byKey(const Key('street-invite')), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
      s.dispose();
    });

    testWidgets('« Vous êtes ici pour… »: asked once; Vendre → the form', (tester) async {
      final s = await noBusiness(tester);
      final me = _Shopper();
      final router = await street(tester, s, shopper: me);
      expect(find.byKey(const Key('arrival')), findsOneWidget);
      expect(find.text('Vous êtes ici pour…'), findsOneWidget);
      for (final k in ['buy', 'sell', 'deliver']) {
        expect(find.byKey(Key('arrival-$k')), findsOneWidget);
      }
      expect(find.text('Je choisirai plus tard'), findsOneWidget);
      // « Vendre ou gérer » is the one chosen; Continuer.
      await tester.tap(find.byKey(const Key('arrival-continue')));
      await _settle(tester);
      expect(me.answers, ['sell']);
      expect(find.text('page ${Routes.createBusiness}'), findsOneWidget);
      // Back on the market: never asked again in this run.
      router.go(Routes.directory);
      await _settle(tester);
      expect(find.byKey(const Key('arrival')), findsNothing);
      expect(me.asked, 1);
      s.dispose();
    });

    testWidgets('« Livrer » → the courier\'s application; « plus tard » → the market', (tester) async {
      final s = await noBusiness(tester);
      final me = _Shopper();
      await street(tester, s, shopper: me);
      await tester.tap(find.byKey(const Key('arrival-deliver')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('arrival-continue')));
      await _settle(tester);
      expect(find.text('page ${Routes.becomeCourier}'), findsOneWidget);
      expect(me.answers, ['deliver']);

      forgetStreetArrival();
      final later = _Shopper();
      await street(tester, s, shopper: later);
      await tester.tap(find.byKey(const Key('arrival-later')));
      await _settle(tester);
      expect(later.answers, ['later']);
      expect(find.byKey(const Key('street-sell')), findsOneWidget, reason: 'back on the market');
      s.dispose();
    });

    testWidgets('never for somebody who has a business, nor when the server says it was answered',
        (tester) async {
      final member = session0(orgs: [_shop]);
      await tester.runAsync(member.resolveOrgs);
      final me = _Shopper();
      await street(tester, member, shopper: me);
      expect(find.byKey(const Key('arrival')), findsNothing);
      expect(me.asked, 0);
      member.dispose();

      final s = await noBusiness(tester);
      forgetStreetArrival();
      await street(tester, s, shopper: _Shopper(pending: false));
      expect(find.byKey(const Key('arrival')), findsNothing);
      s.dispose();
    });

    testWidgets('English: the invite and the question', (tester) async {
      final s = await noBusiness(tester);
      await _phone(tester, height: 1400);
      await tester.pumpWidget(scoped(
          s,
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
            home: Column(children: [
              StreetInviteCard(onCreate: () {}, onClose: () {}),
              Expanded(child: ArrivalScreen(shopper: _Shopper())),
            ]),
          )));
      await tester.pump();
      expect(find.text('FREE · 3 MINUTES'), findsOneWidget);
      expect(find.text('Create my business'), findsOneWidget);
      expect(find.text('You are here to…'), findsOneWidget);
      expect(find.text('Sell or manage'), findsOneWidget);
      s.dispose();
    });
  });
}
