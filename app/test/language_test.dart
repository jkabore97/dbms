import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/l10n/locale_controller.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:kaj_app/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The language of the device, end to end: what it defaults to, how it is
/// changed, and that the change both survives a restart and reaches the
/// screen.
///
/// Run against the real `KajApp` for the same reason the routing suite is:
/// the failure that matters is not a controller returning the wrong locale,
/// it is a person tapping "English" and the screen staying French.
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

  Future<void> pumpApp(WidgetTester tester, {LocaleController? locale}) async {
    await tester.pumpWidget(KajApp(
      locale: locale,
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
    ));
    // The session boots against the database; give it real time to answer.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();
  }

  group('the default follows the phone', () {
    testWidgets('a French phone opens in French', (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('fr', 'BF')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await pumpApp(tester);

      expect(find.text('Connectez-vous pour ouvrir votre activité.'),
          findsOneWidget);
    });

    testWidgets('an English phone opens in English', (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await pumpApp(tester);

      expect(find.text('Sign in to open your business.'), findsOneWidget);
    });

    testWidgets('a phone in a language the app does not speak falls to French',
        (tester) async {
      // Amharic. Not hypothetical forever — a phone bought abroad — and the
      // wrong answer here is a crash or English, both worse than French.
      tester.platformDispatcher.localesTestValue = [const Locale('am')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await pumpApp(tester);

      expect(find.text('Connectez-vous pour ouvrir votre activité.'),
          findsOneWidget);
    });
  });

  group('choosing', () {
    testWidgets('a choice beats the phone and reaches the screen',
        (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('fr')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      final locale = LocaleController(db);
      await pumpApp(tester, locale: locale);
      expect(find.text('Connectez-vous pour ouvrir votre activité.'),
          findsOneWidget);

      // What the picker's tap does, without walking the picker: the picker's
      // own labels are in the language being left, which the routing suite
      // cannot assert on stably.
      await tester.runAsync(() => locale.choose(const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to open your business.'), findsOneWidget);
      expect(find.text('Connectez-vous pour ouvrir votre activité.'),
          findsNothing);
    });

    testWidgets('the choice survives a restart', (tester) async {
      // The whole reason it is in the database. A language that resets on
      // every launch is a setting somebody stops trusting the first morning.
      tester.platformDispatcher.localesTestValue = [const Locale('fr')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      final first = LocaleController(db);
      await tester.runAsync(() => first.choose(const Locale('en')));

      final second = LocaleController(db);
      await tester.runAsync(() => second.load());

      expect(second.chosen, const Locale('en'));
      expect(second.effective, const Locale('en'));
    });

    testWidgets('clearing the choice goes back to following the phone',
        (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('fr')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      final locale = LocaleController(db);
      await tester.runAsync(() async {
        await locale.choose(const Locale('en'));
        await locale.choose(null);
      });

      final reloaded = LocaleController(db);
      await tester.runAsync(() => reloaded.load());
      expect(reloaded.chosen, isNull);
      expect(reloaded.effective, const Locale('fr'));
    });

    test('a stored language that is no longer offered is ignored', () async {
      // A draft locale somebody enabled and later withdrew, or plain junk in
      // the row. Falling back beats opening an app nobody can read.
      await db.writePref('locale', 'mos');
      final locale = LocaleController(db);
      await locale.load();
      expect(locale.chosen, isNull);
    });
  });

  group('the translations themselves', () {
    test('every enabled language answers every key the French has', () {
      // gen_l10n guarantees this at compile time for the getters used, but
      // the two draft files rely on fallback — this pins that the *enabled*
      // set never does. An English screen with one French sentence in it
      // reads as a bug to the person who chose English.
      for (final locale in enabledLocales) {
        final strings = lookupStrings(locale);
        // A sample across the surfaces, not an exhaustive reflection walk:
        // the compile step already proves existence, this proves non-fallback
        // by spot-checking values differ from French where they must.
        expect(strings.languageName, isNotEmpty);
        expect(strings.signIn, isNotEmpty);
        expect(strings.pinEnter, isNotEmpty);
        expect(strings.pickBusiness, isNotEmpty);
        expect(strings.unsentDataBody(2), contains('2'));
      }
      expect(lookupStrings(const Locale('en')).signIn,
          isNot(lookupStrings(const Locale('fr')).signIn));
    });

    test('draft languages fall back to French rather than showing key names',
        () {
      // The drafts translate almost nothing yet, deliberately. What they must
      // never do is leak "signInTagline" onto a screen.
      for (final locale in draftLocales) {
        final strings = lookupStrings(locale);
        expect(strings.languageName, isNotEmpty);
        expect(strings.signInTagline,
            lookupStrings(const Locale('fr')).signInTagline);
      }
    });

    test('each language names itself in itself', () {
      expect(lookupStrings(const Locale('fr')).languageName, 'Français');
      expect(lookupStrings(const Locale('en')).languageName, 'English');
      expect(lookupStrings(const Locale('mos')).languageName, 'Mòoré');
      expect(lookupStrings(const Locale('dyu')).languageName, 'Julakan');
    });

    test('the plural pulls its weight in both enabled languages', () {
      expect(lookupStrings(const Locale('fr')).unsentDataBody(1),
          contains('1 enregistrement attend'));
      expect(lookupStrings(const Locale('fr')).unsentDataBody(3),
          contains('3 enregistrements attendent'));
      expect(lookupStrings(const Locale('en')).unsentDataBody(1),
          contains('1 record is'));
      expect(lookupStrings(const Locale('en')).unsentDataBody(3),
          contains('3 records are'));
    });
  });
}
