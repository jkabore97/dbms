import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/org_access.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/analytics/analytics_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/features/retail/sale_flow.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
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
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/tontine/tontine_repository.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/core/notify/bell.dart';
import 'package:kaj_app/core/notify/bell_room.dart';
import 'package:kaj_app/features/notify/page_bell.dart';
import 'package:kaj_app/features/notify/push_offer.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Batch 114/115's corrections on the three homes:
///   A2 — « Activer » (the push offer) for every member who records
///        something, not the admins alone; never for an observer;
///   A4 — a tool page's title never under the bell, with or without
///        actions of its own; the bell on the row of the page's own bar
///        (tabs under it, a pane's bar);
///   A3 — the carnet's overdue credits counted on Compte only for somebody
///        who may see the carnet, an association's Compte counting them as
///        a shop's does, and no number at all for an observer.

/// The server's feature states for a business, or no signal at all.
class _Features extends AdminRepository {
  _Features(this.states) : super(null);

  FeatureStates? states;

  @override
  Future<bool> isPlatformAdmin() async => false;
  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;
  @override
  Future<FeatureStates?> featureStates(String orgId) async {
    final s = states;
    if (s == null) throw const SocketException('Failed host lookup');
    return s;
  }
  @override
  Future<Map<String, String>> featureRulesForTier(String orgId, String tier) async => const {};
}

class _Shop extends RetailRepository {
  _Shop() : super(null);

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

/// The server's home_counts: three credits past their date, nothing else.
class _Notify extends NotificationsRepository {
  _Notify() : super(null);

  @override
  bool get isConfigured => true;
  @override
  Future<NotificationCounts> counts() async => NotificationCounts.none;
  @override
  Future<Map<String, int>> homeCounts(String orgId) async => const {'credit': 3};
}

/// Who is signed in, and their numbers (none once signed out, as the
/// server answers nobody).
class _Me extends NotificationsRepository {
  _Me() : super(null);

  String? who = 'u1';

  @override
  bool get isConfigured => true;
  @override
  String? get me => who;
  @override
  void Function() watch(String userId, VoidCallback onChange) => () {};
  @override
  Future<NotificationCounts> counts() async => who == null
      ? NotificationCounts.none
      : NotificationCounts.fromJson(const {'customer': 2});
  @override
  Future<Map<String, int>> homeCounts(String orgId) async => const {};
}

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
  tearDown(() async => db.close());

  Widget scoped(NotificationsRepository notify, Widget child) {
    final session = SessionController(
      db: db,
      auth: AuthRepository(null),
      admin: AdminRepository(null),
      accounting: AccountingRepository(null),
    );
    return AppScope(
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
      retail: _Shop(),
      staff: StaffRepository(null),
      capture: CaptureRepository(null, db: db),
      onboarding: OnboardingRepository(null),
      credit: CreditRepository(null),
      tontine: TontineRepository(null),
      production: ProductionRepository(null),
      notify: notify,
      analytics: AnalyticsRepository(null),
      child: MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: child,
      ),
    );
  }

  Widget home(String kind, OrgSummary org, OrgAccess access) => switch (kind) {
        'shop' => StoreHomeScreen(org: org, retail: _Shop(), access: access),
        'farm' => FarmHomeScreen(db: db, org: org, access: access),
        _ => ChurchHomeScreen(db: db, orgId: org.id, orgName: org.name, org: org, access: access),
      };

  String profile(String kind) =>
      switch (kind) { 'shop' => 'retail', 'farm' => 'farm', _ => 'association' };

  Future<void> open(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  }

  /// The numbers drawn on the bar (the badges): every Text that is digits.
  List<String> badges(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.descendant(
            of: find.byType(NavigationBar), matching: find.byType(Text))))
          if (RegExp(r'^\d+\+?$').hasMatch(t.data ?? '')) t.data!,
      ];

  // The offer draws nothing on the test host (no push here), so it is
  // looked for in the tree, drawn or not.
  for (final kind in ['shop', 'farm', 'association']) {
    group(kind, () {
      testWidgets('A2: « Activer » for an employee who records, never for an observer',
          (tester) async {
        final employee = OrgSummary(
            id: 'o-$kind', name: 'X', profile: profile(kind), roles: const ['employee']);
        await open(tester, scoped(NotificationsRepository(null),
            home(kind, employee, OrgAccess.allEdit)));
        expect(find.byType(PushOfferCard, skipOffstage: false), findsOneWidget,
            reason: 'a $kind\'s employee is offered the ring');
        await close(tester);

        final observer = OrgSummary(
            id: 'o-$kind', name: 'X', profile: profile(kind), roles: const ['observer']);
        await open(tester, scoped(NotificationsRepository(null),
            home(kind, observer, OrgAccess.allEdit)));
        expect(find.byType(PushOfferCard, skipOffstage: false), findsNothing,
            reason: 'an observer only watches');
        await close(tester);
      });

      testWidgets('A3: the overdue credits counted only with the carnet, never for an observer',
          (tester) async {
        final admin = OrgSummary(
            id: 'c-$kind', name: 'X', profile: profile(kind), roles: const ['employee']);
        await open(tester, scoped(_Notify(), home(kind, admin, OrgAccess.allEdit)));
        expect(badges(tester), contains('3'),
            reason: 'a $kind\'s carnet counts its credits past their date');
        await close(tester);

        await open(tester, scoped(_Notify(),
            home(kind, admin, const OrgAccess.forTier({'credits': 'hidden'}))));
        expect(badges(tester), isNot(contains('3')),
            reason: 'no carnet, no count of it');
        await close(tester);

        final observer = OrgSummary(
            id: 'c-$kind', name: 'X', profile: profile(kind), roles: const ['observer']);
        await open(tester, scoped(_Notify(), home(kind, observer, OrgAccess.allEdit)));
        expect(badges(tester), isEmpty, reason: 'an observer is shown no number');
        await close(tester);
      });
    });
  }

  group('A4 — the bell and the title', () {
    const org = OrgSummary(id: 'o1', name: 'Boutique', profile: 'retail');
    const long = 'Paramètres de l\'activité et de la vitrine de la boutique';

    Widget bellOver(Widget page) => MaterialApp(
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          locale: const Locale('fr'),
          home: PageBell(
              org: org, notify: _Notify(), path: '/o/o1/administration', enabled: true, child: page),
        );

    for (final w in [360.0, 390.0]) {
      testWidgets('a long title with no action of its own stops before the bell at $w', (tester) async {
        tester.view.physicalSize = Size(w, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(bellOver(Scaffold(
            appBar: AppBar(title: const Text(long), actions: const [bellRoom]))));
        await tester.pump();
        await tester.pump();
        final bell = tester.getRect(find.byKey(const Key('page-bell')));
        final title = tester.getRect(find.text(long));
        expect(title.right, lessThanOrEqualTo(bell.left), reason: 'the title is cut before the bell');
        expect(bell.right, lessThanOrEqualTo(w));
        expect(bell.center.dy, closeTo(kToolbarHeight / 2, 1));
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('a bar with tabs: the bell on the title\'s row, not over the tabs', (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(bellOver(DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Bandes'),
            actions: const [bellRoom],
            bottom: const TabBar(tabs: [Tab(text: 'Volailles'), Tab(text: 'Élevage')]),
          ),
        ),
      )));
      await tester.pump();
      await tester.pump();
      final bell = tester.getRect(find.byKey(const Key('page-bell')));
      expect(bell.center.dy, closeTo(tester.getCenter(find.text('Bandes')).dy, 1));
      expect(bell.bottom, lessThanOrEqualTo(tester.getRect(find.byType(TabBar)).top + 0.5));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a wide page whose bar is a pane\'s: the bell at that pane\'s end, on its row',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(bellOver(Material(
        child: Column(children: [
          const SizedBox(height: 40, child: Text('Bandeau')),
          Expanded(
            child: Row(children: [
              SizedBox(
                width: 420,
                child: Scaffold(appBar: AppBar(title: const Text(long), actions: const [bellRoom])),
              ),
              const Expanded(child: ColoredBox(color: Colors.white)),
            ]),
          ),
        ]),
      )));
      await tester.pump();
      await tester.pump();
      final bell = tester.getRect(find.byKey(const Key('page-bell')));
      expect(bell.right, closeTo(420, 1));
      expect(bell.center.dy, closeTo(40 + kToolbarHeight / 2, 1));
      expect(tester.getRect(find.text(long)).right, lessThanOrEqualTo(bell.left));
      await tester.pumpWidget(const SizedBox());
    });

    test('every AppBar in the app ends its actions with bellRoom', () {
      final missing = <String>[];
      for (final f in Directory('lib/features').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        var i = src.indexOf(RegExp(r'\bAppBar\('));
        while (i >= 0) {
          var depth = 0, j = i + 'AppBar'.length;
          do {
            if (src[j] == '(') depth++;
            if (src[j] == ')') depth--;
            j++;
          } while (depth > 0);
          if (!src.substring(i, j).contains('bellRoom')) {
            missing.add('${f.path}:${'\n'.allMatches(src.substring(0, i)).length + 1}');
          }
          final next = src.substring(j).indexOf(RegExp(r'\bAppBar\('));
          i = next < 0 ? -1 : j + next;
        }
      }
      expect(missing, isEmpty);
    });
  });

  testWidgets('Facture: the document pushed from the page under the flow comes over « C\'est fait », and back returns to it',
      (tester) async {
    late BuildContext page;
    final router = GoRouter(initialLocation: '/factures', routes: [
      GoRoute(
        path: '/factures',
        builder: (context, _) {
          page = context;
          return const Scaffold(body: Text('Factures'));
        },
      ),
      GoRoute(path: '/factures/f1', builder: (_, _) => const Scaffold(body: Text('Le document'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    // The flow, as StepFlow.push opens it, at its « C'est fait ».
    Navigator.of(page).push(MaterialPageRoute<bool>(
        fullscreenDialog: true, builder: (_) => const Scaffold(body: Text('C\'est fait'))));
    await tester.pumpAndSettle();
    // InvoicesScreen._openDocument, called by the flow once created.
    unawaited(page.push('/factures/f1'));
    await tester.pumpAndSettle();
    expect(find.text('Le document'), findsOneWidget);
    expect(find.text('C\'est fait', skipOffstage: true), findsNothing, reason: 'the document is on top');
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('C\'est fait'), findsOneWidget, reason: 'the done screen waited behind it');
  });

  group('lost capabilities', () {
    test('« Mobile » at the till offline: the last « Wave autorisé » the device heard', () async {
      const org = OrgSummary(id: 'w1', name: 'Boutique', profile: 'retail', roles: ['owner']);
      await db.cacheOrgs(const [org]);
      final online = SessionController(
          db: db, auth: AuthRepository(null),
          admin: _Features(FeatureStates.fromJson(const {'plan': 'free', 'wave_allowed': true})),
          accounting: AccountingRepository(null));
      await online.resolveOrgs();
      await online.reloadFeatures('w1');
      expect(online.waveAllowedFor('w1'), isTrue);

      // The next start, with no signal: the feature states cannot be read.
      final offline = SessionController(
          db: db, auth: AuthRepository(null), admin: _Features(null),
          accounting: AccountingRepository(null));
      await offline.resolveOrgs();
      await offline.reloadFeatures('w1');
      expect(offline.featuresFor('w1'), isNull);
      expect(offline.waveAllowedFor('w1'), isTrue, reason: 'Mobile stays at the till');

      // Mara takes it back: heard, kept, and offline it stays taken back.
      final back = SessionController(
          db: db, auth: AuthRepository(null),
          admin: _Features(FeatureStates.fromJson(const {'plan': 'free', 'wave_allowed': false})),
          accounting: AccountingRepository(null));
      await back.resolveOrgs();
      await back.reloadFeatures('w1');
      final again = SessionController(
          db: db, auth: AuthRepository(null), admin: _Features(null),
          accounting: AccountingRepository(null));
      await again.resolveOrgs();
      await again.reloadFeatures('w1');
      expect(again.waveAllowedFor('w1'), isFalse);
      // A business never heard of: no.
      expect(again.waveAllowedFor('nobody'), isFalse);
      for (final s in [online, offline, back, again]) {
        s.dispose();
      }
    });

    test('« Banque » at the till waits for the owner: the one-line switch is empty', () {
      expect(tillExtraMethods, isEmpty);
    });
  });

  group('nits', () {
    testWidgets('the bell says nothing the moment the person signs out', (tester) async {
      final notify = _Me();
      final bell = Bell(notify);
      var told = 0;
      void listener() => told++;
      bell.addListener(listener);
      await tester.runAsync(bell.refresh);
      expect(bell.unreadOf(NotifyScope.customer), 2);
      final before = told;
      notify.who = null;
      await tester.runAsync(bell.refresh);
      expect(bell.unreadOf(NotifyScope.customer), 0);
      expect(told, greaterThan(before), reason: 'the bells were told at once');
      bell.removeListener(listener);
      bell.dispose();
    });

    testWidgets('the minute\'s poll stops in the background and starts again on return', (tester) async {
      final notify = _Me();
      final bell = Bell(notify);
      void listener() {}
      bell.addListener(listener);
      expect(bell.polling, isTrue);
      bell.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(bell.polling, isFalse);
      bell.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(bell.polling, isTrue);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      bell.removeListener(listener);
      expect(bell.polling, isFalse);
      bell.dispose();
    });

    testWidgets('the shopper\'s profile keeps no empty gap where the offer is not drawn', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            PushOfferCard(
              key: Key('offer'),
              notify: null,
              padding: EdgeInsets.only(top: 16),
              message: 'x',
            ),
          ]),
        ),
      ));
      expect(tester.getSize(find.byKey(const Key('offer'))).height, 0);
    });
  });
}
