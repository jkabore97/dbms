import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
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
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/tontine/tontine_repository.dart';
import 'package:kaj_app/features/admin/admin_pill.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/home/business_shell.dart';
import 'package:kaj_app/features/setup/association_setup_screen.dart';
import 'package:kaj_app/features/setup/setup_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Batch 104's corrections that need the app's own scope around a screen:
/// the « Admin » pill on the first setup of a shop, a farm and an
/// association (a platform admin only), and a frozen business's banner
/// that does not pad its home for the status bar a second time.

class _Server extends AuthRepository {
  _Server(this.orgs) : super(null);

  final List<OrgSummary> orgs;

  @override
  bool get hasLiveSession => true;

  @override
  Future<List<OrgSummary>> fetchOrgs() async => orgs;
}

class _Admin extends AdminRepository {
  _Admin({required this.platform}) : super(null);

  final bool platform;

  @override
  Future<bool> isPlatformAdmin() async => platform;

  @override
  Future<int> claimMyInvitations() async => 0;

  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;

  @override
  Future<FeatureStates?> featureStates(String orgId) async => null;

  @override
  Future<Map<String, String>> featureRulesForTier(String orgId, String tier) async => const {};
}

/// The setups' writes, never reached here.
class _Steps implements SetupActions {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _AssociationSteps implements AssociationSetupActions {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

const _shop = OrgSummary(id: 'r1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);
const _farm = OrgSummary(id: 'f1', name: 'Ferme du Nord', profile: 'farm', roles: ['owner']);
const _assoc = OrgSummary(id: 'a1', name: 'Entraide', profile: 'association', roles: ['owner']);

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
  tearDown(() async {
    AdminTrail.opened.value = null;
    await db.close();
  });

  /// A session resolved for someone who is (or is not) a platform admin.
  Future<SessionController> signedIn(WidgetTester tester, {required bool platform}) async {
    final session = SessionController(
      db: db,
      auth: _Server(const [_shop, _farm, _assoc]),
      admin: _Admin(platform: platform),
      accounting: AccountingRepository(null),
    );
    await tester.runAsync(session.resolveOrgs);
    expect(session.isPlatformAdmin, platform);
    return session;
  }

  /// The app's scope, every repository offline, around [child].
  Widget app(SessionController session, Widget child, {double statusBar = 0}) => AppScope(
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
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(padding: EdgeInsets.only(top: statusBar)),
              child: child,
            ),
          ),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Widget setupFor(OrgSummary org) => org.profile == 'association'
      ? AssociationSetupScreen(org: org, actions: _AssociationSteps(), onDone: () {})
      : SetupScreen(org: org, actions: _Steps(), onDone: () {});

  for (final width in [360.0, 1280.0]) {
    testWidgets('the first setup carries « Admin » for a platform admin at $width — a shop, a farm, an association',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final session = await signedIn(tester, platform: true);
      for (final org in [_shop, _farm, _assoc]) {
        await tester.pumpWidget(app(session, setupFor(org)));
        await settle(tester);
        expect(find.text('Mise en route'), findsOneWidget, reason: org.profile);
        final pill = find.byKey(const Key('admin-pill'));
        expect(pill, findsOneWidget, reason: org.profile);
        expect(find.text('Admin'), width < 400 ? findsNothing : findsOneWidget,
            reason: 'the shield alone on a phone (${org.profile})');
        // In the header row, beside the step count, on the screen.
        final count = find.byKey(Key(org.profile == 'association' ? 'asetup-count' : 'setup-count'));
        expect(tester.getCenter(pill).dy, closeTo(tester.getCenter(count).dy, 12), reason: org.profile);
        expect(tester.getRect(pill).right, lessThanOrEqualTo(width), reason: org.profile);
        expect(tester.takeException(), isNull, reason: '${org.profile} overflows at $width');
      }
    });
  }

  testWidgets('the first setup has no pill for anybody else — P1: as before', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final session = await signedIn(tester, platform: false);
    for (final org in [_shop, _farm, _assoc]) {
      await tester.pumpWidget(app(session, setupFor(org)));
      await settle(tester);
      expect(find.text('Mise en route'), findsOneWidget, reason: org.profile);
      expect(find.byKey(const Key('admin-pill')), findsNothing, reason: org.profile);
    }
  });

  testWidgets('a frozen business\'s banner takes the status bar: the home under it does not pad again',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final session = await signedIn(tester, platform: true);
    const frozen = OrgSummary(
        id: 'f1', name: 'Ferme du Nord', profile: 'farm', roles: ['owner'], suspended: true);
    double homeTop() => MediaQuery.paddingOf(tester.element(find.byType(FarmHomeScreen))).top;

    await tester.pumpWidget(app(session, const BusinessShell(org: frozen), statusBar: 24));
    await settle(tester);
    expect(find.textContaining('Cette entreprise est suspendue'), findsOneWidget);
    expect(homeTop(), 0, reason: 'no second status bar under the frozen banner');
    expect(tester.takeException(), isNull);

    // Opened from the center as well: the two strips, one status bar.
    AdminTrail.opened.value = (orgId: 'f1', from: Routes.consoleBusinesses);
    await tester.pumpWidget(app(session, const BusinessShell(org: frozen), statusBar: 24));
    await settle(tester);
    expect(find.byKey(const Key('admin-return')), findsOneWidget);
    expect(find.textContaining('Cette entreprise est suspendue'), findsOneWidget);
    expect(homeTop(), 0);
    expect(tester.takeException(), isNull);
  });
}
