import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/site/app_download.dart';

/// The SDK's Roboto, so the bar's lines are measured as a phone draws
/// them, not in the test font's squares (one glyph a square).
Future<void> _realFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6 && !Directory('${dir.path}/material_fonts').existsSync(); i++) {
    dir = dir.parent;
  }
  final fonts = Directory('${dir.path}/material_fonts');
  if (!fonts.existsSync()) return;
  final loader = FontLoader('Roboto');
  for (final f in const ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    final file = File('${fonts.path}/$f');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
}

/// Counts how many times it is born: a page built again from nothing.
class _Counted extends StatefulWidget {
  const _Counted({required this.onInit});
  final VoidCallback onInit;
  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('La rue'));
}

/// The Android bar (152): a member on an Android phone's browser is asked
/// for the app, and the bar never goes.
class _Browser {
  _Browser(this.phone, {this.standalone = false});
  final AppPhone? phone;
  final bool standalone;
  AppDownloadEnv get env =>
      AppDownloadEnv(phone: phone, standalone: standalone, readShownAt: () => null, writeShownAt: (_) {});
}

Future<EdgeInsets> _pump(
  WidgetTester tester,
  _Browser browser,
  ValueNotifier<bool> signedIn, {
  AppLinks links = const AppLinks.fallback(),
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  EdgeInsets padding = EdgeInsets.zero;
  await tester.pumpWidget(
    MaterialApp(
      // As main.dart mounts it: around the app's Navigator, so a sheet or a
      // dialog is drawn in the app's part of the screen, above the bar.
      builder: (context, child) => AndroidInstallBar(
        listenable: signedIn,
        signedIn: () => signedIn.value,
        env: browser.env,
        links: () async => links,
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          padding = MediaQuery.of(context).padding;
          return Scaffold(
            body: ListView(
              children: [
                const SizedBox(height: 2000, child: Text('La rue')),
                FilledButton(
                  key: const Key('open-order'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const SizedBox(height: 600, child: Text('Commande')),
                  ),
                  child: const Text('Commander'),
                ),
              ],
            ),
            bottomNavigationBar: const SafeArea(
              top: false,
              child: SizedBox(key: Key('page-foot'), height: 40, child: Text('Pied')),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return padding;
}

void main() {
  setUpAll(_realFonts);

  testWidgets('a member on Android: the bar, no « Plus tard », the whole page above it', (tester) async {
    final signedIn = ValueNotifier(true);
    final padding = await _pump(tester, _Browser(AppPhone.android), signedIn);
    expect(find.byKey(const Key('android-install-bar')), findsOneWidget);
    expect(find.text("Installez l'application Marakaj pour continuer sur Android."), findsOneWidget);
    expect(find.text('Télécharger'), findsOneWidget, reason: 'the APK before Google Play');
    expect(find.byKey(const Key('app-download-later')), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(padding.bottom, 0, reason: 'the bar takes its own strip; the page has no inset to keep');
    // The page's own foot ends where the bar begins.
    final foot = tester.getBottomLeft(find.byKey(const Key('page-foot'))).dy;
    final bar = tester.getRect(find.byKey(const Key('android-install-bar')));
    expect(foot, closeTo(bar.top, 0.01));
    expect(bar.bottom, 844);
    expect(bar.height, lessThan(90), reason: 'two lines and a button');
  });

  testWidgets('a sheet opened in the page comes above the bar, never over it', (tester) async {
    await _pump(tester, _Browser(AppPhone.android), ValueNotifier(true));
    await tester.scrollUntilVisible(find.byKey(const Key('open-order')), 400);
    await tester.tap(find.byKey(const Key('open-order')));
    await tester.pumpAndSettle();
    expect(find.text('Commande'), findsOneWidget);
    final sheet = tester.getRect(find.text('Commande'));
    final bar = tester.getRect(find.byKey(const Key('android-install-bar')));
    expect(sheet.bottom, lessThanOrEqualTo(bar.top + 0.01));
    expect(
      find.byKey(const Key('android-install-go')).hitTestable(),
      findsOneWidget,
      reason: 'the button stays reachable under an open sheet',
    );
  });

  testWidgets('Google Play once the listing is live', (tester) async {
    await _pump(
      tester,
      _Browser(AppPhone.android),
      ValueNotifier(true),
      links: const AppLinks(android: playStoreUrl, androidStore: true),
    );
    expect(find.text('Google Play'), findsOneWidget);
  });

  testWidgets('a narrow phone with large text: the words whole, the button under them', (tester) async {
    await _pump(tester, _Browser(AppPhone.android), ValueNotifier(true), width: 320, scale: 1.3);
    final words = tester.getRect(find.text("Installez l'application Marakaj pour continuer sur Android."));
    final button = tester.getRect(find.byKey(const Key('android-install-go')));
    expect(button.top, greaterThanOrEqualTo(words.bottom));
    expect(tester.takeException(), isNull, reason: 'no overflow');
  });

  testWidgets('a stranger (the welcome gate is theirs), then signed in: the bar comes', (tester) async {
    final signedIn = ValueNotifier(false);
    await _pump(tester, _Browser(AppPhone.android), signedIn);
    expect(find.byKey(const Key('android-install-bar')), findsNothing);
    signedIn.value = true;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('android-install-bar')), findsOneWidget);
  });

  testWidgets('the bar coming does not build the app under it again', (tester) async {
    var built = 0;
    final signedIn = ValueNotifier(false);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AndroidInstallBar(
          listenable: signedIn,
          signedIn: () => signedIn.value,
          env: _Browser(AppPhone.android).env,
          links: () async => const AppLinks.fallback(),
          child: child!,
        ),
        home: _Counted(onInit: () => built++),
      ),
    );
    await tester.pumpAndSettle();
    expect(built, 1);
    signedIn.value = true;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('android-install-bar')), findsOneWidget);
    expect(built, 1, reason: 'the page was built again from nothing — its scroll and questions lost');
    signedIn.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('android-install-bar')), findsNothing);
    expect(built, 1);
  });

  testWidgets('the website installed on the home screen is not the app: the bar there too', (tester) async {
    await _pump(tester, _Browser(AppPhone.android, standalone: true), ValueNotifier(true));
    expect(find.byKey(const Key('android-install-bar')), findsOneWidget);
  });

  testWidgets('never on an iPhone, a computer or the Android app', (tester) async {
    for (final b in [_Browser(AppPhone.ios), _Browser(null)]) {
      await _pump(tester, b, ValueNotifier(true));
      expect(find.byKey(const Key('android-install-bar')), findsNothing, reason: '${b.phone}');
    }
    await tester.pumpWidget(
      MaterialApp(
        home: AndroidInstallBar(
          listenable: ValueNotifier(true),
          signedIn: () => true,
          env: const AppDownloadEnv.none(),
          links: () async => const AppLinks.fallback(),
          child: const Text('app'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('android-install-bar')), findsNothing);
  });
}
