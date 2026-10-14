// Batch 146: the vitrine's Pro options made obvious, and « Ma vitrine » as
// the vitrine's entry point — for a shop, a farm and an association alike.
//
//   1. the save's words: toSaveJson always says the three Pro keys; the
//      Pro choices' line (« Liste · 3 articles en tête · Épuisés masqués »);
//   2. on Basic: every Pro option with its « PRO » seal and the line above
//      them; trying one draws « Aperçu — avec Mara Pro » across the
//      preview, the preview ordering the pinned and leaving off the
//      sold-out; back to the grid, no band;
//   3. « Enregistrer la vitrine » on Basic with Pro choices: the dialog —
//      its title, the choices, « gardés » only where 141 keeps them;
//      [Passer à Pro] saves nothing; [Enregistrer sans les options Pro]
//      saves every choice, reads them back and says « gardés » — or, before
//      141, that they could not be kept; the owner, an employee (« Demandez
//      au propriétaire »), the iPhone app (no Pro button); no Pro choice:
//      no dialog; Pro: no dialog, no band;
//   4. « Ma vitrine »: the sheet for an owner (four lines) and an employee
//      (no « Personnaliser », no « Mettre en avant »), the not-yet-visible
//      notice and its step, each line where it goes; « Personnaliser ma
//      vitrine » its own page; Le Chemin's vitrine steps there;
//   5. « Modifier ma vitrine » on one's own vitrine only: an owner sees it,
//      an employee, an observer, Mara's admin and a passer-by do not;
//   6. French and English;
//   7. 320 px × 1.3: the card, the dialog, the sheet and the button fit.
//
// B146_SHOTS=<dir> also writes the screenshots.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/access/store_rules.dart';
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
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
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
import 'package:kaj_app/features/admin/vitrine_pro_dialog.dart';
import 'package:kaj_app/features/home/vitrine_button.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// The businesses (no person's first name; Ouagadougou the only town)
// ---------------------------------------------------------------------------

const _shop = OrgSummary(
    id: 'b146-shop', name: 'Maison Élégance', slug: 'maison-elegance', profile: 'retail',
    roles: ['owner'], currency: 'XOF', visibility: 'full');
const _farm = OrgSummary(
    id: 'b146-farm', name: 'Ferme Horizon Vert', slug: 'horizon-vert', profile: 'farm',
    roles: ['owner'], currency: 'XOF', visibility: 'full');
const _club = OrgSummary(
    id: 'b146-club', name: 'Fondation Espoir', slug: 'fondation-espoir', profile: 'association',
    roles: ['owner'], currency: 'XOF', visibility: 'full');
const _proShop = OrgSummary(
    id: 'b146-pro', name: 'Atelier Lumière', slug: 'atelier-lumiere', profile: 'retail',
    plan: 'pro', roles: ['owner'], currency: 'XOF', visibility: 'full');

const _kinds = [_shop, _farm, _club];

OrgSummary _as(OrgSummary o, List<String> roles) => OrgSummary(
    id: o.id, name: o.name, slug: o.slug, profile: o.profile, plan: o.plan,
    roles: roles, currency: o.currency, visibility: o.visibility);

const _goods = [
  Product(id: 'p1', name: 'Pagne wax', salePrice: 6000, quantity: 4, isPublished: true),
  Product(id: 'p2', name: 'Sac en cuir', salePrice: 9000, quantity: 2, isPublished: true),
  Product(id: 'p3', name: 'Sandales', salePrice: 4500, quantity: 0, isPublished: true),
  Product(id: 'p4', name: 'Foulard', salePrice: 2500, quantity: 7, isPublished: true),
];

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// The server: each business's plan, its style, and 141 or not.
class _Admin extends AdminRepository {
  _Admin({this.keeps = true, this.checklist}) : super(null);

  /// 141 installed: the sign says so, and a Basic save keeps the choices.
  final bool keeps;
  final VitrineChecklist? checklist;
  StorefrontStyle stored = StorefrontStyle.none;
  final saved = <StorefrontStyle>[];
  final sent = <Map<String, Object?>>[];

  @override
  Future<bool> isPlatformAdmin() async => false;
  @override
  Future<int> claimMyInvitations() async => 0;
  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;
  @override
  Future<FeatureStates?> featureStates(String orgId) async =>
      FeatureStates.fromJson({'plan': orgId == _proShop.id ? 'pro' : 'free', 'wave_allowed': true, 'hidden': const []});
  @override
  Future<Map<String, String>> featureRulesForTier(String orgId, String tier) async => const {};
  @override
  Future<bool> storefrontKeepsProChoices() async => keeps;
  @override
  Future<StorefrontStyle> storefrontStyle(String orgId) async => stored;
  @override
  Future<void> setStorefrontStyle(String orgId, StorefrontStyle style) async {
    saved.add(style);
    sent.add(style.toSaveJson());
    final plus = orgId == _proShop.id;
    // Before 141 a Basic save keeps the old arrangement and drops the new.
    stored = plus || keeps
        ? style
        : StorefrontStyle(
            tagline: style.tagline,
            hours: style.hours,
            schedule: style.schedule,
            accent: style.accent,
            coverKey: style.coverKey,
            pinned: stored.pinned,
            hideOutOfStock: stored.hideOutOfStock,
            layout: stored.layout);
  }

  @override
  Future<VitrineChecklist?> vitrineChecklist(String orgId) async => checklist;

  // What the settings page reads.
  @override
  Future<Map<String, dynamic>> fetchOrg(String orgId) async => {
        'id': orgId,
        'name': 'Maison Élégance',
        'slug': 'maison-elegance',
        'profile': 'retail',
        'default_currency': 'XOF',
      };
  @override
  Future<String?> waveMerchant(String orgId) async => null;
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
        blurb: 'Le chic du quartier' as String?,
        lat: 12.37 as double?,
        lng: -1.52 as double?,
        deliveryBase: null,
        deliveryPerKm: null,
      );
  @override
  Future<double?> deliveryReach(String orgId) async => null;
  @override
  Future<double?> deliveryIncludedKm(String orgId) async => null;
}

class _Server extends AuthRepository {
  _Server(this.mine) : super(null);
  final List<OrgSummary> mine;
  @override
  bool get hasLiveSession => true;
  @override
  Future<List<OrgSummary>> fetchOrgs() async => mine;
}

class _Shelf extends RetailRepository {
  _Shelf() : super(null);
  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => _goods;
  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {};
}

class _Street extends StorefrontRepository {
  _Street() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<PublicShop?> shop(String slug) async => PublicShop(
        orgId: _shop.id, name: _shop.name, slug: slug, profile: 'retail',
        style: const StorefrontStyle(tagline: 'Le chic du quartier'));
  @override
  Future<List<PublicItem>> items(String slug) async => const [
        PublicItem(id: 'p1', name: 'Pagne wax', price: 6000, inStock: true),
        PublicItem(id: 'p2', name: 'Sac en cuir', price: 9000, inStock: true),
      ];
  @override
  Future<Set<String>> showcaseSlugs() async => const {};
}

class _Session extends SessionController {
  _Session(LocalDb db, this.mine, AdminRepository admin)
      : super(db: db, auth: AuthRepository(null), admin: admin, accounting: AccountingRepository(null));
  final List<OrgSummary> mine;
  @override
  List<OrgSummary> get orgs => mine;
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
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() async {
    debugSellsDigitalInApp = null;
    await db.close();
  });

  /// A session that read every business's plan (Basic, but [_proShop]).
  Future<SessionController> session(WidgetTester tester, _Admin admin, List<OrgSummary> mine) async {
    final s = SessionController(
        db: db, auth: _Server(mine), admin: admin, accounting: AccountingRepository(null));
    await tester.runAsync(() async {
      await s.resolveOrgs();
      for (final o in mine) {
        await s.reloadFeatures(o.id);
      }
    });
    return s;
  }

  Widget scoped(SessionController s, Widget app) => AppScope(
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
        retail: _Shelf(),
        staff: StaffRepository(null),
        capture: CaptureRepository(null, db: db),
        onboarding: OnboardingRepository(null),
        credit: CreditRepository(null),
        tontine: TontineRepository(null),
        production: ProductionRepository(null),
        notify: NotificationsRepository(null),
        analytics: AnalyticsRepository(null),
        child: app,
      );

  MaterialApp app(Widget home, {Locale locale = const Locale('fr')}) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: home,
      );

  /// The vitrine's dressing for [org], as the settings draw it.
  Future<_Admin> card(WidgetTester tester, OrgSummary org,
      {bool keeps = true, Locale locale = const Locale('fr'), Size size = const Size(390, 2600), double scale = 1.0,
      List<String>? roles, _Admin? use}) async {
    await _size(tester, size, scale: scale);
    final admin = use ?? _Admin(keeps: keeps);
    final who = roles == null ? org : _as(org, roles);
    final s = await session(tester, admin, [who]);
    await tester.pumpWidget(scoped(
        s,
        app(
            Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: VitrinePlusCard(orgId: org.id, admin: admin, retail: _Shelf(), shopName: org.name),
              ),
            ),
            locale: locale)));
    await _settle(tester);
    return admin;
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await _settle(tester, 4);
  }

  // -------------------------------------------------------------------------
  // 1. The words sent and said
  // -------------------------------------------------------------------------
  group('1. the save', () {
    test('toSaveJson says the three Pro keys, always; toJson unchanged', () {
      expect(StorefrontStyle.none.toSaveJson(), {'pinned': <String>[], 'hide_out_of_stock': false, 'layout': 'grid'});
      expect(StorefrontStyle.none.toJson(), isEmpty);
      const s = StorefrontStyle(tagline: 'Le chic', layout: VitrineLayout.list, pinned: ['p2', 'p1'], hideOutOfStock: true);
      expect(s.toSaveJson(), {
        'tagline': 'Le chic',
        'pinned': ['p2', 'p1'],
        'hide_out_of_stock': true,
        'layout': 'list',
      });
      expect(s.hasProChoices, isTrue);
      expect(const StorefrontStyle(tagline: 'x').hasProChoices, isFalse);
      expect(s.sameProChoices(const StorefrontStyle(layout: VitrineLayout.list, pinned: ['p2', 'p1'], hideOutOfStock: true)),
          isTrue);
      expect(s.sameProChoices(const StorefrontStyle(layout: VitrineLayout.list, pinned: ['p1', 'p2'], hideOutOfStock: true)),
          isFalse, reason: 'the order of the articles en tête is a choice');
    });

    testWidgets('the choices in one line, FR and EN', (tester) async {
      final lines = <String>[];
      for (final locale in const [Locale('fr'), Locale('en')]) {
        await tester.pumpWidget(app(Builder(builder: (context) {
          lines.add(vitrineProChoicesLine(context,
              const StorefrontStyle(layout: VitrineLayout.list, pinned: ['a', 'b', 'c'], hideOutOfStock: true)));
          lines.add(vitrineProChoicesLine(context, const StorefrontStyle(pinned: ['a'])));
          return const SizedBox();
        }), locale: locale));
      }
      expect(lines, [
        'Liste · 3 articles en tête · Épuisés masqués',
        '1 article en tête',
        'List · 3 featured items · Sold-out items hidden',
        '1 featured item',
      ]);
    });

    test('Le Chemin\'s vitrine steps go to the vitrine\'s own page; the others as written', () {
      expect(Routes.vitrineSettings('o1'), '/o/o1/administration/parametres/vitrine');
      expect(Routes.pathStep('o1', 'administration/parametres?partie=vitrine'),
          '/o/o1/administration/parametres/vitrine');
      expect(Routes.pathStep('o1', 'administration/parametres?partie=position'),
          '/o/o1/administration/parametres?partie=position');
      expect(Routes.pathStep('o1', 'produits'), '/o/o1/produits');
      // Paramètres › Vitrine stays.
      expect(Routes.orgSettings('o1', part: 'vitrine'), '/o/o1/administration/parametres?partie=vitrine');
    });
  });

  // -------------------------------------------------------------------------
  // 2. Basic: the seals, the line, the band
  // -------------------------------------------------------------------------
  group('2. Basic sees and tries', () {
    for (final org in _kinds) {
      testWidgets('${org.profile}: every Pro option sealed « PRO », the line above, « Voir Mara Pro »', (tester) async {
        await card(tester, org);
        expect(find.text('AVEC MARA PRO'), findsOneWidget);
        expect(find.text('Ces options s\'activent avec Mara Pro. Essayez-les : l\'aperçu vous montre le résultat.'),
            findsOneWidget);
        // The section's seal, the layout, the articles en tête, the
        // sold-out switch and « Ouvert maintenant ».
        expect(find.text('PRO'), findsNWidgets(5));
        for (final label in const ['Présentation des articles', 'Articles en tête (0/6)',
            'Ne pas afficher les articles épuisés', '« Ouvert maintenant »']) {
          final row = find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
          expect(find.descendant(of: row, matching: find.text('PRO')), findsOneWidget, reason: label);
        }
        expect(find.text('Voir Mara Pro'), findsOneWidget);
        // Not the old locked card that let the layout alone be tried.
        expect(find.byKey(const Key('dressing-pro-locked')), findsNothing);
        expect(find.byKey(const Key('preview-pro-band')), findsNothing);
        for (final l in VitrineLayout.values) {
          expect(find.byKey(Key('layout-${l.name}')), findsOneWidget);
        }
        expect(find.widgetWithText(FilterChip, 'Pagne wax'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a Pro option tried: the band across the preview; back to the grid, gone', (tester) async {
      await card(tester, _shop);
      await tap(tester, find.byKey(const Key('layout-list')));
      expect(find.byKey(const Key('preview-pro-band')), findsOneWidget);
      expect(find.text('Aperçu — avec Mara Pro'), findsOneWidget);
      await tap(tester, find.byKey(const Key('layout-grid')));
      expect(find.byKey(const Key('preview-pro-band')), findsNothing);
      // An article en tête alone, or the sold-out switch alone.
      await tap(tester, find.widgetWithText(FilterChip, 'Foulard'));
      expect(find.byKey(const Key('preview-pro-band')), findsOneWidget);
      await tap(tester, find.widgetWithText(FilterChip, 'Foulard'));
      expect(find.byKey(const Key('preview-pro-band')), findsNothing);
      await tap(tester, find.byKey(const Key('dressing-hide-out')));
      expect(find.byKey(const Key('preview-pro-band')), findsOneWidget);
    });

    testWidgets('the preview shows the result: pinned first, the sold-out left off', (tester) async {
      await card(tester, _shop);
      final preview = find.byKey(const Key('vitrine-preview'));
      expect(find.descendant(of: preview, matching: find.text('Sandales')), findsOneWidget);
      await tap(tester, find.widgetWithText(FilterChip, 'Foulard'));
      await tap(tester, find.byKey(const Key('dressing-hide-out')));
      expect(find.descendant(of: preview, matching: find.text('Sandales')), findsNothing);
      final foulard = tester.getTopLeft(find.descendant(of: preview, matching: find.text('Foulard')));
      final pagne = tester.getTopLeft(find.descendant(of: preview, matching: find.text('Pagne wax')));
      expect(foulard.dy < pagne.dy || (foulard.dy == pagne.dy && foulard.dx < pagne.dx), isTrue,
          reason: 'the article en tête comes first');
      expect(
          VitrinePreview.arranged(_goods, const StorefrontStyle(pinned: ['p4', 'p2'], hideOutOfStock: true))
              .map((p) => p.id),
          ['p4', 'p2', 'p1']);
    });

    testWidgets('Pro: no line, no band, the choices as before', (tester) async {
      await card(tester, _proShop);
      expect(find.text('Ces options s\'activent avec Mara Pro. Essayez-les : l\'aperçu vous montre le résultat.'),
          findsNothing);
      await tap(tester, find.byKey(const Key('layout-menu')));
      expect(find.byKey(const Key('preview-pro-band')), findsNothing);
      expect(find.text('Voir Mara Pro'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 3. Saving says it plainly
  // -------------------------------------------------------------------------
  group('3. the dialog', () {
    Future<_Admin> tryAndSave(WidgetTester tester, OrgSummary org,
        {bool keeps = true, List<String>? roles, Locale locale = const Locale('fr'), _Admin? use}) async {
      final admin = await card(tester, org, keeps: keeps, roles: roles, locale: locale, use: use);
      await tap(tester, find.byKey(const Key('layout-list')));
      for (final name in const ['Sac en cuir', 'Pagne wax', 'Foulard']) {
        await tap(tester, find.widgetWithText(FilterChip, name));
      }
      await tap(tester, find.byKey(const Key('dressing-save')));
      return admin;
    }

    for (final org in _kinds) {
      testWidgets('${org.profile}, the owner: the choices, « gardés », and saving keeps them', (tester) async {
        final admin = await tryAndSave(tester, org);
        expect(find.byKey(const Key('vitrine-pro-dialog')), findsOneWidget);
        expect(find.text('Ces choix viennent avec Mara Pro'), findsOneWidget);
        expect(find.text('Liste · 3 articles en tête'), findsOneWidget);
        expect(
            find.text(
                'Sans Pro, votre vitrine reste en grille. Vos choix sont gardés : ils s\'activent dès que vous passez à Pro.'),
            findsOneWidget);
        expect(find.byKey(const Key('vitrine-pro-dialog-pro')), findsOneWidget);
        expect(find.text('Passer à Pro'), findsOneWidget);
        expect(find.byKey(const Key('vitrine-pro-dialog-ask')), findsNothing);
        expect(admin.saved, isEmpty, reason: 'nothing saved before an answer');

        await tap(tester, find.byKey(const Key('vitrine-pro-dialog-save')));
        expect(find.byKey(const Key('vitrine-pro-dialog')), findsNothing);
        expect(admin.saved, hasLength(1));
        expect(admin.sent.single, {
          'pinned': ['p2', 'p1', 'p4'],
          'hide_out_of_stock': false,
          'layout': 'list',
        });
        expect(
            find.text(
                'Vitrine enregistrée, en grille. Vos choix Pro sont gardés : ils s\'activent dès que vous passez à Pro.'),
            findsOneWidget);
        // #204's word, and its Pro sheet opened unasked, are gone.
        expect(find.textContaining('vient avec Mara Pro'), findsNothing);
      });
    }

    testWidgets('[Passer à Pro]: the Pro door opens, the dialog goes, nothing is saved', (tester) async {
      await _size(tester, const Size(390, 2600));
      final admin = _Admin();
      final s = await session(tester, admin, const [_shop]);
      final went = <String>[];
      final router = GoRouter(initialLocation: '/', routes: [
        GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
                body: SingleChildScrollView(
                    child: VitrinePlusCard(orgId: _shop.id, admin: admin, retail: _Shelf())))),
        GoRoute(
            path: '/o/:orgId/:rest',
            builder: (_, state) {
              went.add(state.uri.path);
              return const Scaffold(body: Text('pro'));
            }),
      ]);
      await tester.pumpWidget(scoped(
          s,
          MaterialApp.router(
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
            locale: const Locale('fr'),
            routerConfig: router,
          )));
      await _settle(tester);
      await tap(tester, find.byKey(const Key('layout-list')));
      await tap(tester, find.byKey(const Key('dressing-save')));
      await tester.tap(find.byKey(const Key('vitrine-pro-dialog-pro')));
      await _settle(tester);
      expect(find.byKey(const Key('vitrine-pro-dialog')), findsNothing);
      expect(admin.saved, isEmpty);
      // The business's Pro door: the unlock sheet where cauris can buy it,
      // the Pro page otherwise (UnlockSheet, 085).
      expect(went.isNotEmpty || find.byType(BottomSheet).evaluate().isNotEmpty, isTrue);
    });

    testWidgets('dismissed: nothing saved', (tester) async {
      final admin = await tryAndSave(tester, _farm);
      await tester.tapAt(const Offset(5, 5));
      await _settle(tester, 4);
      expect(find.byKey(const Key('vitrine-pro-dialog')), findsNothing);
      expect(admin.saved, isEmpty);
    });

    testWidgets('before 141: never « gardés » — said before, and read back after', (tester) async {
      final admin = await tryAndSave(tester, _club, keeps: false);
      expect(find.textContaining('Vos choix sont gardés'), findsNothing);
      expect(
          find.text(
              'Sans Pro, votre vitrine reste en grille. Pour le moment, ces choix ne peuvent pas être gardés : il faudra les refaire une fois Pro activé.'),
          findsOneWidget);
      await tap(tester, find.byKey(const Key('vitrine-pro-dialog-save')));
      expect(admin.saved, hasLength(1));
      expect(find.text('Vitrine enregistrée, en grille. Vos choix Pro n\'ont pas pu être gardés pour le moment.'),
          findsOneWidget);
      expect(find.textContaining('Vos choix Pro sont gardés'), findsNothing);
    });

    testWidgets('the sign says yes but the read-back disagrees: the read-back is believed', (tester) async {
      final admin = await tryAndSave(tester, _shop, use: _LyingAdmin());
      await tap(tester, find.byKey(const Key('vitrine-pro-dialog-save')));
      expect(admin.saved, hasLength(1));
      expect(find.text('Vitrine enregistrée, en grille. Vos choix Pro n\'ont pas pu être gardés pour le moment.'),
          findsOneWidget);
      // The next save is honest before saving too.
      await tap(tester, find.byKey(const Key('dressing-save')));
      expect(find.textContaining('ne peuvent pas être gardés'), findsOneWidget);
    });

    testWidgets('an employee: « Demandez au propriétaire », no Pro button', (tester) async {
      await tester.pumpWidget(app(const Scaffold(
          body: VitrineProDialog(choices: 'Liste', canBuy: false, sellsPro: true, kept: true))));
      expect(find.text('Demandez au propriétaire de passer à Pro'), findsOneWidget);
      expect(find.byKey(const Key('vitrine-pro-dialog-pro')), findsNothing);
      expect(find.byKey(const Key('vitrine-pro-dialog-save')), findsOneWidget);
      // And from the card, someone who is not an admin of the business.
      await tryAndSave(tester, _shop, roles: const ['employee']);
      expect(find.byKey(const Key('vitrine-pro-dialog-ask')), findsOneWidget);
      expect(find.byKey(const Key('vitrine-pro-dialog-pro')), findsNothing);
    });

    testWidgets('the iPhone app: no Pro button, no invitation, no « Voir Mara Pro »', (tester) async {
      debugSellsDigitalInApp = false;
      await tryAndSave(tester, _shop);
      expect(find.byKey(const Key('vitrine-pro-dialog')), findsOneWidget);
      expect(find.byKey(const Key('vitrine-pro-dialog-pro')), findsNothing);
      expect(find.byKey(const Key('vitrine-pro-dialog-ask')), findsNothing);
      expect(find.text('Passer à Pro'), findsNothing);
      // Kept, said without an invitation to go to Pro (125).
      expect(find.textContaining('passez à Pro'), findsNothing);
      expect(find.text('Sans Pro, votre vitrine reste en grille. Vos choix sont gardés : ils font partie de Mara Pro.'),
          findsOneWidget);
      await tap(tester, find.byKey(const Key('vitrine-pro-dialog-save')));
      expect(find.text('Voir Mara Pro'), findsNothing);
      expect(find.textContaining('passez à Pro'), findsNothing);
      expect(find.text('Vitrine enregistrée, en grille. Vos choix Pro sont gardés : ils font partie de Mara Pro.'),
          findsOneWidget);
    });

    testWidgets('no Pro choice on Basic: no dialog, saved as before', (tester) async {
      final admin = await card(tester, _shop);
      await tap(tester, find.byKey(const Key('dressing-save')));
      expect(find.byKey(const Key('vitrine-pro-dialog')), findsNothing);
      expect(admin.saved, hasLength(1));
      expect(find.text('Vitrine enregistrée. Ouvrez-la pour voir le résultat.'), findsOneWidget);
    });

    testWidgets('kept choices come back: the settings show them tried, under the band', (tester) async {
      await _size(tester, const Size(390, 2600));
      final admin = _Admin()..stored = const StorefrontStyle(layout: VitrineLayout.menu, pinned: ['p2']);
      final s = await session(tester, admin, const [_shop]);
      await tester.pumpWidget(scoped(
          s, app(Scaffold(body: SingleChildScrollView(child: VitrinePlusCard(orgId: _shop.id, admin: admin, retail: _Shelf()))))));
      await _settle(tester);
      expect(find.text('Articles en tête (1/6)'), findsOneWidget);
      expect(find.byKey(const Key('preview-pro-band')), findsOneWidget);
    });

    testWidgets('Pro: no dialog, the choices saved', (tester) async {
      final admin = await card(tester, _proShop);
      await tap(tester, find.byKey(const Key('layout-menu')));
      await tap(tester, find.byKey(const Key('dressing-save')));
      expect(find.byKey(const Key('vitrine-pro-dialog')), findsNothing);
      expect(admin.sent.single['layout'], 'menu');
    });
  });

  // -------------------------------------------------------------------------
  // 4. « Ma vitrine »
  // -------------------------------------------------------------------------
  group('4. « Ma vitrine »', () {
    Future<List<String>> openSheet(WidgetTester tester, OrgSummary org,
        {VitrineChecklist? checklist, Locale locale = const Locale('fr'), Size size = const Size(390, 844),
        double scale = 1.0}) async {
      await _size(tester, size, scale: scale);
      final went = <String>[];
      final admin = _Admin(checklist: checklist);
      final s = await session(tester, admin, [org]);
      final router = GoRouter(initialLocation: '/o/${org.id}', routes: [
        GoRoute(
            path: '/o/:orgId',
            builder: (_, _) => Scaffold(appBar: AppBar(actions: [VitrineButton(org: org)])),
            routes: [
              GoRoute(
                  path: 'administration/parametres/vitrine',
                  builder: (_, state) {
                    went.add(state.uri.path);
                    return const Scaffold(body: Text('personnaliser'));
                  }),
              GoRoute(
                  path: 'administration/parametres',
                  builder: (_, state) {
                    went.add(state.uri.toString());
                    return const Scaffold(body: Text('parametres'));
                  }),
            ]),
        GoRoute(
            path: '/s/:slug',
            builder: (_, state) {
              went.add(state.uri.path);
              return const Scaffold(body: Text('vitrine'));
            }),
      ]);
      await tester.pumpWidget(scoped(
          s,
          MaterialApp.router(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
            locale: locale,
            routerConfig: router,
          )));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('home-vitrine')));
      await _settle(tester);
      expect(find.byKey(const Key('vitrine-sheet')), findsOneWidget);
      return went;
    }

    for (final org in _kinds) {
      testWidgets('${org.profile}, the owner: four lines, each with its icon and its line', (tester) async {
        await openSheet(tester, org);
        for (final k in const ['view', 'customise', 'share', 'promote']) {
          expect(find.byKey(Key('vitrine-sheet-$k')), findsOneWidget, reason: k);
        }
        for (final t in const ['Voir ma vitrine', 'La page que voient vos clients', 'Personnaliser ma vitrine',
            'Couverture, couleur, phrase, horaires, présentation', 'Partager ma vitrine',
            'Une image pour un statut, ou le lien', 'Mettre en avant', 'Une place en tête de la rue']) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
        expect(find.byKey(const Key('vitrine-sheet-hidden')), findsNothing);
      });

      testWidgets('${org.profile}, an employee: no « Personnaliser », no « Mettre en avant »', (tester) async {
        await openSheet(tester, _as(org, const ['employee']));
        expect(find.byKey(const Key('vitrine-sheet-view')), findsOneWidget);
        expect(find.byKey(const Key('vitrine-sheet-share')), findsOneWidget);
        expect(find.byKey(const Key('vitrine-sheet-customise')), findsNothing);
        expect(find.byKey(const Key('vitrine-sheet-promote')), findsNothing);
      });
    }

    testWidgets('« Voir ma vitrine »: the public page, as before', (tester) async {
      final went = await openSheet(tester, _shop);
      await tester.tap(find.byKey(const Key('vitrine-sheet-view')));
      await _settle(tester);
      expect(went, ['/s/maison-elegance']);
    });

    testWidgets('« Personnaliser ma vitrine »: straight to its page', (tester) async {
      final went = await openSheet(tester, _farm);
      await tester.tap(find.byKey(const Key('vitrine-sheet-customise')));
      await _settle(tester);
      expect(went, ['/o/b146-farm/administration/parametres/vitrine']);
      expect(find.text('personnaliser'), findsOneWidget);
    });

    testWidgets('« Partager ma vitrine »: batch 140\'s share sheet, its own words per kind', (tester) async {
      for (final (org, title) in [
        (_shop, 'Partager ma boutique'),
        (_farm, 'Partager ma ferme'),
        (_club, 'Partager mon association'),
      ]) {
        await openSheet(tester, org);
        await tester.tap(find.byKey(const Key('vitrine-sheet-share')));
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byKey(const Key('vitrine-sheet')), findsNothing);
        expect(find.text(title), findsOneWidget, reason: org.profile);
      }
    });

    testWidgets('the iPhone app: no « Mettre en avant »', (tester) async {
      debugSellsDigitalInApp = false;
      await openSheet(tester, _club);
      expect(find.byKey(const Key('vitrine-sheet-promote')), findsNothing);
      expect(find.byKey(const Key('vitrine-sheet-customise')), findsOneWidget);
    });

    testWidgets('closed: said first, « Ouvrir ma vitrine » opens its page', (tester) async {
      final went = await openSheet(tester, _shop, checklist: const VitrineChecklist(open: false, published: 6));
      expect(find.byKey(const Key('vitrine-sheet-hidden')), findsOneWidget);
      expect(find.text('Votre vitrine n\'est pas encore visible des clients'), findsOneWidget);
      expect(find.text('Elle est fermée : ouvrez-la, et vos clients la voient.'), findsOneWidget);
      final notice = tester.getTopLeft(find.byKey(const Key('vitrine-sheet-hidden')));
      final view = tester.getTopLeft(find.byKey(const Key('vitrine-sheet-view')));
      expect(notice.dy < view.dy, isTrue, reason: 'said first');
      await tester.tap(find.byKey(const Key('vitrine-sheet-fix')));
      await _settle(tester);
      expect(went, ['/o/b146-shop/administration/parametres/vitrine']);
    });

    testWidgets('short of articles: how many, and the articles step; an employee is told, no step', (tester) async {
      var went = await openSheet(tester, _farm, checklist: const VitrineChecklist(published: 2, minItems: 5));
      expect(find.text('Encore 3 article(s) en vente, et elle se montre à tout le monde.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vitrine-sheet-fix')));
      await _settle(tester);
      expect(went, ['/o/b146-farm/administration/parametres?partie=articles']);
      went = await openSheet(tester, _as(_farm, const ['employee']),
          checklist: const VitrineChecklist(published: 2, minItems: 5));
      expect(find.byKey(const Key('vitrine-sheet-hidden')), findsOneWidget);
      expect(find.byKey(const Key('vitrine-sheet-fix')), findsNothing);
    });

    testWidgets('English', (tester) async {
      await openSheet(tester, _club,
          locale: const Locale('en'), checklist: const VitrineChecklist(open: false, published: 0));
      expect(find.text('My vitrine'), findsWidgets, reason: 'the button and the sheet');
      for (final t in const ['See my vitrine', 'Customise my vitrine', 'Share my vitrine',
          'The page your customers see', 'It is closed: open it, and your customers see it.']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('« Personnaliser ma vitrine »: the Vitrine rubrique alone, its dressing, no index', (tester) async {
      await _size(tester, const Size(390, 2400));
      final admin = _Admin();
      final s = await session(tester, admin, const [_shop]);
      await tester.pumpWidget(scoped(
          s,
          app(OrgSettingsScreen(
              admin: admin, orgId: _shop.id, retail: _Shelf(), initialPart: 'vitrine', vitrineOnly: true))));
      await _settle(tester, 12);
      expect(find.byKey(const Key('vitrine-settings')), findsOneWidget);
      expect(find.text('Personnaliser ma vitrine'), findsOneWidget);
      expect(find.text('Ouvrir la vitrine'), findsOneWidget);
      expect(find.byType(VitrinePlusCard), findsOneWidget);
      expect(find.byKey(const Key('settings-progress')), findsNothing, reason: 'no index');
      expect(find.text('Retour aux paramètres'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // 5. « Modifier ma vitrine » on one's own vitrine only
  // -------------------------------------------------------------------------
  group('5. « Modifier ma vitrine »', () {
    Future<void> vitrine(WidgetTester tester, List<OrgSummary> mine,
        {Size size = const Size(390, 844), double scale = 1.0, Locale locale = const Locale('fr')}) async {
      await _size(tester, size, scale: scale);
      await tester.pumpWidget(app(
          StorefrontScreen(
            slug: _shop.slug!,
            storefront: _Street(),
            capture: CaptureRepository(null, db: db),
            session: _Session(db, mine, _Admin(checklist: const VitrineChecklist(published: 9, minItems: 5))),
          ),
          locale: locale));
      await _settle(tester);
    }

    testWidgets('its owner sees it, and it leads to « Personnaliser ma vitrine »', (tester) async {
      await vitrine(tester, const [_shop]);
      expect(find.byKey(const Key('vitrine-edit')), findsOneWidget);
      expect(find.text('Modifier ma vitrine'), findsOneWidget);
    });

    for (final (label, mine) in [
      ('a passer-by', const <OrgSummary>[]),
      ('an employee', [_as(_shop, const ['employee'])]),
      ('a trainer\'s look', [_as(_shop, const ['observer'])]),
      ('Mara\'s admin', [_as(_shop, const ['platform_admin'])]),
      ('the owner of another business', const [_farm]),
    ]) {
      testWidgets('$label: never', (tester) async {
        await vitrine(tester, mine);
        expect(find.byKey(const Key('vitrine-edit')), findsNothing);
        expect(find.text('Pagne wax'), findsWidgets, reason: 'the vitrine itself is there');
      });
    }

    testWidgets('the tap goes to the vitrine\'s own page', (tester) async {
      await _size(tester, const Size(390, 844));
      final went = <String>[];
      final router = GoRouter(initialLocation: '/s/${_shop.slug}', routes: [
        GoRoute(
            path: '/s/:slug',
            builder: (_, _) => StorefrontScreen(
                  slug: _shop.slug!,
                  storefront: _Street(),
                  capture: CaptureRepository(null, db: db),
                  session: _Session(db, const [_shop], _Admin()),
                )),
        GoRoute(
            path: '/o/:orgId/administration/parametres/vitrine',
            builder: (_, state) {
              went.add(state.uri.path);
              return const Scaffold(body: Text('personnaliser'));
            }),
      ]);
      await tester.pumpWidget(MaterialApp.router(
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        locale: const Locale('fr'),
        routerConfig: router,
      ));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('vitrine-edit')));
      await _settle(tester);
      expect(went, ['/o/b146-shop/administration/parametres/vitrine']);
    });

    testWidgets('English', (tester) async {
      await vitrine(tester, const [_shop], locale: const Locale('en'));
      expect(find.text('Edit my vitrine'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 6–7. English, and 320 px × 1.3
  // -------------------------------------------------------------------------
  group('6–7. English and 320 px × 1.3', () {
    testWidgets('the card and the dialog in English', (tester) async {
      await card(tester, _farm, locale: const Locale('en'));
      expect(find.text('These options turn on with Mara Pro. Try them: the preview shows you the result.'),
          findsOneWidget);
      await tap(tester, find.byKey(const Key('layout-large')));
      expect(find.text('Preview — with Mara Pro'), findsOneWidget);
      await tap(tester, find.byKey(const Key('dressing-save')));
      expect(find.text('These choices come with Mara Pro'), findsOneWidget);
      expect(find.text('Large photos'), findsWidgets);
      expect(find.text('Save without the Pro options'), findsOneWidget);
      expect(find.text('Go Pro'), findsWidgets);
    });

    for (final locale in const [Locale('fr'), Locale('en')]) {
      testWidgets('320 × 1.3 ${locale.languageCode}: the card with the band, the dialog', (tester) async {
        await card(tester, _club, locale: locale, size: const Size(320, 3600), scale: 1.3);
        await tap(tester, find.byKey(const Key('layout-menu')));
        await tap(tester, find.widgetWithText(FilterChip, 'Sac en cuir'));
        await tap(tester, find.byKey(const Key('dressing-hide-out')));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('preview-pro-band')), findsOneWidget);
        await tap(tester, find.byKey(const Key('dressing-save')));
        expect(find.byKey(const Key('vitrine-pro-dialog')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('320 × 1.3 ${locale.languageCode}: the sheet, the bar icon-only, « Modifier ma vitrine »',
          (tester) async {
        await _size(tester, const Size(320, 640), scale: 1.3);
        final admin = _Admin(checklist: const VitrineChecklist(open: false, published: 0));
        final s = await session(tester, admin, const [_shop]);
        await tester.pumpWidget(scoped(
            s,
            app(Builder(
                builder: (context) => Scaffold(
                      appBar: AppBar(actions: const [VitrineButton(org: _shop)]),
                    )),
                locale: locale)));
        await _settle(tester);
        expect(find.byType(IconButton), findsWidgets, reason: '« Ma vitrine » icon-only on a narrow bar (140)');
        await tester.tap(find.byKey(const Key('home-vitrine')));
        await _settle(tester);
        expect(find.byKey(const Key('vitrine-sheet')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(app(
            StorefrontScreen(
              slug: _shop.slug!,
              storefront: _Street(),
              capture: CaptureRepository(null, db: db),
              session: _Session(db, const [_shop], _Admin()),
            ),
            locale: locale));
        await _settle(tester);
        expect(find.byKey(const Key('vitrine-edit')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // -------------------------------------------------------------------------
  // Screenshots (B146_SHOTS=<dir>)
  // -------------------------------------------------------------------------
  final shots = Platform.environment['B146_SHOTS'];
  group('screenshots', () {
    Future<void> capture(WidgetTester tester, String path) async {
      await tester.pump();
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('screen')));
        final img = await ro.toImage(pixelRatio: 2);
        final data = await img.toByteData(format: ImageByteFormat.png);
        File(path).writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    for (final (w, scale) in const [(390.0, 1.0), (320.0, 1.3)]) {
      for (final locale in const [Locale('fr'), Locale('en')]) {
        final tag = '${locale.languageCode}_${w.toInt()}_$scale';
        testWidgets('the vitrine settings on Basic, the band, the dialog — $tag', (tester) async {
          Directory(shots!).createSync(recursive: true);
          await _size(tester, Size(w, 844), scale: scale);
          final admin = _Admin();
          final s = await session(tester, admin, const [_shop]);
          await tester.pumpWidget(RepaintBoundary(
              key: const Key('screen'),
              child: scoped(
                  s,
                  app(
                      Scaffold(
                        appBar: AppBar(title: Text(locale.languageCode == 'en' ? 'Customise my vitrine' : 'Personnaliser ma vitrine')),
                        body: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: VitrinePlusCard(orgId: _shop.id, admin: admin, retail: _Shelf(), shopName: _shop.name),
                        ),
                      ),
                      locale: locale))));
          await _settle(tester);
          // The Pro options with their seals.
          await tester.ensureVisible(find.byKey(const Key('dressing-pro-intro')));
          await _settle(tester, 2);
          await capture(tester, '$shots/settings_badges_$tag.png');
          // Tried: the band.
          await tap(tester, find.byKey(const Key('layout-list')));
          await tap(tester, find.widgetWithText(FilterChip, 'Sac en cuir'));
          await tap(tester, find.widgetWithText(FilterChip, 'Foulard'));
          await tester.ensureVisible(find.byKey(const Key('preview-pro-band')));
          await _settle(tester, 2);
          await capture(tester, '$shots/preview_band_$tag.png');
          // The dialog.
          await tap(tester, find.byKey(const Key('dressing-save')));
          await capture(tester, '$shots/dialog_$tag.png');
        }, skip: shots == null);

        testWidgets('« Ma vitrine »\'s sheet and « Modifier ma vitrine » — $tag', (tester) async {
          Directory(shots!).createSync(recursive: true);
          await _size(tester, Size(w, 844), scale: scale);
          final admin = _Admin(checklist: const VitrineChecklist(published: 2, minItems: 5));
          final s = await session(tester, admin, const [_shop]);
          await tester.pumpWidget(RepaintBoundary(
              key: const Key('screen'),
              child: scoped(
                  s,
                  app(
                      Builder(
                          builder: (context) => Scaffold(
                                appBar: AppBar(title: const Text('Mara'), actions: const [VitrineButton(org: _shop)]),
                                body: const SizedBox.expand(),
                              )),
                      locale: locale))));
          await _settle(tester);
          await tester.tap(find.byKey(const Key('home-vitrine')));
          await _settle(tester);
          await capture(tester, '$shots/sheet_$tag.png');

          await tester.pumpWidget(RepaintBoundary(
              key: const Key('screen'),
              child: app(
                  StorefrontScreen(
                    slug: _shop.slug!,
                    storefront: _Street(),
                    capture: CaptureRepository(null, db: db),
                    session: _Session(db, const [_shop], _Admin()),
                  ),
                  locale: locale)));
          await _settle(tester);
          await tester.pump(const Duration(milliseconds: 800));
          await capture(tester, '$shots/edit_button_$tag.png');
        }, skip: shots == null);
      }
    }
  });
}

/// A server whose sign says 141 while the save drops the choices.
class _LyingAdmin extends _Admin {
  _LyingAdmin() : super(keeps: true);
  @override
  Future<void> setStorefrontStyle(String orgId, StorefrontStyle style) async {
    saved.add(style);
    stored = StorefrontStyle(tagline: style.tagline);
  }
}
