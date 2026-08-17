import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/features/admin/create_business_screen.dart';
import 'package:kaj_app/features/auth/no_org_screen.dart';
import 'package:kaj_app/core/auth/models.dart';

/// The screen that makes the first business, and the two rules that decide
/// whether what it sends can work at all.
///
/// The slug becomes a live subdomain, so it is checked here rather than
/// discovered when a hostname fails to resolve. Everything below runs against
/// `AdminRepository(null)` — nothing reaches the network, and the parts under
/// test are pure.
void main() {
  group('slugify', () {
    test('turns a name typed by a person into a hostname', () {
      expect(CreateBusinessScreen.slugify('Église Bethel'), 'eglise-bethel');
      expect(CreateBusinessScreen.slugify('Ignace Poultry'), 'ignace-poultry');
    });

    test('strips the accents that a French name arrives with', () {
      // The whole point: "Église d'Israël" cannot go in a hostname as typed,
      // and dropping the accented letters entirely would leave "glise-d-sral".
      expect(
        CreateBusinessScreen.slugify("Église d'Israël"),
        'eglise-d-israel',
      );
      expect(CreateBusinessScreen.slugify('Ferme Aviçôle'), 'ferme-avicole');
    });

    test('collapses punctuation and never leaves a trailing hyphen', () {
      expect(CreateBusinessScreen.slugify('  Chez  Awa & Fils!  '),
          'chez-awa-fils');
      expect(CreateBusinessScreen.slugify('--Bethel--'), 'bethel');
    });
  });

  group('slugProblem', () {
    test('accepts what the server will accept', () {
      expect(CreateBusinessScreen.slugProblem('eglise-bethel'), isNull);
      expect(CreateBusinessScreen.slugProblem('ferme2'), isNull);
    });

    test('refuses what would not survive as a subdomain', () {
      expect(CreateBusinessScreen.slugProblem('ab'), isNotNull);
      expect(CreateBusinessScreen.slugProblem('Eglise'), isNotNull);
      expect(CreateBusinessScreen.slugProblem('eglise bethel'), isNotNull);
      expect(CreateBusinessScreen.slugProblem('-bethel'), isNotNull);
      expect(CreateBusinessScreen.slugProblem('bethel-'), isNotNull);
      expect(CreateBusinessScreen.slugProblem('a' * 41), isNotNull);
    });
  });

  group('the screen', () {
    Future<void> pump(WidgetTester tester) async {
      // A viewport tall enough to build the whole form. The default 800x600
      // test window leaves the button below the fold of a lazy ListView, where
      // it is never built — and scrolling to it instead unmounts the name
      // field at the top, so `find.byType(TextField).first` then lands on a
      // different field and the text goes somewhere nobody asked for.
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
            locale: const Locale('fr'),
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
            home: CreateBusinessScreen(admin: AdminRepository(null))),
      );
      await tester.pumpAndSettle();
    }

    /// The button's own callback, not its colour: a button styled as disabled
    /// while still firing would pass a pixel check and lose somebody's data.
    VoidCallback? createCallback(WidgetTester tester) {
      return tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text("Créer l'activité"),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed;
    }

    testWidgets('the create button is dead until a name has been typed',
        (tester) async {
      await pump(tester);
      expect(createCallback(tester), isNull);

      await tester.enterText(find.byType(TextField).first, 'Église Bethel');
      await tester.pumpAndSettle();
      expect(createCallback(tester), isNotNull);
    });

    testWidgets('the empty "Autre" profile is no longer offered',
        (tester) async {
      await pump(tester);
      // The three profiles with a real home screen remain; the empty one that
      // made a business with no module is gone.
      expect(find.text('Église'), findsOneWidget);
      expect(find.text('Ferme'), findsOneWidget);
      expect(find.text('Commerce'), findsOneWidget);
      expect(find.text('Autre'), findsNothing);
    });

    testWidgets('typing the name fills the address in', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField).first, 'Ignace Poultry');
      await tester.pumpAndSettle();

      expect(find.text('ignace-poultry'), findsOneWidget);
    });

    testWidgets('an address edited by hand is not overwritten', (tester) async {
      // Regression guard: the name field's listener rewrites the slug on every
      // keystroke, so without the touched flag a deliberate address is undone
      // by the next letter typed above it.
      await pump(tester);
      final fields = find.byType(TextField);

      await tester.enterText(fields.first, 'Église Bethel');
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(1), 'bethel');
      await tester.pumpAndSettle();

      await tester.enterText(fields.first, 'Église Bethel de Ouaga');
      await tester.pumpAndSettle();

      expect(find.text('bethel'), findsOneWidget);
      expect(find.text('eglise-bethel-de-ouaga'), findsNothing);
    });

    testWidgets('a name that slugifies to nothing leaves the button dead',
        (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField).first, '!!!');
      await tester.pumpAndSettle();
      expect(createCallback(tester), isNull);
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
