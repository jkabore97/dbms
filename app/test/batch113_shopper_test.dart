import 'dart:convert';
import 'dart:io';

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
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/credit/credit_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/l10n/locale_controller.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/nav/app_scope.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/orders/orders.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/shopper/shopper_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/tontine/tontine_repository.dart';
import 'package:kaj_app/features/account/compte_screen.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/admin/center/todo_section.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/features/orders/my_orders_screen.dart';
import 'package:kaj_app/features/shopper/addresses_screen.dart';
import 'package:kaj_app/features/shopper/favourites_screen.dart';
import 'package:kaj_app/features/shopper/shopper_profile_screen.dart';
import 'package:kaj_app/features/storefront/directory_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/// Batch 111, builder K (migration 113): the shopper's page — who they
/// are, their purchases, the vitrines they follow (♥ on the street and on
/// the vitrine), where they are delivered (picked in the order sheet), how
/// they like to pay (Wave only when the platform allows it: RULE M), help,
/// a report, their data and the account's deletion; a business's people
/// find « Mes achats » in their Compte; the platform reads the reports in
/// À faire.

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

  int deleted = 0;
  Object? refuse;
  bool accounts = true;

  @override
  bool get canManageAccounts => accounts;
  @override
  Future<bool> isPlatformAdmin() async => false;
  @override
  Future<int> claimMyInvitations() async => 0;
  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;
  @override
  Future<void> deleteMyAccount() async {
    final r = refuse;
    if (r != null) throw r;
    deleted++;
  }
}

/// 113's functions, as the server answers them — no network.
class _Shopper extends ShopperRepository {
  _Shopper(this.me) : super(null);

  ShopperProfile me;
  List<FollowedVitrine> followed = [];
  final settings = <Map<String, Object?>>[];
  final followedNow = <String>[];
  final letGo = <String>[];
  final news = <String, bool>{};
  final saved = <SavedAddress>[];
  final deleted = <String>[];
  final reports = <Map<String, String?>>[];
  final reordered = <String>[];
  ReorderBasket basket = const ReorderBasket(slug: 'boutique-awa');
  int exports = 0;

  @override
  bool get isConfigured => true;
  @override
  String? get picture => null;
  @override
  Future<ShopperProfile> profile() async => me;
  @override
  Future<void> setSettings({String? city, String? payment, bool? news}) async {
    settings.add({'city': city, 'payment': payment, 'news': news});
    me = ShopperProfile(
      name: me.name,
      phone: me.phone,
      verifiedPhone: me.verifiedPhone,
      verifyOn: me.verifyOn,
      city: city ?? me.city,
      waveAllowed: me.waveAllowed,
      payment: payment ?? me.payment,
      news: news ?? me.news,
      supportWhatsApp: me.supportWhatsApp,
      courier: me.courier,
      member: me.member,
      addresses: me.addresses,
      follows: me.follows,
    );
  }

  @override
  Future<List<FollowedVitrine>> follows() async => followed;
  @override
  Future<String> follow(String slug) async {
    followedNow.add(slug);
    followed = [...followed, FollowedVitrine(orgId: 'org-$slug', slug: slug, name: slug, profile: 'retail')];
    return 'org-$slug';
  }

  @override
  Future<void> unfollow(String orgId) async {
    letGo.add(orgId);
    followed = [for (final f in followed) if (f.orgId != orgId) f];
  }

  @override
  Future<void> setFollowNews(String orgId, bool on) async {
    news[orgId] = on;
    followed = [
      for (final f in followed)
        f.orgId == orgId
            ? FollowedVitrine(orgId: f.orgId, slug: f.slug, name: f.name, profile: f.profile, news: on)
            : f,
    ];
  }

  @override
  Future<List<SavedAddress>> addresses() async => me.addresses;
  @override
  Future<String> saveAddress(SavedAddress a) async {
    saved.add(a);
    return 'a-new';
  }

  @override
  Future<void> deleteAddress(String id) async => deleted.add(id);
  @override
  Future<ReorderBasket> reorder(String orderId) async {
    reordered.add(orderId);
    return basket;
  }

  @override
  Future<void> report({required String topic, required String message, String? slug, String? orderId}) async {
    reports.add({'topic': topic, 'message': message, 'slug': slug, 'order': orderId});
  }

  @override
  Future<String> exportData() async {
    exports++;
    return '{"profile": {}}';
  }
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
  _Street() : super(null);

  @override
  bool get isConfigured => true;
  @override
  Future<KeptStreet?> keptStreet() async => null;
  @override
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) async => const [
        DirectoryEntry(orgId: 'o1', name: 'Boutique Awa', slug: 'boutique-awa', profile: 'retail'),
        DirectoryEntry(orgId: 'o2', name: 'Ferme Ignace', slug: 'ferme-ignace', profile: 'farm'),
        DirectoryEntry(orgId: 'o3', name: 'Entraide', slug: 'entraide', profile: 'association'),
      ];
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
  @override
  Future<PublicShop?> shop(String slug) async =>
      PublicShop(orgId: 'o1', name: 'Boutique Awa', slug: slug, profile: 'retail');
  @override
  Future<List<PublicItem>> items(String slug) async =>
      const [PublicItem(id: 'p1', name: 'Savon', price: 500, inStock: true)];
  @override
  Future<KeptVitrine?> keptVitrine(String slug) async => null;
  @override
  Future<void> recordVisit(String slug, String kind, {String? productId}) async {}
  @override
  Future<void> recordVisitor(String slug, String visitorId) async {}
}

class _Center extends CommandCenterRepository {
  _Center() : super(null);

  final closed = <String, String?>{};
  List<ProblemReport> open = const [
    ProblemReport(
      id: 'r1',
      topic: 'order',
      message: 'Les œufs sont arrivés cassés.',
      reporter: 'Awa Ouédraogo',
      contact: '+22670113005',
      orgId: 'o2',
      orgName: 'Ferme Ignace',
    ),
  ];

  @override
  Future<PlatformTodo> todo() async => const PlatformTodo({'reports_open': 1});
  @override
  Future<List<ProblemReport>> reports({bool handled = false}) async => handled ? const [] : open;
  @override
  Future<String?> handleReport(String id, {String? answer}) async {
    closed[id] = answer;
    open = const [];
    return 'action-1';
  }
}

const _awa = User(
  id: 'awa-1',
  appMetadata: {'provider': 'google'},
  userMetadata: {'full_name': 'Awa Ouédraogo'},
  aud: 'authenticated',
  email: 'awa@example.com',
  createdAt: '2026-10-08T00:00:00Z',
);

const _home = SavedAddress(
  id: 'a1', kind: 'home', address: 'Ouaga 2000, près de l\'école', note: 'Portail bleu', lat: 12.33, lng: -1.51);
const _work = SavedAddress(id: 'a2', kind: 'work', address: 'Zone du bois');

ShopperProfile _profile({
  bool wave = false,
  String payment = 'cash',
  String? verified = '+22670113005',
  bool verifyOn = false,
  String? support,
  String? courier,
  bool member = false,
  List<SavedAddress> addresses = const [],
}) =>
    ShopperProfile(
      name: 'Awa Ouédraogo',
      phone: '+22670113005',
      verifiedPhone: verified,
      verifyOn: verifyOn,
      waveAllowed: wave,
      payment: wave ? payment : 'cash',
      supportWhatsApp: support,
      courier: courier,
      member: member,
      addresses: addresses,
      follows: 2,
      ordersOpen: 1,
    );

CustomerOrder _order(String id, String status, {bool service = false, String slug = 'boutique-awa'}) => CustomerOrder(
      id: id,
      shopName: 'Boutique Awa',
      shopSlug: slug,
      status: status,
      fulfilment: 'pickup',
      total: 1000,
      currency: 'XOF',
      createdAt: DateTime(2026, 10, 1, 10),
      lines: [OrderLine(name: service ? 'Coupe' : 'Savon', unitPrice: 500, quantity: 2, isService: service)],
    );

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

  Future<SessionController> shopper(WidgetTester tester, {_Admin? admin}) async {
    final s = SessionController(
      db: db,
      auth: _Server(),
      admin: admin ?? _Admin(),
      accounting: AccountingRepository(null),
    );
    await tester.runAsync(s.resolveOrgs);
    expect(s.phase, SessionPhase.noOrg);
    return s;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The app's scope around a little router, at [at].
  Future<GoRouter> pump(
    WidgetTester tester,
    SessionController session, {
    required String at,
    required List<RouteBase> routes,
    Size size = const Size(390, 844),
    Locale locale = const Locale('fr'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final stub = [
      for (final p in [
        Routes.myOrders, Routes.bookings, Routes.favourites, Routes.addresses, Routes.myNotifications,
        Routes.language, Routes.becomeCourier, Routes.courier, Routes.createBusiness, Routes.myProfile,
        Routes.faq, Routes.privacy, Routes.terms, Routes.directory, '/s/:slug',
      ])
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
        locale: locale,
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
      ),
    ));
    await settle(tester);
    return router;
  }

  Future<GoRouter> profilePage(WidgetTester tester, SessionController s, _Shopper me) => pump(tester, s,
      at: Routes.shopperProfile,
      routes: [GoRoute(path: Routes.shopperProfile, builder: (_, _) => ShopperProfileScreen(shopper: me))]);

  Future<void> tapRow(WidgetTester tester, String key) async {
    await tester.scrollUntilVisible(find.byKey(Key(key)), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  group('the page', () {
    testWidgets('a shopper: the header, the four purchases, cash only while Wave is not allowed, no help row nor verify link until set up',
        (tester) async {
      final me = _Shopper(_profile());
      await profilePage(tester, await shopper(tester), me);
      expect(find.text('Mon profil'), findsWidgets);
      expect(find.text('Awa Ouédraogo'), findsOneWidget);
      expect(find.text('+22670113005 · WhatsApp vérifié'), findsOneWidget);
      expect(find.byKey(const Key('shopper-verify')), findsNothing);
      expect(find.text('Ajouter ma ville'), findsOneWidget);
      for (final row in ['Mes commandes', 'Mes réservations', 'Mes vitrines favorites', 'Mes adresses de livraison']) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      expect(find.text('1 en cours'), findsOneWidget);
      // RULE M: no Wave drawn at all, not even greyed.
      await tester.scrollUntilVisible(find.byKey(const Key('shopper-payment-cash')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Wave'), findsNothing);
      expect(find.byKey(const Key('shopper-payment')), findsNothing);
      await tester.scrollUntilVisible(find.byKey(const Key('shopper-report')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const Key('shopper-support')), findsNothing);
      expect(find.text('Devenir livreur'), findsOneWidget);
      expect(find.text('Créer mon activité'), findsOneWidget);
    });

    testWidgets('Wave allowed: chosen and saved; the help number and the verify link appear once set',
        (tester) async {
      final me = _Shopper(_profile(wave: true, verified: null, verifyOn: true, support: '22670113000'));
      await profilePage(tester, await shopper(tester), me);
      expect(find.byKey(const Key('shopper-verify')), findsOneWidget);
      expect(find.text('+22670113005'), findsOneWidget, reason: 'the typed number, not said proved');
      await tester.scrollUntilVisible(find.byKey(const Key('shopper-payment')), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Wave'));
      await settle(tester);
      expect(me.settings.last['payment'], 'wave');
      await tester.scrollUntilVisible(find.byKey(const Key('shopper-support')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Écrire à Mara sur WhatsApp'), findsOneWidget);
    });

    testWidgets('each row opens its page; a courier reads « Espace livreur »; a member is not offered « Créer mon activité »',
        (tester) async {
      final me = _Shopper(_profile());
      final router = await profilePage(tester, await shopper(tester), me);
      final rows = {
        'shopper-orders': Routes.myOrders,
        'shopper-bookings': Routes.bookings,
        'shopper-favourites': Routes.favourites,
        'shopper-addresses': Routes.addresses,
        'shopper-notifications': Routes.myNotifications,
        'shopper-language': Routes.language,
        'shopper-courier': Routes.becomeCourier,
        'shopper-create': Routes.createBusiness,
        'shopper-name': Routes.myProfile,
      };
      for (final e in rows.entries) {
        await tapRow(tester, e.key);
        expect(find.text('page ${e.value}'), findsOneWidget, reason: e.key);
        router.pop();
        await settle(tester);
      }

      me.me = _profile(courier: 'approved', member: true);
      await profilePage(tester, await shopper(tester), me);
      await tester.scrollUntilVisible(find.byKey(const Key('shopper-courier')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Espace livreur'), findsOneWidget);
      expect(find.byKey(const Key('shopper-create')), findsNothing);
      await tapRow(tester, 'shopper-courier');
      expect(find.text('page ${Routes.courier}'), findsOneWidget);
    });

    testWidgets('the city: picked or typed, saved', (tester) async {
      final me = _Shopper(_profile());
      await profilePage(tester, await shopper(tester), me);
      await tester.tap(find.byKey(const Key('shopper-city')));
      await settle(tester);
      await tester.tap(find.text('Bobo-Dioulasso'));
      await settle(tester);
      expect(me.settings.last['city'], 'Bobo-Dioulasso');
      expect(find.text('Bobo-Dioulasso'), findsOneWidget);
    });

    testWidgets('« Signaler un problème »: too short is said; sent with its topic', (tester) async {
      final me = _Shopper(_profile());
      await profilePage(tester, await shopper(tester), me);
      await tapRow(tester, 'shopper-report');
      expect(find.text('De quoi s\'agit-il ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-delivery')));
      await tester.enterText(find.byKey(const Key('report-text')), 'Trop');
      await tester.tap(find.byKey(const Key('report-send')));
      await settle(tester);
      expect(find.text('Dites en quelques mots ce qui ne va pas (10 caractères au moins).'), findsOneWidget);
      expect(me.reports, isEmpty);
      await tester.enterText(find.byKey(const Key('report-text')), 'Le livreur ne trouve pas ma maison.');
      await tester.tap(find.byKey(const Key('report-send')));
      await settle(tester);
      expect(me.reports.single, {'topic': 'delivery', 'message': 'Le livreur ne trouve pas ma maison.', 'slug': null, 'order': null});
      expect(find.text('Merci : Mara a reçu votre signalement et vous répondra dans vos notifications.'), findsOneWidget);
    });

    testWidgets('« Supprimer mon compte »: the word first; the server\'s refusal said; done, signed out', (tester) async {
      final admin = _Admin()
        ..refuse = StateError('Une commande est en cours : attendez qu\'elle soit terminée, ou annulez-la, puis supprimez votre compte.');
      final session = await shopper(tester, admin: admin);
      final me = _Shopper(_profile());
      await profilePage(tester, session, me);
      await tapRow(tester, 'shopper-delete');
      final confirm = find.byKey(const Key('delete-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull, reason: 'nothing before the word');
      await tester.enterText(find.byKey(const Key('delete-word')), 'supprimer');
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await settle(tester);
      expect(find.text('Une commande est en cours : attendez qu\'elle soit terminée, ou annulez-la, puis supprimez votre compte.'),
          findsOneWidget);
      expect(admin.deleted, 0);
      admin.refuse = null;
      await tester.tap(confirm);
      await settle(tester);
      expect(admin.deleted, 1);
      expect(session.phase, SessionPhase.signedOut);
    });

    testWidgets('« Supprimer mon compte » with no account Worker says how, and deletes nothing', (tester) async {
      final admin = _Admin()..accounts = false;
      final me = _Shopper(_profile());
      await profilePage(tester, await shopper(tester, admin: admin), me);
      await tapRow(tester, 'shopper-delete');
      await tester.enterText(find.byKey(const Key('delete-word')), 'SUPPRIMER');
      await tester.pump();
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await settle(tester);
      expect(find.text('La suppression en ligne n\'est pas encore ouverte : écrivez à Mara et votre compte sera supprimé.'),
          findsOneWidget);
      expect(admin.deleted, 0);
    });

    testWidgets('« Télécharger mes données » asks the server for the caller\'s own', (tester) async {
      final me = _Shopper(_profile());
      await profilePage(tester, await shopper(tester), me);
      await tapRow(tester, 'shopper-download');
      expect(me.exports, 1);
    });

    testWidgets('in English, the page reads English', (tester) async {
      final me = _Shopper(_profile());
      await pump(tester, await shopper(tester),
          at: Routes.shopperProfile,
          locale: const Locale('en'),
          routes: [GoRoute(path: Routes.shopperProfile, builder: (_, _) => ShopperProfileScreen(shopper: me))]);
      expect(find.text('My purchases'), findsOneWidget);
      expect(find.text('My favourite vitrines'), findsOneWidget);
    });
  });

  group('the vitrines followed', () {
    testWidgets('each its news switch, all at once, and let go with « Suivre à nouveau »', (tester) async {
      final me = _Shopper(_profile())
        ..followed = const [
          FollowedVitrine(orgId: 'o1', slug: 'boutique-awa', name: 'Boutique Awa', profile: 'retail'),
          FollowedVitrine(orgId: 'o2', slug: 'ferme-ignace', name: 'Ferme Ignace', profile: 'farm', open: false),
        ];
      await pump(tester, await shopper(tester),
          at: Routes.favourites,
          routes: [GoRoute(path: Routes.favourites, builder: (_, _) => FavouritesScreen(shopper: me))]);
      expect(find.text('Boutique Awa'), findsOneWidget);
      expect(find.text('Ferme · fermée pour le moment'), findsOneWidget);
      await tester.tap(find.byKey(const Key('news-boutique-awa')));
      await settle(tester);
      expect(me.news['o1'], isFalse);
      await tester.tap(find.byKey(const Key('news-all')));
      await settle(tester);
      expect(me.settings.last['news'], isFalse);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('news-ferme-ignace'))).onChanged, isNull,
          reason: 'all off: each switch waits');
      await tester.tap(find.byKey(const Key('unfollow-boutique-awa')));
      await settle(tester);
      expect(me.letGo, ['o1']);
      expect(find.text('Boutique Awa'), findsNothing);
      await tester.tap(find.text('Suivre à nouveau'));
      await settle(tester);
      expect(me.followedNow, ['boutique-awa']);
      expect(me.news['org-boutique-awa'], isFalse, reason: 'its news off as it was');
    });

    testWidgets('the street: a heart on every card for a shopper, the followed ones filled; tapping follows', (tester) async {
      final me = _Shopper(_profile())
        ..followed = const [FollowedVitrine(orgId: 'o2', slug: 'ferme-ignace', name: 'Ferme Ignace', profile: 'farm')];
      final session = await shopper(tester);
      await pump(tester, session, at: Routes.directory, routes: [
        GoRoute(
          path: Routes.directory,
          builder: (_, _) => DirectoryScreen(
            storefront: _Street(),
            capture: CaptureRepository(null, db: db),
            session: session,
            shopper: me,
          ),
        ),
      ]);
      expect(find.byKey(const Key('heart-boutique-awa')), findsOneWidget);
      expect(find.byKey(const Key('heart-ferme-ignace')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('heart-ferme-ignace')), matching: find.byIcon(Icons.favorite)),
          findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('heart-entraide')));
      await tester.tap(find.byKey(const Key('heart-entraide')));
      await settle(tester);
      expect(me.followedNow, ['entraide']);
      expect(find.text('Vitrine suivie : ses nouveautés et ses offres vous seront dites.'), findsOneWidget);
    });

    testWidgets('the street of a stranger (no repository) has no heart', (tester) async {
      final session = await shopper(tester);
      await pump(tester, session, at: Routes.directory, routes: [
        GoRoute(
          path: Routes.directory,
          builder: (_, _) => DirectoryScreen(
            storefront: _Street(),
            capture: CaptureRepository(null, db: db),
            session: session,
          ),
        ),
      ]);
      expect(find.text('Boutique Awa'), findsWidgets);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    });

    testWidgets('the vitrine: ♥ beside the name', (tester) async {
      final me = _Shopper(_profile());
      final session = await shopper(tester);
      await pump(tester, session, at: Routes.storefront('boutique-awa'), routes: [
        GoRoute(
          path: '/s/:slug',
          builder: (_, state) => StorefrontScreen(
            slug: state.pathParameters['slug']!,
            storefront: _Street(),
            capture: CaptureRepository(null, db: db),
            session: session,
            shopper: me,
          ),
        ),
      ]);
      await tester.tap(find.byKey(const Key('heart-boutique-awa')));
      await settle(tester);
      expect(me.followedNow, ['boutique-awa']);
      expect(find.descendant(of: find.byKey(const Key('heart-boutique-awa')), matching: find.byIcon(Icons.favorite)),
          findsOneWidget);
    });
  });

  group('where to deliver', () {
    testWidgets('a home: the words required; Maison and Travail once each', (tester) async {
      final me = _Shopper(_profile(addresses: const [_work]));
      await pump(tester, await shopper(tester),
          at: Routes.addresses,
          routes: [GoRoute(path: Routes.addresses, builder: (_, _) => AddressesScreen(shopper: me, tiles: false))]);
      expect(find.text('Travail'), findsOneWidget);
      await tester.tap(find.byKey(const Key('address-add')));
      await settle(tester);
      // Travail is taken: the new one starts as Maison, Travail not offered.
      final kinds = tester.widget<SegmentedButton<String>>(find.byKey(const Key('address-kind')));
      expect(kinds.selected, {'home'});
      expect(kinds.segments.firstWhere((s) => s.value == 'work').enabled, isFalse);
      await tester.tap(find.byKey(const Key('address-save')));
      await settle(tester);
      expect(find.text('Dites où livrer : le quartier, un repère.'), findsOneWidget);
      expect(me.saved, isEmpty);
      await tester.enterText(find.byKey(const Key('address-words')), 'Ouaga 2000');
      await tester.enterText(find.byKey(const Key('address-note')), 'Portail bleu');
      await tester.tap(find.byKey(const Key('address-save')));
      await settle(tester);
      expect(me.saved.single.kind, 'home');
      expect(me.saved.single.address, 'Ouaga 2000');
      expect(me.saved.single.note, 'Portail bleu');
      expect(me.saved.single.lat, isNull);
    });

    testWidgets('the order sheet: « Livraison » picks the first saved place with its pin, a chip the other; Wave first only when preferred and taken',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final quoted = <String>[];
      Widget sheet({List<SavedAddress> addresses = const [], String preferred = 'cash', String? wave}) => MaterialApp(
            home: Scaffold(
              body: OrderSheet(
                items: const [PublicItem(id: 'p1', name: 'Savon', price: 500, inStock: true)],
                basket: const {'p1': 1},
                currency: 'XOF',
                waveMerchant: wave,
                addresses: addresses,
                preferredPayment: preferred,
                onSubmit: ({required lines, required fulfilment, note, address, phone, required payment, dropLat, dropLng}) async => null,
                quote: (lat, lng) async {
                  quoted.add('$lat,$lng');
                  return const DeliveryCheck(fee: 750);
                },
              ),
            ),
          );
      await tester.pumpWidget(sheet(addresses: const [_home, _work], preferred: 'wave', wave: 'M1'));
      final payment = tester.widget<SegmentedButton<String>>(find.byWidgetPredicate(
          (w) => w is SegmentedButton<String> && w.segments.any((s) => s.value == 'wave')));
      expect(payment.selected, {'wave'});
      await tester.tap(find.text('Livraison').first);
      await tester.pumpAndSettle();
      expect(find.text('Ouaga 2000, près de l\'école — Portail bleu'), findsOneWidget);
      expect(quoted, ['12.33,-1.51']);
      expect(find.text('750 FCFA'), findsWidgets);
      await tester.tap(find.byKey(const Key('order-address-1')));
      await tester.pumpAndSettle();
      expect(find.text('Zone du bois'), findsOneWidget);

      // Wave preferred but this vitrine does not take it: no payment row.
      await tester.pumpWidget(sheet(preferred: 'wave'));
      expect(find.text('Wave'), findsNothing);
      // P1: no saved place, cash — the sheet as before, no chips.
      await tester.pumpWidget(sheet());
      await tester.tap(find.text('Livraison').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-addresses')), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const Key('order-address'))).controller!.text, isEmpty);
    });
  });

  group('my orders', () {
    testWidgets('« Recommander » fills the vitrine\'s basket (kept items stay) and opens it, saying what is gone; not on an open order',
        (tester) async {
      await tester.runAsync(() => db.writePref('street_basket_boutique-awa', jsonEncode({'p9': 1.0})));
      final me = _Shopper(_profile())
        ..basket = const ReorderBasket(slug: 'boutique-awa', lines: {'p1': 2}, missing: 1);
      await pump(tester, await shopper(tester), at: Routes.myOrders, routes: [
        GoRoute(
          path: Routes.myOrders,
          builder: (_, _) => MyOrdersScreen(
            storefront: _Orders([_order('open-1', 'pending'), _order('done-1', 'picked_up')]),
            shopper: me,
          ),
        ),
      ]);
      expect(find.byKey(const Key('again-open-1')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('again-done-1')));
      await tester.tap(find.byKey(const Key('again-done-1')));
      await settle(tester);
      expect(me.reordered, ['done-1']);
      expect(find.text('page /s/boutique-awa'), findsOneWidget);
      expect(find.text('Votre panier est prêt. 1 article(s) de la commande ne sont plus disponibles.'), findsOneWidget);
      final kept = await tester.runAsync(() => db.readPref('street_basket_boutique-awa'));
      expect(jsonDecode(kept!), {'p9': 1.0, 'p1': 2.0});
    });

    testWidgets('a vitrine that takes no orders: said, nothing written', (tester) async {
      final me = _Shopper(_profile())..basket = const ReorderBasket(slug: 'boutique-awa', closed: true, missing: 1);
      await pump(tester, await shopper(tester), at: Routes.myOrders, routes: [
        GoRoute(
          path: Routes.myOrders,
          builder: (_, _) => MyOrdersScreen(storefront: _Orders([_order('done-1', 'picked_up')]), shopper: me),
        ),
      ]);
      await tester.ensureVisible(find.byKey(const Key('again-done-1')));
      await tester.tap(find.byKey(const Key('again-done-1')));
      await settle(tester);
      expect(find.text('Cette vitrine ne prend pas de commandes pour le moment.'), findsOneWidget);
      expect(await tester.runAsync(() => db.readPref('street_basket_boutique-awa')), isNull);
    });

    testWidgets('« Mes réservations »: the bookings only, « Réserver à nouveau »', (tester) async {
      await pump(tester, await shopper(tester), at: Routes.bookings, routes: [
        GoRoute(
          path: Routes.bookings,
          builder: (_, _) => MyOrdersScreen(
            storefront: _Orders([_order('goods-1', 'picked_up'), _order('book-1', 'picked_up', service: true)]),
            shopper: _Shopper(_profile()),
            bookingsOnly: true,
          ),
        ),
      ]);
      expect(find.text('Mes réservations'), findsWidgets);
      expect(find.text('2 × Coupe'), findsOneWidget);
      expect(find.text('2 × Savon'), findsNothing);
      expect(find.text('Réserver à nouveau'), findsOneWidget);
    });

    testWidgets('P1: with no repository, « Mes commandes » is what it was — no « Recommander »', (tester) async {
      await pump(tester, await shopper(tester), at: Routes.myOrders, routes: [
        GoRoute(
          path: Routes.myOrders,
          builder: (_, _) => MyOrdersScreen(storefront: _Orders([_order('done-1', 'picked_up')])),
        ),
      ]);
      expect(find.text('2 × Savon'), findsOneWidget);
      expect(find.text('Recommander'), findsNothing);
    });
  });

  group('the bell', () {
    test('a followed vitrine\'s news opens the vitrine; a report answered opens nothing more', () {
      final news = NotificationRow(
        id: 'n1', kind: 'vitrine_news', message: 'Nouveau chez Boutique Awa : Huile',
        createdAt: DateTime(2026, 10, 8), orgId: 'o1',
        params: const {'slug': 'boutique-awa', 'shop': 'Boutique Awa', 'count': 1, 'names': ['Huile']},
      );
      expect(notificationTarget(news, isAdminOf: (_) => false), Routes.storefront('boutique-awa'));
      final answered = NotificationRow(
        id: 'n2', kind: 'report_handled', message: 'Mara a traité votre signalement.', createdAt: DateTime(2026, 10, 8));
      expect(notificationTarget(answered), isNull);
    });

    testWidgets('in English: new, several, an offer', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      NotificationRow row(Map<String, dynamic> p) =>
          NotificationRow(id: 'n', kind: 'vitrine_news', message: 'fr', createdAt: DateTime(2026), params: p);
      expect(notificationLine(ctx, row(const {'shop': 'Awa', 'count': 1, 'names': ['Oil']})), 'New at Awa: Oil');
      expect(notificationLine(ctx, row(const {'shop': 'Awa', 'count': 4, 'names': ['Oil', 'Tea', 'Rice']})),
          '4 new at Awa: Oil, Tea, Rice…');
      expect(notificationLine(ctx, row(const {'shop': 'Awa', 'count': 1, 'names': ['Soap'], 'offer': true, 'price': 450, 'currency': 'XOF'})),
          startsWith('Price down at Awa: Soap at 450'));
    });
  });

  group('the business\'s people and the platform', () {
    for (final (profile, name) in [('retail', 'Boutique Awa'), ('farm', 'Ferme Ignace'), ('association', 'Entraide')]) {
      testWidgets('Compte of a $profile has « Mes achats »: orders, favourites, addresses', (tester) async {
        final session = await shopper(tester);
        final org = OrgSummary(id: 'o1', name: name, profile: profile, roles: const ['owner']);
        await pump(tester, session, at: '/compte', routes: [
          GoRoute(path: '/compte', builder: (_, _) => CompteScreen(org: org)),
        ]);
        await tester.tap(find.byKey(const Key('group-Mes achats')));
        await settle(tester);
        await tester.tap(find.byKey(const Key('compte-favourites')));
        await settle(tester);
        expect(find.text('page ${Routes.favourites}'), findsOneWidget);
      });
    }

    testWidgets('À faire « Signalements »: the report read, closed with a word, « Annuler » offered', (tester) async {
      final center = _Center();
      await pump(tester, await shopper(tester), at: '/console', size: const Size(1280, 900), routes: [
        GoRoute(path: '/console', builder: (_, _) => TodoSection(center: center, admin: _Admin())),
      ]);
      final tile = find.byKey(const Key('todo-reports_open'));
      expect(find.descendant(of: tile, matching: find.text('Signalements')), findsOneWidget);
      await tester.tap(tile);
      await settle(tester);
      expect(find.text('Les œufs sont arrivés cassés.'), findsOneWidget);
      expect(find.text('Ferme Ignace'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-close-r1')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('report-answer')), 'Remboursé par la ferme.');
      await tester.tap(find.byKey(const Key('report-answer-send')));
      await settle(tester);
      expect(center.closed, {'r1': 'Remboursé par la ferme.'});
      expect(find.text('Signalement traité : la personne est prévenue.'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
    });

    test('Réglages lists the help number, in its own group', () {
      final def = platformSettingDefs.where((d) => d.key == 'support_whatsapp').single;
      expect(def.type, SettingType.text);
      expect(def.group, 'help');
    });

    test('the router: the shopper\'s pages are the street\'s half and open in every signed-in phase', () {
      final src = File('lib/core/nav/router.dart').readAsStringSync();
      expect(src, contains("static const shopperProfile = '/mon-compte';"));
      expect(RegExp(r'at\(Routes\.shopperProfile\) \|\|').allMatches(src).length, 3,
          reason: 'noOrg, picking and ready');
      final street = src.substring(src.indexOf('bool _shopperPath'), src.indexOf('Future<bool>? _businessScreens'));
      expect(street, contains('Routes.shopperProfile,'));
      for (final child in ["path: 'vitrines'", "path: 'adresses'", "path: 'reservations'", "path: 'notifications'"]) {
        expect(src, contains(child));
      }
      expect(src, contains('shopper: ShopperRepository(scope.auth.client)'));
    });

    test('every refusal 113 says reads in English too', () {
      final sql = File('../database/migrations/113_shopper_profile.sql').readAsStringSync();
      final said = <String>{
        for (final m in RegExp(r"raise exception '((?:[^']|'')*)'").allMatches(sql))
          if (!m.group(1)!.contains('%')) m.group(1)!.replaceAll("''", "'"),
        for (final m in RegExp(r"(?:then|else) '((?:[^']|'')*)' end;").allMatches(sql))
          m.group(1)!.replaceAll("''", "'"),
      };
      expect(said.length, greaterThan(25));
      final untranslated = [for (final fr in said) if (translate('en', fr) == fr) fr];
      expect(untranslated, isEmpty, reason: 'add these to lib/core/l10n/en.dart');
    });
  });
}
