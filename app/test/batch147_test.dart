import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;


import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, RenderRepaintBoundary;
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/console/models.dart';
import 'package:kaj_app/core/courier/courier_dossier.dart';
import 'package:kaj_app/features/courier/become_courier_screen.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/errors.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/help/help_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/l10n/en.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/onboarding/business_creation.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/terms/terms.dart';
import 'package:kaj_app/features/account/legal_screens.dart';
import 'package:kaj_app/features/account/support.dart';
import 'package:kaj_app/features/account/terms_gate.dart';
import 'package:kaj_app/features/admin/platform_people_screen.dart';
import 'package:kaj_app/features/admin/terms_admin_screen.dart';
import 'package:kaj_app/features/courier/courier_words.dart';
import 'package:kaj_app/features/setup/create_my_business_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:kaj_app/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Batch 147 (142): the new Conditions d'utilisation, accepted before
/// anything else — by everyone at the first sign-in after 142 (existing
/// people once, a new version again), by an owner the seller's commitments,
/// by an approved courier the new charter; the seller's commitments before
/// a shop, a farm or an association is created (and the platform's own
/// « Nouvelle activité »); the courier's charter's two new lines; the app
/// before 142 asking nothing; French and English; 320 px at 1.3.

/// my_terms_state() as the server says it.
TermsState serverState({
  List<String> gate = const ['terms', 'privacy'],
  Map<String, int?> accepted = const {},
  Map<String, int> current = const {'terms': 2, 'privacy': 2, 'seller': 1, 'courier': 2},
  bool changed = false,
  String? changes,
  String? changesEn,
}) =>
    TermsState.fromJson({
      'version': 142,
      'documents': {
        for (final d in TermsDoc.all)
          d: {'current': current[d], 'accepted': accepted[d], 'pending': (accepted[d] ?? 0) < current[d]!},
      },
      'gate': gate,
      'changed': changed,
      'date': '2026-10-14',
      'changes': changes,
      'changes_en': changesEn,
    });

class FakeTerms implements TermsApi {
  FakeTerms(this.now);

  TermsState now;
  Object? fail;
  final accepted = <String>[];
  final platforms = <String?>[];
  int asked = 0;
  TermsBoard? boardNow = const TermsBoard();
  List<TermsAcceptance>? rows = const [];
  final bumps = <String>[];

  @override
  Future<TermsState> state() async {
    asked++;
    final f = fail;
    if (f != null) throw f;
    return now;
  }

  @override
  Future<TermsState> accept(String doc, int version, {String? platform, String? appVersion}) async {
    accepted.add('$doc:$version');
    platforms.add(platform);
    final docs = {
      for (final d in TermsDoc.all)
        d: TermsDocState(
            current: now.version(d),
            accepted: d == doc ? version : now.documents[d]?.accepted),
    };
    now = TermsState(
      documents: docs,
      gate: [for (final g in now.gate) if (g != doc) g],
      changed: now.changed,
      date: now.date,
      changes: now.changes,
      changesEn: now.changesEn,
    );
    return now;
  }

  @override
  Future<TermsBoard?> board() async => boardNow;

  @override
  Future<List<TermsAcceptance>?> of(String userId) async => rows;

  @override
  Future<TermsBoard> bump(List<String> docs, {required String changes, String? changesEn, int graceDays = 14}) async {
    bumps.add('${docs.join('+')}|$changes|$changesEn|$graceDays');
    return boardNow!;
  }
}

/// The gate alone, over a page, in [locale].
Widget gateHost(TermsController c, {Locale locale = const Locale('fr'), List<String>? signedOut}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      builder: (context, child) => TermsScope(
        controller: c,
        child: TermsGate(
          controller: c,
          onSignOut: () async {
            signedOut?.add('out');
            c.clear();
          },
          child: child!,
        ),
      ),
      home: const Scaffold(body: Center(child: Text('La rue'))),
    );

/// A screen tall enough for the whole gate (its list builds what it shows).
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<TermsController> tracked(WidgetTester tester, FakeTerms api) async {
  final c = TermsController(api: api, platform: 'android', appVersion: '1.0.0');
  await c.track('user-1');
  return c;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('the gate in the whole app (KajApp)', () {
    late LocalDb db;
    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    Future<void> flush(WidgetTester tester, {int rounds = 8}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pump();
    }

    /// A shopper's phone, signed in before (no business, no code).
    Future<void> pumpApp(WidgetTester tester, FakeTerms terms) async {
      await tester.runAsync(() async {
        await db.saveIdentity(LocalIdentity(
          userId: 'user-147',
          displayName: 'Client Marakaj',
          phone: '+22670147000',
          orgsRefreshedAt: DateTime.now(),
        ));
      });
      tester.platformDispatcher.localesTestValue = [const Locale('fr')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(KajApp(
        db: db,
        auth: AuthRepository(null),
        admin: AdminRepository(null),
        reports: ReportsRepository(null),
        accounting: AccountingRepository(null),
        console: ConsoleRepository(null),
        farm: FarmRepository(null),
        invoicing: InvoicingRepository(null),
        retail: RetailRepository(null),
        staff: StaffRepository(null),
        capture: CaptureRepository(null, db: db),
        onboarding: OnboardingRepository(null),
        terms: terms,
      ));
      await flush(tester);
    }

    testWidgets('first sign-in: the gate before anything, not skipped, then the street', (tester) async {
      tall(tester);
      final terms = FakeTerms(serverState());
      await pumpApp(tester, terms);

      expect(find.byKey(const Key('terms-gate')), findsOneWidget);
      expect(find.text('Avant de continuer'), findsOneWidget);
      expect(find.textContaining('KAJ Consulting LLC'), findsOneWidget);
      // The street is under it, out of reach.
      expect(find.byKey(const Key('mara-header')).hitTestable(), findsNothing);
      final go = find.byKey(const Key('terms-continue'));
      expect(tester.widget<FilledButton>(go).onPressed, isNull, reason: 'nothing ticked yet');

      // Back does not take it away.
      await tester.binding.handlePopRoute();
      await flush(tester);
      expect(find.byKey(const Key('terms-gate')), findsOneWidget);

      await tester.tap(find.byKey(const Key('terms-accept')));
      await tester.pump();
      await tester.tap(go);
      await flush(tester);
      expect(terms.accepted, ['terms:2', 'privacy:2']);
      expect(terms.platforms, everyElement('android'));
      expect(find.byKey(const Key('terms-gate')), findsNothing);
      expect(find.byKey(const Key('mara-header')), findsOneWidget);
    });

    testWidgets('« Se déconnecter » is the only other way out', (tester) async {
      tall(tester);
      final terms = FakeTerms(serverState());
      await pumpApp(tester, terms);
      expect(find.byKey(const Key('terms-gate')), findsOneWidget);
      await tester.tap(find.byKey(const Key('terms-signout')));
      await flush(tester);
      expect(find.byKey(const Key('terms-gate')), findsNothing);
      expect(find.text('Se connecter'), findsOneWidget);
      expect(terms.accepted, isEmpty);
    });

    testWidgets('someone who already accepted is not asked; the app before 142 asks nothing', (tester) async {
      final done = FakeTerms(serverState(gate: const [], accepted: const {'terms': 2, 'privacy': 2}));
      await pumpApp(tester, done);
      expect(done.asked, greaterThan(0));
      expect(find.byKey(const Key('terms-gate')), findsNothing);
      expect(find.text('Vendre sur Marakaj').hitTestable(), findsOneWidget);
    });

    testWidgets('before 142 (no my_terms_state): nothing shown, nothing blocked', (tester) async {
      final before = FakeTerms(TermsState.none);
      await pumpApp(tester, before);
      expect(find.byKey(const Key('terms-gate')), findsNothing);
      expect(find.text('Vendre sur Marakaj').hitTestable(), findsOneWidget);
    });
  });

  group('the gate page', () {
    testWidgets('existing people see it once: accepted, the same person is not asked again', (tester) async {
      tall(tester);
      final api = FakeTerms(serverState());
      final c = await tracked(tester, api);
      await tester.pumpWidget(gateHost(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('terms-accept')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('terms-continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('terms-gate')), findsNothing);
      // Opened again later: the server says nothing is left.
      await c.track('user-1', force: true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('terms-gate')), findsNothing);
      expect(find.text('La rue').hitTestable(), findsOneWidget);
    });

    testWidgets('a new version asks again, with what changed', (tester) async {
      tall(tester);
      final api = FakeTerms(serverState(
        current: const {'terms': 3, 'privacy': 3, 'seller': 1, 'courier': 2},
        accepted: const {'terms': 2, 'privacy': 2},
        changed: true,
        changes: 'Les remboursements des mises en avant.',
        changesEn: 'Refunds of promotions.',
      ));
      final c = await tracked(tester, api);
      await tester.pumpWidget(gateHost(c));
      await tester.pumpAndSettle();
      expect(find.text('Nos conditions ont changé'), findsOneWidget);
      expect(find.text('Ce qui change : Les remboursements des mises en avant.'), findsOneWidget);
      expect(find.text('Version 3 du 14 octobre 2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('terms-accept')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('terms-continue')));
      await tester.pumpAndSettle();
      expect(api.accepted, ['terms:3', 'privacy:3']);
    });

    testWidgets('an owner also accepts the seller\'s commitments; both boxes needed', (tester) async {
      tall(tester);
      final api = FakeTerms(serverState(gate: const ['terms', 'privacy', 'seller']));
      final c = await tracked(tester, api);
      await tester.pumpWidget(gateHost(c));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('terms-seller')), findsOneWidget);
      await tester.tap(find.byKey(const Key('terms-accept')));
      await tester.pump();
      final go = find.byKey(const Key('terms-continue'));
      expect(tester.widget<FilledButton>(go).onPressed, isNull, reason: 'the seller box not ticked');
      await tester.scrollUntilVisible(find.byKey(const Key('terms-seller-accept')), 200);
      await tester.tap(find.byKey(const Key('terms-seller-accept')));
      await tester.pump();
      await tester.tap(go);
      await tester.pumpAndSettle();
      expect(api.accepted, ['terms:2', 'privacy:2', 'seller:1']);
    });

    testWidgets('an approved courier accepts the new charter at the gate', (tester) async {
      tall(tester);
      final api = FakeTerms(serverState(gate: const ['courier'], accepted: const {'terms': 2, 'privacy': 2, 'courier': 1}));
      final c = await tracked(tester, api);
      await tester.pumpWidget(gateHost(c));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('terms-accept')), findsNothing, reason: 'the terms are accepted');
      expect(find.text('Je travaille à mon compte : je ne suis employé ni par Marakaj ni par la boutique.'),
          findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('terms-courier-accept')), 200);
      await tester.tap(find.byKey(const Key('terms-courier-accept')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('terms-continue')));
      await tester.pumpAndSettle();
      expect(api.accepted, ['courier:2']);
    });

    testWidgets('the whole terms read from the gate, and back to it', (tester) async {
      tall(tester);
      final c = await tracked(tester, FakeTerms(serverState()));
      await tester.pumpWidget(gateHost(c));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('terms-read')), 200);
      await tester.tap(find.byKey(const Key('terms-read')));
      await tester.pumpAndSettle();
      expect(find.text('Qui exploite Marakaj'), findsOneWidget);
      expect(find.text('Version 2 — en vigueur le 14 octobre 2026.'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('terms-gate')), findsOneWidget);
    });

    testWidgets('the server refuses the acceptance (a version changed meanwhile): said, the gate stays', (tester) async {
      tall(tester);
      final api = _Refusing(serverState());
      final c = TermsController(api: api);
      await c.track('user-1');
      await tester.pumpWidget(gateHost(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('terms-accept')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('terms-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Ces conditions ont changé entre-temps : relisez-les, puis acceptez-les à nouveau.'),
          findsOneWidget);
      expect(find.byKey(const Key('terms-gate')), findsOneWidget);
    });

    testWidgets('in English', (tester) async {
      tall(tester);
      final c = await tracked(tester, FakeTerms(serverState(gate: const ['terms', 'privacy', 'seller'])));
      await tester.pumpWidget(gateHost(c, locale: const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.text('Terms of use'), findsOneWidget);
      expect(find.text('Before you continue'), findsOneWidget);
      expect(find.textContaining('a platform run by KAJ Consulting LLC'), findsOneWidget);
      expect(find.text('I have read and accept the Terms of Use and the Privacy Policy'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('I accept the seller\'s commitments'), 200);
      expect(find.text('I accept the seller\'s commitments'), findsOneWidget);
      expect(find.text('Se déconnecter'), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);
    });

    for (final (width, scale) in [(390.0, 1.0), (320.0, 1.3)]) {
      for (final lang in ['fr', 'en']) {
        testWidgets('$width px × $scale, $lang: the gate, the full terms, no overflow', (tester) async {
          tester.view.physicalSize = Size(width, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final c = await tracked(tester, FakeTerms(serverState(gate: const ['terms', 'privacy', 'seller', 'courier'])));
          await tester.pumpWidget(gateHost(c, locale: Locale(lang)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(find.byKey(const Key('terms-courier-accept')), 300);
          expect(tester.takeException(), isNull);
          // The whole terms, as the gate's link opens them.
          await tester.pumpWidget(MaterialApp(
            locale: Locale(lang),
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
            home: const TermsScreen(),
          ));
          await tester.pumpAndSettle();
          expect(find.byType(TermsScreen), findsOneWidget);
          await tester.drag(find.byType(ListView).last, const Offset(0, -8000));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('the controller', () {
    test('fails open: offline, a refusal it cannot read, before 142', () async {
      for (final f in <Object>[const SocketException('no signal'), StateError('boom'),
        const PostgrestException(message: 'Could not find the function my_terms_state', code: 'PGRST202')]) {
        final api = FakeTerms(serverState())..fail = f;
        final c = TermsController(api: api);
        await c.track('u');
        expect(c.gate, isEmpty, reason: '$f');
        expect(c.needs(TermsDoc.seller), isFalse);
      }
      final before = TermsController(api: FakeTerms(TermsState.none));
      await before.track('u');
      expect(before.gate, isEmpty);
      expect(before.needs(TermsDoc.terms), isFalse);
    });

    test('follows the person: hidden at the code screen, forgotten at sign-out, a new person asked', () async {
      final api = FakeTerms(serverState());
      final c = TermsController(api: api);
      await c.track('a');
      expect(c.gate, ['terms', 'privacy']);
      await c.track(null);
      expect(c.gate, isEmpty, reason: 'at the code screen');
      await c.track('a');
      expect(c.gate, ['terms', 'privacy']);
      expect(api.asked, 1, reason: 'the same person, asked recently');
      c.clear();
      expect(c.state, isNull);
      await c.track('b');
      expect(api.asked, 2);
    });

    test('the server\'s refusals are known and said in English', () {
      const order = 'Acceptez d\'abord les Conditions d\'utilisation de Marakaj pour commander (mettez l\'application à jour si elle ne vous les montre pas).';
      const seller = 'Acceptez d\'abord les engagements du vendeur pour créer une activité (mettez l\'application à jour si elle ne vous les montre pas).';
      const courier = 'Acceptez d\'abord la charte du livreur pour envoyer votre demande (mettez l\'application à jour si elle ne vous la montre pas).';
      for (final m in [order, seller, courier]) {
        expect(TermsController.refusedFor(PostgrestException(message: m)), isTrue);
      }
      expect(TermsController.refusedFor(const PostgrestException(message: 'Autre chose')), isFalse);
      trCurrent = 'en';
      addTearDown(() => trCurrent = 'fr');
      expect(describeError(const PostgrestException(message: order)),
          'First accept Marakaj\'s Terms of Use to order (update the app if it does not show them to you).');
      expect(describeError(const PostgrestException(message: seller)),
          'First accept the seller\'s commitments to create a business (update the app if it does not show them to you).');
      expect(describeError(const PostgrestException(message: courier)),
          'First accept the courier\'s charter to send your application (update the app if it does not show it to you).');
    });
  });

  // The supervisor's review of 147: the gate never traps, never loops.
  group('the review: no trap, no loop', () {
    test('a refresh asked before « Continuer » never brings the gate back after it', () async {
      final api = _Slow(serverState());
      final c = TermsController(api: api);
      await c.track('u');
      expect(c.gate, ['terms', 'privacy']);
      // A refresh goes out (a resume), answered only after the acceptance.
      api.hold = Completer<void>();
      final late = c.refresh();
      await c.accept(['terms', 'privacy']);
      expect(c.gate, isEmpty);
      api.hold!.complete();
      await late;
      await Future<void>.delayed(Duration.zero);
      expect(c.gate, isEmpty, reason: 'the stale answer (gate shown) must not win');
    });

    test('a server that cannot take the acceptance (5xx, offline, missing) lets the person through', () async {
      for (final f in <Object>[
        const PostgrestException(message: 'upstream timeout', code: '504'),
        const SocketException('no signal'),
        const PostgrestException(message: 'Could not find the function accept_terms', code: 'PGRST202'),
      ]) {
        final api = _FailingAccept(serverState(), f);
        final c = TermsController(api: api);
        await c.track('u');
        await expectLater(c.accept(['terms', 'privacy']), throwsA(anything));
        expect(c.gate, isEmpty, reason: '$f');
        // The next real answer asks again.
        await c.track('u', force: true);
        expect(c.gate, ['terms', 'privacy'], reason: '$f');
      }
      // A refusal (a version changed meanwhile) keeps the gate.
      final c = TermsController(api: _FailingAccept(serverState(),
          const PostgrestException(message: 'Ces conditions ont changé entre-temps : relisez-les, puis acceptez-les à nouveau.', code: 'P0001')));
      await c.track('u');
      await expectLater(c.accept(['terms']), throwsA(isA<PostgrestException>()));
      expect(c.gate, ['terms', 'privacy']);
    });

    test('the person changes while a question is out: the new one is asked', () async {
      final api = _Slow(serverState());
      final c = TermsController(api: api);
      api.hold = Completer<void>();
      final first = c.track('a');
      c.clear();
      final second = c.track('b');
      api.hold!.complete();
      api.hold = null;
      await first;
      await second;
      await Future<void>.delayed(Duration.zero);
      expect(c.userId, 'b');
      expect(c.state, isNotNull, reason: 'b was asked once a\'s answer was dropped');
      expect(api.asked, 2);
    });

    testWidgets('held briefly while the first answer is out, then the app (fails open)', (tester) async {
      final api = _Slow(serverState(gate: const []));
      api.hold = Completer<void>();
      final c = TermsController(api: api, holdFor: const Duration(seconds: 3));
      unawaited(c.track('u'));
      await tester.pumpWidget(gateHost(c));
      await tester.pump();
      expect(find.byKey(const Key('terms-hold')), findsOneWidget);
      expect(find.text('La rue').hitTestable(), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('terms-hold')), findsNothing, reason: 'the hold times out');
      expect(find.text('La rue').hitTestable(), findsOneWidget);
      api.hold!.complete();
      await tester.pump();
    });

    testWidgets('held, then the answer: the gate at once, no flash of the app', (tester) async {
      final api = _Slow(serverState());
      api.hold = Completer<void>();
      final c = TermsController(api: api, holdFor: const Duration(seconds: 3));
      unawaited(c.track('u'));
      await tester.pumpWidget(gateHost(c));
      await tester.pump();
      expect(find.byKey(const Key('terms-hold')), findsOneWidget);
      api.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('terms-hold')), findsNothing);
      expect(find.byKey(const Key('terms-gate')), findsOneWidget);
    });

    testWidgets('Android\'s back closes a text read from the gate, never the page under it', (tester) async {
      tall(tester);
      final c = await tracked(tester, FakeTerms(serverState()));
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        locale: const Locale('fr'),
        builder: (context, child) => TermsGate(
          controller: c,
          navigatorKey: key,
          onSignOut: () async => c.clear(),
          child: child!,
        ),
        home: const Scaffold(body: Text('La rue')),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('terms-read')), 200);
      await tester.tap(find.byKey(const Key('terms-read')));
      await tester.pumpAndSettle();
      expect(find.text('Qui exploite Marakaj'), findsOneWidget);
      expect(await TermsGate.handleBack(c, key), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Qui exploite Marakaj'), findsNothing);
      expect(find.byKey(const Key('terms-gate')), findsOneWidget);
      // On the gate itself: taken (the phone leaves), not the router's.
      expect(await TermsGate.handleBack(c, key), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('terms-gate')), findsOneWidget);
      // No gate: the back is the app's again.
      await c.accept(['terms', 'privacy']);
      expect(await TermsGate.handleBack(c, key), isNull);
    });

    testWidgets('a new version of the seller\'s commitments alone says what changed', (tester) async {
      tall(tester);
      final c = await tracked(tester, FakeTerms(serverState(
        gate: const ['seller'],
        current: const {'terms': 2, 'privacy': 2, 'seller': 2, 'courier': 2},
        accepted: const {'terms': 2, 'privacy': 2, 'seller': 1},
        changed: true,
        changes: 'Les pièces demandées aux vendeurs.',
      )));
      await tester.pumpWidget(gateHost(c));
      await tester.pumpAndSettle();
      expect(find.text('Nos conditions ont changé'), findsOneWidget);
      expect(find.text('Ce qui change : Les pièces demandées aux vendeurs.'), findsOneWidget);
    });
  });

  group('the seller\'s commitments before a business is created', () {
    for (final (profile, activity) in [('retail', 'alimentation'), ('farm', 'volaille'), ('association', 'tontine')]) {
      testWidgets('$profile: asked on the summary, accepted before the creation', (tester) async {
      tall(tester);
        final api = FakeTerms(serverState(gate: const [], accepted: const {'terms': 2, 'privacy': 2}));
        final c = await tracked(tester, api);
        final creation = _Creation(api);
        await tester.pumpWidget(MaterialApp(
          home: CreateMyBusinessScreen(
            api: creation,
            terms: c,
            drafts: _Drafts(BusinessDraft(
              step: 5, profile: profile, name: 'Maison Élégance', slug: 'maison-elegance',
              slugTouched: true, activity: activity, city: 'Ouagadougou', phone: '70147000',
            )),
            onCreated: (_) async => true,
          ),
        ));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.byKey(const Key('seller-commitments')), 200);
        expect(find.byKey(const Key('seller-commitments')), findsOneWidget);
        final submit = find.byKey(const Key('create-submit'));
        expect(tester.widget<FilledButton>(submit).onPressed, isNull);
        await tester.scrollUntilVisible(find.byKey(const Key('seller-accept')), 200);
        await tester.tap(find.byKey(const Key('seller-accept')));
        await tester.pump();
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(api.accepted, ['seller:1']);
        expect(creation.log, ['seller:1', 'create $profile']);
      });
    }

    for (final lang in ['fr', 'en']) {
      testWidgets('320 px × 1.3, $lang: the summary, its seller card and « Create my business » whole', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final api = FakeTerms(serverState(gate: const [], accepted: const {'terms': 2, 'privacy': 2}));
        final c = await tracked(tester, api);
        await tester.pumpWidget(MaterialApp(
          locale: Locale(lang),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          home: CreateMyBusinessScreen(
            api: _Creation(api),
            terms: c,
            drafts: _Drafts(BusinessDraft(
              step: 5, profile: 'retail', name: 'Maison Élégance', slug: 'maison-elegance',
              slugTouched: true, activity: 'alimentation', city: 'Ouagadougou', phone: '70147000',
            )),
            onCreated: (_) async => true,
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.byKey(const Key('seller-accept')), 200);
        expect(tester.takeException(), isNull);
        // The label drawn whole inside its button (one line, scaled down
        // when it must be), beside « Retour ».
        final submit = find.byKey(const Key('create-submit'));
        final label = find.descendant(of: submit, matching: find.byType(Text));
        final button = tester.getRect(submit);
        final text = tester.getRect(label);
        expect(text.left, greaterThanOrEqualTo(button.left));
        expect(text.right, lessThanOrEqualTo(button.right));
        expect(text.height, lessThan(button.height));
        expect(tester.renderObject<RenderParagraph>(label).didExceedMaxLines, isFalse);
      });
    }

    testWidgets('already accepted, or before 142: no box, the creation as before', (tester) async {
      tall(tester);
      for (final state in [
        serverState(gate: const [], accepted: const {'terms': 2, 'privacy': 2, 'seller': 1}),
        TermsState.none,
      ]) {
        final api = FakeTerms(state);
        final c = await tracked(tester, api);
        final creation = _Creation(api);
        await tester.pumpWidget(MaterialApp(
          home: CreateMyBusinessScreen(
            key: UniqueKey(),
            api: creation,
            terms: c,
            drafts: _Drafts(BusinessDraft(
              step: 5, profile: 'retail', name: 'Maison Élégance', slug: 'maison-elegance',
              slugTouched: true, activity: 'alimentation', city: 'Ouagadougou', phone: '70147000',
            )),
            onCreated: (_) async => true,
          ),
        ));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('create-after')), findsOneWidget);
        expect(find.byKey(const Key('seller-commitments')), findsNothing);
        await tester.tap(find.byKey(const Key('create-submit')));
        await tester.pumpAndSettle();
        expect(creation.log, ['create retail']);
        expect(api.accepted, isEmpty);
      }
    });
  });

  group('the courier\'s charter, version 2', () {
    testWidgets('the application\'s charter step: the nine lines, the box, version 2 saved', (tester) async {
      tall(tester);
      final dossier = CharterDossier();
      await tester.pumpWidget(MaterialApp(
        home: BecomeCourierScreen(dossier: dossier, files: CourierFiles(null, url: 'https://up.example')),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('courier-start')));
      await tester.pumpAndSettle();
      expect(find.text('La charte du livreur'), findsOneWidget);
      expect(find.text('Je travaille à mon compte : je ne suis employé ni par Marakaj ni par la boutique.'),
          findsOneWidget);
      final next = find.byKey(const Key('courier-next'));
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      await tester.tap(find.byKey(const Key('courier-charter')));
      await tester.pump();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(dossier.saves.single.$1, 'charter');
      expect(dossier.saves.single.$2, {'charter_version': 2});
    });

    testWidgets('its two new lines, among 112\'s seven', (tester) async {
      late List<String> lines;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        lines = courierCharter(context);
        return const SizedBox();
      })));
      expect(lines, hasLength(9));
      expect(lines.first, 'Je travaille à mon compte : je ne suis employé ni par Marakaj ni par la boutique.');
      expect(lines[7], startsWith('Je ne marque une commande livrée qu\'avec le code'));
      expect(lines.last, 'Un manquement à cette charte peut suspendre mon accès livreur.');
      for (final l in lines) {
        expect(translate('en', l), isNot(l), reason: 'no English: $l');
      }
    });
  });

  group('the terms themselves', () {
    String dart() => File('lib/features/account/legal_screens.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r"'\s*\n\s*'"), '')
        .replaceAll(r"\'", "'");

    test('every section the owner asked for, a version and a date, the lawyer\'s placeholder', () {
      final terms = dart().substring(dart().indexOf('class TermsScreen'), dart().indexOf('class FaqScreen'));
      for (final heading in [
        '# Qui exploite Marakaj', '# Le rôle de Marakaj', '# Votre compte', '# Les entreprises', '# Les clients',
        '# Les paiements', '# Marakaj Pro', '# Les livreurs', '# Cauris, ligues, prix et parrainage',
        '# Formateurs et aide', '# Les droits de Marakaj', '# Signaler un problème', '# Responsabilité',
        '# Vos données', '# Modifications', '# Droit applicable et litiges', '# Langue et contact',
      ]) {
        expect(terms, contains("'$heading'"), reason: heading);
      }
      for (final words in [
        'exploité par KAJ Consulting LLC',
        'Chaque entreprise est le vendeur',
        'Marakaj n\'est pas partie à la vente',
        '16 ans pour commander ; 18 ans pour ouvrir une entreprise',
        'armes, munitions et explosifs',
        'se faire passer pour une marque',
        'payer autrement que par les moyens convenus',
        'Marakaj peut vérifier l\'identité',
        'Les fausses commandes',
        'Ils n\'ont aucune valeur en argent',
        'en lecture seule et pour une durée limitée',
        'Marakaj coopère avec les autorités',
        'Marakaj ne garantit aucune vente',
        '[à valider par un avocat]',
        'Version 2 — en vigueur le 14 octobre 2026.',
        '{email}',
      ]) {
        expect(terms, contains(words), reason: words);
      }
      expect(termsTextVersion, 2);
    });

    test('the privacy policy says who receives a customer\'s name, number and address (the fraud audit)', () {
      final text = dart();
      final privacy = text.substring(text.indexOf('class PrivacyScreen'), text.indexOf('class TermsScreen'));
      expect(privacy, isNot(contains('ne transmettons ces informations à personne')));
      expect(privacy, isNot(contains('Nous ne transmettons ces informations à personne.')));
      expect(privacy, contains("'# Qui voit vos informations'"));
      for (final words in [
        'l\'entreprise reçoit ce qu\'il lui faut pour vous servir : votre nom, votre numéro de téléphone',
        'les livreurs proches voient l\'adresse et le point de livraison, sans votre nom ni votre numéro',
        'le livreur qui prend la course reçoit ensuite votre nom et votre numéro',
        '# Vérifications contre la fraude',
        '# Ce que Marakaj garde',
      ]) {
        expect(privacy, contains(words), reason: words);
      }
    });

    test('every terms and privacy paragraph has its English', () {
      final text = dart();
      final blocks = RegExp(r"^\s*'(.+)',$", multiLine: true)
          .allMatches(text.substring(text.indexOf('class PrivacyScreen'), text.indexOf('class FaqScreen')))
          .map((m) => m.group(1)!)
          .where((b) => b.length > 3);
      for (final b in blocks) {
        expect(enStrings.containsKey(b), isTrue, reason: 'no English: $b');
      }
    });

    testWidgets('the support e-mail the platform set is the one the terms name, in both languages', (tester) async {
      Support.reset(const SupportContacts(email: 'aide@marakaj.com', hours: '8 h – 20 h'));
      addTearDown(Support.reset);
      for (final (locale, words) in [
        (const Locale('fr'), 'écrivez à aide@marakaj.com'),
        (const Locale('en'), 'write to aide@marakaj.com'),
      ]) {
        await tester.pumpWidget(MaterialApp(
          key: UniqueKey(),
          locale: locale,
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          home: const TermsScreen(),
        ));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.textContaining(words), 400);
        expect(find.textContaining(words), findsOneWidget);
        expect(find.textContaining('{email}'), findsNothing);
      }
    });
  });

  group('the command center', () {
    testWidgets('a person\'s fiche lists their acceptances, version and date', (tester) async {
      final api = FakeTerms(TermsState.none)
        ..rows = [
          TermsAcceptance(document: 'terms', version: 2, acceptedAt: DateTime(2026, 10, 14, 9, 5),
              platform: 'android', appVersion: '1.0.0+abc1234', current: true),
          TermsAcceptance(document: 'courier', version: 1, acceptedAt: DateTime(2026, 3, 2, 18, 30)),
        ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PersonSheet(
            person: const PlatformPerson(userId: 'u1', isPlatformAdmin: false, businessCount: 0,
                fullName: 'Client Marakaj'),
            console: ConsoleRepository(null),
            admin: AdminRepository(null),
            help: HelpRepository(null),
            terms: api,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Conditions acceptées'), findsOneWidget);
      expect(find.text('Conditions d\'utilisation · version 2'), findsOneWidget);
      expect(find.text('14 oct. 2026, 09:05 · Android · 1.0.0+abc1234'), findsOneWidget);
      expect(find.text('Charte du livreur · version 1'), findsOneWidget);
      expect(find.textContaining('ancienne version'), findsOneWidget);
    });

    testWidgets('« Nouvelle version »: the documents, what changed, a confirmation, then everyone asked', (tester) async {
      final api = FakeTerms(TermsState.none)
        ..boardNow = TermsBoard.fromJson({
          'documents': {
            'terms': {'version': 2, 'since': '2026-10-14T08:00:00Z', 'accepted': 12},
            'privacy': {'version': 2, 'accepted': 12},
            'seller': {'version': 1, 'accepted': 3},
            'courier': {'version': 2, 'accepted': 1},
          },
          'people': 40,
        });
      await tester.pumpWidget(MaterialApp(home: TermsAdminScreen(api: api)));
      await tester.pumpAndSettle();
      expect(find.textContaining('12 personnes l\'ont acceptée, sur 40 comptes'), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('terms-bump')));
      await tester.pumpAndSettle();
      final next = find.byKey(const Key('terms-bump-next'));
      expect(tester.widget<FilledButton>(next).onPressed, isNull, reason: 'no sentence yet');
      await tester.enterText(find.byKey(const Key('terms-bump-changes')), 'Les remboursements.');
      await tester.pump();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('terms-bump-confirm')), findsOneWidget);
      expect(find.textContaining('Tout le monde devra accepter à nouveau'), findsOneWidget);
      expect(api.bumps, isEmpty, reason: 'not before the confirmation');
      await tester.tap(find.byKey(const Key('terms-bump-go')));
      await tester.pumpAndSettle();
      expect(api.bumps, ['terms+privacy|Les remboursements.|null|14']);
    });

    testWidgets('before 142: the page says so', (tester) async {
      final api = FakeTerms(TermsState.none)..boardNow = null;
      await tester.pumpWidget(MaterialApp(home: TermsAdminScreen(api: api)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('terms-admin-before')), findsOneWidget);
    });
  });

  screenshots();
}

/// The real Roboto and icons, for screenshots a person can read.
Future<void> realFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6 && !Directory('${dir.path}/material_fonts').existsSync(); i++) {
    dir = dir.parent;
  }
  final fonts = Directory('${dir.path}/material_fonts');
  if (!fonts.existsSync()) return;
  final loader = FontLoader('Roboto');
  for (final f in const ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    final file = File('${fonts.path}/$f');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
  final icons = File('${fonts.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
  }
}

/// `B147_SHOTS=<dir>`: the gate, the seller's and the courier's acceptances
/// and the whole terms, FR and EN, 390 × 844 and 320 × 640 at 1.3.
void screenshots() {
  final shots = Platform.environment['B147_SHOTS'];
  group('screenshots', () {
    setUpAll(realFonts);

    Future<void> capture(WidgetTester tester, String name) async {
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
        final img = await ro.toImage(pixelRatio: 2);
        final data = await img.toByteData(format: ImageByteFormat.png);
        File('$shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    Widget framed(Widget app) => RepaintBoundary(key: const Key('shot'), child: KeyedSubtree(key: UniqueKey(), child: app));

    MaterialApp app(Widget home, Locale locale) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: kajTheme(kajPalette),
          locale: locale,
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          home: home,
        );

    testWidgets('all of them', (tester) async {
      Directory(shots!).createSync(recursive: true);
      for (final (size, scale, tag) in const [(Size(390, 844), 1.0, '390'), (Size(320, 640), 1.3, '320x1.3')]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final lang in const ['fr', 'en']) {
          final locale = Locale(lang);
          // The gate, first sign-in.
          var c = await tracked(tester, FakeTerms(serverState()));
          await tester.pumpWidget(framed(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: kajTheme(kajPalette),
            locale: locale,
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
            builder: (context, child) => TermsGate(controller: c, onSignOut: () async {}, child: child!),
            home: const Scaffold(body: SizedBox()),
          )));
          await tester.pumpAndSettle();
          await capture(tester, 'gate_${tag}_$lang');
          await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
          await tester.pumpAndSettle();
          await capture(tester, 'gate_end_${tag}_$lang');
          // A new version, an owner and a courier asked too.
          c = await tracked(tester, FakeTerms(serverState(
              gate: const ['terms', 'privacy', 'seller'], accepted: const {'terms': 1, 'privacy': 1}, changed: true,
              changes: 'Nouvelles conditions : Marakaj est une plateforme, chaque entreprise vend elle-même.',
              changesEn: 'New terms: Marakaj is a platform, each business sells for itself.')));
          await tester.pumpWidget(framed(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: kajTheme(kajPalette),
            locale: locale,
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
            builder: (context, child) => TermsGate(controller: c, onSignOut: () async {}, child: child!),
            home: const Scaffold(body: SizedBox()),
          )));
          await tester.pumpAndSettle();
          await capture(tester, 'gate_changed_${tag}_$lang');
          await tester.drag(find.byType(ListView).first, const Offset(0, -900));
          await tester.pumpAndSettle();
          await capture(tester, 'gate_seller_${tag}_$lang');
          // The seller's commitments at the creation (an association here).
          final api = FakeTerms(serverState(gate: const [], accepted: const {'terms': 2, 'privacy': 2}));
          c = await tracked(tester, api);
          await tester.pumpWidget(framed(app(
              CreateMyBusinessScreen(
                api: _Creation(api),
                terms: c,
                drafts: _Drafts(BusinessDraft(
                  step: 5, profile: 'association', name: 'Fondation Espoir', slug: 'fondation-espoir',
                  slugTouched: true, activity: 'tontine', city: 'Ouagadougou', phone: '70147000')),
              ),
              locale)));
          await tester.pumpAndSettle();
          await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
          await tester.pumpAndSettle();
          await capture(tester, 'seller_${tag}_$lang');
          // The courier's charter, in the application.
          await tester.pumpWidget(framed(app(
              BecomeCourierScreen(dossier: CharterDossier(), files: CourierFiles(null, url: 'https://up.example')),
              locale)));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('courier-start')));
          await tester.pumpAndSettle();
          await capture(tester, 'courier_${tag}_$lang');
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
          await tester.pumpAndSettle();
          await capture(tester, 'courier_end_${tag}_$lang');
          // The whole terms.
          await tester.pumpWidget(framed(app(const TermsScreen(), locale)));
          await tester.pumpAndSettle();
          await capture(tester, 'terms_${tag}_$lang');
          await tester.drag(find.byType(ListView).first, const Offset(0, -6000));
          await tester.pumpAndSettle();
          await capture(tester, 'terms_mid_${tag}_$lang');
          expect(tester.takeException(), isNull);
        }
      }
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }, skip: shots == null);
}

/// A courier's dossier with everything but the charter (142's version 2).
class CharterDossier extends CourierDossierRepository {
  CharterDossier() : super(null);

  final saves = <(String, Map<String, Object?>)>[];
  int? charter;

  @override
  bool get isConfigured => true;

  @override
  Future<CourierDossier> mine() async => CourierDossier.fromJson({
        'status': 'draft',
        'files': {'selfie': true, 'id_front': true, 'id_back': true, 'licence': false},
        'open_steps': ['zone', 'hours', 'vehicle', 'selfie', 'id', 'phone', 'charter'],
        'timeline': [],
        'rules': {'licence_required': false, 'phone_verified': false, 'mobile_money': false, 'charter_version': 2},
        'city': 'Ouagadougou',
        'zones': ['Gounghin'],
        'days': ['lun', 'mar'],
        'hours_from': '08:00',
        'hours_to': '12:00',
        'vehicle': 'velo',
        'id_kind': 'cnib',
        'phone': '+22670147000',
        'charter_version': charter,
      });

  @override
  Future<CourierDossier> save(String step, Map<String, Object?> answers) async {
    saves.add((step, answers));
    if (step == 'charter') charter = answers['charter_version'] as int?;
    return mine();
  }
}

class _Slow extends FakeTerms {
  _Slow(super.now);

  Completer<void>? hold;

  @override
  Future<TermsState> state() async {
    final before = now;
    asked++;
    final h = hold;
    if (h != null) await h.future;
    return before;
  }
}

class _FailingAccept extends FakeTerms {
  _FailingAccept(super.now, this.error);

  final Object error;

  @override
  Future<TermsState> accept(String doc, int version, {String? platform, String? appVersion}) async => throw error;
}

class _Refusing extends FakeTerms {
  _Refusing(super.now);

  @override
  Future<TermsState> accept(String doc, int version, {String? platform, String? appVersion}) async =>
      throw const PostgrestException(
          message: 'Ces conditions ont changé entre-temps : relisez-les, puis acceptez-les à nouveau.');
}

class _Creation implements BusinessCreation {
  _Creation(this.terms);

  final FakeTerms terms;
  final log = <String>[];

  @override
  Future<BusinessStart> start() async => const BusinessStart();

  @override
  Future<AddressCheck> checkAddress(String slug) async => AddressCheck(slug: slug);

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
    log
      ..addAll(terms.accepted.where((a) => !log.contains(a)))
      ..add('create $profile');
    return 'org-new';
  }
}

class _Drafts implements DraftStore {
  _Drafts(this.kept);

  BusinessDraft? kept;

  @override
  Future<BusinessDraft?> read() async => kept;

  @override
  Future<void> write(BusinessDraft? draft) async => kept = draft;
}

