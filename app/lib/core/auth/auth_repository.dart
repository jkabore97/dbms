import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import '../errors.dart' as errors;

/// Everything the app does with Supabase auth, behind one door.
///
/// Phone + OTP is the primary route on purpose: most of the people this app is
/// for have a phone number and no email address. Email and password exist for
/// the accountant on a laptop and for anyone whose SMS never arrives.
///
/// The client is nullable. A build made with no `--dart-define` values has no
/// backend at all, and the app is still expected to run against the local
/// database; every method here fails politely rather than throwing a null.
/// Apple's native sheet (sign_in_with_apple): asks for [scopes] and seals
/// [nonce] — the SHA-256 of the raw nonce — into the identity token. A
/// parameter so a test can stand in for Apple.
typedef AppleCredentialRequest = Future<AuthorizationCredentialAppleID>
    Function({
  required List<AppleIDAuthorizationScopes> scopes,
  required String nonce,
});

/// Where « Continuer avec Apple » may be drawn: the iPhone app only (125).
/// On Android and the web, Apple's sign-in would be a web page of its own,
/// and App Review's rule (4.8) is about the iPhone app beside Google.
bool get appleSignInPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

class AuthRepository {
  AuthRepository(
    this._client, {
    this.authUrl,
    this.apiKey,
    http.Client? httpClient,
    AppleCredentialRequest? appleCredential,
  })  : _http = httpClient,
        _appleCredential = appleCredential ?? _askApple;

  final SupabaseClient? _client;

  /// `<project>/auth/v1` and the publishable key, to ask which sign-in
  /// providers the project has switched on. Null in tests and in a build
  /// with no server: no Google button.
  final String? authUrl;
  final String? apiKey;
  final http.Client? _http;

  /// The raw client, for repositories built at the scope rather than in
  /// main(). Null in a build with no server, like everything else here.
  SupabaseClient? get client => _client;

  bool get isConfigured => _client != null;

  User? get currentUser => _client?.auth.currentUser;

  Session? get currentSession => _client?.auth.currentSession;

  /// True when the stored token is still good. False when it has expired and
  /// the refresh could not happen — which, out at the farm, is most of the
  /// time. That is what the PIN is for.
  bool get hasLiveSession {
    final session = currentSession;
    return session != null && !session.isExpired;
  }

  Stream<AuthState>? get onAuthStateChange => _client?.auth.onAuthStateChange;

  // ----------------------------------------------------------------
  // Phone + OTP — the primary route
  // ----------------------------------------------------------------

  /// Sends the six-digit code to somebody who already has an account.
  ///
  /// `shouldCreateUser: false` is the whole difference between this and
  /// [signUpWithPhone], and it matters more than it looks. Supabase creates an
  /// account on the first OTP by default, so a mistyped digit used to become a
  /// silent second account with an empty waiting screen behind it — and the
  /// person, who had signed in successfully as far as they could tell, would
  /// conclude the app was broken rather than that they were now somebody else.
  /// Refusing an unknown number here is what lets the screen say the true
  /// thing: this number has no account yet, create one.
  ///
  /// Signing in is e-mail and password, and nothing else.
  ///
  /// The phone/OTP methods that used to sit here — `sendPhoneOtp`,
  /// `sendSignUpOtp`, `verifyPhoneOtp` — are gone by decision, not by
  /// oversight. SMS to Burkinabè numbers costs money per message, depends on
  /// a delivery route nobody in this project controls, and fails quietly in
  /// exactly the places the app is meant to work. They are deleted rather
  /// than left unused so the route cannot be reintroduced by autocomplete.
  ///
  /// Being far from signal is covered by the device PIN, which unlocks the
  /// session already written to device storage. The network is needed once,
  /// at sign-in, and not again until the session needs refreshing.
  ///
  /// `normalizePhone` stays: a telephone number is still contact information
  /// and still what an invitation is pinned to. It is no longer a credential.
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    final client = _requireClient();
    return client.auth.signInWithPassword(email: email, password: password);
  }

  // ----------------------------------------------------------------
  // Google
  // ----------------------------------------------------------------

  /// Where Google sends an Android phone back: the intent filter in
  /// AndroidManifest.xml catches it, and supabase_flutter swaps the code in
  /// it for a session. Must be in the project's Redirect URLs.
  static const androidCallback = 'bf.kaj.app://login-callback';

  /// The project's `external` providers, asked once per launch and shared
  /// by Google's question and Apple's: one request, even when both are
  /// asked at the same moment. Forgotten when it could not be asked.
  Future<Map<dynamic, dynamic>?>? _external;

  /// Whether the project has Google switched on (Supabase dashboard ›
  /// Authentication › Providers). Asked once: a button for a provider that is
  /// off would send people to an error page at Google's door.
  Future<bool> googleAvailable() => _providerOn('google');

  /// Whether the project has Apple switched on, read the same way as
  /// Google (`external.apple`) and kept the same way: once known, for the
  /// launch; false while offline, and asked again next time.
  Future<bool> appleAvailable() => _providerOn('apple');

  Future<bool> _providerOn(String provider) async {
    final external = await (_external ??= _readExternal());
    if (external == null) _external = null; // Offline: asked again next time.
    return external?[provider] == true;
  }

  /// `external` from `/auth/v1/settings`; null when it could not be asked
  /// (no server, offline, refused).
  Future<Map<dynamic, dynamic>?> _readExternal() async {
    final url = authUrl, key = apiKey;
    if (!isConfigured || url == null || key == null) return null;
    try {
      final client = _http ?? http.Client();
      final r = await client
          .get(Uri.parse('$url/settings'), headers: {'apikey': key})
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final body = jsonDecode(r.body);
      return body is Map && body['external'] is Map
          ? body['external'] as Map
          : const {};
    } catch (_) {
      return null;
    }
  }

  /// Sends the person to Google. On the web the page leaves and comes back
  /// to /connexion with a code that Supabase.initialize turns into a session
  /// before the app starts; on Android the browser hands back to the app
  /// through [androidCallback] and the session arrives as an auth event.
  /// Either way, an account that did not exist is created — named from
  /// Google — and one with the same verified e-mail is the same account.
  Future<void> signInWithGoogle() async {
    final client = _requireClient();
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? '${Uri.base.origin}/connexion' : androidCallback,
      // Several Google accounts on one phone are common: let them choose.
      queryParams: const {'prompt': 'select_account'},
    );
    if (!launched) {
      throw StateError("La page de connexion Google n'a pas pu s'ouvrir.");
    }
  }

  // ----------------------------------------------------------------
  // Apple — the iPhone app only (125)
  // ----------------------------------------------------------------

  final AppleCredentialRequest _appleCredential;

  static Future<AuthorizationCredentialAppleID> _askApple({
    required List<AppleIDAuthorizationScopes> scopes,
    required String nonce,
  }) =>
      SignInWithApple.getAppleIDCredential(scopes: scopes, nonce: nonce);

  /// A fresh random nonce for one sign-in: 32 characters from a secure
  /// source. Apple is handed its SHA-256; Supabase the raw one, and checks
  /// that its hash is the one sealed in Apple's token — so a token caught
  /// on its way cannot be replayed.
  static String newNonce([Random? random]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final r = random ?? Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Signs in with Apple's own sheet, natively: no browser, no redirect.
  /// Apple's identity token goes to Supabase, which creates the account
  /// the first time and finds it every time after; the session is in hand
  /// when this returns. Null when the person closed Apple's sheet — nothing
  /// to say about that. Any other failure throws, for the screen to say.
  ///
  /// Apple gives the name only the very first time somebody signs in to
  /// the app. When it does and the profile has no name yet, it is written
  /// the same way as at sign-up ([saveMyName]); the e-mail may be a private
  /// relay address Apple makes, and is kept as Apple gives it.
  Future<User?> signInWithApple() async {
    final client = _requireClient();
    final rawNonce = newNonce();
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await _appleCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw StateError("La connexion avec Apple n'a pas abouti. Réessayez.");
    } on SignInWithAppleException {
      throw StateError("La connexion avec Apple n'a pas abouti. Réessayez.");
    }
    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError("La connexion avec Apple n'a pas abouti. Réessayez.");
    }
    final response = await client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
    final user = response.user;
    if (user == null) {
      throw StateError("La connexion avec Apple n'a pas abouti. Réessayez.");
    }
    final name = [credential.givenName, credential.familyName]
        .map((p) => p?.trim() ?? '')
        .where((p) => p.isNotEmpty)
        .join(' ');
    if (name.isNotEmpty && !await _profileHasName(user.id)) {
      await saveMyName(name);
    }
    return client.auth.currentUser ?? user;
  }

  /// Whether the signed-in person's profile already carries a name. When it
  /// cannot be read, it is taken as named: a name Apple gives once is only
  /// written where nothing would be overwritten.
  Future<bool> _profileHasName(String userId) async {
    final client = _client;
    if (client == null) return true;
    try {
      final row = await client
          .from('profiles')
          .select('full_name')
          .eq('id', userId)
          .maybeSingle();
      final name = (row?['full_name'] as String?)?.trim() ?? '';
      return name.isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  /// Creates an account from an email and a password.
  ///
  /// Returns a response whose `session` is null when the project has email
  /// confirmation switched on — the account exists, but nobody is signed in
  /// until the link is clicked. The caller has to tell those two outcomes
  /// apart, because "check your email" and "you're in" are different screens.
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) {
    final client = _requireClient();
    final name = fullName?.trim();
    return client.auth.signUp(
      email: email,
      password: password,
      data: (name == null || name.isEmpty) ? null : {'full_name': name},
    );
  }

  // ----------------------------------------------------------------
  // The name people are known by
  // ----------------------------------------------------------------

  /// Writes the name onto the signed-in person's profile.
  ///
  /// The trigger in 004 sets it at sign-up from the metadata, so this is for
  /// the cases the trigger cannot cover: an account created before the name
  /// was asked for, or a person correcting a typo. `profiles` has an update
  /// policy for `id = auth.uid()` and nothing wider, so this can only ever
  /// rename the caller.
  ///
  /// Never throws. It runs on the sign-up path, where failing to save a
  /// display name must not be the thing that stops somebody getting into the
  /// app; the name can be set again from the account menu.
  Future<void> saveMyName(String fullName) async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    final name = fullName.trim();
    if (client == null || userId == null || name.isEmpty) return;

    try {
      await client.auth.updateUser(UserAttributes(data: {'full_name': name}));
      await client
          .from('profiles')
          .update({'full_name': name})
          .eq('id', userId);
    } catch (_) {
      // Offline, or the profile row has not been mirrored across yet. The
      // account is what matters and the account is already made.
    }
  }

  /// Changes the signed-in person's own password. Self-service through
  /// Supabase, so it needs no service-role key and no Worker — the admin path
  /// (resetting someone else's) is the one that does. Throws on failure so the
  /// screen can say what went wrong.
  Future<void> updateMyPassword(String newPassword) async {
    final client = _requireClient();
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() async {
    // A failure here means the token could not be revoked server-side. The
    // local session is dropped either way; the alternative is a user who
    // cannot sign out until they have signal.
    try {
      await _client?.auth.signOut();
    } on AuthException {
      // Already gone as far as this device is concerned.
    }
  }

  // ----------------------------------------------------------------
  // Which businesses does this person belong to?
  // ----------------------------------------------------------------

  /// Calls `my_orgs()` (004_rls_policies.sql). One row per org, already
  /// filtered server-side to this user — the client never asks for someone
  /// else's memberships, and would be refused if it did.
  Future<List<OrgSummary>> fetchOrgs() async {
    final client = _requireClient();
    final rows = await client.rpc('my_orgs') as List<dynamic>;
    return rows
        .map((r) => OrgSummary.fromRpc(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError(
        "Cette version de l'application a été compilée sans serveur. "
        'Reconstruisez-la avec SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY.',
      );
    }
    return client;
  }

  /// Turns what someone types into E.164.
  ///
  /// Burkina Faso numbers are eight digits and are written locally with spaces
  /// and no country code — "70 12 34 56". A number typed that way is assumed
  /// to be local; anything starting with + is left alone.
  static String normalizePhone(String input, {String defaultCode = '+226'}) {
    var cleaned = input.replaceAll(RegExp(r'[\s\-().]'), '');
    if (cleaned.startsWith('00')) cleaned = '+${cleaned.substring(2)}';
    if (cleaned.startsWith('+')) return cleaned;
    // A leading 0 is a national trunk prefix and is dropped before the code.
    if (cleaned.startsWith('0')) cleaned = cleaned.substring(1);
    return '$defaultCode$cleaned';
  }

  /// Kept as the name most screens call, now delegating.
  ///
  /// It used to hold the whole translation table, which meant auth failures
  /// were humanised and database failures were not: a screen that caught a
  /// `PostgrestException` printed the raw object, tables and error codes and
  /// all. See `core/errors.dart` for what replaced it and why.
  static String describeError(Object error) => errors.describeError(error);
}
