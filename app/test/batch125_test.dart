import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/access/store_rules.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/features/account/pro_sheet.dart';
import 'package:kaj_app/features/admin/spots_card.dart';
import 'package:kaj_app/features/auth/login_screen.dart';
import 'package:kaj_app/features/cauris/unlock_sheet.dart';
import 'package:kaj_app/features/pay/stripe_button.dart';
import 'package:kaj_app/features/pay/wave_buttons.dart';
import 'package:kaj_app/features/pro/pro_plans_screen.dart';
import 'package:kaj_app/features/pro/pro_strip.dart';
import 'package:kaj_app/features/storefront/order_sign_in_sheet.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:kaj_app/main.dart' show appVersion;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient, User;

/// Batch 125: the iPhone app, ready for App Review — the crash reporter's
/// version, Sign in with Apple (4.8) and no sale of digital goods in the
/// App Store build (3.1.1).

/// A sign-in screen's server: which providers are on, and what Apple's
/// sign-in gives back.
class _Server extends AuthRepository {
  _Server() : super(null);

  bool google = true;
  bool apple = true;
  bool live = false;
  User? user;

  /// What signInWithApple answers: the user, null (closed), or a throw.
  Object? appleResult;
  int appleAsked = 0;

  @override
  bool get isConfigured => true;

  @override
  bool get hasLiveSession => live;

  @override
  User? get currentUser => user;

  @override
  Future<bool> googleAvailable() async => google;

  @override
  Future<bool> appleAvailable() async => apple;

  @override
  Future<User?> signInWithApple() async {
    appleAsked++;
    final r = appleResult;
    if (r is Exception || r is Error) throw r!;
    if (r is User) {
      live = true;
      user = r;
      return r;
    }
    return null;
  }

  List<OrgSummary> orgs = const [
    OrgSummary(id: 'shop-1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']),
  ];

  @override
  Future<List<OrgSummary>> fetchOrgs() async => orgs;
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<bool> isPlatformAdmin() async => false;
  @override
  Future<int> claimMyInvitations() async => 0;
  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;
  @override
  Future<List<Promotion>> myPromotions(String orgId) async => const [];
}

const _ali = User(
  id: 'ali-1',
  appMetadata: {'provider': 'apple'},
  userMetadata: {},
  aud: 'authenticated',
  email: 'x7k2@privaterelay.appleid.com',
  createdAt: '2026-10-10T00:00:00Z',
);

const _free = OrgSummary(id: 'o1', name: 'Elim Shop', profile: 'retail', roles: ['owner']);
const _pro = OrgSummary(
    id: 'o1', name: 'Elim Shop', profile: 'retail', roles: ['owner'], plan: 'pro');

/// A token-shaped string whose payload says it expires in an hour.
String _jwt(String sub) {
  String part(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': sub, 'exp': exp, 'role': 'authenticated', 'aud': 'authenticated'})}.sig';
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR');
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    debugSellsDigitalInApp = null;
  });

  // ------------------------------------------------------------------
  // 1. The crash reporter's version
  // ------------------------------------------------------------------

  test('appVersion is pubspec\'s version, before the +', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([^\s+]+)\+', multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml has a version: x.y.z+n line');
    expect(appVersion, m!.group(1),
        reason: 'lib/main.dart appVersion and pubspec.yaml version must move together');
  });

  // ------------------------------------------------------------------
  // 2. Sign in with Apple
  // ------------------------------------------------------------------

  group('Apple: the project\'s switch', () {
    test('reads external.apple, in the same single request as Google', () async {
      var asked = 0;
      final repo = _Probe(MockClient((req) async {
        asked++;
        expect(req.url.path, '/auth/v1/settings');
        return http.Response(
            jsonEncode({
              'external': {'google': true, 'apple': true},
            }),
            200);
      }));
      final both = await Future.wait([repo.googleAvailable(), repo.appleAvailable()]);
      expect(both, [true, true]);
      expect(await repo.appleAvailable(), isTrue);
      expect(asked, 1, reason: 'asked once per launch, for both');
    });

    test('off, or offline: no Apple (and offline is asked again)', () async {
      final off = _Probe(MockClient((_) async => http.Response(
          jsonEncode({
            'external': {'google': true, 'apple': false},
          }),
          200)));
      expect(await off.appleAvailable(), isFalse);
      expect(await off.googleAvailable(), isTrue);

      var calls = 0;
      final down = _Probe(MockClient((_) async {
        calls++;
        throw Exception('no signal');
      }));
      expect(await down.appleAvailable(), isFalse);
      expect(await down.appleAvailable(), isFalse);
      expect(calls, 2, reason: 'an offline answer is not kept');
      expect(await AuthRepository(null).appleAvailable(), isFalse);
    });
  });

  group('Apple: the nonce and the name', () {
    /// A Supabase that records what it is sent.
    ({SupabaseClient client, List<http.Request> sent}) supabase(
        {String? profileName}) {
      final sent = <http.Request>[];
      final client = SupabaseClient(
        'https://x.supabase.co',
        'pk',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((req) async {
          sent.add(req);
          const json = {'content-type': 'application/json; charset=utf-8'};
          final user = {
            'id': 'ali-1',
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'x7k2@privaterelay.appleid.com',
            'app_metadata': {'provider': 'apple'},
            'user_metadata': <String, Object?>{},
            'created_at': '2026-10-10T00:00:00Z',
          };
          if (req.url.path == '/auth/v1/token') {
            return http.Response(
                jsonEncode({
                  'access_token': _jwt('ali-1'),
                  'token_type': 'bearer',
                  'expires_in': 3600,
                  'expires_at': DateTime.now()
                          .add(const Duration(hours: 1))
                          .millisecondsSinceEpoch ~/
                      1000,
                  'refresh_token': 'rt',
                  'user': user,
                }),
                200,
                headers: json, request: req);
          }
          if (req.url.path == '/auth/v1/user') {
            final body = jsonDecode(req.body) as Map;
            return http.Response(
                jsonEncode({...user, 'user_metadata': body['data'] ?? {}}), 200,
                headers: json, request: req);
          }
          if (req.url.path == '/rest/v1/profiles' && req.method == 'GET') {
            return http.Response(
                jsonEncode([
                  {'full_name': profileName},
                ]),
                200,
                headers: json, request: req);
          }
          return http.Response('[]', 200, headers: json, request: req);
        }),
      );
      return (client: client, sent: sent);
    }

    AuthorizationCredentialAppleID credential({String? given, String? family}) =>
        AuthorizationCredentialAppleID(
          userIdentifier: '001.apple',
          state: null,
          givenName: given,
          familyName: family,
          email: 'x7k2@privaterelay.appleid.com',
          authorizationCode: 'code',
          identityToken: 'apple.id.token',
        );

    test('SHA-256 of the nonce to Apple, the raw nonce to Supabase, '
        'email and name asked', () async {
      final s = supabase(profileName: 'Ali Traoré');
      String? toApple;
      final scopesAsked = <AppleIDAuthorizationScopes>[];
      final repo = AuthRepository(s.client,
          appleCredential: ({required scopes, required nonce}) async {
        toApple = nonce;
        scopesAsked.addAll(scopes);
        return credential();
      });
      final user = await repo.signInWithApple();
      expect(user?.id, 'ali-1');

      final token = s.sent.singleWhere((r) => r.url.path == '/auth/v1/token');
      expect(token.url.queryParameters['grant_type'], 'id_token');
      final body = jsonDecode(token.body) as Map;
      expect(body['provider'], 'apple');
      expect(body['id_token'], 'apple.id.token');
      final raw = body['nonce'] as String;
      expect(raw.length, 32);
      expect(toApple, sha256.convert(utf8.encode(raw)).toString(),
          reason: 'Apple seals the hash; Supabase checks the raw nonce against it');
      expect(toApple, isNot(raw));
      expect(scopesAsked, [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName]);
    });

    test('a new nonce every time', () {
      final a = AuthRepository.newNonce(), b = AuthRepository.newNonce();
      expect(a, isNot(b));
      expect(a, matches(RegExp(r'^[0-9A-Za-z\-._]{32}$')));
    });

    test('the name Apple gives the first time is written when the profile '
        'has none', () async {
      final s = supabase(profileName: null);
      final repo = AuthRepository(s.client,
          appleCredential: ({required scopes, required nonce}) async =>
              credential(given: 'Ali', family: 'Traoré'));
      final user = await repo.signInWithApple();
      final update = s.sent.singleWhere((r) => r.url.path == '/auth/v1/user');
      expect((jsonDecode(update.body) as Map)['data'], {'full_name': 'Ali Traoré'});
      final patch = s.sent.singleWhere(
          (r) => r.url.path == '/rest/v1/profiles' && r.method == 'PATCH');
      expect(jsonDecode(patch.body), {'full_name': 'Ali Traoré'});
      expect(user?.userMetadata?['full_name'], 'Ali Traoré',
          reason: 'the device identity is named from it');
    });

    test('a profile that has a name keeps it; no name from Apple writes nothing',
        () async {
      final named = supabase(profileName: 'Ali T.');
      await AuthRepository(named.client,
              appleCredential: ({required scopes, required nonce}) async =>
                  credential(given: 'Ali', family: 'Traoré'))
          .signInWithApple();
      expect(named.sent.where((r) => r.url.path == '/auth/v1/user'), isEmpty);
      expect(named.sent.where((r) => r.method == 'PATCH'), isEmpty);

      final silent = supabase(profileName: null);
      await AuthRepository(silent.client,
              appleCredential: ({required scopes, required nonce}) async => credential())
          .signInWithApple();
      expect(silent.sent.where((r) => r.url.path == '/auth/v1/user'), isEmpty);
    });

    test('closing Apple\'s sheet does nothing: no Supabase call, no error', () async {
      final s = supabase();
      final repo = AuthRepository(s.client,
          appleCredential: ({required scopes, required nonce}) async =>
              throw const SignInWithAppleAuthorizationException(
                  code: AuthorizationErrorCode.canceled, message: 'canceled'));
      expect(await repo.signInWithApple(), isNull);
      expect(s.sent, isEmpty);
    });

    test('any other failure is said, in words', () async {
      final s = supabase();
      final repo = AuthRepository(s.client,
          appleCredential: ({required scopes, required nonce}) async =>
              throw const SignInWithAppleAuthorizationException(
                  code: AuthorizationErrorCode.failed, message: 'failed'));
      await expectLater(
          repo.signInWithApple(),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              "La connexion avec Apple n'a pas abouti. Réessayez.")));
      expect(s.sent, isEmpty);
    });
  });

  group('Apple: the session that results', () {
    late LocalDb db;
    setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
    tearDown(() => db.close());

    SessionController sessionOn(_Server server) => SessionController(
          db: db,
          auth: server,
          admin: _Admin(),
          accounting: AccountingRepository(null),
        );

    test('a business member goes on to the device code, as after Google', () async {
      final server = _Server()..appleResult = _ali;
      final session = sessionOn(server);
      expect(await session.signInWithApple(), isTrue);
      expect(session.phase, SessionPhase.choosingPin);
      expect(session.identity?.userId, 'ali-1');
      expect(session.identity?.email, 'x7k2@privaterelay.appleid.com');
    });

    test('a shopper goes to the street, with no code (108)', () async {
      final server = _Server()
        ..appleResult = _ali
        ..orgs = const [];
      final session = sessionOn(server);
      await session.signInWithApple();
      expect(session.phase, SessionPhase.noOrg);
    });

    test('closed: nothing happens, nothing is kept', () async {
      final server = _Server();
      final session = sessionOn(server);
      expect(await session.signInWithApple(), isFalse);
      expect(session.phase, SessionPhase.booting);
      expect(await db.loadIdentity(), isNull);
    });
  });

  group('Apple: the button', () {
    Future<void> pump(WidgetTester tester, _Server server,
        {Future<void> Function()? onApple, Future<void> Function()? onGoogle}) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: const [
          Strings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: Strings.supportedLocales,
        home: LoginScreen(
          auth: server,
          onSignedIn: (_) async {},
          onGoogle: onGoogle ?? () async {},
          onApple: onApple ?? () async {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    final apple = find.byKey(const Key('apple-sign-in'));
    final google = find.byKey(const Key('google-sign-in'));

    testWidgets('on an iPhone with Apple on: above Google, as tall', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var asked = 0;
      await pump(tester, _Server(), onApple: () async => asked++);
      expect(apple, findsOneWidget);
      expect(find.text('Continuer avec Apple'), findsOneWidget);
      expect(google, findsOneWidget);
      expect(tester.getTopLeft(apple).dy, lessThan(tester.getTopLeft(google).dy));
      expect(tester.getSize(apple).height,
          greaterThanOrEqualTo(tester.getSize(google).height));
      expect(tester.getSize(apple).width, tester.getSize(google).width);
      await tester.tap(apple);
      await tester.pumpAndSettle();
      expect(asked, 1);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('on an iPhone with Apple off: no Apple', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await pump(tester, _Server()..apple = false);
      expect(apple, findsNothing);
      expect(google, findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('on Android: no Apple, even with it on', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pump(tester, _Server());
      expect(apple, findsNothing);
      expect(google, findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    test('the web never offers it (kIsWeb is part of the rule)', () {
      // A VM test cannot be the web; what it can check is that the rule
      // is iOS-and-not-web, so a browser on an iPhone gets no button.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(appleSignInPlatform, !kIsWeb);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(appleSignInPlatform, isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(appleSignInPlatform, isFalse);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a failure is said where Google\'s is; a closed sheet says nothing',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await pump(tester, _Server(),
          onApple: () async =>
              throw StateError("La connexion avec Apple n'a pas abouti. Réessayez."));
      await tester.tap(apple);
      await tester.pumpAndSettle();
      expect(find.text("La connexion avec Apple n'a pas abouti. Réessayez."), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('closed: the screen stays as it was', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      late SessionController session;
      final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
      final server = _Server();
      session = SessionController(
          db: db!, auth: server, admin: _Admin(), accounting: AccountingRepository(null));
      await pump(tester, server, onApple: session.signInWithApple);
      await tester.tap(apple);
      await tester.pumpAndSettle();
      expect(server.appleAsked, 1);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.textContaining('Apple n\'a pas'), findsNothing);
      expect(session.phase, SessionPhase.booting);
      await tester.runAsync(db.close);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('Apple: the vitrine\'s sign-in sheet', () {
    Future<List<OrderSignIn?>> pumpSheet(WidgetTester tester, {bool apple = true}) async {
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final chosen = <OrderSignIn?>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => chosen.add(await showOrderSignInSheet(
                context,
                booking: false,
                googleAvailable: () async => true,
                appleAvailable: () async => apple,
              )),
              child: const Text('Commander'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Commander'));
      await tester.pumpAndSettle();
      return chosen;
    }

    testWidgets('on an iPhone: Apple above Google, and it is the choice', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final chosen = await pumpSheet(tester);
      final apple = find.byKey(const Key('order-sign-in-apple'));
      final google = find.byKey(const Key('order-sign-in-google'));
      expect(apple, findsOneWidget);
      expect(tester.getTopLeft(apple).dy, lessThan(tester.getTopLeft(google).dy));
      expect(tester.getSize(apple).height, greaterThanOrEqualTo(tester.getSize(google).height));
      await tester.tap(apple);
      await tester.pumpAndSettle();
      expect(chosen, [OrderSignIn.apple]);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Apple off, or Android: only Google', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await pumpSheet(tester, apple: false);
      expect(find.byKey(const Key('order-sign-in-apple')), findsNothing);
      expect(find.byKey(const Key('order-sign-in-google')), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Android: only Google', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpSheet(tester);
      expect(find.byKey(const Key('order-sign-in-apple')), findsNothing);
      expect(find.byKey(const Key('order-sign-in-google')), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  test('the iPhone project: Apple\'s entitlement, iPhone only, nothing else lost', () {
    final ent = File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(ent, contains('<key>com.apple.developer.applesignin</key>'));
    expect(ent, contains('<string>Default</string>'));
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'.allMatches(pbx).length, 3,
        reason: 'the Runner target\'s Debug, Release and Profile');
    expect(pbx, isNot(contains('"1,2"')));
    expect('TARGETED_DEVICE_FAMILY = 1;'.allMatches(pbx).length, 3);
    expect('PRODUCT_BUNDLE_IDENTIFIER = bf.kaj.app;'.allMatches(pbx).length, 3);
    expect('IPHONEOS_DEPLOYMENT_TARGET = 15.5;'.allMatches(pbx).length, 3);
    // Only the Runner target's blocks name the entitlements.
    for (final block in RegExp(r'/\* (Debug|Release|Profile) \*/ = \{(.*?)\n\t\t\};', dotAll: true)
        .allMatches(pbx)) {
      final body = block.group(2)!;
      expect(body.contains('CODE_SIGN_ENTITLEMENTS'),
          body.contains('PRODUCT_BUNDLE_IDENTIFIER = bf.kaj.app;'));
    }
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, isNot(contains('~ipad')));
    for (final usage in [
      'NSCameraUsageDescription',
      'NSPhotoLibraryUsageDescription',
      'NSPhotoLibraryAddUsageDescription',
      'NSLocationWhenInUseUsageDescription',
      'NSFaceIDUsageDescription',
    ]) {
      expect(plist, contains('<key>$usage</key>'));
    }
    expect(File('../codemagic.yaml').readAsStringSync(), contains('--dart-define=STORE=appstore'));
  });

  // ------------------------------------------------------------------
  // 3. No sale of digital goods in the iPhone app
  // ------------------------------------------------------------------

  group('the App Store build sells no Pro and no spot', () {
    Future<void> plans(WidgetTester tester, OrgSummary org, {bool cardOn = true}) async {
      tester.view.physicalSize = const Size(800, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final terms = PlanTerms(stripeOn: cardOn, priceMonth: 3000, priceYear: 30000);
      await tester.pumpWidget(MaterialApp(
        home: ProPlansScreen(
          org: org,
          terms: terms,
          admin: _Admin(),
          cardButton: (period) => Container(key: const Key('card-button')),
          cardManage: Container(key: const Key('card-manage')),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    void noSale(WidgetTester tester) {
      expect(find.byKey(const Key('pro-price')), findsNothing);
      expect(find.byKey(const Key('pro-period')), findsNothing);
      expect(find.byKey(const Key('pro-soon')), findsNothing);
      expect(find.byKey(const Key('card-button')), findsNothing);
      expect(find.text('Bientôt disponible'), findsNothing);
      expect(find.textContaining(RegExp(r'F / (an|mois)')), findsNothing);
      expect(find.textContaining('par mois, ou'), findsNothing);
      expect(find.textContaining('passer à Mara Pro'), findsNothing);
    }

    testWidgets('the Pro page: what each plan gives, and no price, no way to pay',
        (tester) async {
      debugSellsDigitalInApp = false;
      await plans(tester, _free);
      noSale(tester);
      expect(find.textContaining('Pointages et paie'), findsOneWidget,
          reason: 'what Pro includes is still said');
      expect(find.text('Mara Pro'), findsWidgets);
    });

    testWidgets('an employee is not told to ask the owner to buy', (tester) async {
      debugSellsDigitalInApp = false;
      await plans(tester, const OrgSummary(
          id: 'o1', name: 'Elim Shop', profile: 'retail', roles: ['employee']));
      noSale(tester);
      expect(find.text('Seul le propriétaire peut passer à Mara Pro.'), findsNothing);
    });

    testWidgets('a Pro business: « Vous êtes sur Mara Pro », no Stripe page',
        (tester) async {
      debugSellsDigitalInApp = false;
      await plans(tester, _pro);
      expect(find.text('Vous êtes sur Mara Pro'), findsOneWidget);
      expect(find.byKey(const Key('card-manage')), findsNothing);
    });

    testWidgets('on Play and the web the same page sells as before', (tester) async {
      debugSellsDigitalInApp = true;
      await plans(tester, _free);
      expect(find.byKey(const Key('pro-price')), findsOneWidget);
      expect(find.byKey(const Key('pro-period')), findsOneWidget);
      expect(find.byKey(const Key('card-button')), findsOneWidget);
    });

    testWidgets('ProPayPanel: the description, « Active », and nothing to buy',
        (tester) async {
      debugSellsDigitalInApp = false;
      Future<void> panel(OrgSummary org) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProPayPanel(
                org: org,
                terms: const PlanTerms(stripeOn: true),
                admin: _Admin(),
                canRequest: true,
                top: Container(key: const Key('card-button')),
              ),
            ),
          ),
        ));
        await tester.pump();
      }

      await panel(_free);
      noSale(tester);
      expect(find.textContaining('Pointages et paie'), findsOneWidget);
      await panel(_pro);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Cette entreprise est sur Mara Pro. Tous les outils ci-dessous sont ouverts.'),
          findsOneWidget);

      debugSellsDigitalInApp = true;
      await panel(_free);
      expect(find.textContaining('par mois, ou'), findsOneWidget);
      expect(find.byKey(const Key('card-button')), findsOneWidget);
    });

    test('no « PRO » strip inviting to upgrade', () {
      debugSellsDigitalInApp = false;
      expect(ProStrip.shownFor(_free), isFalse);
      debugSellsDigitalInApp = true;
      expect(ProStrip.shownFor(_free), isTrue);
      expect(ProStrip.shownFor(_pro), isFalse);
    });

    testWidgets('a locked tool with no cauris door: the neutral sheet, only « Fermer »',
        (tester) async {
      debugSellsDigitalInApp = false;
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => UnlockSheet.open(context, org: _free, feature: 'analytics'),
              child: const Text('Analyses'),
            ),
          ),
        ),
        GoRoute(path: '/o/:id/kaj-pro', builder: (_, _) => const Text('la page Pro')),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('Analyses'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pro-only')), findsOneWidget);
      expect(find.text('Cette fonction fait partie de Mara Pro.'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(TextButton).hitTestable(), findsNothing);
      expect(find.textContaining(RegExp(r'F CFA|Stripe|Wave|carte')), findsNothing);
      await tester.tap(find.byKey(const Key('pro-only-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pro-only')), findsNothing);
      expect(find.text('la page Pro'), findsNothing);

      // On Play and the web: the comparison page, as before.
      debugSellsDigitalInApp = true;
      await tester.tap(find.text('Analyses'));
      await tester.pumpAndSettle();
      expect(find.text('la page Pro'), findsOneWidget);
    });

    testWidgets('cauris still open a tool; only « Ou passer à Mara Pro » goes', (tester) async {
      debugSellsDigitalInApp = false;
      final states = FeatureStates.fromJson({
        'plan': 'free',
        'balance': 500,
        'tools': [
          {'feature': 'analytics', 'cost': 400},
        ],
      });
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UnlockSheet(org: _free, feature: 'analytics', states: states, admin: _Admin()),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('unlock-buy')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('unlock-buy'))).onPressed,
          isNotNull);
      expect(find.byKey(const Key('unlock-earn')), findsOneWidget);
      expect(find.byKey(const Key('unlock-pro')), findsNothing);
    });

    testWidgets('« Mettre en avant »: no new spot, no payment', (tester) async {
      debugSellsDigitalInApp = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SpotsCard(orgId: 'o1', admin: _Admin(), retail: null),
        ),
      ));
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Mettre en avant'), findsNothing);
      expect(find.text('Payer et confirmer'), findsNothing);

      debugSellsDigitalInApp = true;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SpotsCard(key: const Key('again'), orgId: 'o1', admin: _Admin(), retail: null),
        ),
      ));
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Mettre en avant'), findsOneWidget);
    });

    testWidgets('Stripe and Wave draw nothing for Pro or a spot; an order pays as ever',
        (tester) async {
      debugSellsDigitalInApp = false;
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            StripeCardButton(
                orgId: 'o1', terms: PlanTerms(stripeOn: true), period: 'year'),
            StripeManage(orgId: 'o1'),
            WaveButtons(kind: 'pro', ref: 'o1', onUnavailable: Text('à la main')),
            WaveButtons(kind: 'spot', ref: 's1', onUnavailable: Text('à la main')),
            WaveButtons(kind: 'order', ref: 'c1', onUnavailable: Text('payer la commande')),
          ]),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('stripe-card')), findsNothing);
      expect(find.text('à la main'), findsNothing,
          reason: 'not even the old way of paying for a digital good');
      expect(find.text('payer la commande'), findsOneWidget,
          reason: 'a shop\'s goods are paid outside, which Apple allows');
    });
  });
}

/// The real settings probe, on a repository that reports a server.
class _Probe extends AuthRepository {
  _Probe(http.Client client)
      : super(null, authUrl: 'https://x.supabase.co/auth/v1', apiKey: 'pk', httpClient: client);

  @override
  bool get isConfigured => true;
}
