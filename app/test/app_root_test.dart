import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/app_root.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/pin_codec.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The M1 flow, exercised the way it will actually be used: on a phone with no
/// signal, where the only things the app has to go on are the identity and the
/// org list it cached the last time it could reach the server.
///
/// The repository is built with a null client, which is what a device with no
/// connection effectively has — no live session, no way to fetch orgs. Every
/// decision below therefore comes from the device.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  final auth = AuthRepository(null);

  // Same null client, for the same reason: with no connection there is nothing
  // to claim an invitation against, and the admin entry points stay hidden.
  final admin = AdminRepository(null);
  final reports = ReportsRepository(null);

  // Same null client as the others: these two exist so AppRoot can be built,
  // and every screen behind them is a server query that a build with no
  // backend never reaches.
  final accounting = AccountingRepository(null);
  final console = ConsoleRepository(null);
  final farm = FarmRepository(null);
  final retail = RetailRepository(null);
  final staff = StaffRepository(null);
  final onboarding = OnboardingRepository(null);

  late CaptureRepository capture;

  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
    // Null client and no upload URL: the camera button is hidden rather than
    // shown and failing, which is what a build with no backend must do.
    capture = CaptureRepository(null, db: db);
  });

  // sqflite keys open databases by path, so an in-memory database outlives the
  // test that opened it unless every connection to it is closed. Without this
  // each case inherits the previous one's orgs.
  tearDown(() => db.close());

  /// `pumpAndSettle` is unusable here for two independent reasons: widget tests
  /// run in a fake-async zone where sqflite's real background I/O never
  /// completes, and the loading spinner animates forever so the tree never
  /// settles. This alternates fake time (which fires the app's own timers)
  /// with real time (which lets the database answer).
  Future<void> flush(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppRoot(
          db: db,
          auth: auth,
          admin: admin,
          reports: reports,
          accounting: accounting,
          console: console,
          farm: farm,
          retail: retail,
          staff: staff,
          capture: capture,
          onboarding: onboarding,
        ),
      ),
    );
    await flush(tester);
  }

  /// Seeds the device the way a previous successful sign-in would have left
  /// it. Every database call has to go through `runAsync`: inside a widget
  /// test the default zone fakes time, and sqflite's real I/O never completes
  /// there.
  Future<void> seedDevice(
    WidgetTester tester, {
    String? pin = '1379',
    List<OrgSummary> orgs = const [],
    bool signedInBefore = true,
  }) async {
    await tester.runAsync(() async {
      if (signedInBefore) {
        final salt = pin == null ? null : PinCodec.newSalt();
        await db.saveIdentity(LocalIdentity(
          userId: 'user-israel',
          displayName: 'Israel',
          phone: '+22670000001',
          pinSalt: salt,
          pinHash: salt == null ? null : PinCodec.hash(pin!, salt),
          orgsRefreshedAt: DateTime.now(),
        ));
      }
      if (orgs.isNotEmpty) await db.cacheOrgs(orgs);
    });
  }

  Future<void> enterPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.widgetWithText(TextButton, digit));
      await tester.pump();
    }
    await flush(tester);
  }

  testWidgets('a fresh device asks who you are', (tester) async {
    await pumpApp(tester);

    expect(find.text('Kaj'), findsOneWidget);
    expect(find.text('Connectez-vous pour ouvrir votre activité.'),
        findsOneWidget);
  });

  testWidgets('a known device with a stale token asks for the code',
      (tester) async {
    await seedDevice(tester);
    await pumpApp(tester);

    expect(find.text('Entrez votre code'), findsOneWidget);
    expect(find.text('Israel'), findsOneWidget);
  });

  testWidgets('the wrong code does not open anything', (tester) async {
    await seedDevice(tester, orgs: const [
      OrgSummary(id: 'org-1', name: 'Grace Chapel', profile: 'church'),
    ]);
    await pumpApp(tester);

    await enterPin(tester, '1378');

    expect(find.text('Code incorrect.'), findsOneWidget);
    expect(find.text('Grace Chapel'), findsNothing);
  });

  testWidgets('one business opens straight into it', (tester) async {
    await seedDevice(tester, orgs: const [
      OrgSummary(
        id: 'org-1',
        name: 'Grace Chapel',
        profile: 'church',
        roles: ['owner'],
      ),
    ]);
    await pumpApp(tester);

    await enterPin(tester, '1379');

    // No picker: straight to the church module, named after the org the
    // membership resolved to — not after anything compiled into the build.
    expect(find.text('Grace Chapel'), findsOneWidget);
    expect(find.text('Recette'), findsOneWidget);
    expect(find.text("Aujourd'hui"), findsOneWidget);
  });

  testWidgets('the profile column decides the screen, not the build',
      (tester) async {
    await seedDevice(tester, orgs: const [
      OrgSummary(id: 'org-2', name: 'Ferme Ignace', profile: 'farm'),
    ]);
    await pumpApp(tester);

    await enterPin(tester, '1379');

    // Same binary, same PIN, different business: the farm does not land in a
    // screen built for counting offerings.
    //
    // Until M4 this asserted the word "Ferme" — the label on the placeholder
    // screen a farm used to fall through to. The farm has its own module now,
    // so the claim is made against what that module actually puts on screen:
    // the morning collection, and the two things a church home screen has
    // that a farm one must not.
    expect(find.text('Ferme Ignace'), findsWidgets);
    expect(find.text('Ramassage'), findsOneWidget);
    expect(find.text('Bandes'), findsOneWidget);
    expect(find.text('Recette'), findsNothing);
    expect(find.text('Dépense'), findsNothing);
  });

  testWidgets('two businesses show a picker, and picking one opens it',
      (tester) async {
    await seedDevice(tester, orgs: const [
      OrgSummary(id: 'org-1', name: 'Grace Chapel', profile: 'church'),
      OrgSummary(id: 'org-2', name: 'Ferme Ignace', profile: 'farm'),
    ]);
    await pumpApp(tester);

    await enterPin(tester, '1379');

    expect(find.text('Choisissez une activité'), findsOneWidget);
    expect(find.text('Grace Chapel'), findsOneWidget);
    expect(find.text('Ferme Ignace'), findsOneWidget);

    await tester.tap(find.text('Ferme Ignace'));
    await flush(tester);

    expect(find.text('Ramassage'), findsOneWidget);
    expect(find.text('Choisissez une activité'), findsNothing);
  });

  testWidgets('belonging to nothing is a waiting room, not an error',
      (tester) async {
    await seedDevice(tester);
    await pumpApp(tester);

    await enterPin(tester, '1379');

    expect(find.text('Votre compte est prêt'), findsOneWidget);
    // The number the owner needs in order to add them.
    expect(find.text('+22670000001'), findsOneWidget);
  });

  testWidgets('an identity with no code cannot be trusted offline',
      (tester) async {
    // Signed in once, never chose a code, token now stale. Nothing on the
    // device can prove who this is, so it has to be a real sign-in.
    await seedDevice(tester, pin: null);
    await pumpApp(tester);

    expect(find.text('Connectez-vous pour ouvrir votre activité.'),
        findsOneWidget);
    expect(find.text('Entrez votre code'), findsNothing);
  });
}
