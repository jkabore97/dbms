import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/pin_codec.dart';
import 'package:kaj_app/core/auth/two_step.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/features/account/two_step_screen.dart';
import 'package:kaj_app/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

/// A platform admin passes two steps (077).
///
/// The server's gate is proved in database/tests/test_two_step.sql. What is
/// proved here is the app's half: a resolve stops at the code screen before
/// asking the server anything the gate would refuse, the screen enrols and
/// verifies, a wrong code says so, and passing lands where the person was
/// going — and nobody else is ever stopped.
class _Server extends AuthRepository {
  _Server() : super(null);

  int asked = 0;

  @override
  bool get hasLiveSession => true;

  @override
  Future<List<OrgSummary>> fetchOrgs() async {
    asked++;
    return const [
      OrgSummary(
        id: 'o1',
        name: 'Boutique Awa',
        profile: 'retail',
        roles: ['owner'],
      ),
    ];
  }
}

class _Admin extends AdminRepository {
  _Admin() : super(null);

  @override
  Future<bool> isPlatformAdmin() async => true;

  @override
  Future<int> claimMyInvitations() async => 0;

  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;

  @override
  Future<Map<String, String>> featureRulesForTier(
    String orgId,
    String tier,
  ) async => const {};
}

class _Step extends TwoStep {
  _Step({this.required = true, this.enrolled = false, this.fails = false})
    : super(null);

  final bool required;
  bool enrolled;
  bool passed = false;
  bool fails;
  bool logged = false;
  final codes = <String>[];

  @override
  Future<TwoStepStatus> status() async {
    if (fails) throw Exception('no signal');
    return TwoStepStatus(
      required: required,
      enrolled: enrolled,
      passed: passed,
    );
  }

  @override
  Future<TwoStepEnrollment> enroll({String? label}) async =>
      const TwoStepEnrollment(
        factorId: 'f1',
        secret: 'JBSWY3DPEHPK3PXP',
        uri: 'otpauth://totp/Kaj:admin?secret=JBSWY3DPEHPK3PXP&issuer=Kaj',
      );

  @override
  Future<String?> verifiedFactorId() async => enrolled ? 'f1' : null;

  @override
  Future<void> verify(String factorId, String code) async {
    codes.add(code);
    if (code != '123456') {
      throw const AuthException('Invalid TOTP code entered');
    }
    enrolled = true;
    passed = true;
  }

  @override
  Future<void> logEnabled() async => logged = true;
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
  tearDown(() => db.close());

  SessionController sessionWith(_Server server, TwoStep? step) =>
      SessionController(
        db: db,
        auth: server,
        admin: _Admin(),
        accounting: AccountingRepository(null),
        twoStep: step,
      );

  group('the session', () {
    test(
      'an admin below aal2 stops at the code screen, asking nothing else',
      () async {
        final server = _Server();
        final step = _Step();
        final session = sessionWith(server, step);
        await session.resolveOrgs();

        expect(session.phase, SessionPhase.twoStep);
        expect(session.twoStepEnrolled, isFalse);
        expect(
          server.asked,
          0,
          reason: 'the gate would refuse my_orgs; it is not asked',
        );

        step.passed = true;
        await session.twoStepPassed();
        expect(session.phase, SessionPhase.ready);
        expect(server.asked, 1);
      },
    );

    test(
      'an enrolled admin is asked the code, not shown how to enrol',
      () async {
        final session = sessionWith(_Server(), _Step(enrolled: true));
        await session.resolveOrgs();
        expect(session.phase, SessionPhase.twoStep);
        expect(session.twoStepEnrolled, isTrue);
      },
    );

    test('a seller, or no answer, goes straight through', () async {
      final seller = sessionWith(_Server(), _Step(required: false));
      await seller.resolveOrgs();
      expect(seller.phase, SessionPhase.ready);

      // A stalled or failed ask is not a reason to strand anybody: the
      // server is what enforces, and refuses an admin's calls itself.
      final offline = sessionWith(_Server(), _Step(fails: true));
      await offline.resolveOrgs();
      expect(offline.phase, SessionPhase.ready);
    });
  });

  group('the screen', () {
    Future<void> pump(
      WidgetTester tester,
      _Step step, {
      required Future<void> Function() onPassed,
    }) async {
      // A tall phone: the enrolment page is one long list.
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: TwoStepScreen(
            twoStep: step,
            enrolled: step.enrolled,
            onPassed: onPassed,
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'enrolling: the app, the key, a wrong code, then the right one',
      (tester) async {
        final step = _Step();
        var passed = 0;
        await pump(tester, step, onPassed: () async => passed++);

        expect(
          find.text('Protégez le compte de la plateforme'),
          findsOneWidget,
        );
        expect(
          find.text("Ouvrir l'application d'authentification"),
          findsOneWidget,
        );
        expect(
          find.text('JBSW Y3DP EHPK 3PXP'),
          findsOneWidget,
          reason: 'the key, in groups of four, for typing by hand',
        );

        await tester.enterText(
          find.byKey(const Key('two-step-code')),
          '111111',
        );
        await tester.tap(find.text('Activer'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Code incorrect ou expiré'), findsOneWidget);
        expect(passed, 0);

        await tester.enterText(
          find.byKey(const Key('two-step-code')),
          '123456',
        );
        await tester.tap(find.text('Activer'));
        await tester.pumpAndSettle();
        expect(passed, 1);
        expect(
          step.logged,
          isTrue,
          reason: 'the account history records the activation',
        );
      },
    );

    testWidgets('signing in: only the code is asked', (tester) async {
      final step = _Step(enrolled: true);
      var passed = 0;
      await pump(tester, step, onPassed: () async => passed++);

      expect(find.text('Code de votre application'), findsOneWidget);
      expect(
        find.text("Ouvrir l'application d'authentification"),
        findsNothing,
      );
      await tester.enterText(find.byKey(const Key('two-step-code')), '12345');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(find.text('Le code a 6 chiffres.'), findsOneWidget);
      expect(step.codes, isEmpty);

      await tester.enterText(find.byKey(const Key('two-step-code')), '123456');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(passed, 1);
      expect(step.logged, isFalse, reason: 'only enrolling is an event');
    });
  });

  testWidgets('the real app: unlock, the second step, then the street', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.runAsync(() async {
      final salt = PinCodec.newSalt();
      await db.saveIdentity(
        LocalIdentity(
          userId: 'admin-1',
          displayName: 'Plateforme',
          pinSalt: salt,
          pinHash: PinCodec.hash('1379', salt),
          orgsRefreshedAt: DateTime.now(),
        ),
      );
    });
    final step = _Step(enrolled: true);
    await tester.pumpWidget(
      KajApp(
        db: db,
        auth: _Server(),
        admin: _Admin(),
        reports: ReportsRepository(null),
        accounting: AccountingRepository(null),
        console: ConsoleRepository(null),
        farm: FarmRepository(null),
        invoicing: InvoicingRepository(null),
        retail: RetailRepository(null),
        staff: StaffRepository(null),
        capture: CaptureRepository(null, db: db),
        onboarding: OnboardingRepository(null),
        twoStep: step,
      ),
    );
    Future<void> flush() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pump();
    }

    await flush();
    expect(
      find.text('Code de votre application'),
      findsOneWidget,
      reason: 'a live admin session opens on the second step',
    );

    await tester.enterText(find.byKey(const Key('two-step-code')), '123456');
    await tester.tap(find.text('Valider'));
    await flush();
    expect(find.text('Code de votre application'), findsNothing);
    expect(find.text('Les vitrines'), findsOneWidget);
  });
}
