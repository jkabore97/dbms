import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/notify/push_client.dart';
import 'package:kaj_app/core/notify/push_setup.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/phone/country_codes.dart';
import 'package:kaj_app/core/security/security_repository.dart';
import 'package:kaj_app/core/security/security_settings.dart';
import 'package:kaj_app/features/account/security_screen.dart';
import 'package:kaj_app/features/storefront/shop_style.dart';
import 'package:intl/intl.dart';
import 'package:kaj_app/core/onboarding/business_creation.dart';
import 'package:kaj_app/features/notify/notification_settings_sheet.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Batch 122, builder R: the owner's list of 2026-10-09.
class _Notify extends NotificationsRepository {
  _Notify({this.who}) : super(null);

  /// The person signed in.
  final String? who;

  @override
  String? get me => who;
  @override
  bool get isConfigured => true;
  @override
  Future<List<NotificationPref>> prefs() async => const [
        NotificationPref(type: 'order_updates', audience: 'customer', label: 'Mes commandes', enabled: true),
      ];
}

/// A phone: its permission, and whether it is in the person's book.
class _Phone extends PushDevice {
  _Phone(this.permitted);

  PushPermission permitted;
  bool registered = false;
  int asked = 0;
  int withdrawn = 0;
  int settingsOpened = 0;

  @override
  Future<bool> available() async => true;
  @override
  Future<bool> ensure(NotificationsRepository notify) async => registered;
  @override
  Future<PushPermission> permission() async => permitted;
  @override
  Future<bool> enable(NotificationsRepository notify) async {
    asked++;
    if (permitted == PushPermission.blocked) return false;
    permitted = PushPermission.granted;
    return registered = true;
  }

  @override
  Future<void> disable(NotificationsRepository notify) async {
    withdrawn++;
    registered = false;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

Widget _app(Widget child, {String lang = 'fr'}) => MaterialApp(
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      locale: Locale(lang),
      home: Scaffold(body: child),
    );

/// A vitrine whose business chose an app colour ([theme]) and maybe one
/// for the vitrine itself.
class _Vitrine extends StorefrontRepository {
  _Vitrine({this.theme, this.style = StorefrontStyle.none, this.profile = 'retail'}) : super(null);
  final String? theme;
  final StorefrontStyle style;
  final String profile;
  @override
  bool get isConfigured => true;
  @override
  Future<PublicShop?> shop(String slug) async => PublicShop(
      orgId: 'o1', name: 'Boutique Awa', slug: 'boutique-awa', profile: profile,
      theme: theme, style: style);
  @override
  Future<List<PublicItem>> items(String slug) async =>
      const [PublicItem(id: 'p1', name: 'Sucre', price: 750, inStock: true)];
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('R2 « Notifications sur ce téléphone »: one switch, no tones', () {
    Finder theSwitch() => find.byKey(const Key('settings-push-switch'));

    testWidgets('off → on asks and registers; on → off withdraws this phone', (tester) async {
      final phone = _Phone(PushPermission.prompt);
      await tester.pumpWidget(_app(NotificationSettingsSheet(
          notify: _Notify(), audiences: const {'customer'}, device: phone)));
      await tester.pumpAndSettle();
      expect(find.text('Notifications sur ce téléphone'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(theSwitch()).value, isFalse);
      // Nothing about tones or vibration is offered any more.
      expect(find.textContaining('Sons'), findsNothing);
      expect(find.text('Vibrer'), findsNothing);
      // What to receive stays.
      expect(find.byKey(const Key('pref-order_updates')), findsOneWidget);

      await tester.tap(theSwitch());
      await tester.pumpAndSettle();
      expect(phone.asked, 1);
      expect(tester.widget<SwitchListTile>(theSwitch()).value, isTrue);
      expect(find.textContaining('son et la vibration du téléphone'), findsOneWidget);

      await tester.tap(theSwitch());
      await tester.pumpAndSettle();
      expect(phone.withdrawn, 1);
      expect(tester.widget<SwitchListTile>(theSwitch()).value, isFalse);
    });

    testWidgets('blocked in the phone: switch greyed, the phone\'s settings offered', (tester) async {
      final phone = _Phone(PushPermission.blocked);
      await tester.pumpWidget(_app(NotificationSettingsSheet(
          notify: _Notify(), audiences: const {'customer'}, device: phone)));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(theSwitch()).onChanged, isNull);
      expect(find.textContaining('Bloquées dans les réglages du téléphone'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-push-open-settings')));
      await tester.pump();
      expect(phone.settingsOpened, 1);

      // Turned on in the phone's settings, then back to the app.
      phone
        ..permitted = PushPermission.granted
        ..registered = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(theSwitch()).value, isTrue,
          reason: 'true to what the phone now says');
    });

    testWidgets('in English', (tester) async {
      await tester.pumpWidget(_app(
          NotificationSettingsSheet(
              notify: _Notify(), audiences: const {'customer'}, device: _Phone(PushPermission.prompt)),
          lang: 'en'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications on this phone'), findsOneWidget);
    });

    test('off is kept on the phone, for the person who said it, and nothing writes the device back', () async {
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      await PushSetup.load(db);
      final awa = _Notify(who: 'awa');
      final issa = _Notify(who: 'issa');
      expect(PushSetup.isOff(awa), isFalse);
      await PushSetup.disable(awa);
      expect(PushSetup.isOff(awa), isTrue);
      expect(await PushSetup.ensure(awa), isFalse);
      expect(await PushSetup.standing(awa), PushStanding.unavailable,
          reason: 'no pop-up at the opening for a phone switched off');
      expect(PushSetup.isOff(issa), isFalse,
          reason: 'someone else signing in on the same phone is asked as anyone is');
      expect(PushSetup.isOff(_Notify()), isFalse, reason: 'nobody signed in');
      await PushSetup.disable(issa);
      await PushSetup.load(db);
      expect(PushSetup.isOff(awa), isTrue, reason: 'remembered across launches');
      expect(PushSetup.isOff(issa), isTrue);
      await PushSetup.enable(awa);
      expect(PushSetup.isOff(awa), isFalse, reason: 'the person\'s own tap turns it back on');
      expect(PushSetup.isOff(issa), isTrue, reason: 'for that person only');
      await PushSetup.load(db);
      expect(PushSetup.isOff(awa), isFalse);
      expect(PushSetup.isOff(issa), isTrue);
      await PushSetup.enable(issa);
    });
  });

  group('R4 the city suggestions: the person\'s country, then the world', () {
    test('Burkina: its towns, West Africa, then every other continent', () {
      final t = suggestedTowns('BF');
      expect(t.first, 'Ouagadougou');
      expect(t.take(6), contains('Bobo-Dioulasso'));
      expect(t.indexOf('Abidjan'), lessThan(t.indexOf('Paris')),
          reason: 'West Africa first for a country there');
      for (final city in ['Paris', 'Montréal', 'New York', 'Dubai', 'Tokyo']) {
        expect(t, contains(city));
      }
      expect(t.toSet().length, t.length, reason: 'no town twice');
      expect(t.length, lessThanOrEqualTo(18), reason: 'a few rows of chips, not a page');
    });

    test('France: its own first, then Europe, Africa still there', () {
      final t = suggestedTowns('FR');
      expect(t.first, 'Paris');
      expect(t.indexOf('Bruxelles'), lessThan(t.indexOf('Abidjan')));
      expect(t, containsAll(['Abidjan', 'Dakar', 'New York', 'Tokyo']));
    });

    test('a country with no list of its own: its part of the world leads', () {
      expect(suggestedTowns('KE').first, 'Douala');
      expect(suggestedTowns('SG').first, 'Tokyo');
    });

    test('the country: the phone number\'s, else the phone\'s region, else Burkina', () {
      expect(townCountry('+33612345678'), 'FR');
      expect(townCountry(null, deviceRegion: 'ca'), 'CA');
      expect(townCountry(null, deviceRegion: ''), 'BF');
    });
  });

  group('R5 the business\'s own design reaches its vitrine', () {
    test('the vitrine\'s colour, else the app colour the business chose, else none', () {
      const own = Color(0xFFB1541A);
      PublicShop shop({String? theme, Color? accent}) => PublicShop(
          orgId: 'o', name: 'n', slug: 's', profile: 'retail', theme: theme,
          style: StorefrontStyle(accent: accent));
      expect(shop(theme: 'prune', accent: own).accent, own);
      expect(shop(theme: 'prune').accent, prunePalette.ink);
      expect(shop().accent, isNull, reason: 'neither chosen: Mara\'s black');
      expect(shop(theme: 'not-a-palette').accent, isNull);
    });

    for (final profile in ['retail', 'farm', 'association']) {
      testWidgets('a $profile in « Prune » shows its tagline in prune', (tester) async {
        tester.view.physicalSize = const Size(390, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
        addTearDown(() => tester.runAsync(db.close));
        await tester.pumpWidget(MaterialApp(
          home: StorefrontScreen(
            slug: 'boutique-awa',
            storefront: _Vitrine(
                theme: 'prune', profile: profile, style: const StorefrontStyle(tagline: 'Depuis 1998')),
            capture: CaptureRepository(null, db: db),
            session: SessionController(
              db: db,
              auth: AuthRepository(null),
              admin: AdminRepository(null),
              accounting: AccountingRepository(null),
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 800));
        final tagline = tester.widget<Text>(find.text('Depuis 1998'));
        expect(tagline.style?.color, prunePalette.ink);
      });
    }
  });

  group('R3 every word, in English too', () {
    testWidgets('the street\'s strip and a section label read English', (tester) async {
      await tester.pumpWidget(_app(
          ShopPage(
            title: 'Mara',
            announcements: ShopPage.street,
            body: Builder(builder: (context) => ShopSectionLabel(context.tr('Passées'))),
          ),
          lang: 'en'));
      await tester.pump();
      expect(find.text('Pick up at the shop, or delivery in the neighbourhood'), findsOneWidget);
      expect(find.text('PAST'), findsOneWidget);
      expect(find.text('PASSÉES'), findsNothing);
    });

    testWidgets('Sécurité in English: the delays and the fingerprint', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      final settings = SecuritySettings(db);
      await tester.runAsync(settings.load);
      await tester.pumpWidget(_app(SecurityScreen(settings: settings, api: SecurityRepository(null)), lang: 'en'));
      await tester.pump();
      await tester.pump();
      expect(find.text('After 5 min'), findsOneWidget);
      expect(find.text('Après 5 min'), findsNothing);
      expect(find.text('Never'), findsOneWidget);
    });

    test('dates, countries, devices and the server\'s words follow the language', () async {
      final before = trCurrent;
      addTearDown(() => trCurrent = before);
      trCurrent = 'en';
      expect(intlLocale(), 'en');
      expect(DateFormat('d MMM', intlLocale()).format(DateTime(2026, 10, 5)), '5 Oct');
      expect(translate('en', countryByIso('SN').name), 'Senegal');
      expect(countryByIso('BF').lengthProblem('70 11'), '8 digits for Burkina Faso (+226)');
      expect(countryMatches(countryByIso('DE'), 'germ'), isTrue, reason: 'searched in English too');
      expect(describeUserAgent(null), 'Unknown device');
      expect(translate('en', 'Pas de connexion. Réessayez quand le réseau revient.'),
          'No connection. Try again when the network is back.');
      trCurrent = 'fr';
      expect(intlLocale(), 'fr_FR');
      expect(countryByIso('BF').lengthProblem('70 11'), '8 chiffres pour Burkina Faso (+226)');
    });
  });
}
