import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/theme/kaj_mark.dart';
import 'package:kaj_app/features/auth/login_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// The owner's logo — KAJ Consulting's K — is the app's face: on the
/// sign-in, and as the icon the browser tab, the home screen and Android
/// show. No stand-in icon anywhere.
void main() {
  testWidgets('the sign-in opens on the KAJ mark', (tester) async {
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
    expect(find.byType(KajMark), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsNothing);
  });

  test('the icons are the official logo, at every size', () {
    // The old icon was a white K on black; the official one is the
    // KAJ Consulting K on its navy ground. Same file names, new pictures:
    // a size mismatch is the cheap tell of a missed one.
    const sizes = {
      'web/favicon.png': 64,
      'web/icons/Icon-192.png': 192,
      'web/icons/Icon-512.png': 512,
      'web/icons/Icon-maskable-192.png': 192,
      'web/icons/Icon-maskable-512.png': 512,
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
    };
    for (final entry in sizes.entries) {
      final bytes = File(entry.key).readAsBytesSync();
      // PNG width: big-endian at byte 16.
      final width =
          (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      expect(width, entry.value, reason: entry.key);
    }
    expect(File(KajMark.asset).existsSync(), isTrue);
  });
}
