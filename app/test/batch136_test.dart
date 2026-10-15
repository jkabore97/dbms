// Batch 136: « Besoin d'aide » — Mara's training team behind Mara Pro
// (migration 133; the owner's approved mockups, scratchpad/aide_mockups).
//
//   1. the button on all three homes: « Besoin d'aide » (caramel) for a Pro
//      business's member, « Aide » for a free one or a database without
//      133, « Demandes » for a trainer, nothing for a platform admin or an
//      observer who is no trainer — the business's name kept beside it, in
//      French and in English, at 390 px and 320 px;
//   2. the request (143: the step-by-step « Demander un formateur » that
//      replaced 136's sheet): the kind's own subjects, a subject needed,
//      the contact chosen, the number asked when the account has none, the
//      screen sent, the hours said out of them, nothing left today;
//   3. the status (143: under « Mes demandes »): waiting (and when an
//      answer comes), taken (WhatsApp and call, « Autoriser l'accès 48 h »
//      only for a trainer not of the business and only for an admin), the
//      access live and its « Retirer », « C'est réglé ? », « Fermer la
//      demande » with a thumb; the free page: FAQ, guides, Mara's contacts
//      « réponse sous 48 h », « Signaler un problème » — and, since 143, no
//      « Avec Mara Pro » card (the once-a-day pop-up and the FAQ banner,
//      batch143_test);
//   4. the trainer's inbox: « Je m'en occupe », WhatsApp / call / resolved
//      with a note, the visit's two answers, « Ouvrir l'activité (lecture
//      seule) » only with a live access, on/off duty, nothing for others;
//   5. the admin: « Aujourd'hui »'s two counters (late among the urgent,
//      only with 133), the console (numbers, the late one, WhatsApp's
//      state, the trainers), the settings in Réglages;
//   6. the bells: where each opens, and its English.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/help/help_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/invoicing/models.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/admin/center/todo_section.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/help/help_button.dart';
import 'package:kaj_app/features/help/help_console_screen.dart';
import 'package:kaj_app/features/help/help_screen.dart';
import 'package:kaj_app/features/account/support.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/help/help_contact.dart';
import 'package:kaj_app/features/help/help_request_flow.dart';
import 'package:kaj_app/features/help/help_requests_screen.dart';
import 'package:kaj_app/features/help/help_words.dart';
import 'package:kaj_app/features/help/trainer_inbox_screen.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// The businesses
// ---------------------------------------------------------------------------

const _shopPro = OrgSummary(
    id: '13600000-0000-0000-0000-0000000000a1',
    name: 'Salon Belle Vie',
    slug: 'salon-belle-vie',
    profile: 'retail',
    plan: 'pro',
    roles: ['owner']);
const _farmPro = OrgSummary(
    id: '13600000-0000-0000-0000-0000000000a2',
    name: 'Ferme Wendkouni',
    slug: 'ferme-wendkouni',
    profile: 'farm',
    plan: 'pro',
    roles: ['owner']);
const _assocPro = OrgSummary(
    id: '13600000-0000-0000-0000-0000000000a3',
    name: 'Groupement Wend-Panga',
    slug: 'wend-panga',
    profile: 'association',
    plan: 'pro',
    roles: ['owner']);

OrgSummary _as(OrgSummary o, {String? plan, List<String>? roles}) => OrgSummary(
    id: o.id, name: o.name, slug: o.slug, profile: o.profile, plan: plan ?? o.plan, roles: roles ?? o.roles);

final _now = DateTime.now();

HelpState _proState({HelpRequest? request, bool inHours = true, int left = 5}) => HelpState(
      available: true,
      pro: true,
      hours: HelpHours(
        open: 7,
        close: 21,
        inHours: inHours,
        nextOpen: inHours ? _now : DateTime.utc(_now.year, _now.month, _now.day + 1, 7),
      ),
      request: request,
      left: left,
    );

const _freeState = HelpState(available: true, pro: false);

HelpRequest _req({
  String status = 'open',
  HelpTrainer? trainer,
  HelpAccess? access,
  bool mine = true,
  String contact = 'whatsapp',
  DateTime? routedAt,
}) =>
    HelpRequest(
      id: 'req-1',
      subject: 'ventes',
      contact: contact,
      status: status,
      createdAt: _now.subtract(const Duration(minutes: 2)),
      routedAt: routedAt ?? _now.subtract(const Duration(minutes: 2)),
      message: 'Je n\'arrive pas à annuler une vente',
      takenAt: trainer == null ? null : _now,
      trainer: trainer,
      access: access,
      mine: mine,
      resolutionNote: status == 'resolved' ? 'Vente annulée ensemble' : null,
    );

// ---------------------------------------------------------------------------
// The server
// ---------------------------------------------------------------------------

class _Help extends HelpRepository {
  _Help({
    HelpState? state,
    this.inboxAnswer = HelpInbox.none,
    this.consoleAnswer,
  })  : stateAnswer = state ?? _proState(),
        super(null);

  HelpState stateAnswer;
  HelpInbox inboxAnswer;
  HelpConsole? consoleAnswer;
  final calls = <String>[];
  Map<String, Object?>? created;

  @override
  bool get isConfigured => true;

  @override
  Future<HelpState> state(String orgId) async => stateAnswer;

  @override
  Future<HelpRequest> create({
    required String orgId,
    required String subject,
    required String contact,
    String? message,
    String? phone,
    String? photoDocumentId,
    DateTime? preferredAt,
    String? subjectWords,
    String? whenWords,
    int server = HelpState.current,
    Map<String, String> context = const {},
  }) async {
    created = {
      'org': orgId,
      'subject': subject,
      'contact': contact,
      'message': message,
      'phone': phone,
      'screen': context['screen'],
    };
    final r = _req(contact: contact);
    stateAnswer = _proState(request: r);
    return r;
  }

  @override
  Future<HelpRequest> close(String id, {int? rating}) async {
    calls.add('close:$id:$rating');
    stateAnswer = _proState();
    return _req(status: 'closed');
  }

  @override
  Future<HelpRequest> reopen(String id) async {
    calls.add('reopen:$id');
    return _req(status: 'taken');
  }

  @override
  Future<HelpRequest> grantAccess(String id) async {
    calls.add('grant:$id');
    return _req(status: 'taken');
  }

  @override
  Future<void> revokeAccess(String id) async => calls.add('revoke:$id');

  @override
  Future<HelpInbox> inbox() async => inboxAnswer;

  @override
  Future<bool> setOnDuty(bool on) async {
    calls.add('duty:$on');
    return on;
  }

  @override
  Future<InboxRequest> take(String id) async {
    calls.add('take:$id');
    return inboxAnswer.requests.first;
  }

  @override
  Future<InboxRequest> answerVisit(String id, String answer, {String? note}) async {
    calls.add('visit:$id:$answer:$note');
    return inboxAnswer.requests.first;
  }

  @override
  Future<InboxRequest> resolve(String id, {String? note}) async {
    calls.add('resolve:$id:$note');
    return inboxAnswer.requests.first;
  }

  @override
  Future<String> openAccess(String id) async {
    calls.add('open:$id');
    return 'org-x';
  }

  @override
  Future<HelpConsole?> console() async => consoleAnswer;
}

class _Shelf extends RetailRepository {
  _Shelf() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();
  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) async => const [];
  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [];
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
  _Bills() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<List<InvoiceSummary>> list(String orgId, {bool includePaid = true, int limit = 200}) async =>
      const [];
  @override
  Future<BillingDetails> billingDetails(String orgId) async => const BillingDetails();
}

class _Center extends CommandCenterRepository {
  _Center(this.answer) : super(null);
  final PlatformTodo answer;
  @override
  bool get isConfigured => true;
  @override
  Future<PlatformTodo> todo() async => answer;
  @override
  Future<PlatformToday?> today() async => null;
  @override
  Future<PlatformOverview?> overview() async => null;
  @override
  Future<TodayCounts?> todayCounts() async => null;
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _phone(WidgetTester tester, {double width = 390, double height = 844}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _home(OrgSummary org, LocalDb db, HelpRepository help) => switch (org.profile) {
      'retail' => StoreHomeScreen(org: org, retail: _Shelf(), invoicing: _Bills(), help: help),
      'farm' => FarmHomeScreen(db: db, org: org, retail: _Shelf(), invoicing: _Bills(), help: help),
      _ => ChurchHomeScreen(
          db: db,
          orgId: org.id,
          orgName: org.name,
          org: org,
          reports: ReportsRepository(null),
          invoicing: _Bills(),
          retail: _Shelf(),
          onHistory: () {},
          help: help,
        ),
    };

/// The home at `/o/<id>`, its `aide` page, the inbox and a stub for the
/// rest — as the router has them.
GoRouter _router(Widget Function() home, OrgSummary org, _Help help, {String? at, List<String>? went}) =>
    GoRouter(initialLocation: at ?? '/o/${org.id}', routes: [
      GoRoute(
        path: '/o/:orgId',
        builder: (_, _) => home(),
        routes: [
          GoRoute(
              path: 'aide',
              builder: (_, _) {
                went?.add('aide');
                return HelpScreen(org: org, help: help);
              },
              routes: [
                GoRoute(
                    path: 'demandes',
                    builder: (_, state) {
                      went?.add('demandes');
                      return HelpRequestsScreen(
                          org: org, help: help, focus: state.uri.queryParameters['demande']);
                    }),
              ]),
          for (final r in const ['chemin', 'kaj-pro'])
            GoRoute(path: r, builder: (_, _) {
              went?.add(r);
              return Scaffold(body: Text('page $r'));
            }),
        ],
      ),
      GoRoute(path: Routes.trainerInbox, builder: (_, state) {
        went?.add('inbox');
        return TrainerInboxScreen(help: help, focus: state.uri.queryParameters['demande']);
      }),
      GoRoute(path: Routes.faq, builder: (_, _) {
        went?.add('faq');
        return const Scaffold(body: Text('page faq'));
      }),
      GoRoute(path: Routes.consoleHelp, builder: (_, _) {
        went?.add('console-help');
        return HelpConsoleScreen(help: help);
      }),
    ]);

Widget _routed(GoRouter r, {Locale locale = const Locale('fr')}) => MaterialApp.router(
      locale: locale,
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      routerConfig: r,
    );

Widget _app(Widget home, {Locale locale = const Locale('fr')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

InboxRequest _inboxRow({
  String id = 'r1',
  String status = 'open',
  bool mine = false,
  String contact = 'whatsapp',
  DateTime? accessUntil,
  bool member = false,
  String org = 'Salon Belle Vie',
  String? visitAnswer,
}) =>
    InboxRequest(
      id: id,
      orgId: 'o-$id',
      org: org,
      profile: 'retail',
      subject: 'ventes',
      contact: contact,
      status: status,
      createdAt: _now.subtract(const Duration(minutes: 1)),
      city: 'Ouagadougou',
      message: 'Je n\'arrive pas à annuler une vente',
      screen: 'Vente',
      mine: mine,
      takenBy: mine ? 'Awa' : null,
      phone: mine ? '22670000001' : null,
      accessUntil: accessUntil,
      member: member,
      visitAnswer: visitAnswer,
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
  });

  late LocalDb db;
  setUp(() async {
    HelpButton.reset();
    HelpContact.reset();
    HelpContact.debugStore = MemoryHelpPrefs();
    Support.reset();
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  // -------------------------------------------------------------------------
  group('1. the button on all three homes', () {
    for (final org in [_shopPro, _farmPro, _assocPro]) {
      for (final width in [390.0, 320.0]) {
        testWidgets('${org.profile} Pro at $width px: « Besoin d\'aide », the name kept', (tester) async {
          await _phone(tester, width: width);
          await tester.pumpWidget(_app(_home(org, db, _Help())));
          await _settle(tester);
          expect(find.byKey(const Key('help-pro-button')), findsOneWidget);
          expect(find.byKey(const Key('help-free-button')), findsNothing);
          expect(find.text(org.name), findsOneWidget, reason: 'the business keeps its name');
          if (width >= HelpButton.wordsWidth) {
            // On a phone the label is on two lines, never cut.
            expect(find.text('Besoin\nd\'aide'), findsOneWidget);
          } else {
            // 140: « Ma vitrine » shares the bar — both icons under 360.
            expect(find.descendant(of: find.byKey(const Key('help-pro-button')), matching: find.byType(Text)),
                findsNothing);
            expect(find.byTooltip('Besoin d\'aide'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }

      // Review of 136: at 320 px with large text the pill took the room of
      // the business's name (« Group / eme… »). Since 140 (« Ma vitrine » on
      // the bar) the help leaves it there for Compte › Aide.
      for (final free in [false, true]) {
        testWidgets('${org.profile} ${free ? 'free' : 'Pro'} at 320 px, text ×1.3: help in Compte, the name its room',
            (tester) async {
          await _phone(tester, width: 320);
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(_app(_home(
              free ? _as(org, plan: 'free') : org, db, free ? _Help(state: _freeState) : _Help())));
          await _settle(tester);
          final key = Key(free ? 'help-free-button' : 'help-pro-button');
          expect(find.byKey(key), findsNothing);
          expect(find.byTooltip('Ma vitrine'), findsOneWidget);
          expect(find.text(org.name), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }

      // 136's guarantee kept where « Ma vitrine » is not on the bar (no
      // vitrine address yet): the help stays, its icon alone.
      for (final free in [false, true]) {
        testWidgets('${org.profile} ${free ? 'free' : 'Pro'} at 320 px, text ×1.3, no vitrine: the icon alone',
            (tester) async {
          await _phone(tester, width: 320);
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final bare = OrgSummary(
              id: org.id, name: org.name, profile: org.profile, plan: free ? 'free' : org.plan, roles: org.roles);
          await tester.pumpWidget(_app(_home(bare, db, free ? _Help(state: _freeState) : _Help())));
          await _settle(tester);
          final key = Key(free ? 'help-free-button' : 'help-pro-button');
          expect(find.byTooltip('Ma vitrine'), findsNothing);
          expect(find.byKey(key), findsOneWidget);
          expect(find.descendant(of: find.byKey(key), matching: find.byType(Text)), findsNothing);
          expect(find.byTooltip(free ? 'Aide' : 'Besoin d\'aide'), findsOneWidget);
          expect(tester.getSize(find.byKey(key)).width, lessThanOrEqualTo(48));
          expect(find.text(org.name), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }

      // A request on (140): beside « Ma vitrine » the help stays, its dot
      // in sight.
      testWidgets('${org.profile} Pro at 320 px, text ×1.3, a request on: the help stays', (tester) async {
        await _phone(tester, width: 320);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(_app(_home(org, db, _Help(state: _proState(request: _req())))));
        await _settle(tester);
        expect(find.byTooltip('Ma vitrine'), findsOneWidget);
        expect(find.byKey(const Key('help-pro-button')), findsOneWidget);
        expect(find.text(org.name), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${org.profile} free: « Aide »', (tester) async {
        await _phone(tester);
        await tester.pumpWidget(_app(_home(_as(org, plan: 'free'), db, _Help(state: _freeState))));
        await _settle(tester);
        expect(find.byKey(const Key('help-free-button')), findsOneWidget);
        expect(find.byKey(const Key('help-pro-button')), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${org.profile} Pro on a database without 133: the basic « Aide »', (tester) async {
        await _phone(tester);
        await tester.pumpWidget(_app(_home(org, db, _Help(state: HelpState.missing))));
        await _settle(tester);
        expect(find.byKey(const Key('help-free-button')), findsOneWidget);
        expect(find.byKey(const Key('help-pro-button')), findsNothing);
      });
    }

    testWidgets('the first frame guesses from the cached plan, before the server answers', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(_home(_shopPro, db, _Help())));
      expect(find.byKey(const Key('help-pro-button')), findsOneWidget);
    });

    testWidgets('an active request: a dot on the button', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(_home(_shopPro, db, _Help(state: _proState(request: _req())))));
      await _settle(tester);
      expect(find.byKey(const Key('help-pro-active')), findsOneWidget);
    });

    testWidgets('a trainer in a business they help: « Demandes », with what waits', (tester) async {
      await _phone(tester);
      final help = _Help(
          inboxAnswer: HelpInbox(trainer: true, requests: [_inboxRow(), _inboxRow(id: 'r2')]));
      await tester.pumpWidget(_app(_home(_as(_shopPro, roles: ['observer']), db, help)));
      await _settle(tester);
      expect(find.byKey(const Key('help-trainer-button')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byKey(const Key('help-pro-button')), findsNothing);
    });

    testWidgets('an observer who is no trainer, and a platform admin in someone else\'s business: no button',
        (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(_home(_as(_shopPro, roles: ['observer']), db, _Help())));
      await _settle(tester);
      expect(find.byKey(const Key('help-trainer-button')), findsNothing);
      expect(find.byKey(const Key('help-pro-button')), findsNothing);
      // help_state says « not available »: no membership of theirs here.
      await tester.pumpWidget(_app(_home(_as(_farmPro, roles: ['platform_admin']), db,
          _Help(state: const HelpState(available: false)))));
      await _settle(tester);
      expect(find.byKey(const Key('help-pro-button')), findsNothing);
      expect(find.byKey(const Key('help-free-button')), findsNothing);
    });

    // 143's fix: my_orgs() gives a platform admin « platform_admin » in
    // their own business too; 136 hid the button there for good.
    testWidgets('a platform admin in their OWN business: the button, as its owner has it', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(_home(_as(_farmPro, roles: ['platform_admin'], plan: 'free'), db,
          _Help(state: _freeState))));
      await _settle(tester);
      expect(find.byKey(const Key('help-free-button')), findsOneWidget);
    });

    testWidgets('English: « Need help » and « Help »', (tester) async {
      await _phone(tester, width: 1000);
      await tester.pumpWidget(_app(_home(_shopPro, db, _Help()), locale: const Locale('en')));
      await _settle(tester);
      expect(find.text('Need help'), findsOneWidget);
      await tester.pumpWidget(_app(_home(_as(_assocPro, plan: 'free'), db, _Help(state: _freeState)),
          locale: const Locale('en')));
      await _settle(tester);
      expect(find.text('Help'), findsOneWidget);
    });

    testWidgets('the free button opens the free « Aide » page; the Pro one its page, the request under « Mes demandes »',
        (tester) async {
      await _phone(tester);
      final went = <String>[];
      final free = _Help(state: _freeState);
      final freeOrg = _as(_shopPro, plan: 'free');
      await tester.pumpWidget(_routed(_router(() => _home(freeOrg, db, free), freeOrg, free, went: went)));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('help-free-button')));
      await _settle(tester);
      expect(went, contains('aide'));
      expect(find.byKey(const Key('help-faq')), findsOneWidget);

      HelpButton.reset();
      went.clear();
      final pro = _Help(state: _proState(request: _req()));
      await tester.pumpWidget(_routed(_router(() => _home(_farmPro, db, pro), _farmPro, pro, went: went)));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('help-pro-button')));
      await _settle(tester);
      expect(went, contains('aide'));
      expect(find.byKey(const Key('help-ask')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('help-my-requests')));
      await tester.tap(find.byKey(const Key('help-my-requests')));
      await _settle(tester);
      expect(went, contains('demandes'));
      await tester.tap(find.byKey(const Key('help-request-req-1')));
      await _settle(tester);
      expect(find.byKey(const Key('help-request-card')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('2. the request (143: the flow that replaced the sheet)', () {
    Future<void> flow(WidgetTester tester, OrgSummary org, HelpState state, _Help help,
        {String? phone = '22670000000'}) async {
      await _phone(tester);
      await tester.pumpWidget(_app(HelpRequestFlow(
          org: org, state: state, help: help, phone: phone, store: MemoryFlowStore(), screen: 'Vente')));
      await _settle(tester);
    }

    for (final (org, first, own) in [
      (_shopPro, 'Articles / Catalogue', 'Caisse / Ventes'),
      (_farmPro, 'Articles / Catalogue', 'Bandes / Récoltes'),
      (_assocPro, 'Articles / Catalogue', 'Cotisations'),
    ]) {
      testWidgets('${org.profile}: its own subjects, « Autre » last', (tester) async {
        await flow(tester, org, _proState(), _Help());
        final subjects = helpSubjectsFor(org.profile);
        expect(subjects.last, 'autre');
        expect(subjects, hasLength(switch (org.profile) { 'farm' => 10, 'association' => 11, _ => 8 }));
        expect(find.text(first), findsOneWidget);
        await tester.scrollUntilVisible(find.text(own), 200);
        expect(find.text(own), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Autre'), 200);
        expect(find.text('Autre'), findsOneWidget);
      });
    }

    testWidgets('a subject is needed; the number is asked; sent with the screen', (tester) async {
      final help = _Help();
      await flow(tester, _shopPro, _proState(), help, phone: null);
      final next = find.byKey(const Key('flow-next'));
      expect(tester.widget<FilledButton>(next).onPressed, isNull, reason: 'a subject is needed');
      await tester.tap(find.byKey(const Key('flow-option-catalogue')));
      await tester.pump();
      await tester.tap(next);
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('help-message')), 'Le stock ne baisse pas');
      await tester.pump();
      await tester.tap(next);
      await _settle(tester);
      await tester.tap(find.byKey(const Key('flow-option-visit')));
      await tester.pump();
      // No account number: asked, and « Suivant » waits for it.
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('help-phone')), '+226 70 12 34 56');
      await tester.pump();
      await tester.tap(next);
      await _settle(tester);
      await tester.tap(next); // « Maintenant »
      await _settle(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await _settle(tester);
      expect(help.created, {
        'org': _shopPro.id,
        'subject': 'catalogue',
        'contact': 'visit',
        'message': 'Le stock ne baisse pas',
        'phone': '22670123456',
        'screen': 'Vente',
      });
      expect(find.byKey(const Key('flow-done')), findsOneWidget);
    });

    testWidgets('out of the hours: the Aide page says when a trainer answers', (tester) async {
      await _phone(tester, height: 1200);
      final help = _Help(state: _proState(inHours: false));
      await tester.pumpWidget(_routed(_router(() => const SizedBox(), _shopPro, help, at: '/o/${_shopPro.id}/aide')));
      await _settle(tester);
      expect(find.textContaining('Un formateur vous répondra demain à partir de 7 h'), findsOneWidget);
    });

    testWidgets('nothing left today: « Nouvelle demande » is off and says why', (tester) async {
      await _phone(tester, height: 1200);
      final help = _Help(state: _proState(left: 0, request: _req(status: 'closed')));
      await tester.pumpWidget(
          _routed(_router(() => const SizedBox(), _shopPro, help, at: '/o/${_shopPro.id}/aide/demandes')));
      await _settle(tester);
      final add = tester.widget<FilledButton>(find.byKey(const Key('help-new-request')));
      expect(add.onPressed, isNull);
      expect(find.byKey(const Key('help-none-left')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('3. the status, and the free page', () {
    // 143: a request's status is its own page under « Mes demandes »
    // (?demande= opens it, as a bell does).
    Future<_Help> open(WidgetTester tester, HelpState s, {OrgSummary org = _shopPro}) async {
      await _phone(tester, height: 1200);
      final help = _Help(state: s);
      await tester.pumpWidget(_routed(
          _router(() => const SizedBox(), org, help, at: '/o/${org.id}/aide/demandes?demande=req-1')));
      await _settle(tester);
      return help;
    }

    testWidgets('waiting: received, then « En attente d\'un formateur »', (tester) async {
      await open(tester, _proState(request: _req()));
      expect(find.byKey(const Key('help-step-received')), findsOneWidget);
      expect(find.byKey(const Key('help-step-waiting')), findsOneWidget);
      expect(find.text('Un formateur va prendre votre demande.'), findsOneWidget);
      expect(find.byKey(const Key('help-grant-card')), findsNothing);
      expect(find.byKey(const Key('help-write-trainer')), findsNothing);
    });

    testWidgets('queued out of the hours: when the answer comes', (tester) async {
      await open(tester,
          _proState(request: _req(routedAt: DateTime.utc(_now.year, _now.month, _now.day + 1, 7))));
      expect(find.text('Un formateur vous répondra demain à partir de 7 h'), findsOneWidget);
    });

    testWidgets('taken by a trainer not of the business: WhatsApp, call, « Autoriser l\'accès 48 h »',
        (tester) async {
      final help = await open(tester,
          _proState(request: _req(status: 'taken', trainer: const HelpTrainer(firstName: 'Awa', phone: '22670000001'))));
      expect(find.byKey(const Key('help-step-taken')), findsOneWidget);
      expect(find.text('Awa, de l\'équipe de formation, s\'en occupe'), findsOneWidget);
      expect(find.byKey(const Key('help-write-trainer')), findsOneWidget);
      expect(find.text('Écrire à Awa'), findsOneWidget);
      expect(find.byKey(const Key('help-call-trainer')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('help-grant')));
      await tester.tap(find.byKey(const Key('help-grant')));
      await _settle(tester);
      expect(find.text('Autoriser l\'accès 48 h ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('help-grant-confirm')));
      await _settle(tester);
      expect(help.calls, ['grant:req-1']);
    });

    testWidgets('taken by an assigned trainer (already of the business): no access to give', (tester) async {
      await open(tester,
          _proState(request: _req(status: 'taken', trainer: const HelpTrainer(firstName: 'Awa', member: true))));
      expect(find.byKey(const Key('help-grant-card')), findsNothing);
    });

    testWidgets('a member who is not an admin: no access to give, no close', (tester) async {
      await open(tester,
          _proState(request: _req(status: 'taken', mine: false, trainer: const HelpTrainer(firstName: 'Awa'))),
          org: _as(_shopPro, roles: ['employee']));
      expect(find.byKey(const Key('help-grant-card')), findsNothing);
      expect(find.byKey(const Key('help-close')), findsNothing);
    });

    testWidgets('the access live: said, with « Retirer l\'accès »', (tester) async {
      final help = await open(
          tester,
          _proState(
              request: _req(
                  status: 'taken',
                  trainer: const HelpTrainer(firstName: 'Awa'),
                  access: HelpAccess(expiresAt: _now.add(const Duration(hours: 40))))));
      expect(find.byKey(const Key('help-access-live')), findsOneWidget);
      expect(find.byKey(const Key('help-grant-card')), findsNothing);
      await tester.tap(find.byKey(const Key('help-revoke')));
      await _settle(tester);
      expect(help.calls, ['revoke:req-1']);
    });

    testWidgets('resolved: « C\'est réglé ? » — « Oui, merci » closes with a 👍, « Pas encore » reopens',
        (tester) async {
      var help = await open(tester,
          _proState(request: _req(status: 'resolved', trainer: const HelpTrainer(firstName: 'Awa'))));
      expect(find.byKey(const Key('help-settled')), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      await tester.tap(find.byKey(const Key('help-yes')));
      await _settle(tester);
      expect(help.calls, ['close:req-1:1']);

      help = await open(tester,
          _proState(request: _req(status: 'resolved', trainer: const HelpTrainer(firstName: 'Awa'))));
      await tester.tap(find.byKey(const Key('help-not-yet')));
      await _settle(tester);
      expect(help.calls, ['reopen:req-1']);
    });

    testWidgets('« Fermer la demande » with a thumb down', (tester) async {
      final help = await open(tester,
          _proState(request: _req(status: 'taken', trainer: const HelpTrainer(firstName: 'Awa'))));
      await tester.ensureVisible(find.byKey(const Key('help-close')));
      await tester.tap(find.byKey(const Key('help-close')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('help-rate-down')));
      await _settle(tester);
      expect(help.calls, ['close:req-1:-1']);
    });

    testWidgets('no request yet: the button and the hours, the basics under them', (tester) async {
      await _phone(tester, height: 1200);
      final help = _Help(state: _proState());
      await tester.pumpWidget(_routed(_router(() => const SizedBox(), _shopPro, help, at: '/o/${_shopPro.id}/aide')));
      await _settle(tester);
      expect(find.byKey(const Key('help-trainer-card')), findsOneWidget);
      expect(find.byKey(const Key('help-ask')), findsOneWidget);
      expect(find.text('Réponse en quelques minutes, 07:00–21:00'), findsOneWidget);
      expect(find.byKey(const Key('help-my-requests')), findsNothing, reason: 'none yet');
      expect(find.byKey(const Key('help-faq')), findsOneWidget);
      expect(find.byKey(const Key('help-pro-invite')), findsNothing, reason: 'Pro already');
    });

    testWidgets('the free page (mockup 7, 143): FAQ, guides, Marakaj « réponse sous 48 h », report — no Pro card',
        (tester) async {
      final went = <String>[];
      Support.reset(const SupportContacts(email: Support.defaultEmail, whatsapp: '22670000099', hours: Support.defaultHours));
      await _phone(tester, height: 1200);
      final help = _Help(state: _freeState);
      final org = _as(_shopPro, plan: 'free');
      await tester.pumpWidget(_routed(_router(() => const SizedBox(), org, help, at: '/o/${org.id}/aide', went: went)));
      await _settle(tester);
      expect(find.text('Aide'), findsOneWidget);
      expect(find.byKey(const Key('help-faq')), findsOneWidget);
      expect(find.byKey(const Key('help-guides')), findsOneWidget);
      expect(find.byKey(const Key('help-write-mara')), findsOneWidget);
      expect(find.textContaining('réponse sous 48 h'), findsOneWidget);
      expect(find.byKey(const Key('help-48h')), findsOneWidget);
      expect(find.byKey(const Key('help-247')), findsNothing);
      expect(find.textContaining('24/7'), findsNothing);
      expect(find.textContaining('24 h/24'), findsNothing);
      expect(find.byKey(const Key('help-mara-email')), findsOneWidget);
      expect(find.byKey(const Key('help-report')), findsOneWidget);
      // 143: the card gave way to the pop-up and the FAQ banner.
      expect(find.byKey(const Key('help-pro-invite')), findsNothing);
      // No trainer queue for a free business.
      expect(find.byKey(const Key('help-ask')), findsNothing);
      await tester.tap(find.byKey(const Key('help-guides')));
      await _settle(tester);
      expect(went, contains('chemin'));
    });

    testWidgets('a Pro business on a database without 133: the basics, no Pro invitation, no trainer', (tester) async {
      await _phone(tester, height: 1200);
      final help = _Help(state: HelpState.missing);
      await tester.pumpWidget(_routed(_router(() => const SizedBox(), _shopPro, help, at: '/o/${_shopPro.id}/aide')));
      await _settle(tester);
      expect(find.byKey(const Key('help-faq')), findsOneWidget);
      expect(find.byKey(const Key('help-pro-invite')), findsNothing);
      // No 133, no trainers' queue: « Demander un formateur » is not offered.
      expect(find.byKey(const Key('help-ask')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('4. the trainer\'s inbox', () {
    Future<_Help> open(WidgetTester tester, HelpInbox inbox, {String? focus}) async {
      await _phone(tester, height: 1400);
      final help = _Help(inboxAnswer: inbox);
      await tester.pumpWidget(_app(TrainerInboxScreen(help: help, focus: focus)));
      await _settle(tester);
      return help;
    }

    testWidgets('an open one: « NOUVELLE », its business and words, « Je m\'en occupe »', (tester) async {
      final help = await open(tester, HelpInbox(trainer: true, requests: [_inboxRow()]));
      expect(find.textContaining('NOUVELLE'), findsOneWidget);
      expect(find.text('Salon Belle Vie · Ouagadougou'), findsOneWidget);
      expect(find.textContaining('écran Vente'), findsOneWidget);
      expect(find.byKey(const Key('help-wa-r1')), findsNothing, reason: 'no number before the take');
      await tester.tap(find.byKey(const Key('help-take-r1')));
      await _settle(tester);
      expect(help.calls, ['take:r1']);
    });

    testWidgets('mine: WhatsApp, call, « Marquer résolue » with a note', (tester) async {
      final help = await open(tester, HelpInbox(trainer: true, requests: [_inboxRow(status: 'taken', mine: true)]));
      expect(find.text('MOI · en cours'), findsOneWidget);
      expect(find.byKey(const Key('help-wa-r1')), findsOneWidget);
      expect(find.byKey(const Key('help-tel-r1')), findsOneWidget);
      expect(find.byKey(const Key('help-open-r1')), findsNothing, reason: 'no access given');
      await tester.tap(find.byKey(const Key('help-resolve-r1')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('help-note')), 'Vente annulée');
      await tester.tap(find.byKey(const Key('help-note-ok')));
      await _settle(tester);
      expect(help.calls, ['resolve:r1:Vente annulée']);
    });

    testWidgets('a visit: accept, or propose a call instead', (tester) async {
      final help = await open(
          tester, HelpInbox(trainer: true, requests: [_inboxRow(status: 'taken', mine: true, contact: 'visit')]));
      await tester.tap(find.byKey(const Key('help-visit-call-r1')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('help-note')), 'À 15 h');
      await tester.tap(find.byKey(const Key('help-note-ok')));
      await _settle(tester);
      expect(help.calls, ['visit:r1:call_instead:À 15 h']);
      expect(find.byKey(const Key('help-visit-yes-r1')), findsOneWidget);
    });

    testWidgets('a live access: « Ouvrir l\'activité (lecture seule) »', (tester) async {
      await open(tester, HelpInbox(trainer: true, requests: [
        _inboxRow(status: 'taken', mine: true, accessUntil: _now.add(const Duration(hours: 10))),
      ]));
      expect(find.byKey(const Key('help-open-r1')), findsOneWidget);
      expect(find.text('Ouvrir l\'activité (lecture seule)'), findsOneWidget);
    });

    testWidgets('on and off duty', (tester) async {
      final help = await open(tester, const HelpInbox(trainer: true));
      expect(find.text('En service'), findsOneWidget);
      expect(find.byKey(const Key('help-inbox-empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('help-duty')));
      await _settle(tester);
      expect(help.calls, ['duty:false']);
    });

    testWidgets('the bell\'s request first, outlined', (tester) async {
      await open(tester, HelpInbox(trainer: true, requests: [_inboxRow(id: 'a'), _inboxRow(id: 'b', org: 'Ferme B')]),
          focus: 'b');
      final a = tester.getTopLeft(find.byKey(const Key('help-inbox-a'))).dy;
      final b = tester.getTopLeft(find.byKey(const Key('help-inbox-b'))).dy;
      expect(b, lessThan(a));
    });

    testWidgets('not a trainer: nothing but a word', (tester) async {
      await open(tester, HelpInbox.none);
      expect(find.byKey(const Key('help-inbox-not-trainer')), findsOneWidget);
      expect(find.byKey(const Key('help-duty')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('5. the admin', () {
    test('« Aujourd\'hui »: late among the urgent, open with the couriers — only with 133', () {
      const with133 = PlatformTodo({'help_late': 1, 'help_open': 2, 'orders_stuck': 1, 'couriers': 1});
      expect(with133.waitingOrder, ['orders_stuck', 'help_late', 'help_open', 'couriers']);
      expect(with133.waiting, 5);
      const without = PlatformTodo({'orders_stuck': 1});
      expect([...without.waitingOrder, ...without.zeroKeys], hasLength(14),
          reason: 'batch 135\'s fourteen, as before');
      const zero = PlatformTodo({'help_late': 0, 'help_open': 0});
      expect(zero.zeroKeys, containsAll(['help_late', 'help_open']));
    });

    testWidgets('the counter in « Vous attend », urgent, opening the console', (tester) async {
      await _phone(tester, height: 1200);
      final help = _Help(consoleAnswer: const HelpConsole(open: 3));
      final router = GoRouter(initialLocation: Routes.console, routes: [
        GoRoute(
            path: Routes.console,
            builder: (_, _) => TodoSection(
                center: _Center(const PlatformTodo({'help_late': 1, 'help_open': 2})),
                admin: AdminRepository(null))),
        GoRoute(path: Routes.consoleHelp, builder: (_, _) => HelpConsoleScreen(help: help)),
      ]);
      await tester.pumpWidget(_routed(router));
      await _settle(tester);
      expect(find.byKey(const Key('todo-help_late')), findsOneWidget);
      expect(find.text('Demandes d\'aide sans réponse'), findsOneWidget);
      expect(find.byKey(const Key('todo-help_open')), findsOneWidget);
      final late = tester.getTopLeft(find.byKey(const Key('todo-help_late'))).dy;
      final open = tester.getTopLeft(find.byKey(const Key('todo-help_open'))).dy;
      expect(late, lessThan(open));
      await tester.tap(find.byKey(const Key('todo-help_late')));
      await _settle(tester);
      expect(find.text('Aide · Console'), findsOneWidget);
    });

    testWidgets('the console: the numbers, the late one, WhatsApp off, the trainers', (tester) async {
      await _phone(tester, height: 1400);
      final help = _Help(
          consoleAnswer: const HelpConsole(
        open: 3,
        avgMinutes: 6,
        resolved7: 27,
        up: 47,
        down: 3,
        whatsapp: 'off',
        trainers: [
          ConsoleTrainer(name: 'Awa O.', resolved7: 12),
          ConsoleTrainer(name: 'Mariam T.', onDuty: false, resolved7: 6),
        ],
        waiting: [ConsoleWaiting(id: 'w1', org: 'Ferme Kaboré', subject: 'stock', status: 'open', minutes: 35, late: true, escalated: true)],
      ));
      await tester.pumpWidget(_app(HelpConsoleScreen(help: help)));
      await _settle(tester);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('6 min'), findsOneWidget);
      expect(find.text('27'), findsOneWidget);
      expect(find.text('94 %'), findsOneWidget);
      expect(find.byKey(const Key('help-console-late-w1')), findsOneWidget);
      expect(find.text('Sans réponse depuis 35 min'), findsOneWidget);
      expect(find.textContaining('remontée à vous'), findsOneWidget);
      expect(find.textContaining('WhatsApp : désactivé'), findsOneWidget);
      expect(find.text('Awa O.'), findsOneWidget);
      expect(find.textContaining('hors service'), findsOneWidget);
    });

    testWidgets('the console says when Meta has not approved the template', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(HelpConsoleScreen(
          help: _Help(consoleAnswer: const HelpConsole(whatsapp: 'template', template: 'aide_demande')))));
      await _settle(tester);
      expect(find.textContaining('n\'est pas encore approuvé par Meta'), findsOneWidget);
    });

    test('Réglages: the help\'s seven settings, on the Notifications card, the hours ranged', () {
      const keys = [
        'help_hours_open', 'help_hours_close', 'help_escalate_minutes', 'help_late_minutes',
        'help_daily_limit', 'help_whatsapp_template', 'admin_help_notify',
      ];
      for (final k in keys) {
        expect(platformSettingDefs.any((d) => d.key == k), isTrue, reason: k);
        expect(settingCardOf(k)?.key, 'notifications', reason: k);
      }
      expect(rangedSettings['help_hours_open'], (0, 23));
      expect(rangedSettings['help_hours_close'], (1, 24));
    });
  });

  // -------------------------------------------------------------------------
  group('6. the bells', () {
    NotificationRow row(String kind, {String? org, Map<String, dynamic> params = const {}}) => NotificationRow(
        id: 'n1', kind: kind, message: 'm', createdAt: _now, orgId: org, params: params);
    const id = '13313313-0000-0000-0000-0000000000aa';

    test('each opens its place', () {
      expect(notificationTarget(row('help_request', org: 'o1', params: {'to': 'me', 'request_id': id})),
          '${Routes.trainerInbox}?demande=$id');
      expect(notificationTarget(row('help_access', org: 'o1', params: {'to': 'me', 'request_id': 'x/../y'})),
          Routes.trainerInbox);
      // 143: the business's requests, the one the bell is about opened.
      expect(notificationTarget(row('help_taken', org: 'o1', params: {'to': 'shop'})), '/o/o1/aide/demandes');
      expect(notificationTarget(row('help_resolved', org: 'o1', params: {'to': 'shop', 'request_id': id})),
          '/o/o1/aide/demandes?demande=$id');
      expect(notificationTarget(row('help_escalated', params: {'to': 'platform'})), Routes.consoleHelp);
    });

    testWidgets('in English', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_app(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }), locale: const Locale('en')));
      expect(notificationLine(ctx, row('help_request', params: {'org': 'Salon', 'subject': 'stock'})),
          'Help request — Salon: Stock');
      expect(notificationLine(ctx, row('help_taken', params: {'who': 'Awa'})),
          'Awa (Marakaj training) is handling your help request.');
      expect(notificationLine(ctx, row('help_visit', params: {'who': 'Awa', 'visit_answer': 'call_instead'})),
          'Awa suggests a call instead.');
    });
  });
}
