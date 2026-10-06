import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/theme/mara_mark.dart';
import 'package:kaj_app/features/auth/login_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Mara is the app's name and face: the seal and « mara » on the sign-in,
/// the seal as every icon the browser, the home screen and Android show,
/// and Mara on the tab, the install and the launcher. Kaj signs the
/// street's footer (shop_footer_test).
void main() {
  testWidgets('the sign-in opens on Mara\'s seal and name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: const [
          Strings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: Strings.supportedLocales,
        home: LoginScreen(auth: AuthRepository(null), onSignedIn: (_) async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MaraWordmark), findsOneWidget);
    expect(find.bySemanticsLabel('Mara'), findsWidgets);
  });

  test('the icons are Mara\'s, at every size', () {
    const sizes = {
      'web/favicon.png': 32,
      'web/icons/Icon-192.png': 192,
      'web/icons/Icon-512.png': 512,
      'web/icons/Icon-maskable-192.png': 192,
      'web/icons/Icon-maskable-512.png': 512,
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png': 432,
    };
    for (final entry in sizes.entries) {
      final bytes = File(entry.key).readAsBytesSync();
      // PNG width: big-endian at byte 16.
      final width =
          (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      expect(width, entry.value, reason: entry.key);
    }
    for (final a in [
      MaraMark.asset,
      MaraWordmark.asset,
      MaraWordmark.assetDark,
      MaraStacked.asset,
    ]) {
      expect(File(a).existsSync(), isTrue, reason: a);
    }
    expect(File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
        .existsSync(), isTrue);
  });

  test('the tab, the install and the launcher say Mara', () {
    expect(File('web/index.html').readAsStringSync(),
        contains('<title>Mara — les boutiques près de vous</title>'));
    expect(File('web/manifest.json').readAsStringSync(),
        contains('"short_name": "Mara"'));
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:label="Mara"'));
  });
}
