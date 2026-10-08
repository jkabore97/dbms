import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/org_access.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
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
import 'package:kaj_app/core/l10n/locale_controller.dart';
import 'package:kaj_app/core/nav/app_scope.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/orders/orders.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/tontine/tontine_repository.dart';
import 'package:kaj_app/features/admin/org_settings_screen.dart';
import 'package:kaj_app/features/admin/vitrine_plus_card.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/farm/for_sale_screen.dart';
import 'package:kaj_app/features/orders/shop_orders_screen.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The vitrine's switches (110), from the app's side.
///
/// P1: with no rule — a vitrine whose style says nothing new, a business
/// whose feature_states hides nothing — the vitrine, the settings, the
/// dressing, the homes, « À vendre » and « Commandes » draw what they drew.
/// P2: each switch, hidden, takes its feature away where it is set up and
/// where the street sees it: « Commandes en ligne » makes the vitrine a
/// showcase (« Commandes fermées pour le moment », no « + », no « Réserver »,
/// no basket) and says so in Paramètres and Commandes; « Livraison » has no
/// part; « Paiement en ligne » no payout; « Mettre en avant » no card;
/// « Vitrine Plus » no Pro part; « Services et réservations » no « Mes
/// services »; « À vendre sur la vitrine » says the farm's list is off it.

const _shopOrg = OrgSummary(
    id: 'r1', name: 'Boutique Awa', slug: 'boutique-awa', profile: 'retail',
    roles: ['owner'], currency: 'XOF', visibility: 'full');
const _farmOrg = OrgSummary(
    id: 'f1', name: 'Ferme Ignace', slug: 'ferme-ignace', profile: 'farm',
    roles: ['owner'], visibility: 'full');
const _churchOrg = OrgSummary(
    id: 'c1', name: 'Grace Chapel', slug: 'grace', profile: 'church',
    roles: ['owner'], visibility: 'full');

/// The street: a shop with an article and a service, closed or not.
class _Window extends StorefrontRepository {
  _Window({this.closed = false}) : super(null);

  final bool closed;

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => PublicShop.fromRow({
        'org_id': 'r1',
        'name': 'Boutique Awa',
        'slug': slug,
        'profile': 'retail',
        'style': {if (closed) 'orders_closed': true},
      });

  @override
  Future<List<PublicItem>> items(String slug) async => const [
        PublicItem(id: 'p1', name: 'Savon', price: 450, inStock: true),
        PublicItem(id: 's1', name: 'Coiffure', price: 2000, inStock: true, isService: true),
      ];
}

/// The business: what feature_states says, and its settings' reads.
class _Admin extends AdminRepository {
  _Admin(this.hidden) : super(null);

  final Set<String> hidden;

  @override
  Future<bool> isPlatformAdmin() async => false;

  @override
  Future<int> claimMyInvitations() async => 0;

  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;

  @override
  Future<FeatureStates?> featureStates(String orgId) async =>
      FeatureStates.fromJson({'plan': 'free', 'wave_allowed': true, 'hidden': hidden.toList()});

  @override
  Future<Map<String, String>> featureRulesForTier(String orgId, String tier) async => const {};

  @override
  Future<Map<String, dynamic>> fetchOrg(String orgId) async => {
        'id': orgId,
        'name': 'Boutique Awa',
        'slug': 'boutique-awa',
        'profile': 'retail',
        'default_currency': 'XOF',
      };

  @override
  Future<String?> waveMerchant(String orgId) async => '+22670000000';

  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) async => const [];

  @override
  Future<
      ({
        bool enabled,
        String? blurb,
        double? lat,
        double? lng,
        double? deliveryBase,
        double? deliveryPerKm,
      })> storefront(String orgId) async => (
        enabled: true,
        blurb: 'Tout pour la maison' as String?,
        lat: 12.37 as double?,
        lng: -1.52 as double?,
        deliveryBase: 500.0 as double?,
        deliveryPerKm: 100.0 as double?,
      );

  @override
  Future<double?> deliveryReach(String orgId) async => null;

  @override
  Future<double?> deliveryIncludedKm(String orgId) async => null;

  @override
  Future<StorefrontStyle> storefrontStyle(String orgId) async => StorefrontStyle.none;
}

class _Server extends AuthRepository {
  _Server() : super(null);

  @override
  bool get hasLiveSession => true;

  @override
  Future<List<OrgSummary>> fetchOrgs() async => const [_shopOrg, _farmOrg, _churchOrg];
}

/// A shop with nothing in it, and its orders.
class _Shop extends RetailRepository {
  _Shop() : super(null);

  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();

  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) async => const [];

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [
        Product(id: 'e1', name: 'Plateau d\'œufs', salePrice: 2500, quantity: 12, isPublished: true),
      ];

  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {};

  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) async => 0;

  @override
  Future<int> pendingOrders(String orgId) async => 0;

  @override
  Future<List<ShopOrder>> shopOrders(String orgId) async => const [];

  @override
  Future<Map<String, OrderClock>> orderClocks(String orgId) async => const {};

  @override
  Future<List<CashOwed>> cashOwed(String orgId) async => const [];

  @override
  void Function() watchOrders(String orgId, void Function() onChange) => () {};
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() => db.close());

  /// A session that read [hidden] from feature_states for every business.
  Future<SessionController> session(WidgetTester tester, Set<String> hidden) async {
    final s = SessionController(
      db: db,
      auth: _Server(),
      admin: _Admin(hidden),
      accounting: AccountingRepository(null),
    );
    await tester.runAsync(() async {
      await s.resolveOrgs();
      for (final o in const [_shopOrg, _farmOrg, _churchOrg]) {
        await s.reloadFeatures(o.id);
      }
    });
    expect(s.accessFor('r1').platformHidden, hidden);
    return s;
  }

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
        retail: _Shop(),
        staff: StaffRepository(null),
        capture: CaptureRepository(null, db: db),
        onboarding: OnboardingRepository(null),
        credit: CreditRepository(null),
        tontine: TontineRepository(null),
        production: ProductionRepository(null),
        notify: NotificationsRepository(null),
        analytics: AnalyticsRepository(null),
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          home: child,
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('the vitrine', () {
    test('P1: a style that says nothing new is not closed', () {
      expect(StorefrontStyle.fromJson(const {}).ordersClosed, isFalse);
      expect(StorefrontStyle.fromJson(const {'delivers': true}).ordersClosed, isFalse);
      expect(StorefrontStyle.fromJson(const {'orders_closed': true}).ordersClosed, isTrue);
      final closed = StorefrontStyle.fromJson(const {'orders_closed': true, 'layout': 'list'});
      expect(closed.copyWith(layout: VitrineLayout.grid).ordersClosed, isTrue);
      expect(closed.isEmpty, isFalse);
      expect(StorefrontStyle.fromJson(const {'orders_closed': true}).isEmpty, isTrue,
          reason: 'closing is no dressing of the window');
    });

    Future<void> open(WidgetTester tester, {required bool closed}) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // A basket kept from an earlier visit.
      await tester.runAsync(() => db.writePref('street_basket_boutique-awa', '{"p1": 2}'));
      await tester.pumpWidget(MaterialApp(
        home: StorefrontScreen(
          slug: 'boutique-awa',
          storefront: _Window(closed: closed),
          capture: CaptureRepository(null, db: db),
          session: SessionController(
            db: db,
            auth: AuthRepository(null),
            admin: AdminRepository(null),
            accounting: AccountingRepository(null),
          ),
        ),
      ));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 800));
    }

    testWidgets('P1: open, it adds, books and keeps the basket', (tester) async {
      await open(tester, closed: false);
      expect(find.byKey(const Key('orders-closed')), findsNothing);
      expect(find.bySemanticsLabel('Ajouter un Savon au panier'), findsNothing,
          reason: 'the kept basket shows the stepper instead');
      expect(find.bySemanticsLabel('Ajouter un Savon'), findsWidgets);
      expect(find.byKey(const Key('book-service')), findsOneWidget);
      expect(find.text('Commander'), findsWidgets);
      expect(find.text('Touchez un article pour le voir, « + » pour l\'ajouter.'), findsOneWidget);
    });

    testWidgets('« Commandes en ligne » hidden: a showcase, no basket', (tester) async {
      await open(tester, closed: true);
      expect(find.byKey(const Key('orders-closed')), findsOneWidget);
      expect(find.text('Commandes fermées pour le moment'), findsWidgets);
      // The shelf is there; nothing to add, book or send.
      expect(find.text('Savon'), findsWidgets);
      expect(find.text('Coiffure'), findsWidgets);
      expect(find.bySemanticsLabel('Ajouter un Savon au panier'), findsNothing);
      expect(find.bySemanticsLabel('Ajouter un Savon'), findsNothing);
      expect(find.byKey(const Key('book-service')), findsNothing);
      expect(find.text('Commander'), findsNothing, reason: 'the kept basket is not restored');
      expect(find.text('Réserver'), findsNothing);
      expect(find.text('Touchez un article pour le voir.'), findsOneWidget);
      expect(find.text('Touchez un service pour le voir.'), findsOneWidget);
      // The article on its own: no « Ajouter au panier » either.
      await tester.tap(find.text('Savon').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Ajouter au panier'), findsNothing);
      expect(find.text('En stock'), findsOneWidget);
    });
  });

  group('Paramètres', () {
    Future<void> openSettings(WidgetTester tester, Set<String> hidden, {String? part}) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final s = await session(tester, hidden);
      await tester.pumpWidget(scoped(
          s,
          OrgSettingsScreen(
            admin: _Admin(hidden),
            orgId: 'r1',
            plan: 'pro',
            retail: _Shop(),
            initialPart: part,
          )));
      await settle(tester);
    }

    testWidgets('P1: no rule — Livraison, Paiements with the payout, Mettre en avant', (tester) async {
      await openSettings(tester, const {});
      expect(find.text('Livraison'), findsOneWidget);
      await tester.tap(find.text('Vitrine'));
      await settle(tester);
      expect(find.byKey(const Key('vitrine-spots')), findsOneWidget);
      expect(find.byKey(const Key('vitrine-orders-closed')), findsNothing);
      await tester.tap(find.byTooltip('Retour aux paramètres'));
      await settle(tester);
      await tester.tap(find.text('Paiements'));
      await settle(tester);
      expect(find.text('Recevoir les paiements des clients'), findsOneWidget);
    });

    testWidgets('hidden: no Livraison part, no payout, no spots, the orders said closed', (tester) async {
      await openSettings(tester, const {'delivery', 'online_payment', 'spots', 'online_orders'});
      expect(find.text('Livraison'), findsNothing);
      await tester.tap(find.text('Vitrine'));
      await settle(tester);
      expect(find.byKey(const Key('vitrine-spots')), findsNothing);
      expect(find.byKey(const Key('vitrine-orders-closed')), findsOneWidget);
      // The till's Wave stays: only Mara's online payout goes.
      await tester.tap(find.byTooltip('Retour aux paramètres'));
      await settle(tester);
      await tester.tap(find.text('Paiements'));
      await settle(tester);
      expect(find.byKey(const Key('wave-handle')), findsOneWidget);
      expect(find.text('Recevoir les paiements des clients'), findsNothing);
    });

    testWidgets('a hidden Livraison asked by its address opens the index', (tester) async {
      await openSettings(tester, const {'delivery'}, part: 'livraison');
      expect(find.byKey(const Key('delivery-mode')), findsNothing);
      expect(find.byKey(const Key('pro-lock-delivery')), findsNothing);
      expect(find.text('Vitrine'), findsOneWidget);
    });
  });

  group('Vitrine Plus', () {
    Future<void> card(WidgetTester tester, Set<String> hidden) async {
      tester.view.physicalSize = const Size(480, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final s = await session(tester, hidden);
      await tester.pumpWidget(scoped(
          s,
          Scaffold(
            body: SingleChildScrollView(
              child: VitrinePlusCard(orgId: 'r1', admin: _Admin(hidden)),
            ),
          )));
      await settle(tester);
    }

    testWidgets('P1: on Basic, the Pro part is there, locked', (tester) async {
      await card(tester, const {});
      expect(find.text('Voir Mara Pro'), findsOneWidget);
      expect(find.byKey(const Key('vitrine-plus-hidden')), findsNothing);
    });

    testWidgets('hidden: the free basics only, no door to Pro', (tester) async {
      await card(tester, const {'vitrine_plus'});
      expect(find.byKey(const Key('vitrine-plus-hidden')), findsOneWidget);
      expect(find.text('Voir Mara Pro'), findsNothing);
      expect(find.text('AVEC MARA PRO'), findsNothing);
      expect(find.text('POUR TOUTES LES VITRINES'), findsOneWidget);
      expect(find.byKey(const Key('dressing-save')), findsOneWidget);
    });
  });

  group('the homes, « À vendre » and « Commandes »', () {
    Widget store(OrgAccess a) => StoreHomeScreen(org: _shopOrg, retail: _Shop(), access: a);
    Widget farm(OrgAccess a) => FarmHomeScreen(db: db, org: _farmOrg, access: a);
    Widget church(OrgAccess a) => ChurchHomeScreen(
        db: db, orgId: _churchOrg.id, orgName: _churchOrg.name, org: _churchOrg,
        reports: ReportsRepository(null), retail: _Shop(), onHistory: () {}, access: a);

    Future<List<String>> places(WidgetTester tester) async {
      final labels = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((d) => d.label)
          .toList();
      if (labels.contains('Plus')) {
        await tester.tap(find.text('Plus'));
        await tester.pumpAndSettle();
        labels.addAll(tester
            .widgetList<ListTile>(find.byType(ListTile))
            .map((t) => (t.title as Text).data ?? ''));
        Navigator.of(tester.element(find.byType(ListTile).first)).pop();
        await tester.pumpAndSettle();
      }
      return labels;
    }

    testWidgets('« Mes services » leaves the shop, the farm and the association', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      Widget app(Widget home) => MaterialApp(
            locale: const Locale('fr'),
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
            home: home,
          );
      for (final build in [store, farm]) {
        await tester.pumpWidget(app(build(OrgAccess.allEdit)));
        await settle(tester);
        expect(await places(tester), contains('Mes services'));
        await tester.pumpWidget(app(build(const OrgAccess.admin(hidden: {}))));
        await settle(tester);
        expect(await places(tester), contains('Mes services'), reason: 'P1');
        await tester.pumpWidget(app(build(const OrgAccess.admin(hidden: {'services'}))));
        await settle(tester);
        final after = await places(tester);
        expect(after, isNot(contains('Mes services')));
        expect(after, contains('Compte'));
      }
      await tester.pumpWidget(app(church(const OrgAccess.admin(hidden: {}))));
      await settle(tester);
      expect(find.byKey(const Key('association-services')), findsOneWidget);
      await tester.pumpWidget(app(church(const OrgAccess.admin(hidden: {'services'}))));
      await settle(tester);
      expect(find.byKey(const Key('association-services')), findsNothing);
      expect(find.byKey(const Key('association-requests')), findsOneWidget,
          reason: 'the requests already sent are still answered');
    });

    testWidgets('« À vendre » says the farm\'s list is off the vitrine, and keeps it', (tester) async {
      for (final hidden in [const <String>{}, const {'for_sale'}]) {
        final s = await session(tester, hidden);
        await tester.pumpWidget(scoped(s, ForSaleScreen(org: _farmOrg, retail: _Shop())));
        await settle(tester);
        expect(find.byKey(const Key('for-sale-off-vitrine')),
            hidden.isEmpty ? findsNothing : findsOneWidget);
        expect(find.text('Plateau d\'œufs'), findsOneWidget);
        expect(find.byKey(const Key('for-sale-add')), findsOneWidget);
      }
    });

    testWidgets('« Commandes » says the vitrine takes none, and keeps the orders', (tester) async {
      for (final hidden in [const <String>{}, const {'online_orders'}]) {
        final s = await session(tester, hidden);
        await tester.pumpWidget(scoped(s, ShopOrdersScreen(org: _shopOrg, retail: _Shop())));
        await settle(tester);
        expect(find.byKey(const Key('orders-closed-note')),
            hidden.isEmpty ? findsNothing : findsOneWidget);
      }
    });
  });
}
