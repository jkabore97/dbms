// Batch 143: the help, Basic and Pro, as the owner decided it (migration
// 138), for a shop, a farm and an association, in French and in English.
//
//   1. Basic: WhatsApp « Réponse sous 48 h », never « 24/7 »; the pop-up
//      once a day per device (« Passer à Pro » / « Continuer »), the
//      employee's wording, none where this build sells no Pro; Compte's
//      card says 48 h too;
//   2. the FAQ's banner: Basic yes, Pro no, nobody without a business;
//      closed, back the next day; the employee's wording;
//   3. Pro: the « 24/7 » badge, WhatsApp straight away, « [PRO] »;
//   4. « Demander un formateur », every step, for each kind; an older
//      server gets what it knows;
//   5. several requests: their statuses, « Nouvelle demande », the button
//      that opens the list once there are some;
//   6. the pre-filled WhatsApp and the e-mail's subject, Pro and Basic,
//      French and English;
//   7. the command center's trainer switch, its number warning, the
//      console's Formateurs;
//   8. 320 px with text ×1.3, French and English: nothing overflows;
//   9. the platform admin's own business keeps its button (the bug).
//
// B143_SHOTS=<dir> also writes the screenshots (390 × 844 and 320 px at
// text ×1.3, French and English).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/store_rules.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/console/models.dart';
import 'package:kaj_app/core/help/help_repository.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/account/legal_screens.dart';
import 'package:kaj_app/features/account/support.dart';
import 'package:kaj_app/features/admin/platform_people_screen.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/help/help_button.dart';
import 'package:kaj_app/features/help/help_console_screen.dart';
import 'package:kaj_app/features/help/help_contact.dart';
import 'package:kaj_app/features/help/help_request_flow.dart';
import 'package:kaj_app/features/help/help_requests_screen.dart';
import 'package:kaj_app/features/help/help_screen.dart';
import 'package:kaj_app/features/help/help_words.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/l10n/strings.dart';

// ---------------------------------------------------------------------------
// The businesses (the owner's naming rule: brand-like names, no first names)
// ---------------------------------------------------------------------------

const _shopPro = OrgSummary(
  id: '3f2a91c0-1430-0000-0000-000000000001',
  name: 'Maison Élégance',
  slug: 'maison-elegance',
  profile: 'retail',
  plan: 'pro',
  roles: ['owner'],
);
const _farmPro = OrgSummary(
  id: '14300000-0000-0000-0000-000000000002',
  name: 'Ferme Horizon Vert',
  slug: 'horizon-vert',
  profile: 'farm',
  plan: 'pro',
  roles: ['owner'],
);
const _assocPro = OrgSummary(
  id: '14300000-0000-0000-0000-000000000003',
  name: 'Fondation Espoir',
  slug: 'fondation-espoir',
  profile: 'association',
  plan: 'pro',
  roles: ['owner'],
);
const _shopBasic = OrgSummary(
  id: '14300000-0000-0000-0000-000000000004',
  name: 'Maison Élégance',
  slug: 'maison-elegance-basic',
  profile: 'retail',
  roles: ['owner'],
);
const _farmBasic = OrgSummary(
  id: '14300000-0000-0000-0000-000000000005',
  name: 'Domaine des Acacias',
  slug: 'domaine-des-acacias',
  profile: 'farm',
  roles: ['owner'],
);
const _assocBasic = OrgSummary(
  id: '14300000-0000-0000-0000-000000000006',
  name: 'Cercle des Bâtisseurs',
  slug: 'cercle-des-batisseurs',
  profile: 'association',
  roles: ['owner'],
);

OrgSummary _as(OrgSummary o, {List<String>? roles, String? plan}) => OrgSummary(
  id: o.id,
  name: o.name,
  slug: o.slug,
  profile: o.profile,
  plan: plan ?? o.plan,
  roles: roles ?? o.roles,
);

final _now = DateTime.now();
final _clock = DateTime.utc(2026, 10, 14, 9);

const _support = SupportContacts(
  email: 'hello@kaj-consulting.com',
  whatsapp: '18623354492',
  hours: '24 h/24, 7 j/7',
);

HelpState _pro({
  List<HelpRequest>? requests,
  bool? canUpgrade = true,
  int left = 5,
}) => HelpState(
  available: true,
  pro: true,
  hours: HelpHours(open: 0, close: 24, inHours: true, nextOpen: _now),
  listed: requests ?? const [],
  request: (requests ?? const []).where((r) => r.active).firstOrNull,
  left: left,
  canUpgrade: canUpgrade,
  ref: null,
);

HelpState _basic({bool? canUpgrade = true}) => HelpState(
  available: true,
  pro: false,
  canUpgrade: canUpgrade,
  listed: const [],
);

HelpRequest _req(
  String id,
  String status, {
  String subject = 'catalogue',
  HelpTrainer? trainer,
  String? message,
}) => HelpRequest(
  id: id,
  subject: subject,
  contact: 'whatsapp',
  status: status,
  createdAt: _now.subtract(const Duration(hours: 2)),
  routedAt: _now.subtract(const Duration(hours: 2)),
  message: message ?? 'Je n\'arrive pas à ajouter un article',
  trainer: trainer,
  takenAt: trainer == null ? null : _now,
  mine: true,
);

// ---------------------------------------------------------------------------
// The server
// ---------------------------------------------------------------------------

class _Help extends HelpRepository {
  _Help({HelpState? state, this.trainer})
    : stateAnswer = state ?? _pro(),
      super(null);

  HelpState stateAnswer;
  TrainerSwitch? trainer;
  final created = <Map<String, Object?>>[];
  final calls = <String>[];
  HelpConsole? consoleAnswer;

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
    created.add({
      'org': orgId,
      'subject': subject,
      'contact': contact,
      'message': message,
      'phone': phone,
      'preferred_at': preferredAt,
      'server': server,
      'screen': context['screen'],
    });
    final r = HelpRequest(
      id: 'new-${created.length}',
      subject: subject,
      contact: contact,
      status: 'open',
      createdAt: _clock,
      routedAt: preferredAt == null
          ? _clock
          : preferredAt.subtract(const Duration(minutes: 30)),
      preferredAt: preferredAt,
      message: message,
      mine: true,
    );
    stateAnswer = _pro(requests: [r, ...stateAnswer.requests]);
    return r;
  }

  @override
  Future<TrainerSwitch?> trainerState(String userId) async => trainer;

  @override
  Future<TrainerSwitch> setTrainer(
    String userId,
    bool on, {
    String? phone,
  }) async {
    calls.add('trainer:$userId:$on');
    trainer = TrainerSwitch(isTrainer: on, phone: trainer?.phone);
    return trainer!;
  }

  @override
  Future<HelpConsole?> console() async => consoleAnswer;

  @override
  Future<HelpInbox> inbox() async => HelpInbox.none;
}

class _Console extends ConsoleRepository {
  _Console() : super(null);
  @override
  Future<List<PersonOrg>> userOrgs(String userId) async => const [
    PersonOrg(
      orgId: 'o1',
      orgName: 'Maison Élégance',
      profile: 'retail',
      role: 'employee',
    ),
  ];
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// A server out of its hours: the request made now is queued until
/// tomorrow's opening, 7:00.
class _QueuedHelp extends _Help {
  _QueuedHelp() : super();

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
    final n = DateTime.now().toUtc();
    return HelpRequest(
      id: 'queued',
      subject: subject,
      contact: contact,
      status: 'open',
      createdAt: n,
      routedAt: DateTime.utc(n.year, n.month, n.day + 1, 7),
      queued: true,
      mine: true,
    );
  }
}

Future<void> _size(
  WidgetTester tester,
  double w,
  double h, {
  double text = 1,
}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// Every link url_launcher was asked to open.
List<String> _launches(WidgetTester tester) {
  final opened = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    final args = call.arguments;
    if (args is Map && args['url'] != null) opened.add('${args['url']}');
    return true;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
  return opened;
}

String _textOf(String waUrl) => Uri.parse(waUrl).queryParameters['text'] ?? '';

Widget _shot(Widget child) =>
    RepaintBoundary(key: const Key('shot'), child: child);

Widget _app(Widget home, {String lang = 'fr'}) => MaterialApp(
  locale: Locale(lang),
  theme: kajTheme(kajPalette),
  localizationsDelegates: Strings.localizationsDelegates,
  supportedLocales: Strings.supportedLocales,
  debugShowCheckedModeBanner: false,
  builder: (context, child) => _shot(child!),
  home: home,
);

GoRouter _router(
  OrgSummary org,
  _Help help, {
  String? at,
  List<String>? went,
}) => GoRouter(
  initialLocation: at ?? '/o/${org.id}/aide',
  routes: [
    GoRoute(
      path: '/o/:orgId',
      builder: (_, _) => const Scaffold(body: Text('home')),
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
                  org: org,
                  help: help,
                  focus: state.uri.queryParameters['demande'],
                );
              },
            ),
          ],
        ),
        for (final r in const ['kaj-pro', 'chemin'])
          GoRoute(
            path: r,
            builder: (_, _) {
              went?.add(r);
              return Scaffold(body: Text('page $r'));
            },
          ),
      ],
    ),
    GoRoute(
      path: Routes.faq,
      builder: (_, state) {
        went?.add('faq?${state.uri.query}');
        return FaqScreen(org: org);
      },
    ),
  ],
);

Widget _routed(GoRouter r, {String lang = 'fr'}) => MaterialApp.router(
  locale: Locale(lang),
  theme: kajTheme(kajPalette),
  localizationsDelegates: Strings.localizationsDelegates,
  supportedLocales: Strings.supportedLocales,
  debugShowCheckedModeBanner: false,
  builder: (context, child) => _shot(child!),
  routerConfig: r,
);

Future<void> _openAide(
  WidgetTester tester,
  OrgSummary org,
  _Help help, {
  String lang = 'fr',
  List<String>? went,
  double w = 390,
  double h = 900,
  double text = 1,
}) async {
  await _size(tester, w, h, text: text);
  await tester.pumpWidget(_routed(_router(org, help, went: went), lang: lang));
  await _settle(tester);
}

Future<void> _tapWhatsApp(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('help-mara-whatsapp')));
  await tester.tap(find.byKey(const Key('help-mara-whatsapp')));
  await _settle(tester);
}

Future<void> _tapSeen(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('flow-next')));
  await _settle(tester);
}

Widget _flow(OrgSummary org, _Help help, {String? phone = '22670000000'}) =>
    HelpRequestFlow(
      org: org,
      state: help.stateAnswer,
      help: help,
      phone: phone,
      screen: 'Aide',
      store: MemoryFlowStore(),
      now: () => _clock,
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
  });

  late MemoryHelpPrefs prefs;
  setUp(() {
    HelpButton.reset();
    HelpContact.reset();
    prefs = MemoryHelpPrefs();
    HelpContact.debugStore = prefs;
    HelpContact.debugNow = () => DateTime(2026, 10, 14, 10);
    Support.reset(_support);
    debugSellsDigitalInApp = null;
  });
  tearDown(() {
    HelpContact.debugStore = null;
    HelpContact.debugNow = null;
    debugSellsDigitalInApp = null;
    Support.reset();
  });

  // -------------------------------------------------------------------------
  group('1. Basic: WhatsApp « Réponse sous 48 h » and the day\'s word about Pro', () {
    for (final org in [_shopBasic, _farmBasic, _assocBasic]) {
      testWidgets(
        '${org.profile}: « Réponse sous 48 h », never 24/7; the pop-up once a day; « Continuer » opens WhatsApp',
        (tester) async {
          final opened = _launches(tester);
          await _openAide(tester, org, _Help(state: _basic()));
          expect(find.byKey(const Key('help-48h')), findsOneWidget);
          expect(find.text('Réponse sous 48 h'), findsOneWidget);
          expect(find.byKey(const Key('help-247')), findsNothing);
          expect(find.textContaining('24/7'), findsNothing);
          expect(find.textContaining('24 h/24'), findsNothing);
          expect(
            find.byKey(const Key('help-ask')),
            findsNothing,
            reason: 'no trainer on Basic',
          );
          expect(
            find.byKey(const Key('help-report')),
            findsOneWidget,
            reason: '« Signaler un problème » kept',
          );
          expect(
            find.byKey(const Key('help-mara-email')),
            findsOneWidget,
            reason: 'the e-mail kept',
          );

          // First tap of the day: the word, the owner's.
          await _tapWhatsApp(tester);
          expect(find.byKey(const Key('help-nudge')), findsOneWidget);
          expect(
            find.text(
              'Obtenez une réponse plus rapide et un meilleur accompagnement avec Marakaj Pro',
            ),
            findsOneWidget,
          );
          expect(find.byKey(const Key('help-nudge-pro')), findsOneWidget);
          expect(find.text('Passer à Pro'), findsOneWidget);
          expect(
            opened,
            isEmpty,
            reason: 'nothing opened before « Continuer »',
          );
          await tester.tap(find.byKey(const Key('help-nudge-continue')));
          await _settle(tester);
          expect(find.byKey(const Key('help-nudge')), findsNothing);
          expect(opened, hasLength(1));
          expect(opened.single, startsWith('https://wa.me/18623354492?text='));
          expect(
            _textOf(opened.single),
            startsWith('Bonjour Marakaj'),
            reason: 'Basic: no [PRO]',
          );

          // Again the same day: straight to WhatsApp.
          await _tapWhatsApp(tester);
          expect(find.byKey(const Key('help-nudge')), findsNothing);
          expect(opened, hasLength(2));
          expect(prefs.values['help_pro_nudge_day'], '2026-10-14');

          // The next day: the word again.
          HelpContact.debugNow = () => DateTime(2026, 10, 15, 8);
          await _tapWhatsApp(tester);
          expect(find.byKey(const Key('help-nudge')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('« Passer à Pro » opens the Pro page', (tester) async {
      final went = <String>[];
      await _openAide(tester, _shopBasic, _Help(state: _basic()), went: went);
      await _tapWhatsApp(tester);
      await tester.tap(find.byKey(const Key('help-nudge-pro')));
      await _settle(tester);
      expect(went, contains('kaj-pro'));
    });

    testWidgets(
      'the day\'s word is remembered on the device: a page opened again does not say it twice',
      (tester) async {
        final opened = _launches(tester);
        await _openAide(tester, _shopBasic, _Help(state: _basic()));
        await _tapWhatsApp(tester);
        await tester.tap(find.byKey(const Key('help-nudge-continue')));
        await _settle(tester);
        // Another opening the same day (the memory forgotten, the device's pref kept).
        HelpContact.reset();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _routed(_router(_shopBasic, _Help(state: _basic()))),
        );
        await _settle(tester);
        await _tapWhatsApp(tester);
        expect(find.byKey(const Key('help-nudge')), findsNothing);
        expect(opened, hasLength(2));
      },
    );

    testWidgets(
      'an employee: « Demandez au propriétaire de passer à Pro », « Continuer » alone',
      (tester) async {
        final opened = _launches(tester);
        await _openAide(
          tester,
          _as(_farmBasic, roles: ['employee']),
          _Help(state: _basic(canUpgrade: false)),
        );
        await _tapWhatsApp(tester);
        expect(find.byKey(const Key('help-nudge')), findsOneWidget);
        expect(
          find.text('Demandez au propriétaire de passer à Pro'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('help-nudge-pro')), findsNothing);
        await tester.tap(find.byKey(const Key('help-nudge-continue')));
        await _settle(tester);
        expect(opened, hasLength(1));
      },
    );

    testWidgets(
      'the server says who may buy: a platform admin with no owner role there is told to ask',
      (tester) async {
        await _openAide(
          tester,
          _as(_shopBasic, roles: ['platform_admin']),
          _Help(state: _basic(canUpgrade: false)),
        );
        await _tapWhatsApp(tester);
        expect(
          find.text('Demandez au propriétaire de passer à Pro'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a build that sells no Pro (the iPhone app): no pop-up, straight to WhatsApp',
      (tester) async {
        debugSellsDigitalInApp = false;
        storeBillingOn = false;
        final opened = _launches(tester);
        await _openAide(tester, _shopBasic, _Help(state: _basic()));
        await _tapWhatsApp(tester);
        expect(find.byKey(const Key('help-nudge')), findsNothing);
        expect(opened, hasLength(1));
      },
    );

    testWidgets(
      'Compte\'s card on Basic: « Réponse sous 48 h », its WhatsApp through the day\'s word',
      (tester) async {
        final opened = _launches(tester);
        await _size(tester, 390, 844);
        await tester.pumpWidget(
          _app(
            const Scaffold(
              body: SupportCard(org: _assocBasic, page: 'Compte'),
            ),
          ),
        );
        await _settle(tester);
        expect(
          find.text('Une question, un souci ? Réponse sous 48 h.'),
          findsOneWidget,
        );
        expect(find.textContaining('24 h/24'), findsNothing);
        expect(find.text('WhatsApp · réponse sous 48 h'), findsOneWidget);
        await tester.tap(find.byKey(const Key('support-whatsapp')));
        await _settle(tester);
        expect(find.byKey(const Key('help-nudge')), findsOneWidget);
        await tester.tap(find.byKey(const Key('help-nudge-continue')));
        await _settle(tester);
        expect(
          _textOf(opened.single),
          contains('Cercle des Bâtisseurs (Association · Basic)'),
        );
        expect(_textOf(opened.single), contains('Page : Compte'));
        // Without a business (a shopper): 126's card, as it was.
        await tester.pumpWidget(_app(const Scaffold(body: SupportCard())));
        await _settle(tester);
        expect(find.textContaining('24'), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('2. the FAQ\'s banner', () {
    Future<void> faq(
      WidgetTester tester,
      OrgSummary? org, {
      String lang = 'fr',
    }) async {
      await _size(tester, 390, 1400);
      await tester.pumpWidget(_app(FaqScreen(org: org), lang: lang));
      await _settle(tester);
    }

    testWidgets(
      'Basic: the banner at the top, « Passer à Pro », every question below',
      (tester) async {
        await faq(tester, _farmBasic);
        expect(find.byKey(const Key('faq-pro-banner')), findsOneWidget);
        expect(
          find.text('Une aide plus rapide, un formateur, avec Marakaj Pro'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('faq-pro-banner-go')), findsOneWidget);
        final banner = tester
            .getTopLeft(find.byKey(const Key('faq-pro-banner')))
            .dy;
        final question = tester
            .getTopLeft(
              find.text('L\'application fonctionne-t-elle sans internet ?'),
            )
            .dy;
        expect(banner, lessThan(question));
        await tester.scrollUntilVisible(
          find.text('Comment contacter quelqu\'un ?'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Comment contacter quelqu\'un ?'), findsOneWidget);
      },
    );

    testWidgets(
      'closed with its cross: gone the rest of the day, back the next',
      (tester) async {
        await faq(tester, _shopBasic);
        await tester.tap(find.byKey(const Key('faq-pro-banner-close')));
        await _settle(tester);
        expect(find.byKey(const Key('faq-pro-banner')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await faq(tester, _shopBasic);
        expect(
          find.byKey(const Key('faq-pro-banner')),
          findsNothing,
          reason: 'the same day',
        );
        HelpContact.debugNow = () => DateTime(2026, 10, 15, 7);
        await tester.pumpWidget(const SizedBox());
        await faq(tester, _shopBasic);
        expect(
          find.byKey(const Key('faq-pro-banner')),
          findsOneWidget,
          reason: 'the next day',
        );
      },
    );

    testWidgets('Pro: no banner; nobody without a business: no banner', (
      tester,
    ) async {
      await faq(tester, _shopPro);
      expect(find.byKey(const Key('faq-pro-banner')), findsNothing);
      expect(find.textContaining('Questions fréquentes'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await faq(tester, null);
      expect(find.byKey(const Key('faq-pro-banner')), findsNothing);
      expect(
        find.text('L\'application fonctionne-t-elle sans internet ?'),
        findsOneWidget,
      );
    });

    testWidgets('an employee: « Demandez au propriétaire », no button', (
      tester,
    ) async {
      await faq(tester, _as(_assocBasic, roles: ['employee']));
      expect(
        find.text('Demandez au propriétaire de passer à Pro'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('faq-pro-banner-go')), findsNothing);
    });

    testWidgets('the Aide page opens the FAQ as the business\'s', (
      tester,
    ) async {
      final went = <String>[];
      await _openAide(tester, _shopBasic, _Help(state: _basic()), went: went);
      await tester.ensureVisible(find.byKey(const Key('help-faq')));
      await tester.tap(find.byKey(const Key('help-faq')));
      await _settle(tester);
      expect(went, contains('faq?org=${_shopBasic.id}'));
      expect(find.byKey(const Key('faq-pro-banner')), findsOneWidget);
    });

    testWidgets('English', (tester) async {
      await faq(tester, _shopBasic, lang: 'en');
      expect(
        find.text('Faster help, a trainer, with Marakaj Pro'),
        findsOneWidget,
      );
      expect(find.text('Go Pro'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('3. Pro: « 24/7 », no pop-up', () {
    for (final org in [_shopPro, _farmPro, _assocPro]) {
      testWidgets(
        '${org.profile}: the 24/7 badge; WhatsApp at once, « [PRO] »',
        (tester) async {
          final opened = _launches(tester);
          await _openAide(tester, org, _Help(state: _pro()));
          expect(find.byKey(const Key('help-247')), findsOneWidget);
          expect(find.text('24/7'), findsOneWidget);
          expect(find.byKey(const Key('help-48h')), findsNothing);
          // Pro's card beside the badge: quick, round the clock — never
          // Basic's 48 h.
          expect(
            find.text('Réponse rapide, 24 h/24'),
            findsOneWidget,
          );
          expect(find.textContaining('48 h'), findsNothing);
          expect(find.byKey(const Key('help-ask')), findsOneWidget);
          expect(find.text('Demander un formateur'), findsOneWidget);
          expect(find.byKey(const Key('help-faq')), findsOneWidget);
          await _tapWhatsApp(tester);
          expect(find.byKey(const Key('help-nudge')), findsNothing);
          expect(opened, hasLength(1));
          expect(_textOf(opened.single), startsWith('[PRO] Bonjour Marakaj'));
          expect(_textOf(opened.single), contains('· Pro)'));
        },
      );
    }

    testWidgets('Pro\'s FAQ from its Aide page: no banner', (tester) async {
      await _openAide(tester, _shopPro, _Help(state: _pro()));
      await tester.ensureVisible(find.byKey(const Key('help-faq')));
      await tester.tap(find.byKey(const Key('help-faq')));
      await _settle(tester);
      expect(find.byKey(const Key('faq-pro-banner')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('4. « Demander un formateur », step by step', () {
    for (final (org, own, ownLabel) in [
      (_shopPro, 'livraison', 'Livraison'),
      (_farmPro, 'bandes', 'Bandes / Récoltes'),
      (_assocPro, 'evenements', 'Événements'),
    ]) {
      testWidgets('${org.profile}: subject, words, how, when, summary, sent', (
        tester,
      ) async {
        final help = _Help();
        await _size(tester, 390, 844);
        await tester.pumpWidget(_app(_flow(org, help)));
        await _settle(tester);

        // 1. What it is about: every kind's eight, the kind's own.
        expect(find.byKey(const Key('flow-step-subject')), findsOneWidget);
        expect(find.text('Étape 1 sur 5'), findsOneWidget);
        expect(find.text('Articles / Catalogue'), findsOneWidget);
        for (final s in helpSubjectsFor(org.profile)) {
          await tester.scrollUntilVisible(
            find.byKey(Key('flow-option-$s')),
            120,
          );
          expect(find.byKey(Key('flow-option-$s')), findsOneWidget);
        }
        expect(
          helpSubjectsFor(org.profile),
          containsAll(<String>[
            'catalogue',
            'vitrine',
            'ventes',
            'factures',
            'livraison',
            'rapports',
            'equipe',
            'autre',
          ]),
        );
        if (org.profile == 'farm') {
          expect(
            helpSubjectsFor('farm'),
            containsAll(<String>['bandes', 'stock']),
          );
        }
        if (org.profile == 'association') {
          expect(
            helpSubjectsFor('association'),
            containsAll(<String>['membres', 'contributions', 'evenements']),
          );
        }
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('flow-next')))
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(find.byKey(Key('flow-option-$own')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('flow-option-$own')));
        await tester.pump();
        await _next(tester);

        // 2. The words.
        expect(find.byKey(const Key('flow-step-describe')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('flow-next')))
              .onPressed,
          isNull,
          reason: 'a few words (or a photo) needed',
        );
        await tester.enterText(
          find.byKey(const Key('help-message')),
          'Comment ajouter une photo ?',
        );
        await tester.pump();
        await _next(tester);

        // 3. How: the account's number known.
        expect(find.byKey(const Key('flow-step-how')), findsOneWidget);
        expect(find.byKey(const Key('help-phone-known')), findsOneWidget);
        // The number read out with its « + », in groups.
        expect(find.text('On vous joint au +226 70 00 00 00'), findsOneWidget);
        await _tapSeen(tester, 'flow-option-call');
        await _next(tester);

        // 4. When: tomorrow at 10:00.
        expect(find.byKey(const Key('flow-step-when')), findsOneWidget);
        await _tapSeen(tester, 'flow-option-true');
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('flow-next')))
              .onPressed,
          isNull,
          reason: 'an hour is needed',
        );
        await _tapSeen(tester, 'help-day-1');
        await _tapSeen(tester, 'help-hour-10');
        await _next(tester);

        // 5. The summary, and « Envoyer la demande ».
        expect(find.byKey(const Key('flow-summary')), findsOneWidget);
        expect(find.text(ownLabel), findsOneWidget);
        expect(find.text('demain à 10:00'), findsOneWidget);
        expect(find.text('+226 70 00 00 00'), findsOneWidget);
        expect(find.text('Envoyer la demande'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('flow-save')));
        await tester.tap(find.byKey(const Key('flow-save')));
        await _settle(tester);
        expect(help.created.single, {
          'org': org.id,
          'subject': own,
          'contact': 'call',
          'message': 'Comment ajouter une photo ?',
          'phone': '22670000000',
          'preferred_at': DateTime.utc(2026, 10, 15, 10),
          'server': 138,
          'screen': 'Aide',
        });
        expect(find.byKey(const Key('flow-done')), findsOneWidget);
        expect(find.text('Demande d\'aide envoyée'), findsOneWidget);
        expect(
          find.text('Un formateur vous contactera demain à 10:00.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      '« Maintenant », a photo instead of words, the number asked when the account has none',
      (tester) async {
        final help = _Help();
        await _size(tester, 390, 844);
        await tester.pumpWidget(_app(_flow(_shopPro, help, phone: null)));
        await _settle(tester);
        await _tapSeen(tester, 'flow-option-vitrine');
        await _next(tester);
        await tester.enterText(
          find.byKey(const Key('help-message')),
          'La vitrine est vide',
        );
        await tester.pump();
        await _next(tester);
        expect(find.byKey(const Key('help-phone')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('flow-next')))
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byKey(const Key('help-phone')),
          '+226 70 11 22 33',
        );
        await tester.pump();
        await _next(tester);
        await _next(tester); // « Maintenant », chosen already
        expect(find.text('Maintenant'), findsWidgets);
        await tester.ensureVisible(find.byKey(const Key('flow-save')));
        await tester.tap(find.byKey(const Key('flow-save')));
        await _settle(tester);
        expect(help.created.single['phone'], '22670112233');
        expect(help.created.single['preferred_at'], isNull);
        expect(help.created.single['contact'], 'whatsapp');
      },
    );

    test(
      'an older server (133) gets what it knows: « autre » with the subject\'s name, the time in the words',
      () {
        final p = HelpRepository.createParams(
          orgId: 'o1',
          subject: 'livraison',
          contact: 'call',
          message: 'Le livreur ne voit pas la commande',
          preferredAt: DateTime.utc(2026, 10, 15, 10),
          subjectWords: 'Livraison',
          whenWords: 'Souhaité demain à 10:00',
          server: 133,
        );
        expect(p['p_subject'], 'autre');
        expect(
          p['p_message'],
          '[Livraison] (Souhaité demain à 10:00) Le livreur ne voit pas la commande',
        );
        expect((p['p_context'] as Map).containsKey('preferred_at'), isFalse);
        // A subject 133 knows goes as it is.
        expect(
          HelpRepository.createParams(
            orgId: 'o1',
            subject: 'bandes',
            contact: 'call',
            server: 133,
          )['p_subject'],
          'bandes',
        );
        // 138: the subject and the time as they are.
        final q = HelpRepository.createParams(
          orgId: 'o1',
          subject: 'livraison',
          contact: 'call',
          preferredAt: DateTime.utc(2026, 10, 15, 10),
        );
        expect(q['p_subject'], 'livraison');
        expect(
          (q['p_context'] as Map)['preferred_at'],
          '2026-10-15T10:00:00.000Z',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  group('5. several requests, « Nouvelle demande »', () {
    final three = [
      _req('r1', 'open', message: 'Première demande'),
      _req(
        'r2',
        'taken',
        subject: 'ventes',
        trainer: const HelpTrainer(
          firstName: 'Formateur',
          phone: '22670000001',
        ),
      ),
      _req(
        'r3',
        'resolved',
        subject: 'factures',
        trainer: const HelpTrainer(firstName: 'Formateur'),
      ),
    ];

    testWidgets(
      'the list: each with its status; « Nouvelle demande » opens the flow',
      (tester) async {
        final help = _Help(state: _pro(requests: three));
        await _openAide(tester, _shopPro, help, h: 1200);
        expect(
          find.text('2 en cours'),
          findsOneWidget,
          reason: 'open and taken',
        );
        await tester.tap(find.byKey(const Key('help-my-requests')));
        await _settle(tester);
        expect(find.byKey(const Key('help-request-r1')), findsOneWidget);
        expect(find.byKey(const Key('help-request-r2')), findsOneWidget);
        expect(find.byKey(const Key('help-request-r3')), findsOneWidget);
        expect(find.text('Reçue'), findsOneWidget);
        expect(find.text('Prise en charge par Formateur'), findsOneWidget);
        expect(find.text('Résolue'), findsOneWidget);
        await tester.tap(find.byKey(const Key('help-new-request')));
        await _settle(tester);
        expect(find.byKey(const Key('flow-step-subject')), findsOneWidget);
      },
    );

    testWidgets(
      '« Demander un formateur » again: the list, not the flow; the first time: the flow',
      (tester) async {
        final went = <String>[];
        await _openAide(
          tester,
          _farmPro,
          _Help(state: _pro(requests: three)),
          went: went,
        );
        await tester.ensureVisible(find.byKey(const Key('help-ask')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('help-ask')));
        await _settle(tester);
        expect(went, contains('demandes'));
        expect(find.byKey(const Key('help-new-request')), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        final fresh = <String>[];
        await _openAide(tester, _farmPro, _Help(state: _pro()), went: fresh);
        expect(find.byKey(const Key('help-my-requests')), findsNothing);
        await tester.ensureVisible(find.byKey(const Key('help-ask')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('help-ask')));
        await _settle(tester);
        expect(fresh, isNot(contains('demandes')));
        expect(find.byKey(const Key('flow-step-subject')), findsOneWidget);
      },
    );

    testWidgets('a second request while one is open: sent, both listed', (
      tester,
    ) async {
      final help = _Help(state: _pro(requests: [three.first]));
      await _size(tester, 390, 1200);
      await tester.pumpWidget(
        _routed(
          _router(_assocPro, help, at: '/o/${_assocPro.id}/aide/demandes'),
        ),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const Key('help-new-request')));
      await _settle(tester);
      await _tapSeen(tester, 'flow-option-contributions');
      await _next(tester);
      await tester.enterText(
        find.byKey(const Key('help-message')),
        'Une cotisation en double',
      );
      await tester.pump();
      await _next(tester);
      await tester.enterText(
        find.byKey(const Key('help-phone')),
        '22670000000',
      );
      await tester.pump();
      await _next(tester);
      await _next(tester);
      await tester.ensureVisible(find.byKey(const Key('flow-save')));
      await tester.tap(find.byKey(const Key('flow-save')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('flow-finish')));
      await _settle(tester);
      expect(find.byKey(const Key('help-request-r1')), findsOneWidget);
      expect(find.byKey(const Key('help-request-new-1')), findsOneWidget);
    });

    testWidgets('a bell opens its request', (tester) async {
      await _size(tester, 390, 1200);
      await tester.pumpWidget(
        _routed(
          _router(
            _shopPro,
            _Help(state: _pro(requests: three)),
            at: '/o/${_shopPro.id}/aide/demandes?demande=r2',
          ),
        ),
      );
      await _settle(tester);
      expect(find.byKey(const Key('help-request-card')), findsOneWidget);
      expect(find.byKey(const Key('help-write-trainer')), findsOneWidget);
      final n = NotificationRow(
        id: 'n',
        kind: 'help_resolved',
        message: 'm',
        createdAt: _now,
        orgId: 'o1',
        params: const {
          'to': 'shop',
          'request_id': '13813813-0000-0000-0000-0000000000aa',
        },
      );
      expect(
        notificationTarget(n),
        '/o/o1/aide/demandes?demande=13813813-0000-0000-0000-0000000000aa',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('6. the WhatsApp text and the e-mail\'s subject', () {
    Future<BuildContext> ctx(WidgetTester tester, String lang) async {
      late BuildContext c;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (b) {
              c = b;
              return const SizedBox();
            },
          ),
          lang: lang,
        ),
      );
      return c;
    }

    testWidgets('French, Pro and Basic', (tester) async {
      final c = await ctx(tester, 'fr');
      expect(
        helpWhatsAppText(c, _farmPro, pro: true, page: 'Aide'),
        '[PRO] Bonjour Marakaj, j\'ai besoin d\'aide.\n'
        'Entreprise : Ferme Horizon Vert (Ferme · Pro)\n'
        'Réf. : 14300000\n'
        'Page : Aide',
      );
      expect(
        helpWhatsAppText(c, _shopBasic, pro: false, page: 'Compte'),
        'Bonjour Marakaj, j\'ai besoin d\'aide.\n'
        'Entreprise : Maison Élégance (Boutique · Basic)\n'
        'Réf. : 14300000\n'
        'Page : Compte',
      );
      expect(
        helpWhatsAppText(c, _shopPro, pro: true),
        contains('Réf. : 3F2A91C0'),
      );
      expect(
        helpEmailSubject(c, _shopPro, pro: true),
        'Aide Marakaj — Maison Élégance · Réf. 3F2A91C0 · PRO',
      );
      expect(
        helpEmailSubject(c, _assocBasic, pro: false),
        'Aide Marakaj — Cercle des Bâtisseurs · Réf. 14300000',
      );
      expect(helpRef(_shopPro.id), '3F2A91C0');
    });

    testWidgets('English, Pro and Basic', (tester) async {
      final c = await ctx(tester, 'en');
      expect(
        helpWhatsAppText(c, _assocPro, pro: true, page: 'Help'),
        '[PRO] Hello Marakaj, I need help.\n'
        'Business: Fondation Espoir (Association · Pro)\n'
        'Ref.: 14300000\n'
        'Page: Help',
      );
      expect(
        helpWhatsAppText(c, _farmBasic, pro: false),
        startsWith(
          'Hello Marakaj, I need help.\nBusiness: Domaine des Acacias (Farm · Basic)',
        ),
      );
    });

    testWidgets(
      'the e-mail from the Aide page carries the name and the reference',
      (tester) async {
        final opened = _launches(tester);
        await _openAide(tester, _shopPro, _Help(state: _pro()));
        await tester.ensureVisible(find.byKey(const Key('help-mara-email')));
        await tester.tap(find.byKey(const Key('help-mara-email')));
        await _settle(tester);
        expect(opened.single, startsWith('mailto:hello@kaj-consulting.com'));
        expect(
          Uri.decodeComponent(opened.single),
          contains('Maison Élégance · Réf. 3F2A91C0 · PRO'),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  group('7. trainers chosen in the command center', () {
    const person = PlatformPerson(
      userId: 'u-143',
      isPlatformAdmin: false,
      businessCount: 1,
      fullName: 'Futur Formateur',
      phone: '+22670143143',
    );

    Future<void> sheet(
      WidgetTester tester,
      _Help help, {
      PlatformPerson p = person,
      String lang = 'fr',
      double w = 390,
      double text = 1,
    }) async {
      await _size(tester, w, 1100, text: text);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: PersonSheet(
              person: p,
              console: _Console(),
              admin: AdminRepository(null),
              help: help,
            ),
          ),
          lang: lang,
        ),
      );
      await _settle(tester);
    }

    testWidgets(
      'the switch: off, then « Formateur Marakaj » on after the confirmation',
      (tester) async {
        final help = _Help(
          trainer: const TrainerSwitch(isTrainer: false, phone: '22670143143'),
        );
        await sheet(tester, help);
        final sw = find.byKey(const Key('trainer-switch'));
        expect(sw, findsOneWidget);
        expect(tester.widget<SwitchListTile>(sw).value, isFalse);
        await tester.tap(sw);
        await _settle(tester);
        expect(
          find.text('Faire de Futur Formateur un formateur Marakaj ?'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('trainer-confirm')));
        await _settle(tester);
        expect(help.calls, ['trainer:u-143:true']);
        expect(tester.widget<SwitchListTile>(sw).value, isTrue);
        expect(find.byKey(const Key('trainer-phone')), findsOneWidget);
        expect(find.text('Joint au +226 70 14 31 43'), findsOneWidget);
        // And off again.
        await tester.tap(sw);
        await _settle(tester);
        await tester.tap(find.byKey(const Key('trainer-confirm')));
        await _settle(tester);
        expect(help.calls.last, 'trainer:u-143:false');
        expect(tester.widget<SwitchListTile>(sw).value, isFalse);
      },
    );

    testWidgets('a trainer with no number on their profile: the warning', (
      tester,
    ) async {
      await sheet(
        tester,
        _Help(trainer: const TrainerSwitch(isTrainer: true)),
        p: const PlatformPerson(
          userId: 'u-2',
          isPlatformAdmin: false,
          businessCount: 0,
          fullName: 'Sans Numéro',
        ),
      );
      expect(find.byKey(const Key('trainer-no-phone')), findsOneWidget);
    });

    testWidgets(
      'the server does not answer (not a platform admin): no switch',
      (tester) async {
        await sheet(tester, _Help());
        expect(find.byKey(const Key('trainer-switch')), findsNothing);
      },
    );

    testWidgets(
      'the console\'s Formateurs: the trainers made so, one with no number said',
      (tester) async {
        final help = _Help()
          ..consoleAnswer = const HelpConsole(
            trainers: [
              ConsoleTrainer(
                name: 'Futur Formateur',
                userId: 'u-143',
                hasPhone: true,
              ),
              ConsoleTrainer(name: 'Sans Numéro', userId: 'u-2'),
            ],
          );
        await _size(tester, 390, 1400);
        await tester.pumpWidget(_app(HelpConsoleScreen(help: help)));
        await _settle(tester);
        expect(find.text('Futur Formateur'), findsOneWidget);
        expect(
          find.byKey(const Key('help-console-no-phone-u-2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('help-console-no-phone-u-143')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('help-console-how-trainers')),
          findsOneWidget,
        );
      },
    );

    testWidgets('English', (tester) async {
      await sheet(
        tester,
        _Help(trainer: const TrainerSwitch(isTrainer: true)),
        lang: 'en',
        p: const PlatformPerson(
          userId: 'u-2',
          isPlatformAdmin: false,
          businessCount: 0,
          fullName: 'Sans Numéro',
        ),
      );
      expect(find.text('Marakaj trainer'), findsOneWidget);
      expect(find.textContaining('No number on their profile'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('8. 320 px, text ×1.3, French and English: nothing overflows', () {
    for (final lang in ['fr', 'en']) {
      testWidgets(
        '$lang: Basic Aide and its pop-up, Pro Aide, the list, the FAQ, every step, the fiche',
        (tester) async {
          await _size(tester, 320, 640, text: 1.3);
          for (final (org, state) in [
            (_farmBasic, _basic()),
            (_as(_assocBasic, roles: ['employee']), _basic(canUpgrade: false)),
          ]) {
            HelpContact.reset();
            prefs.values.clear(); // another person, another device
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(
              _routed(_router(org, _Help(state: state)), lang: lang),
            );
            await _settle(tester);
            expect(tester.takeException(), isNull);
            await _tapWhatsApp(tester);
            expect(find.byKey(const Key('help-nudge')), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          final three = [
            _req('r1', 'open'),
            _req(
              'r2',
              'taken',
              trainer: const HelpTrainer(
                firstName: 'Formateur',
                phone: '22670000001',
              ),
            ),
          ];
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            _routed(
              _router(_shopPro, _Help(state: _pro(requests: three))),
              lang: lang,
            ),
          );
          await _settle(tester);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byKey(const Key('help-ask')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('help-ask')));
          await _settle(tester);
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.byKey(const Key('help-request-r2')),
            200,
            scrollable: find
                .descendant(
                  of: find.byType(HelpRequestsScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.tap(find.byKey(const Key('help-request-r2')));
          await _settle(tester);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            _app(const FaqScreen(org: _shopBasic), lang: lang),
          );
          await _settle(tester);
          expect(tester.takeException(), isNull);
          for (final org in [_shopPro, _farmPro, _assocPro]) {
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(_app(_flow(org, _Help()), lang: lang));
            await _settle(tester);
            expect(tester.takeException(), isNull);
            await _tapSeen(tester, 'flow-option-catalogue');
            await _next(tester);
            await tester.enterText(
              find.byKey(const Key('help-message')),
              'Comment ajouter une photo à un article ?',
            );
            await tester.pump();
            await _next(tester);
            expect(tester.takeException(), isNull);
            await _next(tester);
            await _tapSeen(tester, 'flow-option-true');
            await _tapSeen(tester, 'help-day-2');
            await _tapSeen(tester, 'help-hour-20');
            expect(tester.takeException(), isNull);
            await _next(tester);
            expect(tester.takeException(), isNull);
            // The summary scrolled to its end, « Quand » changed from it:
            // step 4 opens at its top, « Quand ? » whole under the bar.
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -2000),
            );
            await tester.pumpAndSettle();
            await _tapSeen(tester, 'flow-edit-when');
            await _settle(tester);
            expect(find.byKey(const Key('flow-step-when')), findsOneWidget);
            expect(
              tester.getRect(find.byKey(const Key('flow-question'))).top,
              greaterThanOrEqualTo(
                tester.getRect(find.byKey(const Key('flow-step-bar'))).bottom,
              ),
            );
            await _next(tester);
            await tester.ensureVisible(find.byKey(const Key('flow-save')));
            await tester.tap(find.byKey(const Key('flow-save')));
            await _settle(tester);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            _app(
              Scaffold(
                body: PersonSheet(
                  person: const PlatformPerson(
                    userId: 'u',
                    isPlatformAdmin: false,
                    businessCount: 2,
                    fullName: 'Futur Formateur du Cercle des Bâtisseurs',
                  ),
                  console: _Console(),
                  admin: AdminRepository(null),
                  help: _Help(trainer: const TrainerSwitch(isTrainer: true)),
                ),
              ),
              lang: lang,
            ),
          );
          await _settle(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // -------------------------------------------------------------------------
  group('9. the missing Pro word on a platform admin\'s own Basic farm', () {
    testWidgets(
      'the help reaches them: the button there, the page, the pop-up',
      (tester) async {
        // my_orgs() gives a platform admin « platform_admin » in their own
        // farm; 136 hid the button and never asked help_state.
        final farm = _as(_farmBasic, roles: ['platform_admin']);
        await _size(tester, 390, 900);
        await tester.pumpWidget(
          _app(
            Scaffold(
              appBar: AppBar(
                actions: [
                  HelpButton(
                    org: farm,
                    help: _Help(state: _basic()),
                  ),
                ],
              ),
            ),
          ),
        );
        await _settle(tester);
        expect(find.byKey(const Key('help-free-button')), findsOneWidget);
        await tester.pumpWidget(
          _app(
            Scaffold(
              appBar: AppBar(
                actions: [
                  HelpButton(
                    org: _as(_farmBasic, roles: ['platform_admin']),
                    help: _Help(state: const HelpState(available: false)),
                  ),
                ],
              ),
            ),
          ),
        );
        HelpButton.reset();
        await _settle(tester);
        // Someone else's business: still nothing.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _app(
            Scaffold(
              appBar: AppBar(
                actions: [
                  HelpButton(
                    org: _as(_shopBasic, roles: ['platform_admin']),
                    help: _Help(state: const HelpState(available: false)),
                  ),
                ],
              ),
            ),
          ),
        );
        await _settle(tester);
        expect(find.byKey(const Key('help-free-button')), findsNothing);
        // And the page tells them about Pro, once.
        await tester.pumpWidget(const SizedBox());
        await _openAide(tester, farm, _Help(state: _basic()));
        await _tapWhatsApp(tester);
        expect(find.byKey(const Key('help-nudge-pro')), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('10. the review\'s fixes', () {
    testWidgets(
      'out of the hours: the request sent says when a trainer answers',
      (tester) async {
        final help = _QueuedHelp();
        await _size(tester, 390, 844);
        await tester.pumpWidget(
          _app(
            HelpRequestFlow(
              org: _shopPro,
              state: help.stateAnswer,
              help: help,
              phone: '22670000000',
              store: MemoryFlowStore(),
            ),
          ),
        );
        await _settle(tester);
        await _tapSeen(tester, 'flow-option-catalogue');
        await _next(tester);
        await tester.enterText(find.byKey(const Key('help-message')), 'Un mot');
        await tester.pump();
        await _next(tester);
        await _next(tester);
        await _next(tester); // « Maintenant »
        await tester.ensureVisible(find.byKey(const Key('flow-save')));
        await tester.tap(find.byKey(const Key('flow-save')));
        await _settle(tester);
        expect(find.byKey(const Key('flow-done')), findsOneWidget);
        expect(
          find.text('Un formateur vous répondra demain à partir de 7 h.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'back on Basic: « Mes demandes » still there, no « Demander un formateur » nor « Nouvelle demande »',
      (tester) async {
        final help = _Help(
          state: HelpState(
            available: true,
            pro: false,
            canUpgrade: true,
            listed: [_req('r1', 'taken', trainer: const HelpTrainer(firstName: 'Formateur'))],
          ),
        );
        await _openAide(tester, _shopBasic, help, h: 1200);
        expect(find.byKey(const Key('help-ask')), findsNothing);
        expect(find.byKey(const Key('help-247')), findsNothing);
        expect(find.byKey(const Key('help-my-requests')), findsOneWidget);
        await tester.tap(find.byKey(const Key('help-my-requests')));
        await _settle(tester);
        expect(find.byKey(const Key('help-request-r1')), findsOneWidget);
        expect(find.byKey(const Key('help-new-request')), findsNothing);
      },
    );

    testWidgets(
      'a server before 138 with a request on: « Nouvelle demande » off, and why',
      (tester) async {
        final active = _req('r1', 'open');
        final help = _Help(
          state: HelpState(
            available: true,
            pro: true,
            request: active,
            left: 4,
            version: 133,
          ),
        );
        await _openAide(
          tester,
          _shopPro,
          help,
          h: 1200,
        );
        await tester.tap(find.byKey(const Key('help-my-requests')));
        await _settle(tester);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('help-new-request')))
              .onPressed,
          isNull,
        );
        expect(
          find.text('Une demande d\'aide est déjà en cours pour cette entreprise.'),
          findsOneWidget,
        );
      },
    );

    test('a server before 138: the whole message within 133\'s 500', () {
      final long = 'é' * 600;
      final p = HelpRepository.createParams(
        orgId: 'o1',
        subject: 'livraison',
        contact: 'call',
        message: long,
        preferredAt: DateTime.utc(2026, 10, 15, 10),
        subjectWords: 'Livraison',
        whenWords: 'Souhaité demain à 10:00',
        server: 133,
      );
      final m = p['p_message'] as String;
      expect(m.runes.length, lessThanOrEqualTo(maxMessage133));
      expect(m, startsWith('[Livraison] (Souhaité demain à 10:00) éé'));
      // 138 takes the words as they are (its own 500 is the flow's).
      expect(
        HelpRepository.createParams(
          orgId: 'o1',
          subject: 'livraison',
          contact: 'call',
          message: long,
        )['p_message'],
        long,
      );
    });

    testWidgets('a trainer turned off: the dialog says the businesses they lose', (
      tester,
    ) async {
      await _size(tester, 390, 900);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: PersonSheet(
              person: const PlatformPerson(
                userId: 'u-off',
                isPlatformAdmin: false,
                businessCount: 3,
                fullName: 'Futur Formateur',
                phone: '+22670143143',
              ),
              console: _Console(),
              admin: AdminRepository(null),
              help: _Help(
                trainer: const TrainerSwitch(
                  isTrainer: true,
                  phone: '22670143143',
                  assigned: 3,
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await tester.ensureVisible(find.byKey(const Key('trainer-switch')));
      await tester.tap(find.byKey(const Key('trainer-switch')));
      await _settle(tester);
      expect(
        find.text(
          'Cette personne ne recevra plus de demandes d\'aide ; ses accès en lecture seule s\'arrêtent, et elle ne verra plus les 3 entreprises qui lui sont confiées.',
        ),
        findsOneWidget,
      );
    });

    test('the new server sentences have their English', () {
      for (final fr in const [
        'Choisissez un moment dans les 14 jours qui viennent.',
        'Choisissez un jour et une heure, s\'il vous plaît.',
        'Seule l\'équipe Marakaj choisit les formateurs.',
        'Formateur : oui ou non.',
        'Ce compte n\'existe pas.',
        'Ce compte n\'a pas de numéro : il pourra devenir formateur une fois le serveur à jour.',
      ]) {
        expect(translate('en', fr), isNot(fr), reason: fr);
      }
    });
  });

  // -------------------------------------------------------------------------
  // Screenshots (B143_SHOTS=<dir>)
  // -------------------------------------------------------------------------
  final shots = Platform.environment['B143_SHOTS'];
  group('screenshots', () {
    Future<void> realFonts() async {
      var dir = File(Platform.resolvedExecutable).parent;
      for (
        var i = 0;
        i < 6 && !Directory('${dir.path}/material_fonts').existsSync();
        i++
      ) {
        dir = dir.parent;
      }
      final fonts = Directory('${dir.path}/material_fonts');
      if (!fonts.existsSync()) return;
      final loader = FontLoader('Roboto');
      for (final f in const [
        'Roboto-Regular.ttf',
        'Roboto-Medium.ttf',
        'Roboto-Bold.ttf',
        'Roboto-Black.ttf',
      ]) {
        final file = File('${fonts.path}/$f');
        if (file.existsSync()) {
          loader.addFont(
            Future.value(ByteData.view(file.readAsBytesSync().buffer)),
          );
        }
      }
      await loader.load();
      final icons = File('${fonts.path}/MaterialIcons-Regular.otf');
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.view(icons.readAsBytesSync().buffer)),
            ))
            .load();
      }
    }

    Future<void> shoot(WidgetTester tester, String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('shot')).first,
        );
        final img = await ro.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    final sizes = [('390', 390.0, 844.0, 1.0), ('320x1.3', 320.0, 640.0, 1.3)];
    for (final lang in ['fr', 'en']) {
      for (final (tag, w, h, text) in sizes) {
        testWidgets('$lang $tag', (tester) async {
          Directory(shots!).createSync(recursive: true);
          await tester.runAsync(realFonts);
          await _size(tester, w, h, text: text);
          final p = '${lang}_${tag}_';

          // Basic Aide, the pop-up (owner and employee).
          await tester.pumpWidget(
            _routed(_router(_farmBasic, _Help(state: _basic())), lang: lang),
          );
          await _settle(tester);
          await shoot(tester, '${p}01_basic_aide');
          await _tapWhatsApp(tester);
          await shoot(tester, '${p}02_popup_owner');
          HelpContact.reset();
          prefs.values.clear(); // another person, another device
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            _routed(
              _router(
                _as(_assocBasic, roles: ['employee']),
                _Help(state: _basic(canUpgrade: false)),
              ),
              lang: lang,
            ),
          );
          await _settle(tester);
          await _tapWhatsApp(tester);
          await shoot(tester, '${p}03_popup_employee');

          // The FAQ with its banner.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            _app(const FaqScreen(org: _shopBasic), lang: lang),
          );
          await _settle(tester);
          await shoot(tester, '${p}04_faq_banner');

          // Pro Aide, with two requests going.
          final reqs = [
            _req(
              'r1',
              'open',
              message: 'Je n\'arrive pas à ajouter un article',
            ),
            _req(
              'r2',
              'taken',
              subject: 'ventes',
              message: 'La caisse ne tombe pas juste',
              trainer: const HelpTrainer(
                firstName: 'Formateur',
                phone: '22670000001',
              ),
            ),
            _req(
              'r3',
              'resolved',
              subject: 'factures',
              message: 'Une facture en double',
              trainer: const HelpTrainer(firstName: 'Formateur'),
            ),
          ];
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            _routed(
              _router(_shopPro, _Help(state: _pro(requests: reqs))),
              lang: lang,
            ),
          );
          await _settle(tester);
          await shoot(tester, '${p}05_pro_aide');
          await tester.ensureVisible(find.byKey(const Key('help-ask')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('help-ask')));
          await _settle(tester);
          await shoot(tester, '${p}06_requests');
          await tester.tap(find.byKey(const Key('help-request-r2')));
          await _settle(tester);
          await shoot(tester, '${p}07_request_taken');

          // Every step of the flow: the shop's, and the farm's and the
          // association's first step (their own subjects).
          for (final (k, org) in [
            ('farm', _farmPro),
            ('association', _assocPro),
          ]) {
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(_app(_flow(org, _Help()), lang: lang));
            await _settle(tester);
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -2000),
            );
            await _settle(tester);
            await shoot(tester, '${p}08_step1_subject_$k');
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_app(_flow(_shopPro, _Help()), lang: lang));
          await _settle(tester);
          await _tapSeen(tester, 'flow-option-catalogue');
          await shoot(tester, '${p}08_step1_subject_shop');
          await _next(tester);
          await tester.enterText(
            find.byKey(const Key('help-message')),
            lang == 'en'
                ? 'How do I add a second photo to an item?'
                : 'Comment ajouter une deuxième photo à un article ?',
          );
          await tester.pump();
          FocusManager.instance.primaryFocus?.unfocus();
          await shoot(tester, '${p}09_step2_describe');
          await _next(tester);
          await _tapSeen(tester, 'flow-option-call');
          await shoot(tester, '${p}10_step3_how');
          await _next(tester);
          await _tapSeen(tester, 'flow-option-true');
          await _tapSeen(tester, 'help-day-1');
          await _tapSeen(tester, 'help-hour-10');
          // From its top, as it opens (the taps scrolled to the hour).
          await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
          await shoot(tester, '${p}11_step4_when');
          await _next(tester);
          await shoot(tester, '${p}12_step5_summary');
          await tester.ensureVisible(find.byKey(const Key('flow-save')));
          await tester.tap(find.byKey(const Key('flow-save')));
          await _settle(tester);
          await shoot(tester, '${p}13_sent');

          // The command center's trainer switch, and its warning.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            _app(
              Scaffold(
                body: PersonSheet(
                  person: const PlatformPerson(
                    userId: 'u',
                    isPlatformAdmin: false,
                    businessCount: 1,
                    fullName: 'Futur Formateur',
                    phone: '+22670143143',
                  ),
                  console: _Console(),
                  admin: AdminRepository(null),
                  help: _Help(
                    trainer: const TrainerSwitch(
                      isTrainer: true,
                      phone: '22670143143',
                    ),
                  ),
                ),
              ),
              lang: lang,
            ),
          );
          await _settle(tester);
          await shoot(tester, '${p}14_trainer_switch');
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            _app(
              Scaffold(
                body: PersonSheet(
                  person: const PlatformPerson(
                    userId: 'u2',
                    isPlatformAdmin: false,
                    businessCount: 0,
                    fullName: 'Sans Numéro',
                  ),
                  console: _Console(),
                  admin: AdminRepository(null),
                  help: _Help(trainer: const TrainerSwitch(isTrainer: true)),
                ),
              ),
              lang: lang,
            ),
          );
          await _settle(tester);
          await shoot(tester, '${p}15_trainer_no_phone');
        });
      }
    }
  }, skip: shots == null ? 'B143_SHOTS=<dir> writes the screenshots' : null);
}
