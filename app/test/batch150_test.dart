// Batch 150: App Store guideline 1.2 — from a vitrine itself, a way to
// report it and a way to stop seeing it. For a shop, a farm and an
// association alike (every kind has a vitrine).
//
//   1. the ⋮ in the vitrine's header: a visitor (signed out or in) sees it;
//      the business's own people and Mara's admin do not;
//   2. « Signaler cette vitrine »: signed in, the report sheet about this
//      vitrine (topic 'vitrine', its slug), sent as such; signed out, the
//      sign-in doors with « ou écrivez-nous », and back signed in the sheet
//      opens by itself;
//   3. « Masquer cette vitrine »: one question, then back to the street —
//      gone from the list, « À la une », the paid spots and the search; its
//      link says « Vous avez masqué cette vitrine », « Afficher à nouveau »
//      brings it back;
//   4. « Vitrines masquées »: the street's foot and the profile lead to the
//      list, which shows them again;
//   5. kept across restarts (the device's preferences);
//   6. the console's Signalements: the vitrine named, « Voir la vitrine »
//      and « Suspendre… » (the existing control);
//   7. English, and 320 px × 1.3.
//
// B150_SHOTS=<dir> also writes the screenshots.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
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
import 'package:kaj_app/core/nav/app_scope.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/shopper/shopper_repository.dart';
import 'package:kaj_app/core/storefront/hidden_vitrines.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/tontine/tontine_repository.dart';
import 'package:kaj_app/features/account/support.dart';
import 'package:kaj_app/features/admin/center/reports_sheet.dart';
import 'package:kaj_app/features/shopper/hidden_vitrines_screen.dart';
import 'package:kaj_app/features/shopper/report_sheet.dart';
import 'package:kaj_app/features/shopper/shopper_profile_screen.dart';
import 'package:kaj_app/features/storefront/booking_sheet.dart' show streetResumeKey;
import 'package:kaj_app/features/storefront/directory_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// The street: a shop, a farm, an association (no person's first name;
// Ouagadougou the only town).
// ---------------------------------------------------------------------------

const _shopSlug = 'atelier-lumiere';
const _farmSlug = 'ferme-horizon-vert';
const _clubSlug = 'fondation-espoir';

const _shops = {
  _shopSlug: PublicShop(
      orgId: 'b150-shop', name: 'Atelier Lumière', slug: _shopSlug, profile: 'retail',
      address: 'Ouagadougou', style: StorefrontStyle(tagline: 'La lumière du quartier')),
  _farmSlug: PublicShop(
      orgId: 'b150-farm', name: 'Ferme Horizon Vert', slug: _farmSlug, profile: 'farm',
      address: 'Ouagadougou'),
  _clubSlug: PublicShop(
      orgId: 'b150-club', name: 'Fondation Espoir', slug: _clubSlug, profile: 'association',
      address: 'Ouagadougou'),
};

const _goods = {
  _shopSlug: [PublicItem(id: 'p-savon', name: 'Savon karité', price: 500, inStock: true)],
  _farmSlug: [PublicItem(id: 'p-sac', name: 'Sac de mil', price: 9000, inStock: true)],
  _clubSlug: [PublicItem(id: 'p-livre', name: 'Livre solidaire', price: 2500, inStock: true)],
};

const _ownShop = OrgSummary(
    id: 'b150-shop', name: 'Atelier Lumière', slug: _shopSlug, profile: 'retail',
    roles: ['owner'], currency: 'XOF', visibility: 'full');

OrgSummary _as(OrgSummary o, List<String> roles) => OrgSummary(
    id: o.id, name: o.name, slug: o.slug, profile: o.profile, plan: o.plan,
    roles: roles, currency: o.currency, visibility: o.visibility);

class _Street extends StorefrontRepository {
  _Street() : super(null);

  final seen = <String>[];

  @override
  bool get isConfigured => true;
  @override
  Future<PublicShop?> shop(String slug) async => _shops[slug];
  @override
  Future<List<PublicItem>> items(String slug) async => _goods[slug] ?? const [];
  @override
  Future<Set<String>> showcaseSlugs() async => const {};
  @override
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) async => [
        for (final s in _shops.values)
          DirectoryEntry(orgId: s.orgId, name: s.name, slug: s.slug, profile: s.profile, address: s.address),
      ];
  @override
  Future<List<FeaturedItem>> featured({double? lat, double? lng}) async => [
        for (final s in _shops.values)
          FeaturedItem(
              id: _goods[s.slug]!.single.id,
              name: _goods[s.slug]!.single.name,
              price: _goods[s.slug]!.single.price,
              inStock: true,
              shopName: s.name,
              shopSlug: s.slug),
      ];
  @override
  Future<Set<String>> spotlights({double? lat, double? lng}) async => {_shopSlug, _clubSlug};
  @override
  Future<Map<String, List<ShopPreview>>> previews(List<String> slugs) async => const {};
  @override
  Future<List<ProductHit>> searchProducts(String query, {double? lat, double? lng}) async => [
        for (final s in _shops.values)
          for (final i in _goods[s.slug]!)
            if (i.name.toLowerCase().contains(query.toLowerCase()) || query == 'tout')
              ProductHit(
                  id: i.id, name: i.name, price: i.price, inStock: true, shopName: s.name, shopSlug: s.slug),
      ];
  @override
  Future<void> recordSeen(List<String> productIds) async => seen.addAll(productIds);
}

class _Shopper extends ShopperRepository {
  _Shopper() : super(null);
  final reports = <Map<String, String?>>[];
  @override
  bool get isConfigured => true;
  @override
  String? get picture => null;
  @override
  Future<ShopperProfile> profile() async => const ShopperProfile(city: 'Ouagadougou');
  @override
  Future<List<FollowedVitrine>> follows() async => const [];
  @override
  Future<void> report({required String topic, required String message, String? slug, String? orderId}) async =>
      reports.add({'topic': topic, 'message': message, 'slug': slug});
}

/// Who is holding the phone: signed out, or in ([phase]), of [mine].
class _Session extends SessionController {
  _Session(LocalDb db, {this.mine = const [], SessionPhase phase = SessionPhase.signedOut, this.platform = false})
      : _now = phase,
        super(db: db, auth: AuthRepository(null), admin: AdminRepository(null), accounting: AccountingRepository(null));

  final List<OrgSummary> mine;
  final bool platform;
  SessionPhase _now;

  @override
  SessionPhase get phase => _now;
  set now(SessionPhase p) {
    _now = p;
    notifyListeners();
  }

  @override
  List<OrgSummary> get orgs => mine;
  @override
  bool get isPlatformAdmin => platform;
}

class _Center extends CommandCenterRepository {
  _Center() : super(null);
  @override
  Future<List<ProblemReport>> reports({bool handled = false}) async => [
        ProblemReport(
            id: 'r1',
            topic: 'vitrine',
            message: 'Des photos qui n\'ont rien à voir avec la boutique.',
            at: DateTime(2026, 10, 14, 9, 30),
            reporter: 'Client Mara',
            contact: '+22670000000',
            orgId: 'b150-shop',
            orgName: 'Atelier Lumière',
            slug: _shopSlug),
        const ProblemReport(id: 'r2', topic: 'app', message: 'L\'application est lente le soir.'),
      ];
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _size(WidgetTester tester, Size size, {double scale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  if (scale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

Future<void> _settle(WidgetTester tester, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<bool> _realFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6 && !Directory('${dir.path}/material_fonts').existsSync(); i++) {
    dir = dir.parent;
  }
  final fonts = Directory('${dir.path}/material_fonts');
  if (!fonts.existsSync()) return false;
  final loader = FontLoader('Roboto');
  for (final f in const ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    final file = File('${fonts.path}/$f');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
  final icons = File('${fonts.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer))))
        .load();
  }
  return true;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
    await _realFonts();
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
    Support.reset();
  });
  tearDown(() async {
    Support.reset();
    await db.close();
  });

  late _Street street;
  late _Shopper shopper;

  /// The app's street pages, with their real routes: the vitrine, the
  /// street, the hidden list, the profile, a stub sign-in page.
  Future<GoRouter> pump(WidgetTester tester, _Session session,
      {String at = '/s/$_shopSlug',
      Locale locale = const Locale('fr'),
      Size size = const Size(390, 844),
      double scale = 1.0,
      LocalDb? useDb}) async {
    await _size(tester, size, scale: scale);
    final d = useDb ?? db;
    street = _Street();
    shopper = _Shopper();
    final router = GoRouter(initialLocation: at, routes: [
      GoRoute(
          path: '/s/:slug',
          builder: (_, state) => StorefrontScreen(
                slug: state.pathParameters['slug']!,
                storefront: street,
                capture: CaptureRepository(null, db: d),
                session: session,
                shopper: shopper,
              )),
      GoRoute(
          path: Routes.directory,
          builder: (_, _) => DirectoryScreen(
                storefront: street,
                capture: CaptureRepository(null, db: d),
                session: session,
              )),
      GoRoute(path: Routes.hiddenVitrines, builder: (_, _) => HiddenVitrinesScreen(db: d)),
      GoRoute(path: Routes.shopperProfile, builder: (_, _) => ShopperProfileScreen(shopper: shopper)),
      GoRoute(path: Routes.signIn, builder: (_, state) => const Scaffold(body: Text('page connexion'))),
      GoRoute(path: Routes.pin, builder: (_, state) => const Scaffold(body: Text('page code'))),
    ]);
    await tester.pumpWidget(RepaintBoundary(
      key: const Key('screen'),
      child: AppScope(
        session: session,
        localeController: LocaleController(d),
        db: d,
        auth: session.auth,
        admin: session.admin,
        reports: ReportsRepository(null),
        accounting: AccountingRepository(null),
        console: ConsoleRepository(null),
        farm: FarmRepository(null),
        invoicing: InvoicingRepository(null),
        retail: RetailRepository(null),
        staff: StaffRepository(null),
        capture: CaptureRepository(null, db: d),
        onboarding: OnboardingRepository(null),
        credit: CreditRepository(null),
        tontine: TontineRepository(null),
        production: ProductionRepository(null),
        notify: NotificationsRepository(null),
        analytics: AnalyticsRepository(null),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          locale: locale,
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
        ),
      ),
    ));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 800));
    return router;
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await _settle(tester, 6);
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('vitrine-menu')));
    await _settle(tester, 4);
  }

  // -------------------------------------------------------------------------
  // 1. The ⋮
  // -------------------------------------------------------------------------
  group('1. the menu', () {
    for (final slug in [_shopSlug, _farmSlug, _clubSlug]) {
      testWidgets('a visitor sees it on $slug, with its two lines', (tester) async {
        await pump(tester, _Session(db), at: '/s/$slug');
        expect(find.byKey(const Key('vitrine-menu')), findsOneWidget);
        expect(find.byTooltip('Plus d\'actions'), findsOneWidget, reason: 'a name for a screen reader');
        await openMenu(tester);
        expect(find.text('Signaler cette vitrine'), findsOneWidget);
        expect(find.text('Masquer cette vitrine'), findsOneWidget);
      });
    }

    testWidgets('a signed-in shopper sees it too', (tester) async {
      await pump(tester, _Session(db, phase: SessionPhase.noOrg));
      expect(find.byKey(const Key('vitrine-menu')), findsOneWidget);
    });

    for (final (label, session) in [
      ('its owner', (LocalDb d) => _Session(d, mine: const [_ownShop], phase: SessionPhase.ready)),
      ('its employee', (LocalDb d) => _Session(d, mine: [_as(_ownShop, const ['employee'])], phase: SessionPhase.ready)),
      ('Mara\'s admin', (LocalDb d) => _Session(d, mine: [_as(_ownShop, const ['platform_admin'])], phase: SessionPhase.ready)),
      ('Mara\'s admin, by the platform\'s word', (LocalDb d) => _Session(d, platform: true, phase: SessionPhase.noOrg)),
    ]) {
      testWidgets('$label: no menu, the vitrine itself there', (tester) async {
        await pump(tester, session(db));
        expect(find.byKey(const Key('vitrine-menu')), findsNothing);
        expect(find.text('Savon karité'), findsWidgets);
      });
    }

    testWidgets('the owner of another business is a visitor here', (tester) async {
      await pump(tester, _Session(db, mine: const [_ownShop], phase: SessionPhase.ready), at: '/s/$_farmSlug');
      expect(find.byKey(const Key('vitrine-menu')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 2. « Signaler cette vitrine »
  // -------------------------------------------------------------------------
  group('2. report', () {
    testWidgets('signed in: the report sheet about this vitrine, sent with its topic and slug', (tester) async {
      await pump(tester, _Session(db, phase: SessionPhase.noOrg), at: '/s/$_farmSlug');
      await openMenu(tester);
      await tap(tester, find.text('Signaler cette vitrine'));
      final sheet = tester.widget<ReportSheet>(find.byType(ReportSheet));
      expect(sheet.slug, _farmSlug);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('report-vitrine'))).selected, isTrue);
      await tester.enterText(find.byKey(const Key('report-text')), 'Les photos ne sont pas celles des produits.');
      await tap(tester, find.byKey(const Key('report-send')));
      expect(shopper.reports, [
        {'topic': 'vitrine', 'message': 'Les photos ne sont pas celles des produits.', 'slug': _farmSlug},
      ]);
      expect(find.byType(ReportSheet), findsNothing);
    });

    testWidgets('signed out: the sign-in doors and « ou écrivez-nous », never a dead end', (tester) async {
      await pump(tester, _Session(db));
      await openMenu(tester);
      await tap(tester, find.text('Signaler cette vitrine'));
      expect(find.byType(ReportSheet), findsNothing, reason: 'a report needs an account');
      expect(find.text('Connectez-vous pour signaler'), findsOneWidget);
      expect(find.byKey(const Key('order-sign-in-other')), findsOneWidget);
      expect(find.byKey(const Key('order-sign-in-create')), findsOneWidget);
      expect(find.byKey(const Key('order-sign-in-write-us')), findsOneWidget);
      expect(find.text('ou écrivez-nous'), findsOneWidget);
    });

    testWidgets('signed out → sign in → back on the vitrine: the sheet opens by itself', (tester) async {
      final session = _Session(db);
      final router = await pump(tester, session, at: '/s/$_clubSlug');
      await openMenu(tester);
      await tap(tester, find.text('Signaler cette vitrine'));
      await tap(tester, find.byKey(const Key('order-sign-in-other')));
      expect(find.text('page connexion'), findsOneWidget);
      final note = await tester.runAsync(() => db.readPref(streetResumeKey));
      expect(note, startsWith('$_clubSlug|'));
      expect(note, endsWith('|report'));
      // Signed in: the router gives the page the sign-in interrupted back.
      session.now = SessionPhase.noOrg;
      final back = session.takeReturnTo();
      expect(back, '/s/$_clubSlug');
      router.go(back!);
      await _settle(tester, 10);
      final sheet = tester.widget<ReportSheet>(find.byType(ReportSheet));
      expect(sheet.slug, _clubSlug);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('report-vitrine'))).selected, isTrue);
      expect(await tester.runAsync(() => db.readPref(streetResumeKey)), isNull, reason: 'taken once');
    });

    testWidgets('a report\'s note never opens an order, even with a basket', (tester) async {
      await tester.runAsync(() => db.writePref('street_basket_$_shopSlug', '{"p-savon":1}'));
      await tester.runAsync(() => db.writePref(streetResumeKey, '$_shopSlug|${DateTime.now().toIso8601String()}|report'));
      await pump(tester, _Session(db, phase: SessionPhase.noOrg));
      expect(find.byType(ReportSheet), findsOneWidget);
      expect(find.byType(OrderSheet), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 3. « Masquer cette vitrine »
  // -------------------------------------------------------------------------
  group('3. hide', () {
    Future<GoRouter> hideShop(WidgetTester tester, _Session session) async {
      final router = await pump(tester, session, size: const Size(390, 2400));
      await openMenu(tester);
      await tap(tester, find.text('Masquer cette vitrine'));
      expect(find.byKey(const Key('vitrine-hide-confirm')), findsOneWidget);
      expect(
          find.text('Vous ne la verrez plus dans la rue. Vous pourrez l\'afficher à nouveau depuis votre profil.'),
          findsOneWidget);
      await tap(tester, find.byKey(const Key('vitrine-hide-yes')));
      await _settle(tester, 6);
      return router;
    }

    testWidgets('« Annuler » in the question hides nothing', (tester) async {
      await pump(tester, _Session(db));
      await openMenu(tester);
      await tap(tester, find.text('Masquer cette vitrine'));
      await tap(tester, find.text('Annuler'));
      expect(await tester.runAsync(() => HiddenVitrines(db).slugs()), isEmpty);
      expect(find.text('Savon karité'), findsWidgets);
    });

    testWidgets('gone from the list, « À la une », the paid spots — the others stay', (tester) async {
      // Before: all three, two of them sponsored.
      await pump(tester, _Session(db), at: Routes.directory, size: const Size(390, 2400));
      expect(find.text('Atelier Lumière'), findsWidgets);
      expect(find.text('Savon karité'), findsOneWidget, reason: '« À la une »');
      expect(find.byType(SponsoredTag), findsNWidgets(2));

      final router = await hideShop(tester, _Session(db));
      expect(router.routerDelegate.currentConfiguration.uri.path, Routes.directory, reason: 'back to the street');
      expect(find.text('Atelier Lumière est masquée.'), findsOneWidget);
      expect(find.text('Atelier Lumière'), findsNothing);
      expect(find.text('Savon karité'), findsNothing, reason: 'its « À la une » item');
      expect(find.text('Ferme Horizon Vert'), findsWidgets);
      expect(find.text('Fondation Espoir'), findsWidgets);
      expect(find.text('Sac de mil'), findsOneWidget);
      expect(find.byType(SponsoredTag), findsOneWidget, reason: 'only the association\'s spot is left');
      expect(street.seen, isNot(contains('p-savon')), reason: 'a hidden spot is not counted as seen');
      expect(find.text('2 vitrines'), findsOneWidget);
      expect(find.byKey(const Key('footer-hidden')), findsOneWidget);
    });

    testWidgets('gone from the search', (tester) async {
      await tester.runAsync(() => HiddenVitrines(db).hide(_shopSlug, name: 'Atelier Lumière'));
      await pump(tester, _Session(db), at: Routes.directory);
      await tester.enterText(find.byType(TextField), 'tout');
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      expect(find.text('RÉSULTATS'), findsOneWidget);
      expect(find.text('Savon karité'), findsNothing);
      expect(find.text('Sac de mil'), findsOneWidget);
      expect(find.text('Livre solidaire'), findsOneWidget);
    });

    testWidgets('« Annuler » on the street brings it back at once', (tester) async {
      await hideShop(tester, _Session(db));
      await tester.tap(find.text('Annuler'));
      await _settle(tester);
      expect(await tester.runAsync(() => HiddenVitrines(db).slugs()), isEmpty);
      expect(find.text('Atelier Lumière'), findsWidgets);
    });

    testWidgets('its link: the notice, « Afficher à nouveau » restores it', (tester) async {
      await tester.runAsync(() => HiddenVitrines(db).hide(_shopSlug, name: 'Atelier Lumière'));
      await pump(tester, _Session(db));
      expect(find.byKey(const Key('vitrine-hidden-notice')), findsOneWidget);
      expect(find.text('Vous avez masqué cette vitrine'), findsOneWidget);
      expect(find.text('Savon karité'), findsNothing);
      expect(find.byKey(const Key('vitrine-menu')), findsNothing);
      expect(find.text('Voir les autres vitrines'), findsOneWidget, reason: 'and the way to the street');
      await tap(tester, find.byKey(const Key('vitrine-show-again')));
      expect(find.byKey(const Key('vitrine-hidden-notice')), findsNothing);
      expect(find.text('Savon karité'), findsWidgets);
      expect(await tester.runAsync(() => HiddenVitrines(db).slugs()), isEmpty);
    });

    testWidgets('its own people never get the notice', (tester) async {
      await tester.runAsync(() => HiddenVitrines(db).hide(_shopSlug, name: 'Atelier Lumière'));
      await pump(tester, _Session(db, mine: const [_ownShop], phase: SessionPhase.ready));
      expect(find.byKey(const Key('vitrine-hidden-notice')), findsNothing);
      expect(find.text('Savon karité'), findsWidgets);
    });
  });

  // -------------------------------------------------------------------------
  // 4. « Vitrines masquées »
  // -------------------------------------------------------------------------
  group('4. the hidden list', () {
    testWidgets('signed out: the street\'s foot leads to it; « Afficher à nouveau » brings the shop back',
        (tester) async {
      await tester.runAsync(() => HiddenVitrines(db).hide(_shopSlug, name: 'Atelier Lumière'));
      await tester.runAsync(() => HiddenVitrines(db).hide(_farmSlug, name: 'Ferme Horizon Vert'));
      await pump(tester, _Session(db), at: Routes.directory, size: const Size(390, 2400));
      expect(find.text('Vitrines masquées (2)'), findsOneWidget);
      await tap(tester, find.byKey(const Key('footer-hidden')));
      expect(find.byKey(const Key('hidden-$_shopSlug')), findsOneWidget);
      expect(find.byKey(const Key('hidden-$_farmSlug')), findsOneWidget);
      await tap(tester, find.byKey(const Key('hidden-show-$_shopSlug')));
      expect(find.byKey(const Key('hidden-$_shopSlug')), findsNothing);
      expect(find.text('Atelier Lumière est de nouveau visible dans la rue.'), findsOneWidget);
      await tap(tester, find.byTooltip('Retour'));
      expect(find.text('Atelier Lumière'), findsWidgets, reason: 'back on the street');
      expect(find.text('Ferme Horizon Vert'), findsNothing);
      expect(find.text('Vitrines masquées (1)'), findsOneWidget);
    });

    testWidgets('no hidden vitrine: no link at the foot', (tester) async {
      await pump(tester, _Session(db), at: Routes.directory, size: const Size(390, 2400));
      expect(find.byKey(const Key('footer-hidden')), findsNothing);
    });

    testWidgets('the profile: « Vitrines masquées » with the count, to the list', (tester) async {
      await tester.runAsync(() => HiddenVitrines(db).hide(_clubSlug, name: 'Fondation Espoir'));
      await pump(tester, _Session(db, phase: SessionPhase.noOrg), at: Routes.shopperProfile, size: const Size(390, 3000));
      expect(find.byKey(const Key('shopper-hidden')), findsOneWidget);
      expect(find.text('1 vitrine masquée sur ce téléphone'), findsOneWidget);
      await tap(tester, find.byKey(const Key('shopper-hidden')));
      expect(find.byKey(const Key('hidden-$_clubSlug')), findsOneWidget);
      await tap(tester, find.byKey(const Key('hidden-show-$_clubSlug')));
      expect(find.byKey(const Key('hidden-none')), findsOneWidget);
      await tap(tester, find.byTooltip('Retour'));
      expect(find.text('Aucune : « Masquer » est dans le menu ⋮ d\'une vitrine'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 5. Across restarts
  // -------------------------------------------------------------------------
  group('5. kept on the device', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('b150'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('hidden, the app closed and opened again: still hidden, with its name', () async {
      final path = '${dir.path}/kaj.db';
      final first = await LocalDb.open(path: path);
      await HiddenVitrines(first).hide(_farmSlug, name: 'Ferme Horizon Vert');
      await first.close();
      final again = await LocalDb.open(path: path);
      final rows = await HiddenVitrines(again).list();
      expect(rows.single.slug, _farmSlug);
      expect(rows.single.name, 'Ferme Horizon Vert');
      expect(rows.single.at, isNotNull);
      await again.close();
    });

    testWidgets('the street opened after a restart leaves it out', (tester) async {
      final path = '${dir.path}/kaj2.db';
      final first = (await tester.runAsync(() => LocalDb.open(path: path)))!;
      await tester.runAsync(() => HiddenVitrines(first).hide(_farmSlug, name: 'Ferme Horizon Vert'));
      await tester.runAsync(first.close);
      final again = (await tester.runAsync(() => LocalDb.open(path: path)))!;
      addTearDown(() => tester.runAsync(again.close));
      // The app's start reads the hidden list once (main.dart).
      await tester.runAsync(() => HiddenVitrines(again).list());
      await pump(tester, _Session(again), at: Routes.directory, useDb: again);
      expect(find.text('Ferme Horizon Vert'), findsNothing);
      expect(find.text('Atelier Lumière'), findsWidgets);
    });

    test('a broken record is no hidden vitrine, never a crash', () async {
      await db.writePref(HiddenVitrines.key, 'pas du json');
      expect(await HiddenVitrines(db).list(), isEmpty);
      await db.writePref(HiddenVitrines.key, '[{"slug":""},{"slug":"x","name":""},3]');
      final rows = await HiddenVitrines(db).list();
      expect(rows.single.slug, 'x');
      expect(rows.single.name, 'x');
    });
  });

  // -------------------------------------------------------------------------
  // 6. The console's Signalements
  // -------------------------------------------------------------------------
  group('6. the console', () {
    Future<List<String>> console(WidgetTester tester, {Locale locale = const Locale('fr'), Size size = const Size(390, 844), double scale = 1.0}) async {
      await _size(tester, size, scale: scale);
      final went = <String>[];
      final router = GoRouter(initialLocation: Routes.consoleReports, routes: [
        GoRoute(path: Routes.consoleReports, builder: (_, _) => ReportsSheet.page(center: _Center())),
        GoRoute(
            path: '/s/:slug',
            builder: (_, state) {
              went.add(state.uri.toString());
              return const Scaffold(body: Text('vitrine'));
            }),
        GoRoute(
            path: '/o/:id/administration/parametres',
            builder: (_, state) {
              went.add(state.uri.toString());
              return const Scaffold(body: Text('paramètres'));
            }),
        GoRoute(
            path: '/console/entreprises/:id',
            builder: (_, state) {
              went.add(state.uri.toString());
              return const Scaffold(body: Text('fiche'));
            }),
      ]);
      await tester.pumpWidget(RepaintBoundary(
          key: const Key('screen'),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            locale: locale,
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
          )));
      await _settle(tester);
      return went;
    }

    testWidgets('a vitrine\'s report names it, opens it, and leads to the existing suspend', (tester) async {
      final went = await console(tester);
      expect(find.text('Vitrine signalée : Atelier Lumière'), findsOneWidget);
      expect(find.byKey(const Key('report-open-vitrine-r1')), findsOneWidget);
      expect(find.byKey(const Key('report-suspend-r1')), findsOneWidget);
      expect(find.byKey(const Key('report-open-vitrine-r2')), findsNothing, reason: 'an app report names none');
      await tap(tester, find.byKey(const Key('report-open-vitrine-r1')));
      expect(went, ['/s/$_shopSlug']);
      GoRouter.of(tester.element(find.text('vitrine'))).pop();
      await _settle(tester);
      await tap(tester, find.byKey(const Key('report-suspend-r1')));
      expect(went.last, '/o/b150-shop/administration/parametres?partie=plateforme');
    });

    testWidgets('English, 320 × 1.3', (tester) async {
      await console(tester, locale: const Locale('en'), size: const Size(320, 844), scale: 1.3);
      expect(find.text('Reported vitrine: Atelier Lumière'), findsOneWidget);
      expect(find.text('Suspend…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // 7. English, and 320 px × 1.3
  // -------------------------------------------------------------------------
  group('7. English and 320 × 1.3', () {
    testWidgets('the menu, the question, the notice in English', (tester) async {
      await pump(tester, _Session(db), locale: const Locale('en'));
      await openMenu(tester);
      expect(find.text('Report this vitrine'), findsOneWidget);
      expect(find.text('Hide this vitrine'), findsOneWidget);
      await tap(tester, find.text('Report this vitrine'));
      expect(find.text('Sign in to report'), findsOneWidget);
      expect(find.text('or write to us'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await _settle(tester);
      await openMenu(tester);
      await tap(tester, find.text('Hide this vitrine'));
      expect(find.text('Hide this vitrine?'), findsOneWidget);
      expect(find.text('You will no longer see it on the street. You can show it again from your profile.'),
          findsOneWidget);
    });

    testWidgets('the notice and the list in English', (tester) async {
      await tester.runAsync(() => HiddenVitrines(db).hide(_shopSlug, name: 'Atelier Lumière'));
      final router = await pump(tester, _Session(db), locale: const Locale('en'));
      expect(find.text('You hid this vitrine'), findsOneWidget);
      expect(find.text('Show again'), findsOneWidget);
      router.go(Routes.hiddenVitrines);
      await _settle(tester);
      expect(find.text('Hidden vitrines'), findsWidgets);
      expect(find.text('Show again'), findsOneWidget);
    });

    for (final locale in const [Locale('fr'), Locale('en')]) {
      testWidgets('320 × 1.3 ${locale.languageCode}: the menu, the sheets, the question, the notice, the list fit',
          (tester) async {
        final session = _Session(db);
        final router = await pump(tester, session, locale: locale, size: const Size(320, 640), scale: 1.3);
        expect(find.byKey(const Key('vitrine-menu')), findsOneWidget);
        await openMenu(tester);
        expect(tester.takeException(), isNull);
        await tap(tester, find.byKey(const Key('vitrine-report')));
        expect(find.byKey(const Key('order-sign-in-write-us')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(10, 10));
        await _settle(tester);
        await openMenu(tester);
        await tap(tester, find.byKey(const Key('vitrine-hide')));
        expect(find.byKey(const Key('vitrine-hide-confirm')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tap(tester, find.byKey(const Key('vitrine-hide-yes')));
        expect(tester.takeException(), isNull);
        router.go('/s/$_shopSlug');
        await _settle(tester);
        expect(find.byKey(const Key('vitrine-hidden-notice')), findsOneWidget);
        expect(tester.takeException(), isNull);
        router.go(Routes.hiddenVitrines);
        await _settle(tester);
        expect(find.byKey(const Key('hidden-$_shopSlug')), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Signed in: the report sheet itself.
        session.now = SessionPhase.noOrg;
        await tester.runAsync(() => HiddenVitrines(db).show(_shopSlug));
        router.go('/s/$_shopSlug');
        await _settle(tester);
        await openMenu(tester);
        await tap(tester, find.byKey(const Key('vitrine-report')));
        expect(find.byType(ReportSheet), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // -------------------------------------------------------------------------
  // Screenshots (B150_SHOTS=<dir>)
  // -------------------------------------------------------------------------
  final shots = Platform.environment['B150_SHOTS'];
  group('screenshots', () {
    Future<void> capture(WidgetTester tester, String path) async {
      await tester.pump();
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('screen')).first);
        final img = await ro.toImage(pixelRatio: 2);
        final data = await img.toByteData(format: ImageByteFormat.png);
        File(path).writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    for (final (w, scale) in const [(390.0, 1.0), (320.0, 1.3)]) {
      for (final locale in const [Locale('fr'), Locale('en')]) {
        final tag = '${locale.languageCode}_${w.toInt()}_$scale';
        testWidgets('the five — $tag', (tester) async {
          Directory(shots!).createSync(recursive: true);
          final session = _Session(db, phase: SessionPhase.noOrg);
          final router = await pump(tester, session, locale: locale, size: Size(w, 760), scale: scale);
          await openMenu(tester);
          await tester.pump(const Duration(seconds: 1));
          await capture(tester, '$shots/1_menu_$tag.png');
          await tap(tester, find.byKey(const Key('vitrine-report')));
          await capture(tester, '$shots/2_report_sheet_$tag.png');
          Navigator.of(tester.element(find.byType(ReportSheet))).pop();
          await _settle(tester);
          // The signed-out doors, for the record.
          session.now = SessionPhase.signedOut;
          await _settle(tester, 2);
          await openMenu(tester);
          await tap(tester, find.byKey(const Key('vitrine-report')));
          await capture(tester, '$shots/2b_report_signed_out_$tag.png');
          await tester.tapAt(const Offset(10, 10));
          await _settle(tester);
          await openMenu(tester);
          await tap(tester, find.byKey(const Key('vitrine-hide')));
          await capture(tester, '$shots/3_hide_confirm_$tag.png');
          await tap(tester, find.byKey(const Key('vitrine-hide-yes')));
          router.go('/s/$_shopSlug');
          await _settle(tester);
          await capture(tester, '$shots/4_hidden_notice_$tag.png');
          await tester.runAsync(() => HiddenVitrines(db).hide(_clubSlug, name: 'Fondation Espoir'));
          router.go(Routes.hiddenVitrines);
          await _settle(tester);
          await capture(tester, '$shots/5_hidden_list_$tag.png');
        }, skip: shots == null);
      }
    }

    testWidgets('the console\'s report', (tester) async {
      Directory(shots!).createSync(recursive: true);
      await _size(tester, const Size(390, 760));
      final router = GoRouter(initialLocation: Routes.consoleReports, routes: [
        GoRoute(path: Routes.consoleReports, builder: (_, _) => ReportsSheet.page(center: _Center())),
      ]);
      await tester.pumpWidget(RepaintBoundary(
          key: const Key('screen'),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            locale: const Locale('fr'),
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
          )));
      await _settle(tester);
      await capture(tester, '$shots/6_console_report_fr_390_1.0.png');
    }, skip: shots == null);
  });
}
