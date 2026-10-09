import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/admin/setup_steps.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/whatsapp_phone.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/application_form.dart';
import 'package:kaj_app/core/onboarding/business_creation.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/features/admin/created_businesses_screen.dart';
import 'package:kaj_app/features/auth/join_or_apply_screen.dart';
import 'package:kaj_app/features/auth/org_picker_screen.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/features/setup/association_setup_screen.dart';
import 'package:kaj_app/features/setup/create_my_business_screen.dart';
import 'package:kaj_app/features/setup/setup_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// 111 in the app: « Créer mon activité » — one question per screen, the
/// address said free or taken at once, the kind's own lines of trade, the
/// phone (proved on WhatsApp when the platform asks), Mara's questions as
/// screens of their own, the answers kept on the device and taken up
/// again, the summary and the creation; the entry points; « Activités
/// créées »; and the setup starting from what the creation wrote.

class _Api implements BusinessCreation {
  _Api({this.start_ = const BusinessStart(), this.taken = const {}, this.reserved = const {}});

  BusinessStart start_;
  Set<String> taken;
  /// Addresses the server says are Mara's (111's business_address_reserved).
  Set<String> reserved;
  final checked = <String>[];
  Map<String, Object?>? sent;
  Object? fail;

  @override
  Future<BusinessStart> start() async => start_;

  @override
  Future<AddressCheck> checkAddress(String slug) async {
    checked.add(slug);
    if (reserved.contains(slug)) {
      return AddressCheck(slug: slug, problem: 'Cette adresse est réservée à Mara : choisissez-en une autre.');
    }
    return taken.contains(slug)
        ? AddressCheck(slug: slug, taken: true, suggestion: '$slug-2')
        : AddressCheck(slug: slug);
  }

  @override
  Future<String> create({
    required String profile,
    required String name,
    required String slug,
    required String activity,
    required String about,
    required String city,
    required String area,
    required String phone,
    required String currency,
    Map<String, Object?>? answers,
  }) async {
    final f = fail;
    if (f != null) throw f;
    sent = {
      'profile': profile, 'name': name, 'slug': slug, 'activity': activity, 'about': about,
      'city': city, 'area': area, 'phone': phone, 'currency': currency, 'answers': answers,
    };
    return 'org-new';
  }
}

class _Drafts implements DraftStore {
  _Drafts([this.kept]);

  BusinessDraft? kept;
  int writes = 0;

  @override
  Future<BusinessDraft?> read() async =>
      kept == null ? null : BusinessDraft.fromJson(Map<String, dynamic>.from(kept!.toJson()));

  @override
  Future<void> write(BusinessDraft? draft) async {
    writes++;
    kept = draft == null ? null : BusinessDraft.fromJson(Map<String, dynamic>.from(draft.toJson()));
  }
}

class _WhatsApp implements WhatsAppPhone {
  @override
  Future<OrderPhoneGate?> gate() async => null;
  @override
  Future<void> sendCode(String e164) async {}
  @override
  Future<void> confirm(String e164, String code) async {}
}

class _Center extends CommandCenterRepository {
  _Center(this.list) : super(null);

  final CreatedBusinesses list;

  @override
  Future<CreatedBusinesses> createdBusinesses({int limit = 200}) async => list;
}

class _Onboarding extends OnboardingRepository {
  _Onboarding() : super(null);

  @override
  Future<bool> isProfileComplete() async => true;
}

class _SetupActions implements SetupActions {
  final log = <String>[];
  @override
  Future<void> rename(String orgId, String name, String currency) async {}
  @override
  Future<void> addArticle(String orgId,
      {required String name, required double price, required double quantity}) async {}
  @override
  Future<void> saveVitrine(String orgId,
          {required bool open, required String blurb, required String phone, required String address}) async =>
      log.add('vitrine $blurb $phone $address');
  @override
  Future<void> savePosition(String orgId, double lat, double lng) async {}
  @override
  Future<void> finish(String orgId) async {}
}

class _AssociationActions implements AssociationSetupActions {
  final log = <String>[];
  @override
  Future<void> identify(String orgId,
          {required String name, required String currency, required String kind, required String about}) async =>
      log.add('identify $name $kind $about');
  @override
  Future<void> addMember(String orgId, {required String name, required String phone}) async {}
  @override
  Future<void> addService(String orgId, {required String name, required double price}) async {}
  @override
  Future<void> saveVitrine(String orgId,
      {required bool open, required String about, required String phone, required String address}) async {}
  @override
  Future<void> finish(String orgId) async {}
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  VoidCallback? next(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('create-next'))).onPressed;

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('create-next')));
    await settle(tester);
  }

  Future<String?> pumpFlow(WidgetTester tester, _Api api,
      {_Drafts? drafts, ApplicationForm? preview, bool seen = true, List<OrgSummary>? handed}) async {
    String? created;
    await tester.pumpWidget(MaterialApp(
      home: CreateMyBusinessScreen(
        key: UniqueKey(),
        api: api,
        drafts: drafts,
        whatsApp: _WhatsApp(),
        previewForm: preview,
        onCreated: (org) async {
          created = org.id;
          handed?.add(org);
          return seen;
        },
      ),
    ));
    await settle(tester);
    return created;
  }

  group('the flow, one question a screen', () {
    testWidgets('a shop from the first tile to « Créer mon activité »', (tester) async {
      phone(tester);
      final api = _Api();
      final drafts = _Drafts();
      String? created;
      await tester.pumpWidget(MaterialApp(
        home: CreateMyBusinessScreen(
            api: api, drafts: drafts, onCreated: (org) async {
              created = org.id;
              return true;
            }),
      ));
      await settle(tester);

      // No form: the three kinds, no welcome, five screens and the summary.
      expect(find.text('1 / 6'), findsOneWidget);
      expect(find.byKey(const Key('create-welcome')), findsNothing);
      for (final k in ['retail', 'farm', 'association']) {
        expect(find.byKey(Key('create-kind-$k')), findsOneWidget);
      }
      expect(next(tester), isNull, reason: 'nothing chosen yet');
      await tester.tap(find.byKey(const Key('create-kind-retail')));
      await settle(tester);
      await tapNext(tester);

      // The name writes the address, said free at once.
      expect(find.text('Le nom de votre boutique'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('create-name')), 'Chez Awa');
      await settle(tester);
      expect(find.text('marakaj.com/s/chez-awa'), findsOneWidget);
      expect(api.checked.last, 'chez-awa');
      expect(find.byKey(const Key('create-address-free')), findsOneWidget);
      await tapNext(tester);

      // What it does: the shop's lines of trade, and a sentence.
      expect(find.text('Que vend votre boutique ?'), findsOneWidget);
      expect(find.byKey(const Key('create-activity-volaille')), findsNothing);
      expect(next(tester), isNull);
      await tester.tap(find.byKey(const Key('create-activity-alimentation')));
      await tester.enterText(find.byKey(const Key('create-about')), 'Riz et huile au détail');
      await settle(tester);
      await tapNext(tester);

      // Where: a town in one tap, the area typed.
      expect(next(tester), isNull);
      await tester.tap(find.text('Ouagadougou'));
      await tester.enterText(find.byKey(const Key('create-area')), 'Dapoya');
      await settle(tester);
      await tapNext(tester);

      // The phone, its country's length said; the currency the country's.
      await tester.enterText(find.byKey(const Key('create-phone')), '70 11 22');
      await settle(tester);
      expect(find.text('8 chiffres pour Burkina Faso (+226)'), findsOneWidget);
      expect(next(tester), isNull);
      await tester.enterText(find.byKey(const Key('create-phone')), '70 11 22 33');
      await settle(tester);
      expect(find.textContaining('XOF — Franc CFA (UEMOA)'), findsOneWidget);
      await tapNext(tester);

      // Everything on one page; a line taps back to its screen.
      expect(find.text('Tout est juste ?'), findsOneWidget);
      expect(find.text('marakaj.com/s/chez-awa'), findsOneWidget);
      expect(find.text('Alimentation'), findsOneWidget);
      expect(find.text('+22670112233'), findsOneWidget);
      expect(drafts.kept?.name, 'Chez Awa', reason: 'kept on the device as typed');
      await tester.tap(find.byKey(const Key('create-submit')));
      await settle(tester);
      expect(api.sent, {
        'profile': 'retail', 'name': 'Chez Awa', 'slug': 'chez-awa', 'activity': 'alimentation',
        'about': 'Riz et huile au détail', 'city': 'Ouagadougou', 'area': 'Dapoya',
        'phone': '+22670112233', 'currency': 'XOF', 'answers': null,
      });
      expect(created, 'org-new');
      expect(drafts.kept, isNull, reason: 'created: the answers leave the device');
    });

    testWidgets('an address taken is said with a free one, which unlocks Suivant', (tester) async {
      phone(tester);
      final api = _Api(taken: {'chez-awa'});
      await pumpFlow(tester, api);
      await tester.tap(find.byKey(const Key('create-kind-retail')));
      await settle(tester);
      await tapNext(tester);
      await tester.enterText(find.byKey(const Key('create-name')), 'Chez Awa');
      await settle(tester);
      expect(find.byKey(const Key('create-address-taken')), findsOneWidget);
      expect(next(tester), isNull);
      await tester.tap(find.byKey(const Key('create-address-suggestion')));
      await settle(tester);
      expect(find.text('marakaj.com/s/chez-awa-2'), findsOneWidget);
      expect(find.byKey(const Key('create-address-free')), findsOneWidget);
      expect(next(tester), isNotNull);
      // A bad address typed by hand is said before anything is asked.
      await tester.enterText(find.byKey(const Key('create-slug')), 'ab');
      await settle(tester);
      expect(find.text('Au moins 3 caractères.'), findsOneWidget);
      expect(next(tester), isNull);
    });

    testWidgets('an address reserved for Mara is said in its words; Suivant stays off', (tester) async {
      phone(tester);
      final api = _Api(reserved: {'support'});
      await pumpFlow(tester, api);
      await tester.tap(find.byKey(const Key('create-kind-retail')));
      await settle(tester);
      await tapNext(tester);
      await tester.enterText(find.byKey(const Key('create-name')), 'Support');
      await settle(tester);
      expect(api.checked, contains('support'));
      expect(find.text('Cette adresse est réservée à Mara : choisissez-en une autre.'), findsOneWidget);
      expect(next(tester), isNull);
      await tester.enterText(find.byKey(const Key('create-name')), 'Support Awa');
      await settle(tester);
      expect(find.byKey(const Key('create-address-free')), findsOneWidget);
      expect(next(tester), isNotNull);
    });

    testWidgets('an older app\'s request answered at once: the bell reads in English and opens the creation', (tester) async {
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
      final row = NotificationRow(
        id: 'n', kind: 'application_update_app',
        message: 'Mettez à jour Mara : vous créez maintenant votre activité vous-même',
        createdAt: DateTime(2026, 10, 8), params: const {'to': 'applicant', 'name': 'Chez Awa'});
      expect(notificationLine(ctx, row), 'Update Mara: you now create your business yourself');
      expect(notificationTarget(row), Routes.createBusiness);
    });

    testWidgets('each kind its own lines of trade — a farm\'s, an association\'s (102)', (tester) async {
      phone(tester);
      for (final (kind, here, notHere) in [
        ('farm', 'create-activity-volaille', 'create-activity-alimentation'),
        ('association', 'create-activity-tontine', 'create-activity-volaille'),
      ]) {
        await pumpFlow(tester, _Api());
        await tester.tap(find.byKey(Key('create-kind-$kind')));
        await settle(tester);
        await tapNext(tester);
        await tester.enterText(find.byKey(const Key('create-name')), 'Wend Kuni $kind');
        await settle(tester);
        await tapNext(tester);
        expect(find.byKey(Key(here)), findsOneWidget);
        expect(find.byKey(Key(notHere)), findsNothing);
      }
    });

    testWidgets('back steps back; the bar says where', (tester) async {
      phone(tester);
      await pumpFlow(tester, _Api());
      await tester.tap(find.byKey(const Key('create-kind-farm')));
      await settle(tester);
      await tapNext(tester);
      expect(find.text('2 / 6'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-back')));
      await settle(tester);
      expect(find.text('1 / 6'), findsOneWidget);
      expect(find.byKey(const Key('create-back')), findsNothing);
    });

    testWidgets('a refusal from the server is said, the answers kept', (tester) async {
      phone(tester);
      final api = _Api()..fail = Exception('Une deuxième entreprise : avec Mara Pro.');
      final drafts = _Drafts(BusinessDraft(
          step: 5, profile: 'retail', name: 'Chez Awa', slug: 'chez-awa', activity: 'autre',
          city: 'Kaya', phone: '70112233'));
      await pumpFlow(tester, api, drafts: drafts);
      expect(find.text('Tout est juste ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-submit')));
      await settle(tester);
      expect(find.byKey(const Key('create-error')), findsOneWidget);
      expect(drafts.kept?.name, 'Chez Awa');
    });
  });

  group('A7 — back on every question, and the way home (batch 115)', () {
    GoRouter router(_Drafts drafts, {String at = '/depart'}) => GoRouter(
          initialLocation: at,
          routes: [
            GoRoute(path: Routes.directory, builder: (_, _) => const Scaffold(body: Text('La rue'))),
            GoRoute(
              path: '/depart',
              builder: (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () => context.push(Routes.createBusiness),
                  child: const Text('Départ'),
                ),
              ),
            ),
            GoRoute(
              path: Routes.createBusiness,
              builder: (_, _) => CreateMyBusinessScreen(api: _Api(), drafts: drafts, whatsApp: _WhatsApp()),
            ),
          ],
        );

    Future<void> open(WidgetTester tester, GoRouter r, {bool push = true}) async {
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: r,
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
      ));
      await settle(tester);
      if (push) {
        await tester.tap(find.text('Départ'));
        await settle(tester);
      }
    }

    testWidgets('the bar\'s back arrow: the previous question, then where the person came from — asked first, the answers kept',
        (tester) async {
      phone(tester);
      final drafts = _Drafts();
      await open(tester, router(drafts));
      expect(find.text('1 / 6'), findsOneWidget);
      // Nothing answered yet: back at once, nothing asked.
      await tester.tap(find.byKey(const Key('create-bar-back')));
      await settle(tester);
      expect(find.text('Départ'), findsOneWidget);
      expect(find.byKey(const Key('create-leave')), findsNothing);

      await tester.tap(find.text('Départ'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('create-kind-farm')));
      await settle(tester);
      await tapNext(tester);
      expect(find.text('2 / 6'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-bar-back')));
      await settle(tester);
      expect(find.text('1 / 6'), findsOneWidget, reason: 'the previous question');

      // Something answered: « Quitter sans enregistrer ? », and Rester stays.
      await tester.tap(find.byKey(const Key('create-bar-back')));
      await settle(tester);
      expect(find.byKey(const Key('create-leave')), findsOneWidget);
      expect(find.text('Quitter sans enregistrer ?'), findsOneWidget);
      expect(find.textContaining('Vos réponses sont gardées'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-leave-stay')));
      await settle(tester);
      expect(find.text('1 / 6'), findsOneWidget);

      await tester.tap(find.byKey(const Key('create-bar-back')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('create-leave-go')));
      await settle(tester);
      expect(find.text('Départ'), findsOneWidget);
      expect(drafts.kept?.profile, 'farm', reason: 'the answers are kept anyway');
    });

    testWidgets('« Retour à l\'accueil » on the first question: the welcome page, the street', (tester) async {
      phone(tester);
      final drafts = _Drafts();
      await open(tester, router(drafts));
      expect(find.byKey(const Key('create-home')), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-kind-retail')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('create-home')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('create-leave-go')));
      await settle(tester);
      expect(find.text('La rue'), findsOneWidget);
      // Not on the later questions: there the back goes one question back.
      await tester.pumpWidget(const SizedBox());
      final again = _Drafts(BusinessDraft(step: 1, profile: 'retail'));
      await open(tester, router(again));
      expect(find.text('2 / 6'), findsOneWidget);
      expect(find.byKey(const Key('create-home')), findsNothing);
      expect(find.byKey(const Key('create-bar-back')), findsOneWidget);
    });

    testWidgets('reached by its address alone: back from the first question is the street', (tester) async {
      phone(tester);
      await open(tester, router(_Drafts(), at: Routes.createBusiness), push: false);
      await tester.tap(find.byKey(const Key('create-bar-back')));
      await settle(tester);
      expect(find.text('La rue'), findsOneWidget);
    });
  });

  group('kept on the device, taken up again', () {
    testWidgets('reopened, it is where it was, the fields filled', (tester) async {
      phone(tester);
      final drafts = _Drafts(BusinessDraft(
          step: 3, profile: 'farm', name: 'Ferme Wend', slug: 'ferme-wend', activity: 'volaille'));
      await pumpFlow(tester, _Api(), drafts: drafts);
      expect(find.text('4 / 6'), findsOneWidget);
      expect(find.byKey(const Key('create-resumed')), findsOneWidget);
      expect(find.text('Où se trouve votre ferme ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-back')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('create-back')));
      await settle(tester);
      expect(find.text('Ferme Wend'), findsOneWidget);
      expect(find.byKey(const Key('create-resumed')), findsNothing, reason: 'said once');
    });

    testWidgets('created on a bad line: the answers stay until the app has the business', (tester) async {
      phone(tester);
      BusinessDraft summary() => BusinessDraft(
          step: 5, profile: 'retail', name: 'Chez Awa', slug: 'chez-awa', activity: 'alimentation',
          city: 'Ouagadougou', area: 'Dapoya', phoneIso: 'BF', phone: '70112233');
      final handed = <OrgSummary>[];
      // The app could not see it yet: everything typed is still there.
      final kept = _Drafts(summary());
      await pumpFlow(tester, _Api(), drafts: kept, seen: false, handed: handed);
      expect(find.text('Tout est juste ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-submit')));
      await settle(tester);
      expect(kept.kept?.name, 'Chez Awa', reason: 'not seen yet: kept on the device');
      // What the session is handed to add it: the business, its owner.
      expect(handed.single.id, 'org-new');
      expect(handed.single.name, 'Chez Awa');
      expect(handed.single.profile, 'retail');
      expect(handed.single.slug, 'chez-awa');
      expect(handed.single.roles, ['owner']);
      // Seen: the answers leave the device.
      final gone = _Drafts(summary());
      await pumpFlow(tester, _Api(), drafts: gone);
      await tester.tap(find.byKey(const Key('create-submit')));
      await settle(tester);
      expect(gone.kept, isNull);
    });

    test('a draft survives its round trip', () {
      final d = BusinessDraft(step: 2, profile: 'retail', name: 'A', slug: 'a-b', slugTouched: true,
          activity: 'beaute', about: 'x', city: 'Kaya', area: 'y', phoneIso: 'CI', phone: '0701',
          currency: 'EUR', answers: {'q1': true, 'q2': 'oui'});
      expect(BusinessDraft.fromJson(Map<String, dynamic>.from(d.toJson())).toJson(), d.toJson());
    });

    test('the currency follows the phone\'s country', () {
      expect(currencyOfCountry('BF'), 'XOF');
      expect(currencyOfCountry('CI'), 'XOF');
      expect(currencyOfCountry('CM'), 'XAF');
      expect(currencyOfCountry('GH'), 'GHS');
      expect(currencyOfCountry('FR'), 'EUR');
      expect(currencyOfCountry('JP'), 'XOF');
    });
  });

  group('the platform\'s rules, said before the server says them', () {
    testWidgets('a second business without Pro: a page that says so, no questions', (tester) async {
      phone(tester);
      await pumpFlow(tester, _Api(start_: const BusinessStart(locked: true)));
      expect(find.byKey(const Key('create-locked')), findsOneWidget);
      expect(find.byKey(const Key('create-kind-retail')), findsNothing);
    });

    testWidgets('a proved WhatsApp number asked: none, the button; one, prefilled and said', (tester) async {
      phone(tester);
      Future<void> toPhone() async {
        await tester.tap(find.byKey(const Key('create-kind-retail')));
        await settle(tester);
        await tapNext(tester);
        await tester.enterText(find.byKey(const Key('create-name')), 'Chez Awa');
        await settle(tester);
        await tapNext(tester);
        await tester.tap(find.byKey(const Key('create-activity-autre')));
        await settle(tester);
        await tapNext(tester);
        await tester.tap(find.text('Kaya'));
        await settle(tester);
        await tapNext(tester);
      }

      await pumpFlow(tester, _Api(start_: const BusinessStart(phoneRequired: true)));
      await toPhone();
      expect(find.byKey(const Key('create-verify')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('create-phone')), '70112233');
      await settle(tester);
      expect(next(tester), isNull, reason: 'a number typed is not a number proved');

      await pumpFlow(tester, _Api(start_: const BusinessStart(
          phoneRequired: true, verifiedPhone: '+22670998877')));
      await toPhone();
      expect(find.byKey(const Key('create-verify')), findsNothing);
      expect(find.byKey(const Key('create-phone-proved')), findsOneWidget);
      expect(find.text('70998877'), findsOneWidget);
      expect(next(tester), isNotNull);
    });
  });

  group('Mara\'s creation page (107\'s form)', () {
    const form = ApplicationForm(
      welcome: 'Bienvenue chez Mara.',
      kinds: ['farm', 'retail'],
      questions: [
        FormQuestion(id: 'ville', label: 'Votre marché', required: true),
        FormQuestion(id: 'q2', label: 'Vous vendez', type: QuestionType.choice,
            options: ['Alimentation', 'Habits']),
        FormQuestion(id: 'q3', label: 'Depuis combien d\'années ?', type: QuestionType.number),
        FormQuestion(id: 'q4', label: 'Avez-vous un local ?', type: QuestionType.yesno, required: true),
      ],
    );

    testWidgets('its welcome, its kinds, each question a screen, the answers sent', (tester) async {
      phone(tester);
      final api = _Api(start_: const BusinessStart(form: form));
      await pumpFlow(tester, api);
      expect(find.text('Bienvenue chez Mara.'), findsOneWidget);
      expect(find.byKey(const Key('create-kind-association')), findsNothing);
      expect(find.text('1 / 10'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-kind-farm')));
      await settle(tester);
      await tapNext(tester);
      await tester.enterText(find.byKey(const Key('create-name')), 'Ferme Coumba');
      await settle(tester);
      await tapNext(tester);
      await tester.tap(find.byKey(const Key('create-activity-mixte')));
      await settle(tester);
      await tapNext(tester);
      await tester.tap(find.text('Banfora'));
      await settle(tester);
      await tapNext(tester);
      await tester.enterText(find.byKey(const Key('create-phone')), '70112233');
      await settle(tester);
      await tapNext(tester);

      // Mara's questions, one a screen.
      expect(find.text('Votre marché'), findsOneWidget);
      expect(next(tester), isNull, reason: 'required');
      await tester.enterText(find.byKey(const Key('create-q-ville')), 'Bobo');
      await settle(tester);
      await tapNext(tester);
      expect(find.text('Vous vendez (facultatif)'), findsOneWidget);
      await tester.tap(find.text('Habits'));
      await settle(tester);
      await tapNext(tester);
      await tester.enterText(find.byKey(const Key('create-q-q3')), 'trois');
      await settle(tester);
      expect(find.text('En chiffres, s\'il vous plaît.'), findsOneWidget);
      expect(next(tester), isNull);
      await tester.enterText(find.byKey(const Key('create-q-q3')), '3,5');
      await settle(tester);
      await tapNext(tester);
      expect(next(tester), isNull, reason: 'oui ou non, required');
      await tester.tap(find.text('Non'));
      await settle(tester);
      await tapNext(tester);
      expect(find.text('Tout est juste ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-submit')));
      await settle(tester);
      expect(api.sent!['profile'], 'farm');
      expect(api.sent!['answers'], {'ville': 'Bobo', 'q2': 'Habits', 'q3': 3.5, 'q4': false});
    });

    testWidgets('the preview sends nothing', (tester) async {
      phone(tester);
      final api = _Api();
      await pumpFlow(tester, api, preview: form);
      expect(find.text('Bienvenue chez Mara.'), findsOneWidget);
      expect(find.text('Aperçu de la création'), findsOneWidget);
      expect(api.checked, isEmpty);
    });
  });

  group('the entry points', () {
    testWidgets('no business yet: « Créer mon activité », no request to wait on', (tester) async {
      phone(tester);
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => JoinOrApplyScreen(
            identity: const LocalIdentity(userId: 'u1', phone: '+22670000000'),
            onboarding: _Onboarding(),
            admin: AdminRepository(null),
            onRetry: () async {},
            onSignOut: () {},
          ),
        ),
        GoRoute(path: '/creer-mon-activite', builder: (_, _) => const Text('le parcours')),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await settle(tester);
      expect(find.text('Demander une entreprise'), findsNothing);
      expect(find.text('Demande envoyée'), findsNothing);
      await tester.tap(find.byKey(const Key('join-create')));
      await settle(tester);
      expect(find.text('le parcours'), findsOneWidget);
    });

    testWidgets('the picker: « Nouvelle activité » under the list', (tester) async {
      phone(tester);
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: OrgPickerScreen(
          orgs: const [OrgSummary(id: 'o1', name: 'Chez Awa', profile: 'retail', roles: ['owner'])],
          onSelected: (_) {},
          onCreateMine: () => tapped = true,
        ),
      ));
      await settle(tester);
      await tester.tap(find.byKey(const Key('picker-create')));
      expect(tapped, isTrue);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: OrgPickerScreen(
          orgs: const [OrgSummary(id: 'o1', name: 'Chez Awa', profile: 'retail', roles: ['owner'])],
          onSelected: (_) {},
        ),
      ));
      await settle(tester);
      expect(find.byKey(const Key('picker-create')), findsNothing);
    });
  });

  group('« Activités créées »', () {
    testWidgets('what people created, with their answers, and the requests of before', (tester) async {
      phone(tester);
      final list = CreatedBusinesses.fromJson(const {
        'old_requests': 1,
        'items': [
          {
            'how': 'created', 'org_id': 'o1', 'name': 'Chez Awa', 'slug': 'chez-awa',
            'profile': 'retail', 'activity': 'alimentation', 'city': 'Ouagadougou', 'area': 'Dapoya',
            'person': 'Awa Ouédraogo', 'person_phone': '+22670112233', 'phone': '+226 70 11 22 33',
            'answers': [
              {'id': 'q3', 'label': 'Depuis combien d\'années ?', 'type': 'number', 'value': 3.5},
              {'id': 'q4', 'label': 'Avez-vous un local ?', 'type': 'yesno', 'value': false},
            ],
            'at': '2026-10-08T10:00:00Z',
          },
          {
            'how': 'rejected', 'name': 'Refusée', 'slug': 'refusee', 'profile': 'farm',
            'note': 'Informations manquantes', 'at': '2026-09-01T10:00:00Z',
          },
        ],
      });
      await tester.pumpWidget(MaterialApp(home: CreatedBusinessesScreen(center: _Center(list))));
      await settle(tester);
      expect(find.text('Activités créées'), findsOneWidget);
      expect(find.byKey(const Key('created-old-requests')), findsOneWidget);
      // One is said as one, no « (s) ».
      expect(find.textContaining('1 demande envoyée depuis une ancienne version de l\'application attend :'),
          findsOneWidget);
      // The business's phone is the person's: said once.
      expect(find.textContaining('+22670112233'), findsOneWidget);
      expect(find.textContaining('70 11 22 33'), findsNothing);
      expect(find.text('Dapoya · Ouagadougou'), findsOneWidget);
      expect(find.textContaining('Alimentation'), findsOneWidget);
      expect(find.textContaining('Créée par la personne'), findsOneWidget);
      expect(find.text('3,5'), findsOneWidget);
      expect(find.text('Non'), findsOneWidget);
      expect(find.textContaining('Demande refusée : Informations manquantes'), findsOneWidget);

      await tester.pumpWidget(MaterialApp(
          home: CreatedBusinessesScreen(
              key: const Key('three'),
              center: _Center(CreatedBusinesses.fromJson(const {'old_requests': 3, 'items': []})))));
      await settle(tester);
      expect(find.textContaining('3 demandes envoyées depuis une ancienne version de l\'application attendent :'),
          findsOneWidget);
    });
  });

  group('the setup starts from what the creation wrote', () {
    testWidgets('a shop\'s vitrine step: its sentence, phone and area, saved as they are', (tester) async {
      tester.view.physicalSize = const Size(480, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final a = _SetupActions();
      await tester.pumpWidget(MaterialApp(
        home: SetupScreen(
          org: const OrgSummary(id: 'o1', name: 'Chez Awa', profile: 'retail', roles: ['owner']),
          actions: a,
          onDone: () {},
          known: () async => const SetupKnown(
              phone: '+22670112233', address: 'Dapoya', about: 'Riz et huile au détail'),
        ),
      ));
      await settle(tester);
      await tester.tap(find.byKey(const Key('setup-next-0')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('setup-article')), 'Riz 25 kg');
      await tester.enterText(find.byKey(const Key('setup-price')), '17 500');
      await tester.tap(find.byKey(const Key('setup-add')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('setup-next-1')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('setup-next-2')));
      await settle(tester);
      expect(a.log.last, 'vitrine Riz et huile au détail +22670112233 Dapoya',
          reason: 'nothing typed again, nothing cleared');
    });

    testWidgets('an association\'s first step: its kind and its sentence', (tester) async {
      tester.view.physicalSize = const Size(480, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final a = _AssociationActions();
      await tester.pumpWidget(MaterialApp(
        home: AssociationSetupScreen(
          org: const OrgSummary(id: 'a1', name: 'Entraide', profile: 'association', roles: ['owner']),
          actions: a,
          onDone: () {},
          known: () async => const SetupKnown(kind: 'tontine', about: 'Une tontine de quartier'),
        ),
      ));
      await settle(tester);
      expect(find.text('Une tontine de quartier'), findsOneWidget);
      await tester.tap(find.byKey(const Key('asetup-next-0')));
      await settle(tester);
      expect(a.log.last, 'identify Entraide tontine Une tontine de quartier');
    });
  });
}
