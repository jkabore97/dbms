import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/features/auth/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Creating an account.
///
/// Before this, the only way into the app was to be invited by somebody who
/// already had it, and the only way to be the first person was for
/// Kaj-consulting to run an INSERT. A business owner who heard about the app
/// could not start; an employee handed a code could not use it, because there
/// was no account for the code to attach to.
///
/// The order the screen has to teach is: make the account, then join the
/// business. Those are separate acts, and nothing about creating an account
/// grants access to anybody's books — the invitation code does that, on the
/// waiting screen this one leads to.
///
/// The client here points at a host that does not resolve. Everything asserted
/// below happens before any request is made; the one case that would need the
/// network is left to the SQL suites and to a real project, which is stated in
/// BUILD_PLAN.md rather than faked here.
void main() {
  setUpAll(() async {
    // The sign-up form prints the chosen birth date in French.
    await initializeDateFormatting('fr_FR', null);
  });

  late SupabaseClient client;
  late AuthRepository auth;

  setUp(() {
    client = SupabaseClient(
      'https://kaj-tests.invalid',
      'sb_publishable_not_a_real_key',
    );
    auth = AuthRepository(client);
  });

  tearDown(() => client.dispose());

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(auth: auth, onSignedIn: (_) async {}),
      ),
    );
    await tester.pump();
  }

  testWidgets('creating an account is offered beside signing in',
      (tester) async {
    await pumpLogin(tester);

    // Two words side by side, not a link at the bottom of a form. Half the
    // people who need this are reading in poor light on a cracked screen, and
    // "pas encore de compte ?" in eleven-point grey is where they give up.
    expect(find.text('Se connecter'), findsWidgets);
    expect(find.text('Créer un compte'), findsOneWidget);
  });

  testWidgets('signing in asks for an address and a password, and nothing else',
      (tester) async {
    await pumpLogin(tester);

    expect(find.widgetWithText(TextField, 'E-mail'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Mot de passe'), findsOneWidget);
    // Somebody who already has an account has already told us all of this.
    expect(find.widgetWithText(TextField, 'Prénom'), findsNothing);
    expect(find.widgetWithText(TextField, 'Nom de famille'), findsNothing);
    expect(find.widgetWithText(TextField, 'Confirmez le numéro'), findsNothing);
  });

  testWidgets('there is no SMS route left to find', (tester) async {
    // The removal is the assertion. A screen that still offers "recevoir le
    // code" is a screen that still spends money on SMS and still fails in the
    // places this app exists for, whatever the repository no longer exposes.
    await pumpLogin(tester);

    expect(find.text('Recevoir le code'), findsNothing);
    expect(find.text('Utiliser mon numéro de téléphone'), findsNothing);
    expect(find.text('Utiliser un e-mail et un mot de passe'), findsNothing);
    expect(find.widgetWithText(TextField, 'Numéro de téléphone'), findsNothing);
  });

  testWidgets('creating an account asks who somebody is', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();

    // The whole of it, on the form that creates the account — not on a
    // screen afterwards. These end up on a contract and a payslip, and one
    // "Votre nom" field cannot produce a family name to sort a staff list by.
    expect(find.widgetWithText(TextField, 'Prénom'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Deuxième prénom (facultatif)'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Nom de famille'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Fonction (facultatif)'),
        findsOneWidget);
    expect(find.text('Date de naissance'), findsOneWidget);

    // Twice, for the keyboard rather than the server: this is the number a
    // manager sends an invitation to.
    expect(find.widgetWithText(TextField, 'Numéro de téléphone'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Confirmez le numéro'),
        findsOneWidget);

    expect(find.text('Créer mon compte'), findsOneWidget);

    // And the screen says what happens next, because the account on its own
    // opens nothing.
    expect(
      find.textContaining('Vous rejoindrez une activité'),
      findsOneWidget,
    );
  });

  testWidgets('creating an account asks for an address and a password',
      (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Prénom'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Nom de famille'), findsOneWidget);
    // The number is still asked for, and is no longer a credential: it is how
    // a manager reaches somebody, and what an invitation is pinned to.
    expect(find.widgetWithText(TextField, 'Confirmez le numéro'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'E-mail'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Mot de passe'), findsOneWidget);
    expect(find.text('Au moins 6 caractères'), findsOneWidget);
    expect(find.text('Créer mon compte'), findsOneWidget);
  });

  testWidgets('a short password is refused before the network is touched',
      (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();

    // The identity fields are above the password on the form, so an empty
    // form complains about them first. Filled in here so the assertion below
    // is about the password rule and not about the order of the fields.
    await tester.enterText(find.widgetWithText(TextField, 'Prénom'), 'Israel');
    await tester.enterText(
        find.widgetWithText(TextField, 'Nom de famille'), 'SAWADOGO');
    await tester.tap(find.text('Date de naissance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Numéro de téléphone'), '70123456');
    await tester.enterText(
        find.widgetWithText(TextField, 'Confirmez le numéro'), '70123456');
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, 'E-mail'),
      'israel@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Mot de passe'),
      '123',
    );
    await tester.tap(find.text('Créer mon compte'));
    await tester.pump();

    expect(
      find.text('Le mot de passe doit contenir au moins 6 caractères.'),
      findsOneWidget,
    );
  });

  testWidgets('a malformed address is refused before the network is touched',
      (tester) async {
    await pumpLogin(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'E-mail'),
      'israel',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Mot de passe'),
      'longuemotdepasse',
    );
    await tester.tap(find.text('Se connecter').last);
    await tester.pump();

    expect(find.text('Entrez une adresse e-mail valide.'), findsOneWidget);
  });

  group('the error a new user actually hits', () {
    test('an unknown address is told to create an account, not that signups '
        'are disabled', () {
      // The literal string Supabase returns when signInWithOtp is called with
      // shouldCreateUser: false and the number has never been seen. Raw, it
      // reads as a policy refusal and sends somebody looking for a setting.
      final message = AuthRepository.describeError(
        const AuthException('Signups not allowed for otp'),
      );
      expect(message, contains('Créer un compte'));
    });

    test('an existing account is told to sign in', () {
      final message = AuthRepository.describeError(
        const AuthException('User already registered'),
      );
      expect(message, contains('Se connecter'));
    });
  });

  group('phone numbers', () {
    // The sign-up path normalises the same way the sign-in path does, so a
    // number typed one way on Monday and another way on Friday is one account.
    test('a local number gains the country code', () {
      expect(AuthRepository.normalizePhone('70 12 34 56'), '+22670123456');
    });

    test('a trunk prefix is dropped before the code', () {
      expect(AuthRepository.normalizePhone('070123456'), '+22670123456');
    });

    test('an international number is left alone', () {
      expect(AuthRepository.normalizePhone('+33 6 12 34 56 78'),
          '+33612345678');
    });
  });
}
