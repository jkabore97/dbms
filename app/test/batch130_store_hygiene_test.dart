// Batch 130 §5: store hygiene.
//
//   * the iPhone app's privacy manifest: no tracking, the required-reason
//     APIs with their reasons, the data collected — and it is in the app
//     bundle (the Runner target's resources);
//   * Codemagic stops first when a value the build needs is empty;
//   * at sign-up the date of birth and the number are optional, never
//     blocking — and the privacy page says the date of birth is asked.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/features/auth/login_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records the sign-up it is asked for; answers with no user (refused), so
/// the screen stops there.
class _Auth extends AuthRepository {
  _Auth() : super(null);
  final signUps = <String>[];

  @override
  bool get isConfigured => true;
  @override
  Future<bool> googleAvailable() async => false;
  @override
  Future<bool> appleAvailable() async => false;
  @override
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    signUps.add('$email|$fullName');
    return AuthResponse();
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  group('the privacy manifest', () {
    final manifest = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();

    test('no tracking; the required-reason APIs, each with its reason', () {
      expect(manifest, contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
      expect(manifest, contains('<key>NSPrivacyTrackingDomains</key>\n\t<array/>'));
      for (final (api, reason) in [
        ('NSPrivacyAccessedAPICategoryUserDefaults', 'CA92.1'),
        ('NSPrivacyAccessedAPICategoryFileTimestamp', 'C617.1'),
        ('NSPrivacyAccessedAPICategorySystemBootTime', '35F9.1'),
        ('NSPrivacyAccessedAPICategoryDiskSpace', 'E174.1'),
      ]) {
        expect(RegExp('<string>$api</string>\\s*<key>NSPrivacyAccessedAPITypeReasons</key>\\s*'
                    '<array>\\s*<string>$reason</string>')
                .hasMatch(manifest),
            isTrue,
            reason: api);
      }
    });

    test('the data collected, as the privacy page says it', () {
      for (final type in [
        'Name', 'EmailAddress', 'PhoneNumber', 'PhysicalAddress', 'PreciseLocation',
        'PhotosorVideos', 'PurchaseHistory', 'UserID', 'DeviceID', 'OtherUserContent',
        'OtherDataTypes', 'CrashData',
      ]) {
        expect(manifest, contains('<string>NSPrivacyCollectedDataType$type</string>'), reason: type);
      }
      expect('NSPrivacyCollectedDataTypeTracking</key>\n\t\t\t<true/>'.allMatches(manifest), isEmpty);
      // Crash reports carry no name (Sentry): not linked to the person.
      expect(
          RegExp(r'<string>NSPrivacyCollectedDataTypeCrashData</string>\s*'
                  r'<key>NSPrivacyCollectedDataTypeLinked</key>\s*<false/>')
              .hasMatch(manifest),
          isTrue);
    });

    test('it is in the app bundle: a Runner resource', () {
      final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect('PrivacyInfo.xcprivacy in Resources'.allMatches(pbx).length, 2,
          reason: 'the build file, and the Runner target\'s resources phase');
      expect(pbx, contains('path = PrivacyInfo.xcprivacy; sourceTree = "<group>";'));
      expect(pbx, contains('PRODUCT_BUNDLE_IDENTIFIER = bf.kaj.app;'));
    });
  });

  test('Codemagic: the first script stops on an empty value, by name', () {
    final yaml = File('../codemagic.yaml').readAsStringSync();
    final scripts = yaml.substring(yaml.indexOf('    scripts:'));
    final first = scripts.indexOf('- name: The values this build needs are set');
    expect(first, greaterThan(0));
    expect(first, lessThan(scripts.indexOf('- name: Firebase')));
    expect(first, lessThan(scripts.indexOf('- name: Build the ipa')));
    for (final name in ['SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'ACCOUNT_ADMIN_URL', 'PAY_URL', 'UPLOADS_URL']) {
      expect(scripts, contains(name));
    }
    expect(scripts, contains('exit 1'));
  });

  group('sign-up: the date of birth and the number are optional', () {
    Future<_Auth> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(480, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final auth = _Auth();
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: LoginScreen(auth: auth, onSignedIn: (_) async {}, startWithSignUp: true),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Prénom'), 'Awa');
      await tester.enterText(find.widgetWithText(TextField, 'Nom de famille'), 'OUEDRAOGO');
      await tester.enterText(find.widgetWithText(TextField, 'E-mail'), 'awa@example.com');
      await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), 'longuemotdepasse');
      return auth;
    }

    testWidgets('neither given: the account is asked for', (tester) async {
      final auth = await pump(tester);
      expect(find.text('Date de naissance (facultatif)'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Numéro de téléphone (facultatif)'), findsOneWidget);
      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(auth.signUps, ['awa@example.com|Awa OUEDRAOGO']);
    });

    testWidgets('a number given once only is asked again; given twice, it goes', (tester) async {
      final auth = await pump(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Numéro de téléphone (facultatif)'), '70123456');
      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(auth.signUps, isEmpty);
      await tester.enterText(find.widgetWithText(TextField, 'Confirmez le numéro'), '70123456');
      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(auth.signUps, hasLength(1));
    });
  });

  test('the privacy page names the optional date of birth and the stores\' billing', () {
    final legal = File('lib/features/account/legal_screens.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r"'\s*\n\s*'"), '')
        .replaceAll(r"\'", "'");
    expect(legal, contains('votre date de naissance si vous la donnez (elle n\'est jamais obligatoire)'));
    expect(legal, contains('Apple (l\'App Store) et Google (Google Play) pour l\'abonnement Marakaj Pro'));
    expect(legal, contains('Si vous êtes le seul propriétaire d\'une activité, elle est supprimée avec votre compte'));
    expect(legal, contains("'# Marakaj Pro'"));
  });
}
