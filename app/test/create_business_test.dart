import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:kaj_app/core/onboarding/business_creation.dart';
import 'package:kaj_app/features/auth/no_org_screen.dart';
import 'package:kaj_app/core/auth/models.dart';

/// The two rules that decide whether a business's address can work at all
/// (once the platform admin's own form's; that form is gone since 154b —
/// everybody creates a business through « Créer mon activité »).
///
/// The slug becomes a live subdomain, so it is checked here rather than
/// discovered when a hostname fails to resolve. Nothing below reaches the network: the parts under test are pure.
void main() {
  group('slugify', () {
    test('turns a name typed by a person into a hostname', () {
      expect(slugify('Église Bethel'), 'eglise-bethel');
      expect(slugify('Ignace Poultry'), 'ignace-poultry');
    });

    test('strips the accents that a French name arrives with', () {
      // The whole point: "Église d'Israël" cannot go in a hostname as typed,
      // and dropping the accented letters entirely would leave "glise-d-sral".
      expect(
        slugify("Église d'Israël"),
        'eglise-d-israel',
      );
      expect(slugify('Ferme Aviçôle'), 'ferme-avicole');
    });

    test('collapses punctuation and never leaves a trailing hyphen', () {
      expect(slugify('  Chez  Awa & Fils!  '),
          'chez-awa-fils');
      expect(slugify('--Bethel--'), 'bethel');
    });
  });

  group('slugProblem', () {
    test('accepts what the server will accept', () {
      expect(slugProblem('eglise-bethel'), isNull);
      expect(slugProblem('ferme2'), isNull);
    });

    test('refuses what would not survive as a subdomain', () {
      expect(slugProblem('ab'), isNotNull);
      expect(slugProblem('Eglise'), isNotNull);
      expect(slugProblem('eglise bethel'), isNotNull);
      expect(slugProblem('-bethel'), isNotNull);
      expect(slugProblem('bethel-'), isNotNull);
      expect(slugProblem('a' * 41), isNotNull);
    });
  });

  group('the waiting screen', () {
    const identity = LocalIdentity(userId: 'u1', phone: '+22670000001');

    testWidgets('offers nothing to create for an ordinary user',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          home: NoOrgScreen(
            identity: identity,
            onRetry: () async {},
            onSignOut: () {},
            onJoinByCode: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Créer une activité'), findsNothing);
      expect(find.text("J'ai un code"), findsOneWidget);
    });

    testWidgets('is where a platform admin makes the first business',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          home: NoOrgScreen(
            identity: identity,
            onRetry: () async {},
            onSignOut: () {},
            onJoinByCode: () {},
            onCreateBusiness: () => tapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Créer une activité'));
      expect(tapped, isTrue);
    });
  });
}
