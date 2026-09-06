import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/update/update_banner.dart';
import 'package:kaj_app/core/update/update_check.dart';

/// The app knows which build it is and whether a newer one is out.
///
/// The gap this closes: the web app updates on every reload, the Android
/// app never — a phone kept the APK it was installed with and nothing told
/// it otherwise. Every build now carries its commit, the deploy writes the
/// deployed commit beside the app, and the banner says when they differ.
void main() {
  group('version.json', () {
    test('parses the deployed build and its download link', () {
      final info = UpdateInfo.parse(
          '{"sha":"abc123","apk":"https://x/kaj.apk","built_at":"2026-09-06T02:00:00Z"}');
      expect(info, isNotNull);
      expect(info!.sha, 'abc123');
      expect(info.apkUrl, 'https://x/kaj.apk');
      expect(info.builtAt, DateTime.utc(2026, 9, 6, 2));
    });

    test('anything else is not an update', () {
      // A Worker answering index.html for an unknown path, an empty body, a
      // file with no sha: none of these may become a banner.
      expect(UpdateInfo.parse('<!doctype html><html></html>'), isNull);
      expect(UpdateInfo.parse(''), isNull);
      expect(UpdateInfo.parse('{"apk":"x"}'), isNull);
      expect(UpdateInfo.parse('{"sha":"   "}'), isNull);
    });
  });

  group('the check', () {
    UpdateCheck make(String current, String deployed,
        {bool isWeb = false, List<Uri>? asked}) {
      return UpdateCheck(
        currentSha: current,
        isWeb: isWeb,
        versionUrl: Uri.parse('https://kaj.test/version.json'),
        fetch: (uri) async {
          asked?.add(uri);
          return '{"sha":"$deployed","apk":"https://x/kaj.apk"}';
        },
      );
    }

    test('a different deployed commit is newer; the same one is not',
        () async {
      final asked = <Uri>[];
      final check = make('old', 'new', asked: asked);
      await check.check();
      expect(check.shouldShow, isTrue);
      expect(check.available!.apkUrl, 'https://x/kaj.apk');
      // Cache-busted: the one file that must never be served stale.
      expect(asked.single.queryParameters.containsKey('t'), isTrue);

      final same = make('new', 'new');
      await same.check();
      expect(same.shouldShow, isFalse);
    });

    test('a build with no commit of its own never shows the banner',
        () async {
      final local = make('', 'new');
      await local.check();
      expect(local.shouldShow, isFalse);
    });

    test('no signal is not news', () async {
      final check = UpdateCheck(
        currentSha: 'old',
        versionUrl: Uri.parse('https://kaj.test/version.json'),
        fetch: (_) async => throw Exception('offline'),
      );
      await check.check();
      expect(check.shouldShow, isFalse);
    });

    test('"Plus tard" hides it until the next newer build', () async {
      var deployed = 'new';
      final check = UpdateCheck(
        currentSha: 'old',
        versionUrl: Uri.parse('https://kaj.test/version.json'),
        fetch: (_) async => '{"sha":"$deployed"}',
      );
      await check.check();
      check.dismiss();
      expect(check.shouldShow, isFalse);
      // The same build again: still dismissed.
      await check.check();
      expect(check.shouldShow, isFalse);
      // A newer one: shown again.
      deployed = 'newer';
      await check.check();
      expect(check.dismissed, isTrue,
          reason: 'dismissal is per session, the sentence is the same');
      expect(check.available!.sha, 'newer');
    });
  });

  group('the banner', () {
    testWidgets('says download on a phone and reload in a browser, and hides',
        (tester) async {
      final phone = UpdateCheck(
        currentSha: 'old',
        isWeb: false,
        versionUrl: Uri.parse('https://kaj.test/version.json'),
        fetch: (_) async => '{"sha":"new","apk":"https://x/kaj.apk"}',
      );
      await phone.check();
      await tester.pumpWidget(MaterialApp(
        home: UpdateBanner(
            check: phone, child: const Scaffold(body: Text('la page'))),
      ));
      expect(find.text('Une nouvelle version de Kaj est disponible.'),
          findsOneWidget);
      expect(find.text('Télécharger'), findsOneWidget);
      expect(find.text('la page'), findsOneWidget);

      await tester.tap(find.text('Plus tard'));
      await tester.pump();
      expect(find.text('Télécharger'), findsNothing);
      expect(find.text('la page'), findsOneWidget);

      final tab = UpdateCheck(
        currentSha: 'old',
        isWeb: true,
        versionUrl: Uri.parse('https://kaj.test/version.json'),
        fetch: (_) async => '{"sha":"new"}',
      );
      await tab.check();
      await tester.pumpWidget(MaterialApp(
        home: UpdateBanner(
            check: tab, child: const Scaffold(body: Text('la page'))),
      ));
      expect(find.text('Une nouvelle version de Kaj est en ligne.'),
          findsOneWidget);
      expect(find.text('Recharger'), findsOneWidget);
    });

    testWidgets('a current build draws nothing at all', (tester) async {
      final check = UpdateCheck(
        currentSha: 'same',
        versionUrl: Uri.parse('https://kaj.test/version.json'),
        fetch: (_) async => '{"sha":"same"}',
      );
      await check.check();
      await tester.pumpWidget(MaterialApp(
        home: UpdateBanner(
            check: check, child: const Scaffold(body: Text('la page'))),
      ));
      expect(find.text('Plus tard'), findsNothing);
      expect(find.text('la page'), findsOneWidget);
    });
  });
}
