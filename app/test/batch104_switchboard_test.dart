import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/org_access.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/auth/pin_codec.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/main.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/errors.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/account/compte_screen.dart';
import 'package:kaj_app/features/admin/admin_pill.dart';
import 'package:kaj_app/features/home/business_shell.dart' show SwitchActivityButton;
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mara's switchboard (104), from the app's side.
///
/// P1: with no rule written — feature_states with an empty 'hidden', or a
/// database before 104 that says nothing — every business's access, its
/// homes and its Compte are what they were.
/// P2: every catalog key the migration lists is read where its tool is
/// drawn (a home's bar or Plus, a Compte row) and at its address (the
/// router's `feature:`), and hiding it takes it away from each of them.

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

/// The server, as the session reads it: these feature states, this dial.
class _Admin extends AdminRepository {
  _Admin(this.states, {this.rules = const {}}) : super(null);

  final FeatureStates? states;
  final Map<String, String> rules;

  @override
  Future<FeatureStates?> featureStates(String orgId) async => states;

  @override
  Future<Map<String, String>> featureRulesForTier(String orgId, String tier) async => rules;

  @override
  Future<bool> isPlatformAdmin() async => false;
}

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

/// Every place a home leads to: the bar, then Plus.
Future<List<String>> _places(WidgetTester tester) async {
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// The catalog keys, read from the migration that writes them — so a key
/// added there without its wiring here fails this test.
Set<String> _catalogKeys() {
  final sql = File('../database/migrations/104_feature_switchboard.sql').readAsStringSync();
  final start = sql.indexOf('insert into feature_catalog');
  final end = sql.indexOf('on conflict (key)', start);
  expect(start, isNot(-1), reason: 'no catalog insert in 104');
  return RegExp(r"^\s*\('([a-z_]+)',", multiLine: true)
      .allMatches(sql.substring(start, end))
      .map((m) => m.group(1)!)
      .toSet();
}

/// Where each tool is drawn, and the gate there that reads the switch: the
/// dial's own key (accessTo folds the platform's hidden into it) or
/// isHidden by name.
const _drawn = <String, Map<String, List<String>>>{
  'invoices': {
    'lib/features/retail/store_home_screen.dart': ["canSee('invoices')"],
    'lib/features/farm/farm_home_screen.dart': ["canSee('invoices')"],
    'lib/features/church/church_home_screen.dart': ["canSee('invoices')"],
  },
  'credits': {
    'lib/features/account/compte_screen.dart': ["canSee('credits')"],
    'lib/features/farm/farm_home_screen.dart': ["canSee('credits')"],
    // The sale sheet's « À crédit ».
    'lib/features/retail/store_home_screen.dart': ["canEdit('credits')"],
  },
  'corrections': {
    'lib/features/account/compte_screen.dart': ["isHidden('corrections')"],
  },
  'production': {
    'lib/features/account/compte_screen.dart': ["canSee('production')"],
    'lib/features/retail/store_home_screen.dart': ["canSee('production')"],
    'lib/features/farm/farm_home_screen.dart': ["canSee('production')"],
    // The article's « Ingrédient de production » switch.
    'lib/features/retail/products_screen.dart': ["isHidden('production')"],
  },
  'tontines': {
    'lib/features/account/compte_screen.dart': ["canSee('tontines')"],
  },
  'payroll': {
    'lib/features/account/compte_screen.dart': ["isHidden('payroll')"],
    'lib/features/admin/team_screen.dart': ["isHidden('payroll')"],
  },
  'analytics': {
    'lib/features/account/compte_screen.dart': ["isHidden('analytics')"],
  },
  'accounting': {
    'lib/features/account/compte_screen.dart': ["isHidden('accounting')"],
  },
};

const _shop = OrgSummary(
    id: 'shop-1', name: 'Boutique Awa', slug: 'boutique-awa', profile: 'retail',
    roles: ['owner'], currency: 'XOF', visibility: 'full');
const _farm = OrgSummary(
    id: 'farm-1', name: 'Ferme Ignace', profile: 'farm', roles: ['owner'], visibility: 'full');
const _assoc = OrgSummary(
    id: 'asso-1', name: 'Entraide', profile: 'association', roles: ['owner'], visibility: 'full');
const _church = OrgSummary(
    id: 'ch-1', name: 'Grace Chapel', profile: 'church', roles: ['owner'], visibility: 'full');

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

  Widget store(OrgAccess access) => StoreHomeScreen(
      org: _shop, retail: _Shop(client), invoicing: InvoicingRepository(client), access: access);
  Widget farm(OrgAccess access) => FarmHomeScreen(
      db: db, org: _farm, invoicing: InvoicingRepository(client), access: access);
  Widget church(OrgAccess access) => ChurchHomeScreen(
      db: db, orgId: _church.id, orgName: _church.name, org: _church,
      reports: ReportsRepository(client), invoicing: InvoicingRepository(client),
      onHistory: () {}, access: access);

  group('P1: no rule, nothing moves', () {
    test('feature_states with no hidden, or an empty one, hides nothing', () {
      expect(FeatureStates.fromJson(const {'plan': 'free'}).hidden, isEmpty);
      expect(FeatureStates.fromJson(const {'plan': 'free', 'hidden': []}).hidden, isEmpty);
      expect(FeatureStates.fromJson(const {'hidden': ['credits']}).hidden, {'credits'});
    });

    test('an empty switchboard is the access of before, value for value', () {
      expect(const OrgAccess.admin(hidden: {}), OrgAccess.allEdit);
      expect(const OrgAccess.admin(proLocked: {'payroll'}, hidden: {}),
          const OrgAccess.admin(proLocked: {'payroll'}));
      expect(const OrgAccess.forTier({'credits': 'hidden'}, hidden: {}),
          const OrgAccess.forTier({'credits': 'hidden'}));
      for (final k in [..._catalogKeys(), ...OrgAccess.features]) {
        expect(const OrgAccess.admin(hidden: {}).isHidden(k), isFalse, reason: k);
      }
    });

    for (final (label, json) in [
      ('a database before 104', <String, dynamic>{'plan': 'free'}),
      ('104 with no rule', <String, dynamic>{'plan': 'free', 'hidden': <String>[]}),
    ]) {
      test('the session gives every kind and role today\'s access — $label', () async {
        const orgs = [
          OrgSummary(id: 'r', name: 'R', profile: 'retail', roles: ['owner']),
          OrgSummary(id: 'f', name: 'F', profile: 'farm', roles: ['owner']),
          OrgSummary(id: 'a', name: 'A', profile: 'association', roles: ['owner']),
          OrgSummary(id: 'c', name: 'C', profile: 'church', roles: ['owner']),
          OrgSummary(id: 'e', name: 'E', profile: 'retail', roles: ['employee']),
          OrgSummary(id: 'p', name: 'P', profile: 'retail', roles: ['owner'], plan: 'pro'),
        ];
        await db.cacheOrgs(orgs);
        final rules = {'credits': 'hidden', 'products': 'view'};
        final session = SessionController(
          db: db,
          auth: AuthRepository(null),
          admin: _Admin(FeatureStates.fromJson(json), rules: rules),
          accounting: AccountingRepository(null),
        );
        await session.resolveOrgs();
        // Each business's feature states and dial, read as opening it does.
        for (final o in orgs) {
          await session.reloadFeatures(o.id);
        }
        final locked = session.planTerms.proFeatures.toSet();
        for (final o in orgs) {
          final want = o.isPro
              ? OrgAccess.allEdit
              : o.isAdmin
                  ? OrgAccess.admin(proLocked: locked)
                  : OrgAccess.forTier(rules, proLocked: locked);
          expect(session.accessFor(o.id), want, reason: '${o.profile} ${o.roles}');
          expect(session.accessFor(o.id).platformHidden, isEmpty);
        }
      });
    }

    testWidgets('the shop, the farm and the association draw the same places', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      for (final build in [store, farm, church]) {
        await tester.pumpWidget(_app(build(OrgAccess.allEdit)));
        await _settle(tester);
        final before = await _places(tester);
        await tester.pumpWidget(_app(build(const OrgAccess.admin(hidden: {}))));
        await _settle(tester);
        expect(await _places(tester), before);
        expect(before, isNotEmpty);
      }
    });

    testWidgets('a platform admin\'s bar fits at 360 with writes waiting — a shop, a farm, an association',
        (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // Two sales waiting for the network: the pending chip is on the bar.
      for (final id in ['w-1', 'w-2']) {
        await db.queueSale(orgId: 'any', clientUuid: id, params: const {});
      }
      // What business_shell.dart puts in the slot for a platform admin with
      // two activities: the pill, « Changer d'activité », the bell, Compte.
      final slot = Row(mainAxisSize: MainAxisSize.min, children: [
        const AdminPill(platformAdmin: true),
        const SwitchActivityButton(activities: 2),
        IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () {}),
        IconButton(icon: const Icon(Icons.account_circle_outlined), onPressed: () {}),
      ]);
      for (final home in [
        StoreHomeScreen(org: _shop, retail: _Shop(client), invoicing: InvoicingRepository(client),
            accountAction: slot),
        FarmHomeScreen(db: db, org: _farm, invoicing: InvoicingRepository(client), accountAction: slot),
        ChurchHomeScreen(db: db, orgId: _assoc.id, orgName: _assoc.name, org: _assoc,
            reports: ReportsRepository(client), invoicing: InvoicingRepository(client),
            onHistory: () {}, accountAction: slot),
      ]) {
        await tester.pumpWidget(_app(home));
        await _settle(tester);
        expect(find.byKey(const Key('admin-pill')), findsOneWidget);
        expect(find.text('Admin'), findsNothing, reason: 'the shield alone on a phone');
        expect(tester.takeException(), isNull, reason: '${home.runtimeType} overflows at 360');
      }
      expect(find.textContaining('2'), findsWidgets, reason: 'the pending chip is drawn');
    });

    test('Compte lists the same tools for every kind', () {
      for (final org in [_shop, _farm, _assoc, _church]) {
        expect(
            CompteScreen.toolsFor(org, const OrgAccess.admin(hidden: {}), admin: true),
            CompteScreen.toolsFor(org, OrgAccess.allEdit, admin: true),
            reason: org.profile);
      }
      expect(CompteScreen.peopleRow(const OrgAccess.forTier({'staff': 'view'}, hidden: {}), admin: false),
          'payroll');
    });
  });

  group('P2: no dead switch', () {
    test('every catalog key is read where it is drawn and at its address', () {
      final keys = _catalogKeys();
      expect(keys, isNotEmpty);
      expect(keys, _drawn.keys.toSet(),
          reason: 'a catalog key with no draw site here is a dead switch');
      final router = File('lib/core/nav/router.dart').readAsStringSync();
      for (final key in keys) {
        expect(router.contains("feature: '$key',"), isTrue,
            reason: '« $key » has no guarded address in the router');
        for (final site in _drawn[key]!.entries) {
          final src = File(site.key).readAsStringSync();
          for (final gate in site.value) {
            expect(src.contains(gate), isTrue, reason: '${site.key} does not read « $key »');
          }
        }
      }
    });

    test('a hidden key is hidden through every gate, its dial name included', () {
      for (final key in _catalogKeys()) {
        final a = OrgAccess.admin(hidden: {key});
        expect(a.isHidden(key), isTrue);
        expect(a.canSee(key), isFalse);
        expect(a.canEdit(key), isFalse);
        expect(a.isProLocked(key), isFalse, reason: 'a hidden tool is never badged');
      }
      expect(const OrgAccess.forTier({'staff': 'edit'}, hidden: {'payroll'}).canSee('staff'), isFalse);
      expect(const OrgAccess.admin(hidden: {'credits'}).canSee('tontines'), isTrue);
    });

    test('Compte drops each hidden tool, and the payroll row', () {
      for (final org in [_shop, _farm, _assoc, _church]) {
        final all = CompteScreen.toolsFor(org, OrgAccess.allEdit, admin: true);
        for (final key in _catalogKeys()) {
          final row = key == 'invoices' || key == 'payroll' ? null : key;
          if (row == null || !all.contains(row)) continue;
          expect(CompteScreen.toolsFor(org, OrgAccess.admin(hidden: {key}), admin: true),
              isNot(contains(row)), reason: '${org.profile}: $key');
        }
      }
      expect(
          CompteScreen.peopleRow(const OrgAccess.forTier({'staff': 'edit'}, hidden: {'payroll'}),
              admin: false),
          isNull);
    });

    testWidgets('a home closes up around what Mara hid', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final cases = [
        (store, {'invoices', 'production'}, ['Factures', 'Production']),
        (farm, {'invoices', 'credits', 'production'}, ['Factures', 'Carnet de crédit', 'Production']),
        (church, {'invoices'}, ['Factures']),
      ];
      for (final (build, hidden, gone) in cases) {
        await tester.pumpWidget(_app(build(OrgAccess.allEdit)));
        await _settle(tester);
        final before = await _places(tester);
        for (final g in gone) {
          expect(before, contains(g));
        }
        await tester.pumpWidget(_app(build(OrgAccess.admin(hidden: hidden))));
        await _settle(tester);
        final after = await _places(tester);
        for (final g in gone) {
          expect(after, isNot(contains(g)), reason: '$g still drawn with $hidden hidden');
        }
        expect(after.length, before.length - gone.length);
      }
    });

    testWidgets('the address of a hidden tool says « pas disponible »', (tester) async {
      await tester.pumpWidget(_app(const FeatureUnavailableScreen(org: _shop)));
      expect(find.byKey(const Key('feature-unavailable')), findsOneWidget);
      expect(find.text('Pas disponible pour votre activité'), findsOneWidget);
      expect(find.textContaining('Boutique Awa'), findsOneWidget);
      expect(find.text("Retour à l'accueil"), findsOneWidget);
    });

    /// The real app and its router, cold-booted at a tool's address (a
    /// bookmark, a bell's link) on a device that knows the business.
    Future<void> bootAt(WidgetTester tester, String location, Set<String> hidden) async {
      tester.platformDispatcher.localesTestValue = [const Locale('fr')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
      addTearDown(() => tester.binding.platformDispatcher.defaultRouteNameTestValue = '/');
      await tester.runAsync(() async {
        final salt = PinCodec.newSalt();
        await db.saveIdentity(LocalIdentity(
          userId: 'user-awa',
          displayName: 'Awa',
          phone: '+22670000001',
          pinSalt: salt,
          pinHash: PinCodec.hash('1379', salt),
          orgsRefreshedAt: DateTime.now(),
        ));
        await db.cacheOrgs(const [
          OrgSummary(id: 'org-1', name: 'Boutique Awa', profile: 'retail',
              roles: ['owner'], plan: 'pro'),
        ]);
      });
      await tester.pumpWidget(KajApp(
        db: db,
        auth: AuthRepository(null),
        admin: _Admin(FeatureStates(plan: 'pro', hidden: hidden)),
        reports: ReportsRepository(null),
        accounting: AccountingRepository(null),
        console: ConsoleRepository(null),
        farm: FarmRepository(null),
        invoicing: InvoicingRepository(null),
        retail: RetailRepository(null),
        staff: StaffRepository(null),
        capture: CaptureRepository(null, db: db),
        onboarding: OnboardingRepository(null),
      ));
      Future<void> flush() async {
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        }
        await tester.pump();
      }

      await flush();
      for (final digit in '1379'.split('')) {
        await tester.tap(find.widgetWithText(TextButton, digit));
        await tester.pump();
      }
      await flush();
    }

    testWidgets('a hidden tool\'s address is « pas disponible », in the real router', (tester) async {
      await bootAt(tester, '/o/org-1/credits', {'credits'});
      expect(find.byKey(const Key('feature-unavailable')), findsOneWidget);
      expect(find.text('Pas disponible pour votre activité'), findsOneWidget);
    });

    testWidgets('with no rule the same address opens the tool', (tester) async {
      await bootAt(tester, '/o/org-1/credits', const {});
      expect(find.byKey(const Key('feature-unavailable')), findsNothing);
      expect(find.text('Carnet de crédit'), findsWidgets);
    });

    test('a refusal for a hidden tool is said in English too, and recognised', () {
      const e = PostgrestException(
          message: "Cette fonction n'est pas disponible pour votre activité.", code: 'MA002');
      expect(isFeatureHidden(e), isTrue);
      expect(translate('en', e.message), 'This feature is not available for your business.');
      expect(isFeatureHidden(const PostgrestException(message: 'x', code: 'P0001')), isFalse);
      expect(featureHiddenCode, 'MA002');
    });

    test('an offline cold start hides what the server last said — a shop, a farm, an association',
        () async {
      const orgs = [_shop, _farm, _assoc];
      await db.cacheOrgs(orgs);
      Future<SessionController> open(FeatureStates? states) async {
        final session = SessionController(
          db: db,
          auth: AuthRepository(null),
          admin: _Admin(states),
          accounting: AccountingRepository(null),
        );
        await session.resolveOrgs();
        for (final o in orgs) {
          await session.reloadFeatures(o.id);
        }
        return session;
      }

      // The device's copy is written after the answer, without waiting.
      Future<void> kept(String orgId, String? want) async {
        for (var i = 0; i < 50 && await db.readPref('hidden_features:$orgId') != want; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(await db.readPref('hidden_features:$orgId'), want, reason: orgId);
      }

      // Online: Mara hid the credit book and the invoices.
      final online = await open(FeatureStates.fromJson(const {
        'hidden': ['invoices', 'credits'],
      }));
      for (final o in orgs) {
        expect(online.accessFor(o.id).isHidden('credits'), isTrue, reason: o.profile);
        await kept(o.id, 'credits,invoices');
      }
      online.dispose();

      // The next morning, no signal: the same tools stay hidden.
      final offline = await open(null);
      for (final o in orgs) {
        expect(offline.accessFor(o.id).isHidden('credits'), isTrue, reason: o.profile);
        expect(offline.accessFor(o.id).isHidden('invoices'), isTrue, reason: o.profile);
        expect(offline.accessFor(o.id).canSee('tontines'), isTrue, reason: o.profile);
      }
      offline.dispose();

      // Mara put them back: the copy is cleared, and offline shows them again.
      final back = await open(FeatureStates.fromJson(const {'hidden': <String>[]}));
      for (final o in orgs) {
        expect(back.accessFor(o.id).isHidden('credits'), isFalse, reason: o.profile);
        await kept(o.id, null);
      }
      back.dispose();
      final offlineAgain = await open(null);
      for (final o in orgs) {
        expect(offlineAgain.accessFor(o.id).platformHidden, isEmpty, reason: o.profile);
      }
      offlineAgain.dispose();
    });
  });
}
