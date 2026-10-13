// Batch 139: « Continuer avec Apple » on the website (marakaj.com).
//
//   * the website draws Apple's button only when Réglages' « Connexion
//     Apple sur le site » is on (sign_in_options().apple_web, 135) and the
//     project has Apple on — above Google, as on the iPhone (AU-1);
//   * it is Apple's JS popup for the Services ID with a hashed nonce, and
//     Apple's identity token goes to Supabase's signInWithIdToken exactly
//     as on the iPhone — no OAuth redirect for Apple, so no client secret
//     and nothing that expires; the name of the first authorisation is
//     saved the iPhone's way;
//   * the iPhone is unchanged (Apple's native sheet), Android has no Apple;
//   * the vitrine's « Connectez-vous pour commander » the same;
//   * « Supprimer mon compte » on the website asks Apple's popup for the
//     Services ID's code, and says whose it is.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/auth/login_screen.dart';
import 'package:kaj_app/features/storefront/order_sign_in_sheet.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _project = 'https://proj.supabase.co';

/// A token-shaped string whose payload says it expires in an hour.
String _jwt(String sub) {
  String part(Map<String, Object?> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': sub, 'exp': exp, 'role': 'authenticated', 'aud': 'authenticated'})}.sig';
}

AuthorizationCredentialAppleID _credential({String? given, String? family, String code = 'code-web'}) =>
    AuthorizationCredentialAppleID(
      userIdentifier: null,
      state: null,
      givenName: given,
      familyName: family,
      email: 'x7k2@privaterelay.appleid.com',
      authorizationCode: code,
      identityToken: 'apple.web.id.token',
    );

/// A real AuthRepository on a real (PKCE) Supabase client whose network
/// is faked: /auth/v1/settings says which providers are on, the RPC
/// sign_in_options what Réglages says.
class _Real {
  _Real({this.appleOn = true, this.webSwitch = true, this.rpcStatus = 200, this.profileName}) {
    final mock = MockClient((r) async {
      requests.add(r);
      const json = {'content-type': 'application/json; charset=utf-8'};
      final user = {
        'id': 'awa-1',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'x7k2@privaterelay.appleid.com',
        'app_metadata': {'provider': 'apple', 'providers': ['apple']},
        'user_metadata': <String, Object?>{},
        'created_at': '2026-10-13T00:00:00Z',
      };
      if (r.url.path == '/auth/v1/token') {
        return http.Response(
            jsonEncode({
              'access_token': _jwt('awa-1'),
              'token_type': 'bearer',
              'expires_in': 3600,
              'expires_at': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
              'refresh_token': 'rt',
              'user': user,
            }),
            200,
            headers: json,
            request: r);
      }
      if (r.url.path == '/auth/v1/user') {
        final body = jsonDecode(r.body) as Map;
        return http.Response(jsonEncode({...user, 'user_metadata': body['data'] ?? {}}), 200,
            headers: json, request: r);
      }
      if (r.url.path == '/rest/v1/profiles' && r.method == 'GET') {
        return http.Response(jsonEncode([{'full_name': profileName}]), 200, headers: json, request: r);
      }
      if (r.url.path == '/rest/v1/profiles') {
        return http.Response('[]', 200, headers: json, request: r);
      }
      if (r.url.path == '/auth/v1/settings') {
        return http.Response(jsonEncode({'external': {'google': true, 'apple': appleOn}}), 200);
      }
      if (r.url.path == '/rest/v1/rpc/sign_in_options') {
        if (rpcStatus != 200) {
          return http.Response(
              jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function public.sign_in_options'}),
              rpcStatus,
              request: r);
        }
        return http.Response(jsonEncode({'apple_web': webSwitch}), 200,
            headers: {'content-type': 'application/json'}, request: r);
      }
      return http.Response('{}', 404);
    });
    client = SupabaseClient(_project, 'sb_publishable_test',
        httpClient: mock, authOptions: const AuthClientOptions(autoRefreshToken: false));
    repo = AuthRepository(client,
        authUrl: '$_project/auth/v1',
        apiKey: 'sb_publishable_test',
        httpClient: mock,
        webOrigin: () => 'https://marakaj.com',
        // Apple's popup: what it was asked, and what it answers.
        appleWebCredential: ({required scopes, required nonce}) async {
          popups.add((scopes: scopes, nonce: nonce));
          final r = popupAnswer;
          if (r is Exception) throw r;
          return r as AuthorizationCredentialAppleID;
        },
        // The iPhone's native sheet must never be asked on the website.
        appleCredential: ({required scopes, required nonce}) async =>
            throw StateError('the native sheet on the website'));
  }

  final bool appleOn;
  final bool webSwitch;
  final int rpcStatus;
  final String? profileName;
  final requests = <http.Request>[];
  final popups = <({List<AppleIDAuthorizationScopes> scopes, String nonce})>[];
  Object popupAnswer = _credential(given: 'Awa', family: 'Ouédraogo');
  late final SupabaseClient client;
  late final AuthRepository repo;
}

/// A sign-in screen's server: which switches are on, and who asked what.
class _Server extends AuthRepository {
  _Server({this.webApple = true, this.user, super.appleWebCredential}) : super(null);

  /// The project's Apple: on.
  final bool apple = true;
  final bool webApple;
  final calls = <String>[];
  final User? user;

  @override
  User? get currentUser => user;
  @override
  bool get isConfigured => true;
  @override
  Future<bool> googleAvailable() async => true;
  @override
  Future<bool> appleAvailable() async {
    calls.add('appleAvailable');
    return apple;
  }

  @override
  Future<bool> appleWebAvailable() async {
    calls.add('appleWebAvailable');
    return webApple && appleWebPlatform;
  }

  @override
  Future<User?> signInWithApple({Future<void>? ready}) async {
    calls.add('signInWithApple');
    return null;
  }
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
}

Widget _app(Widget home, {String locale = 'fr'}) => MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

Future<void> _size(WidgetTester tester, double w, double h) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

final _apple = find.byKey(const Key('apple-sign-in'));
final _google = find.byKey(const Key('google-sign-in'));

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR');
  });
  tearDown(() {
    debugAppleWebOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  group('the website\'s switch', () {
    test('on: Réglages\' switch and the project\'s Apple, both asked', () async {
      debugAppleWebOverride = true;
      final s = _Real();
      expect(await s.repo.appleWebAvailable(), isTrue);
      expect(s.requests.map((r) => r.url.path), containsAll(['/rest/v1/rpc/sign_in_options', '/auth/v1/settings']));
    });

    test('off when the switch is off, when Apple is off, or the database has no 135', () async {
      debugAppleWebOverride = true;
      expect(await _Real(webSwitch: false).repo.appleWebAvailable(), isFalse);
      expect(await _Real(appleOn: false).repo.appleWebAvailable(), isFalse);
      expect(await _Real(rpcStatus: 404).repo.appleWebAvailable(), isFalse);
      expect(await AuthRepository(null).appleWebAvailable(), isFalse);
    });

    test('not the website (an app): never asked, never on', () async {
      debugAppleWebOverride = false;
      final s = _Real();
      expect(await s.repo.appleWebAvailable(), isFalse);
      expect(s.requests, isEmpty);
    });
  });

  group('signing in with Apple on the website', () {
    test('Apple\'s popup with the SHA-256 of the nonce; its identity token and the raw nonce to signInWithIdToken', () async {
      debugAppleWebOverride = true;
      final s = _Real(profileName: 'Awa Ouédraogo');
      final user = await s.repo.signInWithApple();
      expect(user?.id, 'awa-1');
      expect(s.popups, hasLength(1));
      expect(s.popups.single.scopes, [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName]);
      final token = s.requests.singleWhere((r) => r.url.path == '/auth/v1/token');
      expect(token.url.queryParameters['grant_type'], 'id_token');
      final body = jsonDecode(token.body) as Map;
      expect(body['provider'], 'apple');
      expect(body['id_token'], 'apple.web.id.token');
      final raw = body['nonce'] as String;
      expect(s.popups.single.nonce, sha256.convert(utf8.encode(raw)).toString(),
          reason: 'Apple seals the hash; Supabase checks the raw nonce against it');
      // No OAuth for Apple: nothing to /authorize, nothing that needs a
      // client secret.
      expect(s.requests.where((r) => r.url.path.contains('authorize')), isEmpty);
      expect(s.client.auth.currentUser?.id, 'awa-1');
    });

    test('the name of the first authorisation is written when the profile has none — the iPhone\'s way', () async {
      debugAppleWebOverride = true;
      final s = _Real(profileName: null);
      await s.repo.signInWithApple();
      final put = s.requests.singleWhere((r) => r.url.path == '/auth/v1/user');
      expect((jsonDecode(put.body) as Map)['data'], {'full_name': 'Awa Ouédraogo'});
      expect(s.requests.where((r) => r.url.path == '/rest/v1/profiles' && r.method == 'PATCH'), hasLength(1));

      // A profile already named: nothing overwritten.
      final named = _Real(profileName: 'Awa O.');
      await named.repo.signInWithApple();
      expect(named.requests.where((r) => r.url.path == '/auth/v1/user'), isEmpty);
    });

    test('the popup closed: nothing said, nobody signed in; Apple\'s refusal: said', () async {
      debugAppleWebOverride = true;
      final closed = _Real()
        ..popupAnswer = const SignInWithAppleCredentialsException(
            message: 'Authentication failed with popup_closed_by_user');
      expect(await closed.repo.signInWithApple(), isNull);
      expect(closed.requests.where((r) => r.url.path == '/auth/v1/token'), isEmpty);
      final cancelled = _Real()
        ..popupAnswer = const SignInWithAppleCredentialsException(
            message: 'Authentication failed with user_cancelled_authorize');
      expect(await cancelled.repo.signInWithApple(), isNull);
      final refused = _Real()
        ..popupAnswer = const SignInWithAppleCredentialsException(message: 'Authentication failed with invalid_client');
      await expectLater(refused.repo.signInWithApple(), throwsA(isA<StateError>()));
    });

    test('the popup could not open (blocked, or Apple\'s script too late): « touch again », not a dead end', () async {
      debugAppleWebOverride = true;
      final blocked = _Real()
        ..popupAnswer = const SignInWithAppleCredentialsException(
            message: 'Authentication failed with popup_blocked_by_browser');
      await expectLater(
          blocked.repo.signInWithApple(),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', AuthRepository.appleWebBlocked)));
      final noScript = _Real()
        ..popupAnswer = const SignInWithAppleNotSupportedException(message: 'Sign in with Apple JS did not load');
      await expectLater(
          noScript.repo.signInWithApple(),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', AuthRepository.appleWebBlocked)));
      expect(blocked.requests.where((r) => r.url.path == '/auth/v1/token'), isEmpty);
    });

    test('what the caller had to do first is awaited after Apple answers, before the session is taken', () async {
      debugAppleWebOverride = true;
      final s = _Real(profileName: 'Awa');
      final ready = Completer<void>();
      final signing = s.repo.signInWithApple(ready: ready.future);
      await pumpEventQueue();
      expect(s.popups, hasLength(1), reason: 'the popup is asked without waiting');
      expect(s.requests.where((r) => r.url.path == '/auth/v1/token'), isEmpty,
          reason: 'the session waits for the device\'s notes');
      ready.complete();
      expect((await signing)?.id, 'awa-1');
    });

    test('the iPhone keeps its native sheet, never the popup', () async {
      debugAppleWebOverride = false;
      final s = _Real();
      var native = 0;
      final repo = AuthRepository(s.client,
          appleWebCredential: ({required scopes, required nonce}) async => throw StateError('the popup on the iPhone'),
          appleCredential: ({required scopes, required nonce}) async {
            native++;
            return _credential();
          });
      expect((await repo.signInWithApple())?.id, 'awa-1');
      expect(native, 1);
    });

    test('the session: the popup\'s user taken at once, no note left for a return trip', () async {
      debugAppleWebOverride = true;
      final server = _Server();
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      final session = SessionController(db: db, auth: server, admin: _Admin(), accounting: AccountingRepository(null));
      addTearDown(session.dispose);
      expect(await session.signInWithApple(), isFalse, reason: 'the fake closes the popup');
      expect(server.calls, ['signInWithApple']);
      expect(await db.readPref('google_pending'), isNull);
    });

    test('the session asks Apple within the tap: nothing on the device is waited for first', () async {
      debugAppleWebOverride = true;
      final server = _Server();
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      await db.writePref('google_pending', DateTime.now().toIso8601String());
      final session = SessionController(db: db, auth: server, admin: _Admin(), accounting: AccountingRepository(null));
      addTearDown(session.dispose);
      var noted = false;
      final before = Future<void>.delayed(const Duration(milliseconds: 20), () => noted = true);
      final signing = session.signInWithApple(before: before);
      // Synchronously, in the same turn as the tap: Apple already asked.
      expect(server.calls, ['signInWithApple']);
      expect(await signing, isFalse);
      expect(noted, isTrue, reason: 'the vitrine\'s note is awaited all the same');
      expect(await db.readPref('google_pending'), isNull, reason: 'the Google note still cleared');
    });
  });

  group('the sign-in screen', () {
    Future<void> pump(WidgetTester tester, _Server server, {double w = 390, double h = 844}) async {
      await _size(tester, w, h);
      await tester.pumpWidget(_app(LoginScreen(
        auth: server,
        onSignedIn: (_) async {},
        onGoogle: () async {},
        onApple: () async => server.calls.add('onApple'),
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('the website, switch on: Apple above Google, as tall; a tap leaves for Apple', (tester) async {
      debugAppleWebOverride = true;
      final server = _Server();
      await pump(tester, server);
      expect(_apple, findsOneWidget);
      expect(_google, findsOneWidget);
      expect(tester.getTopLeft(_apple).dy, lessThan(tester.getTopLeft(_google).dy));
      expect(tester.getSize(_apple).height, tester.getSize(_google).height);
      expect(tester.getSize(_apple).width, tester.getSize(_google).width);
      expect(server.calls, contains('appleWebAvailable'));
      expect(server.calls, isNot(contains('appleAvailable')),
          reason: 'the website asks its own switch, which asks the project');
      await tester.tap(_apple);
      await tester.pumpAndSettle();
      expect(server.calls, contains('onApple'));
    });

    testWidgets('the website, switch off: Google alone, as before', (tester) async {
      debugAppleWebOverride = true;
      await pump(tester, _Server(webApple: false));
      expect(_apple, findsNothing);
      expect(_google, findsOneWidget);
    });

    testWidgets('the iPhone is unchanged: the project\'s Apple, never the website\'s switch', (tester) async {
      debugAppleWebOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final server = _Server(webApple: false);
      await pump(tester, server);
      expect(_apple, findsOneWidget);
      expect(tester.getTopLeft(_apple).dy, lessThan(tester.getTopLeft(_google).dy));
      expect(server.calls, ['appleAvailable']);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Android: Google and the e-mail, no Apple', (tester) async {
      debugAppleWebOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final server = _Server();
      await pump(tester, server);
      expect(_apple, findsNothing);
      expect(_google, findsOneWidget);
      expect(server.calls, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('the vitrine\'s sign-in sheet', () {
    Future<List<OrderSignIn?>> pumpSheet(WidgetTester tester, {required bool web, bool on = true}) async {
      await _size(tester, 390, 844);
      final chosen = <OrderSignIn?>[];
      await tester.pumpWidget(_app(Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => chosen.add(await showOrderSignInSheet(
              context,
              booking: false,
              googleAvailable: () async => true,
              appleAvailable: () async => true,
              appleWebAvailable: () async => on,
            )),
            child: const Text('Commander'),
          ),
        ),
      )));
      await tester.tap(find.text('Commander'));
      await tester.pumpAndSettle();
      return chosen;
    }

    final apple = find.byKey(const Key('order-sign-in-apple'));
    final google = find.byKey(const Key('order-sign-in-google'));

    testWidgets('the website, switch on: Apple above Google, as tall, and it is the choice', (tester) async {
      debugAppleWebOverride = true;
      final chosen = await pumpSheet(tester, web: true);
      expect(apple, findsOneWidget);
      expect(tester.getTopLeft(apple).dy, lessThan(tester.getTopLeft(google).dy));
      expect(tester.getSize(apple).height, tester.getSize(google).height);
      await tester.tap(apple);
      await tester.pumpAndSettle();
      expect(chosen, [OrderSignIn.apple]);
    });

    testWidgets('the website, switch off: Google first, no Apple', (tester) async {
      debugAppleWebOverride = true;
      await pumpSheet(tester, web: true, on: false);
      expect(apple, findsNothing);
      expect(google, findsOneWidget);
    });

    testWidgets('Android: no Apple whatever the switch says', (tester) async {
      debugAppleWebOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpSheet(tester, web: false);
      expect(apple, findsNothing);
      expect(google, findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('« Supprimer mon compte » on the website', () {
    const appleUser = User(
      id: 'u1',
      appMetadata: {'provider': 'apple', 'providers': ['apple']},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-10-13T00:00:00Z',
    );

    test('Apple\'s popup gives the Services ID\'s code, and says it is the website\'s', () async {
      debugAppleWebOverride = true;
      var asked = 0;
      final server = _Server(user: appleUser, appleWebCredential: ({required scopes, required nonce}) async {
        asked++;
        expect(scopes, isEmpty, reason: 'a fresh code only: nothing asked of the person');
        return _credential(code: 'c-web');
      });
      expect(server.signedInWithApple, isTrue);
      server.warmAppleWeb();
      await pumpEventQueue();
      expect(await server.appleReauthorizationCode(), 'c-web');
      expect(asked, 1);
      expect(server.appleCodeClient, 'web');
    });

    test('the website\'s switch off (or not heard yet): no Apple window, the deletion goes on without a code', () async {
      debugAppleWebOverride = true;
      var asked = 0;
      Future<AuthorizationCredentialAppleID> popup({required scopes, required nonce}) async {
        asked++;
        return _credential(code: 'c-web');
      }

      // Not warmed: the switch is not known at the tap, so Apple is not asked.
      final cold = _Server(user: appleUser, appleWebCredential: popup);
      expect(await cold.appleReauthorizationCode(), isNull);
      // Warmed, the switch off: the Services ID may not exist yet.
      final off = _Server(user: appleUser, webApple: false, appleWebCredential: popup);
      off.warmAppleWeb();
      await pumpEventQueue();
      expect(off.calls, contains('appleWebAvailable'));
      expect(await off.appleReauthorizationCode(), isNull);
      expect(asked, 0);
    });

    test('a closed or failed popup: no code, the deletion goes on', () async {
      debugAppleWebOverride = true;
      Future<String?> code(AppleCredentialRequest popup) async {
        final server = _Server(user: appleUser, appleWebCredential: popup)..warmAppleWeb();
        await pumpEventQueue();
        return server.appleReauthorizationCode();
      }

      expect(
          await code(({required scopes, required nonce}) async =>
              throw const SignInWithAppleCredentialsException(message: 'popup_closed_by_user')),
          isNull);
      expect(await code(({required scopes, required nonce}) async => _credential(code: '')), isNull);
    });

    test('not an Apple account: Apple is never asked', () async {
      debugAppleWebOverride = true;
      var asked = 0;
      final server = _Server(appleWebCredential: ({required scopes, required nonce}) async {
        asked++;
        return _credential();
      });
      expect(await server.appleReauthorizationCode(), isNull);
      expect(asked, 0);
      debugAppleWebOverride = false;
      expect(_Server().appleCodeClient, 'app');
    });
  });

  group('Réglages', () {
    test('Réglages: « Connexion Apple sur le site », a switch, on the Sécurité card', () {
      final def = platformSettingDefs.singleWhere((d) => d.key == 'apple_web_signin');
      expect(def.type, SettingType.flag);
      expect(settingCardOf('apple_web_signin')?.key, 'securite');
    });
  });
}
