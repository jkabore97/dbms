// SEC_AUDIT_2 M3: a link signs this device in only with the PKCE `code` of
// a sign-in it started itself — never with a raw access_token or
// refresh_token somebody put in a link. Google's return and an e-mail
// confirmation still sign in.
//
// The decision is the one supabase_flutter makes on every incoming link
// (_handleDeeplink: the predicate, then getSessionFromUrl); here it is made
// against a real GoTrueClient whose network is faked.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaj_app/core/auth/auth_callback.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _gotrue = 'https://proj.supabase.co/auth/v1';

Map<String, dynamic> _user(String id, String email) => {
      'id': id,
      'aud': 'authenticated',
      'email': email,
      'created_at': '2026-10-12T08:00:00Z',
      'app_metadata': {'provider': 'email'},
      'user_metadata': {},
    };

Map<String, dynamic> _session(String id, String email) => {
      'access_token': 'at-$id',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'refresh_token': 'rt-$id',
      'user': _user(id, email),
    };

class _MemoryStorage extends GotrueAsyncStorage {
  final items = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => items[key];
  @override
  Future<void> setItem({required String key, required String value}) async => items[key] = value;
  @override
  Future<void> removeItem({required String key}) async => items.remove(key);
}

/// What supabase_flutter does with a link the app is opened with.
Future<Session?> _openLink(GoTrueClient auth, Uri link) async {
  if (!isPkceAuthCallback(link)) return null;
  try {
    return (await auth.getSessionFromUrl(link)).session;
  } on AuthException {
    return null;
  }
}

void main() {
  late List<http.Request> requests;
  late _MemoryStorage storage;
  late GoTrueClient auth;

  setUp(() {
    requests = [];
    storage = _MemoryStorage();
    auth = GoTrueClient(
      url: _gotrue,
      headers: const {'apikey': 'sb_publishable_test'},
      asyncStorage: storage,
      flowType: AuthFlowType.pkce,
      httpClient: MockClient((r) async {
        requests.add(r);
        final path = r.url.path;
        if (path.endsWith('/token') && r.url.queryParameters['grant_type'] == 'pkce') {
          final body = jsonDecode(r.body) as Map;
          // Supabase gives a session for a code only with its verifier.
          if (body['code_verifier'] == null || body['auth_code'] != 'good-code') {
            return http.Response(jsonEncode({'error': 'invalid_grant', 'error_description': 'bad code'}), 400);
          }
          return http.Response(jsonEncode(_session('me', 'awa@example.org')), 200);
        }
        if (path.endsWith('/signup')) {
          return http.Response(jsonEncode(_user('me', 'awa@example.org')), 200);
        }
        if (path.endsWith('/user')) {
          // The stranger's token is a real one: GoTrue would vouch for it.
          return http.Response(jsonEncode(_user('stranger', 'attacker@example.org')), 200);
        }
        return http.Response('{}', 404);
      }),
    );
  });

  group('which links sign in', () {
    test('a PKCE code (Google back on a phone, on the web, an e-mail confirmation) and errors: yes', () {
      expect(isPkceAuthCallback(Uri.parse('bf.kaj.app://login-callback?code=abc')), isTrue);
      expect(isPkceAuthCallback(Uri.parse('https://marakaj.com/connexion?code=abc')), isTrue);
      expect(isPkceAuthCallback(Uri.parse('https://marakaj.com/?code=abc&type=signup')), isTrue);
      expect(
          isPkceAuthCallback(Uri.parse(
              'bf.kaj.app://login-callback?error=access_denied&error_description=refused')),
          isTrue);
      expect(isPkceAuthCallback(Uri.parse('https://marakaj.com/connexion#error_code=otp_expired')), isTrue);
    });

    test('raw tokens, in the query or the fragment, even with a code: never', () {
      for (final link in [
        'bf.kaj.app://login-callback?access_token=AT&refresh_token=RT&expires_in=3600&token_type=bearer',
        'https://marakaj.com/connexion#access_token=AT&refresh_token=RT&expires_in=3600&token_type=bearer',
        'https://marakaj.com/connexion#access_token=AT&refresh_token=RT&expires_in=3600&token_type=bearer&type=recovery',
        'bf.kaj.app://login-callback?code=abc#access_token=AT&refresh_token=RT',
        'https://marakaj.com/connexion?refresh_token=RT',
        'https://marakaj.com/connexion?provider_token=PT&code=abc',
      ]) {
        expect(isPkceAuthCallback(Uri.parse(link)), isFalse, reason: link);
      }
    });

    test('an ordinary address of the app: not a sign-in', () {
      expect(isPkceAuthCallback(Uri.parse('https://marakaj.com/s/boutique-awa')), isFalse);
      expect(isPkceAuthCallback(Uri.parse('https://marakaj.com/rejoindre?invitation=AB12CD34')), isFalse);
      expect(isPkceAuthCallback(Uri.parse('bf.kaj.app://login-callback')), isFalse);
    });
  });

  group('against GoTrue', () {
    test('a stranger\'s tokens in a link: no session (GoTrue alone would have taken them)', () async {
      final attack = Uri.parse('bf.kaj.app://login-callback'
          '?access_token=stranger-at&refresh_token=stranger-rt&expires_in=3600&token_type=bearer');
      expect(await _openLink(auth, attack), isNull);
      expect(auth.currentSession, isNull);
      expect(requests, isEmpty, reason: 'nothing asked of GoTrue');
      // Why the predicate matters: GoTrue itself, even in the PKCE flow,
      // accepts the raw tokens.
      final taken = await auth.getSessionFromUrl(attack);
      expect(taken.session.user.email, 'attacker@example.org');
    });

    test('Google: the return with the code this device asked for signs in', () async {
      final started = await auth.getOAuthSignInUrl(
          provider: OAuthProvider.google, redirectTo: 'bf.kaj.app://login-callback');
      expect(Uri.parse(started.url).queryParameters['code_challenge_method'], 's256');
      final session = await _openLink(auth, Uri.parse('bf.kaj.app://login-callback?code=good-code'));
      expect(session?.user.email, 'awa@example.org');
      final exchange = requests.last;
      expect(exchange.url.queryParameters['grant_type'], 'pkce');
      expect((jsonDecode(exchange.body) as Map)['code_verifier'], isNotEmpty);
    });

    test('an e-mail confirmation asked from here comes back with its code and signs in', () async {
      await auth.signUp(email: 'awa@example.org', password: 'un mot de passe', emailRedirectTo: 'https://marakaj.com/connexion');
      final signup = requests.single;
      expect((jsonDecode(signup.body) as Map)['code_challenge'], isNotEmpty, reason: 'PKCE sign-up');
      final session = await _openLink(auth, Uri.parse('https://marakaj.com/connexion?code=good-code'));
      expect(session?.user.email, 'awa@example.org');
    });

    test('a code this device never asked for (somebody else\'s link): no session', () async {
      final session = await _openLink(auth, Uri.parse('bf.kaj.app://login-callback?code=good-code'));
      expect(session, isNull);
      expect(auth.currentSession, isNull);
    });
  });

  test('main.dart starts Supabase with the PKCE flow and this predicate', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('authFlowType: AuthFlowType.pkce'));
    expect(main, contains('detectSessionInUriPredicate: isPkceAuthCallback'));
  });
}
