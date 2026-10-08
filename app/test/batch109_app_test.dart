import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/whatsapp_phone.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/auth/login_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/features/storefront/whatsapp_verify_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, PostgrestException, User;

/// Batch 109, builder F: a stranger browses and fills a basket, and is
/// asked to sign in only at « Commander » — Google first, the two other
/// doors at the bottom — and comes back to the same basket, the order
/// opening again by itself (F1). Before the order, a number proved on
/// WhatsApp when the platform asks for one; nothing asked when it does not
/// (F2, P1).

class _Server extends AuthRepository {
  _Server() : super(null);

  bool live = false;
  User? user;
  int launches = 0;
  bool google = true;
  bool failGoogle = false;

  @override
  bool get isConfigured => true;
  @override
  bool get hasLiveSession => live;
  @override
  User? get currentUser => user;
  @override
  Future<bool> googleAvailable() async => google;
  @override
  Future<void> signInWithGoogle() async {
    if (failGoogle) throw StateError("La page de connexion Google n'a pas pu s'ouvrir.");
    launches++;
  }

  @override
  Future<List<OrgSummary>> fetchOrgs() async => const [];
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<bool> isPlatformAdmin() async => false;
  @override
  Future<int> claimMyInvitations() async => 0;
  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;
}

class _Window extends StorefrontRepository {
  _Window() : super(null);
  int orders = 0;
  String? orderedPhone;
  Object? refuse;

  @override
  bool get isConfigured => true;
  @override
  Future<PublicShop?> shop(String slug) async =>
      PublicShop(orgId: 'o1', name: 'Boutique Awa', slug: slug, profile: 'retail');
  @override
  Future<List<PublicItem>> items(String slug) async => const [_soap];
  @override
  Future<String> placeOrder(
    String slug, {
    required Map<String, double> lines,
    required String fulfilment,
    String? note,
    String? address,
    String? phone,
    String payment = 'cash',
    double? dropLat,
    double? dropLng,
  }) async {
    final r = refuse;
    if (r != null) throw r;
    orders++;
    orderedPhone = phone;
    return 'order-1';
  }
}

/// WhatsApp, as Supabase and the Worker answer it — no network.
class _Phone implements WhatsAppPhone {
  _Phone(this.answer);

  OrderPhoneGate? answer;
  final sent = <String>[];
  final confirmed = <String>[];
  Object? sendError;
  String goodCode = '123456';

  int asked = 0;

  @override
  Future<OrderPhoneGate?> gate() async {
    asked++;
    return answer;
  }

  @override
  Future<void> sendCode(String e164) async {
    final e = sendError;
    if (e != null) throw e;
    sent.add(e164);
  }

  @override
  Future<void> confirm(String e164, String code) async {
    if (code != goodCode) {
      throw const AuthException('Token has expired or is invalid', statusCode: '403', code: 'otp_expired');
    }
    confirmed.add('$e164:$code');
  }
}

const _soap = PublicItem(id: 'p1', name: 'Savon', price: 500, inStock: true);

const _awa = User(
  id: 'awa-1',
  appMetadata: {'provider': 'google'},
  userMetadata: {'full_name': 'Awa Ouédraogo'},
  aud: 'authenticated',
  email: 'awa@example.com',
  createdAt: '2026-10-08T00:00:00Z',
);

const _slug = 'boutique-awa';
const _resumeKey = 'street_order_after_sign_in';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  SessionController sessionOn(_Server server) => SessionController(
        db: db,
        auth: server,
        admin: _Admin(),
        accounting: AccountingRepository(null),
      );

  /// A stranger: nothing on the device.
  Future<SessionController> stranger(WidgetTester tester, _Server server) async {
    final s = sessionOn(server);
    await tester.runAsync(s.boot);
    expect(s.phase, SessionPhase.signedOut);
    return s;
  }

  /// Somebody signed in with no business: a shopper.
  Future<SessionController> shopper(WidgetTester tester, _Server server) async {
    server
      ..live = true
      ..user = _awa;
    final s = sessionOn(server);
    await tester.runAsync(s.resolveOrgs);
    expect(s.phase, SessionPhase.noOrg);
    return s;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The vitrine inside a little router: /s/:slug, the sign-in page and
  /// « Mes commandes », so a `go` is seen.
  Future<GoRouter> openVitrine(
    WidgetTester tester,
    SessionController session, {
    _Window? window,
    WhatsAppPhone? phone,
    bool basket = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (basket) {
      await tester.runAsync(() => db.writePref('street_basket_$_slug', jsonEncode({'p1': 2})));
    }
    final router = GoRouter(initialLocation: Routes.storefront(_slug), routes: [
      GoRoute(
        path: '/s/:slug',
        builder: (_, state) => StorefrontScreen(
          slug: state.pathParameters['slug']!,
          storefront: window ?? _Window(),
          capture: CaptureRepository(null, db: db),
          session: session,
          whatsApp: phone ?? _Phone(null),
        ),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (_, state) => Scaffold(body: Text('connexion ${state.uri.query}')),
      ),
      GoRoute(path: Routes.myOrders, builder: (_, _) => const Scaffold(body: Text('mes commandes'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      locale: const Locale('fr'),
    ));
    await settle(tester);
    return router;
  }

  Finder orderButton() => find.widgetWithText(FilledButton, 'Commander').first;

  Future<void> tapOrder(WidgetTester tester) async {
    await tester.ensureVisible(orderButton());
    await tester.pump();
    await tester.tap(orderButton());
    await settle(tester);
  }

  group('F1 — signed out, the street is open and only the order asks', () {
    testWidgets('« Commander » opens the sheet: Google first and big, the two other doors at the bottom',
        (tester) async {
      final session = await stranger(tester, _Server());
      await openVitrine(tester, session);
      expect(find.text('Savon'), findsWidgets, reason: 'a stranger browses the vitrine');
      expect(orderButton(), findsOneWidget, reason: 'the basket kept on the device is there');
      await tapOrder(tester);

      expect(find.text('Connectez-vous pour commander'), findsOneWidget);
      expect(find.text('Votre panier est gardé : vous revenez ici juste après.'), findsOneWidget);
      final google = find.byKey(const Key('order-sign-in-google'));
      final other = find.byKey(const Key('order-sign-in-other'));
      final create = find.byKey(const Key('order-sign-in-create'));
      expect(google, findsOneWidget);
      expect(find.text('Continuer avec Google'), findsOneWidget);
      expect(find.text('Se connecter autrement'), findsOneWidget);
      expect(find.text('Créer un compte'), findsOneWidget);
      expect(tester.getTopLeft(google).dy, lessThan(tester.getTopLeft(other).dy), reason: 'Google first');
      // At the bottom, one above the other on a phone (390 px), full width.
      expect(tester.getTopLeft(other).dy, lessThan(tester.getTopLeft(create).dy));
      expect(tester.getSize(other).width, tester.getSize(google).width);
      expect(tester.getSize(google).height, greaterThanOrEqualTo(56));
      // The big one is the filled one; the two others are quieter.
      expect(tester.widget(google), isA<FilledButton>());
      expect(tester.widget(other), isA<OutlinedButton>());
      expect(tester.widget(create), isA<OutlinedButton>());
      expect(tester.getSize(other).height, greaterThanOrEqualTo(48), reason: 'a thumb-sized door');
    });

    testWidgets('Google from the sheet: the way back and the order kept on the device, the basket untouched',
        (tester) async {
      final server = _Server();
      final session = await stranger(tester, server);
      await openVitrine(tester, session);
      await tapOrder(tester);
      await tester.tap(find.byKey(const Key('order-sign-in-google')));
      await settle(tester);

      expect(server.launches, 1);
      // On the web Google comes back as a reload: the device keeps the page.
      expect(await tester.runAsync(() => db.readPref('google_return_to')), Routes.storefront(_slug));
      expect(await tester.runAsync(() => db.readPref('google_pending')), isNotNull);
      final pending = await tester.runAsync(() => db.readPref(_resumeKey));
      expect(pending, startsWith('$_slug|'));
      final basket = await tester.runAsync(() => db.readPref('street_basket_$_slug'));
      expect(jsonDecode(basket!), {'p1': 2});
    });

    testWidgets('« Se connecter autrement » and « Créer un compte » go to the sign-in page, which comes back here',
        (tester) async {
      final session = await stranger(tester, _Server());
      var router = await openVitrine(tester, session);
      await tapOrder(tester);
      await tester.tap(find.byKey(const Key('order-sign-in-other')));
      await settle(tester);
      expect(router.routeInformationProvider.value.uri.path, Routes.signIn);
      expect(find.text('connexion '), findsOneWidget);
      expect(session.takeReturnTo(), Routes.storefront(_slug));

      router = await openVitrine(tester, session);
      await tapOrder(tester);
      await tester.tap(find.byKey(const Key('order-sign-in-create')));
      await settle(tester);
      expect(find.text('connexion compte=nouveau'), findsOneWidget);
      expect(session.takeReturnTo(), Routes.storefront(_slug));
    });

    testWidgets('« Se connecter autrement », then back without signing in: nothing waits to surprise later',
        (tester) async {
      final server = _Server();
      final session = await stranger(tester, server);
      final router = await openVitrine(tester, session);
      await tapOrder(tester);
      await tester.tap(find.byKey(const Key('order-sign-in-other')));
      await settle(tester);
      expect(find.text('connexion '), findsOneWidget);
      // Back to the vitrine, still signed out.
      router.go(Routes.storefront(_slug));
      await settle(tester);
      expect(await tester.runAsync(() => db.readPref(_resumeKey)), isNull, reason: 'the order to resume forgotten');
      expect(session.takeReturnTo(), isNull, reason: 'the way back forgotten');
      expect(await tester.runAsync(() => db.readPref('street_basket_$_slug')), isNotNull,
          reason: 'the basket stays');
      // Signed in later, from wherever: no order sheet by itself.
      server
        ..live = true
        ..user = _awa;
      await tester.runAsync(session.resolveOrgs);
      await settle(tester);
      expect(find.text('Votre commande'), findsNothing);
    });

    testWidgets('closing the sheet leaves nothing behind', (tester) async {
      final session = await stranger(tester, _Server());
      await openVitrine(tester, session);
      await tapOrder(tester);
      await tester.tapAt(const Offset(195, 40));
      await settle(tester);
      expect(find.text('Connectez-vous pour commander'), findsNothing);
      expect(await tester.runAsync(() => db.readPref(_resumeKey)), isNull);
      expect(session.takeReturnTo(), isNull);
    });

    testWidgets('a project with Google off: the sheet keeps the two doors', (tester) async {
      final session = await stranger(tester, _Server()..google = false);
      await openVitrine(tester, session);
      await tapOrder(tester);
      expect(find.byKey(const Key('order-sign-in-google')), findsNothing);
      expect(find.byKey(const Key('order-sign-in-other')), findsOneWidget);
      expect(find.byKey(const Key('order-sign-in-create')), findsOneWidget);
    });

    testWidgets('Google refused: said, nothing launched', (tester) async {
      final server = _Server()..failGoogle = true;
      final session = await stranger(tester, server);
      await openVitrine(tester, session);
      await tapOrder(tester);
      await tester.tap(find.byKey(const Key('order-sign-in-google')));
      await settle(tester);
      expect(find.textContaining('Google'), findsWidgets);
      expect(server.launches, 0);
      expect(await tester.runAsync(() => db.readPref('google_return_to')), isNull);
    });

    testWidgets('back signed in on the vitrine: the same basket, the order opens by itself, once', (tester) async {
      final session = await shopper(tester, _Server());
      // What the sheet left on the device, and the way back the router took.
      await tester.runAsync(() => db.writePref(_resumeKey, '$_slug|${DateTime.now().toIso8601String()}'));
      session.stashReturnTo(Routes.storefront(_slug));
      final window = _Window();
      await openVitrine(tester, session, window: window, phone: _Phone(null));

      expect(find.text('Votre commande'), findsOneWidget, reason: 'the order sheet opened by itself');
      expect(find.text('2 × Savon'), findsOneWidget, reason: 'the basket kept');
      expect(await tester.runAsync(() => db.readPref(_resumeKey)), isNull, reason: 'once');
      expect(session.takeReturnTo(), isNull, reason: 'the way back is used up: nothing sends the shopper here again');
      // And it is sent as before.
      await tester.tap(find.text('Envoyer la commande'));
      await settle(tester);
      expect(window.orders, 1);
      expect(find.text('mes commandes'), findsOneWidget);
    });

    testWidgets('an order begun long ago, or at another vitrine, does not open by itself', (tester) async {
      final session = await shopper(tester, _Server());
      final old = DateTime.now().subtract(const Duration(hours: 2)).toIso8601String();
      await tester.runAsync(() => db.writePref(_resumeKey, '$_slug|$old'));
      await openVitrine(tester, session);
      expect(find.text('Votre commande'), findsNothing);
      expect(await tester.runAsync(() => db.readPref(_resumeKey)), isNull, reason: 'a stale note is dropped');

      await tester.runAsync(() => db.writePref(_resumeKey, 'autre-boutique|${DateTime.now().toIso8601String()}'));
      await openVitrine(tester, session);
      expect(find.text('Votre commande'), findsNothing);
      expect(await tester.runAsync(() => db.readPref(_resumeKey)), startsWith('autre-boutique|'),
          reason: 'another vitrine keeps its own');
    });

    test('Google on the web: the page survives the reload; refused, nothing is kept', () async {
      final server = _Server();
      final before = sessionOn(server);
      before.stashReturnTo(Routes.storefront(_slug));
      await before.signInWithGoogle();
      expect(await db.readPref('google_return_to'), Routes.storefront(_slug));

      // The reload: a new controller, memory empty, Google's session in hand.
      server
        ..live = true
        ..user = _awa;
      final after = sessionOn(server);
      expect(await after.adoptGoogleSession(), isTrue);
      expect(await db.readPref('google_return_to'), isNull);
      expect(after.takeReturnTo(), Routes.storefront(_slug));

      final refused = sessionOn(_Server()..failGoogle = true);
      refused.stashReturnTo('/s/x');
      await expectLater(refused.signInWithGoogle(), throwsA(isA<StateError>()));
      expect(await db.readPref('google_return_to'), isNull);
      expect(await db.readPref('google_pending'), isNull);
    });

    testWidgets('the sign-in page opens on « Créer un compte » when asked', (tester) async {
      tester.view.physicalSize = const Size(420, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      Future<void> page(bool signUp) async {
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          locale: const Locale('fr'),
          home: LoginScreen(
              key: ValueKey(signUp),
              auth: _Server()..google = false,
              onSignedIn: (_) async {},
              startWithSignUp: signUp),
        ));
        await tester.pump();
      }

      await page(true);
      expect(find.text('Prénom'), findsOneWidget, reason: 'the sign-up form');
      expect(find.text('Créer mon compte'), findsOneWidget);
      // From a vitrine: a shopper's line, not « rejoindrez une activité ».
      expect(find.text('Créez votre compte pour commander.'), findsOneWidget);
      expect(find.textContaining('rejoindrez une activité'), findsNothing);
      await page(false);
      expect(find.text('Prénom'), findsNothing);
      // Opened plainly and switched to « Créer un compte »: the joining line.
      await tester.tap(find.text('Créer un compte').first);
      await tester.pump();
      expect(find.textContaining('rejoindrez une activité'), findsOneWidget);
      expect(find.text('Créez votre compte pour commander.'), findsNothing);
    });

    test('the router: the street and every vitrine open signed out; « Mes commandes » asks to sign in', () {
      final source = File('lib/core/nav/router.dart').readAsStringSync();
      // Both public before any phase is looked at.
      final open = source.indexOf('at(Routes.directory) ||');
      expect(open, isNot(-1));
      expect(source.indexOf("here.startsWith('/s/')", open), greaterThan(open));
      expect(source.indexOf('switch (session.phase)'), greaterThan(open),
          reason: 'the street is answered before the phases');
      // My orders is not among them: signed out, it goes through sign-in.
      expect(source.substring(open - 600, open).contains('Routes.myOrders'), isFalse);
      // The page « Créer un compte » opens.
      expect(source.contains("state.uri.queryParameters['compte'] == 'nouveau'"), isTrue);
    });
  });

  group('F2 — a number proved on WhatsApp before the order, when the platform asks', () {
    testWidgets('off (as installed): the order sheet as before, its optional number field', (tester) async {
      final session = await shopper(tester, _Server());
      final phone = _Phone(const OrderPhoneGate(required: false, verified: false));
      await openVitrine(tester, session, phone: phone);
      await tapOrder(tester);
      expect(find.byType(WhatsAppVerifyScreen), findsNothing);
      expect(find.text('Votre commande'), findsOneWidget);
      expect(find.text('Votre numéro (facultatif)'), findsOneWidget);
      expect(find.byKey(const Key('order-proved-phone')), findsNothing);
    });

    testWidgets('a database before 109 (no answer): nothing asked here', (tester) async {
      final session = await shopper(tester, _Server());
      await openVitrine(tester, session, phone: _Phone(null));
      await tapOrder(tester);
      expect(find.byType(WhatsAppVerifyScreen), findsNothing);
      expect(find.text('Votre numéro (facultatif)'), findsOneWidget);
    });

    testWidgets('on, no proved number: the number, the code on WhatsApp, then the order with that number',
        (tester) async {
      final session = await shopper(tester, _Server());
      final phone = _Phone(const OrderPhoneGate(required: true, verified: false));
      final window = _Window();
      await openVitrine(tester, session, window: window, phone: phone);
      await tapOrder(tester);

      expect(find.byType(WhatsAppVerifyScreen), findsOneWidget);
      expect(find.text('Votre commande'), findsNothing, reason: 'no order before the number');
      expect(find.text('BF'), findsOneWidget, reason: 'Burkina Faso unless chosen');
      final send = find.byKey(const Key('whatsapp-send'));
      // Too short for Burkina Faso: said, and the button waits.
      await tester.enterText(find.descendant(of: find.byKey(const Key('whatsapp-number')), matching: find.byType(EditableText)), '7012');
      await tester.pump();
      expect(find.text('8 chiffres pour Burkina Faso (+226)'), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(send).onPressed, isNull);
      await tester.enterText(find.descendant(of: find.byKey(const Key('whatsapp-number')), matching: find.byType(EditableText)), '70 12 34 56');
      await tester.pump();
      await tester.tap(send);
      await settle(tester);
      expect(phone.sent, ['+22670123456']);
      expect(find.text('Code envoyé sur WhatsApp au +22670123456.'), findsOneWidget);

      // « Renvoyer » waits a minute.
      expect(find.textContaining('Renvoyer le code dans'), findsOneWidget);
      await tester.pump(const Duration(seconds: 61));
      expect(find.text('Renvoyer le code'), findsOneWidget);

      // A wrong code: said, in words.
      await tester.enterText(find.byKey(const Key('whatsapp-code')), '000000');
      await settle(tester);
      expect(find.text('Code faux ou expiré. Vérifiez les 6 chiffres, ou demandez un nouveau code.'), findsOneWidget);
      // The right one, typed: no button to hunt for.
      await tester.enterText(find.byKey(const Key('whatsapp-code')), '123456');
      await settle(tester);
      expect(phone.confirmed, ['+22670123456:123456']);
      expect(find.byType(WhatsAppVerifyScreen), findsNothing);

      // The order sheet, with the proved number instead of the field.
      expect(find.text('Votre commande'), findsOneWidget);
      expect(find.text('Votre numéro WhatsApp vérifié : +22670123456'), findsOneWidget);
      expect(find.text('Votre numéro (facultatif)'), findsNothing);
      await tester.tap(find.text('Envoyer la commande'));
      await settle(tester);
      expect(window.orders, 1);
      expect(window.orderedPhone, isNull, reason: 'the server writes the proved number');
    });

    testWidgets('asked once per visit; refused at the order (the switch turned on since), asked again',
        (tester) async {
      final session = await shopper(tester, _Server());
      final phone = _Phone(const OrderPhoneGate(required: false, verified: false));
      final window = _Window()
        ..refuse = const PostgrestException(message: 'Vérifiez d\'abord votre numéro WhatsApp', code: 'P0001');
      await openVitrine(tester, session, window: window, phone: phone);
      await tapOrder(tester);
      expect(phone.asked, 1);
      await tester.tap(find.text('Envoyer la commande'));
      await settle(tester);
      expect(find.text('Vérifiez d\'abord votre numéro WhatsApp'), findsOneWidget, reason: 'said in the sheet');
      Navigator.of(tester.element(find.text('Votre commande'))).pop();
      await settle(tester);
      // The platform's switch is on now.
      phone.answer = const OrderPhoneGate(required: true, verified: false);
      await tapOrder(tester);
      expect(phone.asked, 2);
      expect(find.byType(WhatsAppVerifyScreen), findsOneWidget);
    });

    testWidgets('on, already proved: straight to the order, the number said', (tester) async {
      final session = await shopper(tester, _Server());
      final phone = _Phone(const OrderPhoneGate(required: true, verified: true, phone: '+22670999999'));
      await openVitrine(tester, session, phone: phone);
      await tapOrder(tester);
      expect(find.byType(WhatsAppVerifyScreen), findsNothing);
      expect(find.text('Votre numéro WhatsApp vérifié : +22670999999'), findsOneWidget);
    });

    testWidgets('leaving the number screen sends nothing', (tester) async {
      final session = await shopper(tester, _Server());
      final window = _Window();
      await openVitrine(tester, session, window: window,
          phone: _Phone(const OrderPhoneGate(required: true, verified: false)));
      await tapOrder(tester);
      await tester.tap(find.byTooltip('Fermer'));
      await settle(tester);
      expect(find.byType(WhatsAppVerifyScreen), findsNothing);
      expect(find.text('Votre commande'), findsNothing);
      expect(window.orders, 0);
    });

    test('what went wrong, in words: Supabase\'s codes and the Worker\'s sentences', () {
      String say(Object e, {bool confirming = false}) => whatsAppProblem('fr', e, confirming: confirming);
      expect(say(const AuthException('Phone number already registered', code: 'phone_exists')),
          'Ce numéro est déjà celui d\'un autre compte Mara.');
      expect(say(const AuthException('For security purposes, you can only request this after 42 seconds.',
              statusCode: '429', code: 'over_sms_send_rate_limit')),
          'Patientez une minute avant de demander un nouveau code.');
      expect(say(const AuthException('Ce numéro ne reçoit pas WhatsApp. Vérifiez-le, ou essayez un autre numéro.',
              statusCode: '422')),
          'Ce numéro ne reçoit pas WhatsApp. Vérifiez-le, ou essayez un autre numéro.');
      expect(say(const AuthException('Token has expired or is invalid', code: 'otp_expired'), confirming: true),
          startsWith('Code faux ou expiré'));
      expect(say(StateError('x')), 'Le code n\'a pas pu partir sur WhatsApp. Réessayez dans un moment.');
      expect(say(StateError('x'), confirming: true), startsWith('Le code n\'a pas pu être vérifié'));
      expect(whatsAppProblem('en', const AuthException('x', code: 'phone_exists')),
          'This number already belongs to another Mara account.');
    });

    testWidgets('a number refused by Supabase is said on the screen', (tester) async {
      final phone = _Phone(null)
        ..sendError = const AuthException('Phone number already registered', code: 'phone_exists');
      await tester.pumpWidget(MaterialApp(home: WhatsAppVerifyScreen(phone: phone)));
      await tester.enterText(find.descendant(of: find.byKey(const Key('whatsapp-number')), matching: find.byType(EditableText)), '70123456');
      await tester.pump();
      await tester.tap(find.byKey(const Key('whatsapp-send')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('whatsapp-error')), findsOneWidget);
      expect(find.text('Ce numéro est déjà celui d\'un autre compte Mara.'), findsOneWidget);
      expect(find.byKey(const Key('whatsapp-code')), findsNothing, reason: 'still on the number');
    });

    test('the server\'s refusal has its English', () {
      expect(translate('en', 'Vérifiez d\'abord votre numéro WhatsApp'), 'Check your WhatsApp number first');
      expect(translate('en', 'Connectez-vous pour commander'), 'Sign in to order');
    });

    test('the migration and the app agree on the gate\'s answer and the refusal', () {
      final sql = File('../database/migrations/109_shopper_order_gate.sql').readAsStringSync();
      for (final key in ["'required'", "'verified'", "'phone'"]) {
        expect(sql.contains(key), isTrue, reason: key);
      }
      expect(sql.contains("raise exception 'Vérifiez d''abord votre numéro WhatsApp'"), isTrue);
      expect(sql.contains("('order_phone_verified', 'false')"), isTrue, reason: 'off as installed');
      final gate = OrderPhoneGate.fromJson({'required': true, 'verified': false, 'phone': null});
      expect(gate.mustVerify, isTrue);
      expect(OrderPhoneGate.fromJson({'required': false, 'verified': false}).mustVerify, isFalse);
      expect(OrderPhoneGate.fromJson({'required': true, 'verified': true, 'phone': '+226'}).mustVerify, isFalse);
    });

    testWidgets('Réglages: the switch, off, with what must be set up first', (tester) async {
      final center = _Center({'order_phone_verified': const SettingValue(value: false)});
      await tester.pumpWidget(MaterialApp(home: SettingsSection(center: center)));
      await tester.pump();
      await tester.pump();
      final row = find.byKey(const Key('setting-order_phone_verified'));
      await tester.scrollUntilVisible(row, 200);
      await tester.ensureVisible(row);
      await tester.pump();
      expect(find.text('Commandes de la rue'), findsOneWidget);
      expect(find.text('Numéro WhatsApp vérifié avant de commander'), findsOneWidget);
      expect(find.textContaining('whatsapp-otp'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(row).value, isFalse);
      await tester.tap(row);
      await tester.pump();
      await tester.pump();
      expect(center.calls, ['set:order_phone_verified=true']);
    });
  });
}

class _Center extends CommandCenterRepository {
  _Center(this.values) : super(null);
  final Map<String, SettingValue> values;
  final calls = <String>[];

  @override
  Future<Map<String, SettingValue>> settings() async => values;

  @override
  Future<String?> setSetting(String key, Object? value) async {
    calls.add('set:$key=$value');
    return null;
  }
}
