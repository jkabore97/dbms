import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/main.dart';
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
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
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
///
/// This runs against the real `KajApp`, which builds the real session and the
/// real router — so what is asserted is the wiring a user actually gets, not a
/// screen assembled by the test. The last group is the reason the router
/// exists: every one of these steps used to be a `setState`, which left nothing
/// in history, so pressing back inside a business left the app instead of
/// returning to the picker.
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
  final invoicing = InvoicingRepository(null);
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
    // A Burkinabè phone, not the test harness's en_US default. Language now
    // follows the device, so without this the whole suite would render in
    // English and every French assertion below would be asserting a bug.
    tester.platformDispatcher.localesTestValue = [const Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    // The real app, with the real router. KajApp builds its own MaterialApp,
    // so there is deliberately no wrapper here: a test that supplied its own
    // Navigator would be testing a tree the user never gets.
    await tester.pumpWidget(KajApp(
      db: db,
      auth: auth,
      admin: admin,
      reports: reports,
      accounting: accounting,
      console: console,
      farm: farm,
      invoicing: invoicing,
      retail: retail,
      staff: staff,
      capture: capture,
      onboarding: onboarding,
    ));
    await flush(tester);
  }

  /// What the browser's back button does, as the framework sees it.
  ///
  /// `handlePopRoute` is the same entry point the platform uses for a browser
  /// back or an Android system back, so this asserts the real thing rather
  /// than tapping an AppBar arrow — which is a different gesture and was never
  /// the one that was broken.
  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
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
    expect(find.text('Récolte'), findsOneWidget);
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

    expect(find.text('Récolte'), findsOneWidget);
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

  group('a refresh keeps your place', () {
    // The complaint, verbatim: "when I refresh the webpage it takes me to a
    // different page." On a device with a code, reloading a deep page sent
    // the browser to /code, which replaced the address — and unlocking then
    // landed on the business home, because there was nothing left to return
    // to. The redirect now stashes the interrupted address and unlocks back
    // into it.

    /// What a browser reload amounts to: the app restarts locked while the
    /// address bar still names the deep page.
    Future<void> reloadAt(WidgetTester tester, String location) async {
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      (app.routerConfig as GoRouter).go(location);
      await flush(tester);
    }

    testWidgets('unlocking returns to the page that was reloaded',
        (tester) async {
      await seedDevice(tester, orgs: const [
        OrgSummary(
          id: 'org-1',
          name: 'Grace Chapel',
          profile: 'church',
          roles: ['owner'],
        ),
      ]);
      await pumpApp(tester);
      await reloadAt(tester, '/o/org-1/produits');

      // Still gated: the reload lands on the code screen first.
      expect(find.text('Entrez votre code'), findsOneWidget);

      await enterPin(tester, '1379');

      // The page that was reloaded — not the home the redirect used to pick.
      expect(find.text('Articles'), findsOneWidget,
          reason: 'unlocking forgot the page the refresh was headed to');
      expect(find.text('Recette'), findsNothing);
    });

    testWidgets('with several businesses the reload skips the picker too',
        (tester) async {
      await seedDevice(tester, orgs: const [
        OrgSummary(id: 'org-1', name: 'Grace Chapel', profile: 'church'),
        OrgSummary(id: 'org-2', name: 'Boutique Sanou', profile: 'retail'),
      ]);
      await pumpApp(tester);
      await reloadAt(tester, '/o/org-2/produits');
      await enterPin(tester, '1379');

      expect(find.text('Choisissez une activité'), findsNothing,
          reason: 'the reload named a business; the picker is a detour');
      expect(find.text('Articles'), findsOneWidget);
    });

    testWidgets("someone else's business still lands on the picker",
        (tester) async {
      // The stash must not become a doorway: an address this account cannot
      // open is validated the same way a typed bookmark is.
      await seedDevice(tester, orgs: const [
        OrgSummary(id: 'org-1', name: 'Grace Chapel', profile: 'church'),
        OrgSummary(id: 'org-2', name: 'Ferme Ignace', profile: 'farm'),
      ]);
      await pumpApp(tester);
      await reloadAt(tester, '/o/org-locked-away/produits');
      await enterPin(tester, '1379');

      expect(find.text('Choisissez une activité'), findsOneWidget);
      expect(find.text('Articles'), findsNothing);
    });
  });

  group('a reload remembers which business was open', () {
    // The complaint, with a screenshot: refreshing from the root URL dumped
    // a person with several businesses onto the picker — sometimes before
    // the org list had even arrived, an empty picker. The open business now
    // lives in device_prefs, like the language, and a reload walks straight
    // back into it.

    testWidgets('several businesses, but the remembered one opens directly',
        (tester) async {
      await seedDevice(tester, orgs: const [
        OrgSummary(id: 'org-1', name: 'Grace Chapel', profile: 'church'),
        OrgSummary(id: 'org-2', name: 'Ferme Ignace', profile: 'farm'),
      ]);
      await tester.runAsync(() => db.writePref('last_org_id', 'org-2'));
      await pumpApp(tester);
      await enterPin(tester, '1379');

      expect(find.text('Récolte'), findsOneWidget,
          reason: 'the reload forgot which business was open');
      expect(find.text('Choisissez une activité'), findsNothing);
    });

    testWidgets('a remembered business that no longer exists is the picker',
        (tester) async {
      // Removed from the account since the last visit: the stale memory must
      // fall through to the picker, not crash or loop.
      await seedDevice(tester, orgs: const [
        OrgSummary(id: 'org-1', name: 'Grace Chapel', profile: 'church'),
        OrgSummary(id: 'org-2', name: 'Ferme Ignace', profile: 'farm'),
      ]);
      await tester.runAsync(() => db.writePref('last_org_id', 'org-gone'));
      await pumpApp(tester);
      await enterPin(tester, '1379');

      expect(find.text('Choisissez une activité'), findsOneWidget);
    });
  });

  group('back means what it says', () {
    // The bug this router was built for. Every step below used to be a
    // setState, so the browser kept no record of it: pressing back inside a
    // business went back past the app itself.

    testWidgets('back from a business returns to the picker, not out of the app',
        (tester) async {
      await seedDevice(tester, orgs: const [
        OrgSummary(id: 'org-1', name: 'Grace Chapel', profile: 'church'),
        OrgSummary(id: 'org-2', name: 'Ferme Ignace', profile: 'farm'),
      ]);
      await pumpApp(tester);
      await enterPin(tester, '1379');

      expect(find.text('Choisissez une activité'), findsOneWidget);
      await tester.tap(find.text('Ferme Ignace'));
      await flush(tester);
      expect(find.text('Récolte'), findsOneWidget);

      await pressBack(tester);

      // The whole point: still in the app, and back where we came from.
      expect(find.text('Choisissez une activité'), findsOneWidget,
          reason: 'back from a business left the app instead of returning '
              'to the picker');
      expect(find.text('Récolte'), findsNothing);
    });

    testWidgets('the picker is the first page, so back cannot escape it',
        (tester) async {
      // A person who has just chosen has nowhere further back to go inside
      // the app. What must not happen is a blank screen or a half-built one.
      await seedDevice(tester, orgs: const [
        OrgSummary(id: 'org-1', name: 'Grace Chapel', profile: 'church'),
        OrgSummary(id: 'org-2', name: 'Ferme Ignace', profile: 'farm'),
      ]);
      await pumpApp(tester);
      await enterPin(tester, '1379');

      await pressBack(tester);

      expect(find.text('Choisissez une activité'), findsOneWidget);
    });

    testWidgets('a business can be reopened after going back', (tester) async {
      // Back followed by forward-by-tapping. This is the sequence that breaks
      // when a router keeps stale state: the second open shows the first
      // business, or nothing at all.
      await seedDevice(tester, orgs: const [
        OrgSummary(id: 'org-1', name: 'Grace Chapel', profile: 'church'),
        OrgSummary(id: 'org-2', name: 'Ferme Ignace', profile: 'farm'),
      ]);
      await pumpApp(tester);
      await enterPin(tester, '1379');

      await tester.tap(find.text('Ferme Ignace'));
      await flush(tester);
      await pressBack(tester);

      await tester.tap(find.text('Grace Chapel'));
      await flush(tester);

      // The church, not the farm we opened first.
      expect(find.text('Recette'), findsOneWidget);
      expect(find.text('Récolte'), findsNothing);
    });

    testWidgets('one business has no picker to go back to', (tester) async {
      // Somebody with a single business never sees the picker, so back must
      // not invent one — it has nowhere to go and must leave the app alone.
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
      expect(find.text('Recette'), findsOneWidget);

      await pressBack(tester);

      expect(find.text('Recette'), findsOneWidget,
          reason: 'back emptied the only business this person has');
    });
  });
}
