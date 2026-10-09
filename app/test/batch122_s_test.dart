import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/site/app_download.dart';
import 'package:kaj_app/core/update/update_check.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';

/// Batch 122, builder S: the couriers' radius and the store switches in
/// Réglages (122), and the web's « download the app » pop-up.
class _Center extends CommandCenterRepository {
  _Center() : super(null);

  final calls = <String>[];
  Map<String, SettingValue> values = const {};

  @override
  bool get isConfigured => true;

  @override
  Future<Map<String, SettingValue>> settings() async => values;

  @override
  Future<String?> setSetting(String key, Object? value) async {
    calls.add('set:$key=$value');
    values = {...values, key: SettingValue(value: value)};
    return 'act-$key';
  }
}

/// A browser, as the test says it is.
class _Browser {
  _Browser(this.phone, {this.standalone = false, this.shownAt});

  final AppPhone? phone;
  final bool standalone;
  DateTime? shownAt;

  AppDownloadEnv get env => AppDownloadEnv(
        phone: phone,
        standalone: standalone,
        readShownAt: () => shownAt,
        writeShownAt: (at) => shownAt = at,
      );
}

final _now = DateTime(2026, 10, 9, 12);

Future<void> _street(WidgetTester tester, _Browser browser,
    {AppLinks links = const AppLinks.fallback(), Size size = const Size(390, 844), bool wait = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: AppDownloadPrompt(
      key: UniqueKey(),
      env: browser.env,
      links: () async => links,
      now: () => _now,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('La rue'), actions: [
            TextButton(key: const Key('sign-in'), onPressed: () {}, child: const Text('Se connecter')),
          ]),
          body: Center(
            child: FilledButton(
              key: const Key('open-order'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => const SizedBox(height: 600, child: Text('Commande')),
              ),
              child: const Text('Commander'),
            ),
          ),
        ),
      ),
    ),
  ));
  if (!wait) return;
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('Réglages (122)', () {
    testWidgets('the radius by its name, 1 to 100 km, refused outside before the server',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final center = _Center()
        ..values = {
          'courier_radius_km': const SettingValue(value: 10),
          'play_store_live': const SettingValue(value: false),
          'app_store_url': const SettingValue(value: ''),
        };
      await tester.pumpWidget(MaterialApp(home: SettingsSection(center: center)));
      await tester.pumpAndSettle();
      expect(find.text('Distance où les livreurs reçoivent une livraison (km, 1 à 100)'), findsOneWidget);
      expect(find.text('10 km'), findsOneWidget);
      expect(find.text('Applications mobiles'), findsOneWidget);
      expect(find.text('Mara est publiée sur Google Play (sinon : le fichier APK)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('setting-courier_radius_km')));
      await tester.pumpAndSettle();
      for (final text in ['0', '101', '250']) {
        await tester.enterText(find.byKey(const Key('setting-field')), text);
        await tester.tap(find.byKey(const Key('setting-save')));
        await tester.pumpAndSettle();
        expect(find.text('Un nombre de 1 à 100.'), findsOneWidget, reason: text);
      }
      await tester.enterText(find.byKey(const Key('setting-field')), '12,5');
      await tester.tap(find.byKey(const Key('setting-save')));
      await tester.pumpAndSettle();
      expect(find.text('Un nombre entier, zéro ou plus.'), findsOneWidget);
      expect(center.calls, isEmpty);
      await tester.enterText(find.byKey(const Key('setting-field')), '25');
      await tester.tap(find.byKey(const Key('setting-save')));
      await tester.pumpAndSettle();
      expect(center.calls, ['set:courier_radius_km=25']);
      expect(find.text('25 km'), findsOneWidget);
    });

    testWidgets('the App Store: an https address, or nothing', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final center = _Center()..values = {'app_store_url': const SettingValue(value: '')};
      await tester.pumpWidget(MaterialApp(home: SettingsSection(center: center)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setting-app_store_url')));
      await tester.pumpAndSettle();
      for (final text in ['http://apps.apple.com/app/id1', 'Mara']) {
        await tester.enterText(find.byKey(const Key('setting-field')), text);
        await tester.tap(find.byKey(const Key('setting-save')));
        await tester.pumpAndSettle();
        expect(find.text('Une adresse qui commence par https://, ou rien.'), findsOneWidget, reason: text);
      }
      expect(center.calls, isEmpty);
      await tester.enterText(find.byKey(const Key('setting-field')), 'https://apps.apple.com/app/mara/id1');
      await tester.tap(find.byKey(const Key('setting-save')));
      await tester.pumpAndSettle();
      expect(center.calls, ['set:app_store_url=https://apps.apple.com/app/mara/id1']);
    });

    test('in English', () {
      expect(translate('en', 'Distance où les livreurs reçoivent une livraison (km, 1 à 100)'),
          'Distance within which couriers receive a delivery (km, 1 to 100)');
      expect(translate('en', 'Un nombre de {lo} à {hi}.', {'lo': 1, 'hi': 100}), 'A number from 1 to 100.');
    });
  });

  group('the web\'s download pop-up', () {
    test('the links as the server says them; the APK when it says nothing', () {
      final live = AppLinks.fromJson(const {
        'android': 'https://play.google.com/store/apps/details?id=bf.kaj.app',
        'android_store': true,
        'ios': 'https://apps.apple.com/app/mara/id1',
      });
      expect(live.android, playStoreUrl);
      expect(live.androidStore, isTrue);
      expect(live.ios, 'https://apps.apple.com/app/mara/id1');
      final none = AppLinks.fromJson(const {'android': '', 'ios': null});
      expect(none.android, apkDownloadUrl);
      expect(none.ios, isNull);
      expect(apkDownloadUrl,
          'https://github.com/jkabore97/dbms/releases/latest/download/kaj-arm64-v8a.apk');
    });

    testWidgets('Android before Google Play: the APK; « Plus tard » closes it; the date kept',
        (tester) async {
      final b = _Browser(AppPhone.android);
      await _street(tester, b);
      expect(find.byKey(const Key('app-download')), findsOneWidget);
      expect(find.text('Mara sur votre téléphone'), findsOneWidget);
      expect(find.text('Télécharger pour Android'), findsOneWidget);
      expect(b.shownAt, _now);
      await tester.tap(find.byKey(const Key('app-download-later')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app-download')), findsNothing);
    });

    testWidgets('Android once Google Play is live: the store', (tester) async {
      await _street(tester, _Browser(AppPhone.android),
          links: const AppLinks(android: playStoreUrl, androidStore: true));
      expect(find.text('Ouvrir Google Play'), findsOneWidget);
    });

    testWidgets('iPhone with an App Store address: the App Store', (tester) async {
      await _street(tester, _Browser(AppPhone.ios),
          links: const AppLinks(android: apkDownloadUrl, ios: 'https://apps.apple.com/app/mara/id1'));
      expect(find.text('Ouvrir l\'App Store'), findsOneWidget);
    });

    testWidgets('iPhone with none: how to add Mara to the home screen, no dead button',
        (tester) async {
      await _street(tester, _Browser(AppPhone.ios));
      expect(find.text('Mara sur votre écran d\'accueil'), findsOneWidget);
      expect(find.textContaining('dans Safari, touchez Partager'), findsOneWidget);
      expect(find.byKey(const Key('app-download-go')), findsNothing);
      expect(find.byKey(const Key('app-download-later')), findsOneWidget);
    });

    testWidgets('never on a computer, in the installed web app, or twice in seven days',
        (tester) async {
      await _street(tester, _Browser(null), size: const Size(1280, 800));
      expect(find.byKey(const Key('app-download')), findsNothing);
      await _street(tester, _Browser(AppPhone.android, standalone: true));
      expect(find.byKey(const Key('app-download')), findsNothing);
      final recent = _Browser(AppPhone.android, shownAt: _now.subtract(const Duration(days: 6)));
      await _street(tester, recent);
      expect(find.byKey(const Key('app-download')), findsNothing);
      expect(recent.shownAt, _now.subtract(const Duration(days: 6)), reason: 'not shown, not written');
      await _street(tester, _Browser(AppPhone.ios, shownAt: _now.subtract(const Duration(days: 7))));
      expect(find.byKey(const Key('app-download')), findsOneWidget);
    });

    testWidgets('the Android app (no browser): never', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AppDownloadPrompt(
          links: () async => const AppLinks.fallback(),
          child: const Scaffold(body: Text('La rue')),
        ),
      ));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('app-download')), findsNothing);
    });

    testWidgets('a bottom card: never over the header\'s sign-in corner', (tester) async {
      await _street(tester, _Browser(AppPhone.android));
      final card = tester.getRect(find.byKey(const Key('app-download')));
      final signIn = tester.getRect(find.byKey(const Key('sign-in')));
      expect(card.overlaps(signIn), isFalse);
      expect(card.bottom, closeTo(844 - 12, 1), reason: 'at the bottom');
      await tester.tap(find.byKey(const Key('sign-in')));
    });

    testWidgets('« shown » is written when it is seen: not under a sheet, not in a tab in the background',
        (tester) async {
      // A sheet opened before the card came: it comes under the sheet,
      // unseen; the sheet closed, it is seen — and only then written.
      final b = _Browser(AppPhone.android);
      await _street(tester, b, wait: false);
      await tester.tap(find.byKey(const Key('open-order')));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app-download')), findsOneWidget);
      expect(find.byKey(const Key('app-download')).hitTestable(), findsNothing);
      expect(b.shownAt, isNull, reason: 'covered: not seen');
      Navigator.of(tester.element(find.text('Commande'))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app-download')).hitTestable(), findsOneWidget);
      expect(b.shownAt, _now);

      // The tab in the background when it came: written once back in front.
      final hidden = _Browser(AppPhone.ios);
      await _street(tester, hidden, wait: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(hidden.shownAt, isNull, reason: 'a tab in the background');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(hidden.shownAt, _now);
    });

    testWidgets('an order sheet opened over the page covers it', (tester) async {
      await _street(tester, _Browser(AppPhone.android));
      expect(find.byKey(const Key('app-download')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-order')));
      await tester.pumpAndSettle();
      expect(find.text('Commande'), findsOneWidget);
      expect(find.byKey(const Key('app-download')).hitTestable(), findsNothing,
          reason: 'under the sheet\'s barrier, not over it');
    });
  });

  group('iPhone (S3)', () {
    // Run once with --dart-define=STORE=appstore too: the Codemagic build.
    test('a store build (Google Play, the App Store) never shows the APK banner', () async {
      final check = UpdateCheck(
        currentSha: 'old',
        isWeb: false,
        versionUrl: Uri.parse('https://kaj.test/version.json'),
        fetch: (_) async => '{"sha":"new","apk":"https://x/kaj.apk"}',
      );
      expect(check.fromPlay, installStore == 'play' || installStore == 'appstore');
      await check.check();
      expect(check.shouldShow, !check.fromPlay);
    });
  });
}
