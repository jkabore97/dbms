import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart' show closeInAppWebView;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'apple_js.dart';
import 'models.dart';
import '../errors.dart' as errors;

/// Apple's sheet (sign_in_with_apple) — native on the iPhone, Apple's JS
/// popup on the website (139): asks for [scopes] and seals [nonce] — the
/// SHA-256 of the raw nonce — into the identity token. A parameter so a
/// test can stand in for Apple.
typedef AppleCredentialRequest = Future<AuthorizationCredentialAppleID>
    Function({
  required List<AppleIDAuthorizationScopes> scopes,
  required String nonce,
});

/// Where « Continuer avec Apple » is Apple's native sheet: the iPhone app
/// (125). The website has it too since 139, in Apple's JS popup
/// ([appleWebPlatform]); Android keeps Google and the e-mail.
bool get appleSignInPlatform =>
    !appleWebPlatform && defaultTargetPlatform == TargetPlatform.iOS;

/// Stands in for kIsWeb in tests (139): the website's « Continuer avec
/// Apple » cannot otherwise be drawn in a test, which runs on no web.
@visibleForTesting
bool? debugAppleWebOverride;

/// The website (marakaj.com), where « Continuer avec Apple » is Apple's JS
/// popup (139) once Réglages' « Connexion Apple sur le site » is on.
bool get appleWebPlatform => debugAppleWebOverride ?? kIsWeb;

/// The Services ID the website signs in as (developer.apple.com ›
/// Identifiers › Services IDs, « Mara Web ») — a public identifier, in
/// every Apple sign-in address. Apple's identity token then names it as
/// its audience, so Supabase's Apple « Client IDs » must list it beside
/// bf.kaj.app. No client secret: the identity token is checked against
/// Apple's public keys, nothing of Mara's that could expire.
const appleWebServicesId =
    String.fromEnvironment('APPLE_WEB_SERVICES_ID', defaultValue: 'bf.kaj.app.web');

/// Whether the website's popup failed only because the person closed it
/// (Apple JS's « popup_closed_by_user », or « user_cancelled_authorize »
/// when they pressed Cancel inside it) — the web plugin says so only in
/// its message.
bool appleWebPopupClosed(String message) =>
    message.contains('popup_closed_by_user') || message.contains('user_cancelled_authorize');

/// Whether the website's popup could not open at all: the browser blocked
/// it (Apple JS's « popup_blocked_by_browser »), or Apple's script was not
/// there yet and had to be fetched during the tap, after which a browser
/// such as Safari no longer counts the window as the tap's.
bool appleWebPopupBlocked(String message) =>
    message.contains('popup_blocked') || message.contains('did not load');

/// Everything the app does with Supabase auth, behind one door.
///
/// Phone + OTP is the primary route on purpose: most of the people this app is
/// for have a phone number and no email address. Email and password exist for
/// the accountant on a laptop and for anyone whose SMS never arrives.
///
/// The client is nullable. A build made with no `--dart-define` values has no
/// backend at all, and the app is still expected to run against the local
/// database; every method here fails politely rather than throwing a null.
class AuthRepository {
  AuthRepository(
    this._client, {
    this.authUrl,
    this.apiKey,
    http.Client? httpClient,
    AppleCredentialRequest? appleCredential,
    Future<void> Function()? closeSheet,
    String Function()? webOrigin,
    this.appleWebCredential,
  })  : _http = httpClient,
        _appleCredential = appleCredential ?? _askApple,
        _closeSheet = closeSheet ?? closeInAppWebView,
        _webOrigin = webOrigin ?? (() => Uri.base.origin);

  /// The page's own origin (https://marakaj.com): Apple's popup answers
  /// to `<origin>/connexion`, one of the Services ID's return URLs. A
  /// test's stand-in.
  final String Function() _webOrigin;

  /// Apple's popup on the website (139): a test's stand-in; null, Apple's
  /// own (Sign in with Apple JS).
  final AppleCredentialRequest? appleWebCredential;

  /// url_launcher's closeInAppWebView, or a test's stand-in.
  final Future<void> Function() _closeSheet;

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

  /// Whether the website draws « Continuer avec Apple » (139): this is the
  /// website, Réglages' « Connexion Apple sur le site » is on
  /// (sign_in_options().apple_web, 135 — readable signed out), and the
  /// project has Apple on. Off by default, off while either cannot be
  /// asked, and off against a database without 135 (no such function):
  /// the button never sends anybody to an Apple page that is not set up.
  Future<bool> appleWebAvailable() async {
    if (!appleWebPlatform || !isConfigured) return false;
    final on = await (_appleWeb ??= _readAppleWeb());
    if (on == null) _appleWeb = null; // Could not ask: asked again next time.
    if (on != true) return false;
    final apple = await appleAvailable();
    // The button will be drawn: Apple's script is fetched now, so the tap
    // opens the popup at once, within the tap's own gesture — a popup
    // opened after a wait is blocked by the browser.
    if (apple && appleWebCredential == null) unawaited(ensureAppleJs());
    return apple;
  }

  Future<bool?>? _appleWeb;

  /// What [appleWebAvailable] last answered (139), known without waiting:
  /// the deletion's popup must open within the confirmation's tap, so it
  /// cannot stop to ask. Null until asked ([warmAppleWeb]).
  bool? _appleWebReady;

  Future<bool?> _readAppleWeb() async {
    try {
      final v = await _client!.rpc('sign_in_options').timeout(const Duration(seconds: 8));
      return v is Map && v['apple_web'] == true;
    } on PostgrestException {
      // A database before 135, or refused: the switch is off.
      return false;
    } catch (_) {
      return null;
    }
  }

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
      // On an iPhone, in the in-app Safari sheet (SFSafariViewController),
      // which [closeSignInSheet] can close; Android has its own browser
      // (supabase_flutter forces it for Google).
      authScreenLaunchMode: _ios ? LaunchMode.inAppBrowserView : LaunchMode.platformDefault,
    );
    if (!launched) {
      throw StateError("La page de connexion Google n'a pas pu s'ouvrir.");
    }
  }

  static bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Closes the in-app Safari sheet Google's page opened in (130).
  ///
  /// Why it stayed open: on an iPhone the page runs in SFSafariViewController
  /// over the app. Google's answer comes back to Supabase, which redirects
  /// to bf.kaj.app://login-callback; iOS hands that address to the app
  /// (CFBundleURLSchemes), supabase_flutter turns the code into a session
  /// and raises signedIn — but nothing ever dismissed the sheet, so the
  /// person was left on a blank Safari page over a signed-in app.
  /// SFSafariViewController never closes itself on a redirect to the app:
  /// the app has to (url_launcher's closeInAppWebView). The session calls
  /// this on every signedIn; elsewhere than an iPhone it does nothing.
  Future<void> closeSignInSheet() async {
    if (!_ios) return;
    try {
      await _closeSheet();
    } catch (_) {}
  }

  // ----------------------------------------------------------------
  // Apple — the iPhone app (125) and the website (139)
  // ----------------------------------------------------------------

  final AppleCredentialRequest _appleCredential;

  /// What every Apple failure but a closed sheet says (a key of en.dart,
  /// translated by describeError).
  static const appleFailed =
      "La connexion avec Apple n'a pas abouti. Réessayez.";

  /// The website's popup could not open (139): blocked by the browser, or
  /// Apple's script came too late for this tap. The next tap has the
  /// script in hand and opens it at once.
  static const appleWebBlocked =
      "La fenêtre d'Apple n'a pas pu s'ouvrir. Touchez à nouveau « Continuer avec Apple » ; si rien ne s'ouvre, autorisez les fenêtres pour ce site.";

  static Future<AuthorizationCredentialAppleID> _askApple({
    required List<AppleIDAuthorizationScopes> scopes,
    required String nonce,
  }) =>
      SignInWithApple.getAppleIDCredential(scopes: scopes, nonce: nonce);

  /// A fresh random nonce for one sign-in: 32 characters from a secure
  /// source. Apple is handed its SHA-256; Supabase the raw one, and checks
  /// that its hash is the one sealed in Apple's token — so a token caught
  /// on its way cannot be replayed.
  static String newNonce() {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final r = Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Signs in with Apple's own sheet, natively: no browser, no redirect.
  /// Apple's identity token goes to Supabase, which creates the account
  /// the first time and finds it every time after; the session is in hand
  /// when this returns. Null when the person closed Apple's sheet — nothing
  /// to say about that. Any other failure throws, for the screen to say.
  ///
  /// On the website (139) the very same path, with Apple's JS popup for
  /// the Services ID in place of the native sheet: the identity token, its
  /// nonce, signInWithIdToken — no redirect, and no client secret (which
  /// Apple lets live six months) anywhere.
  ///
  /// Apple gives the name only the very first time somebody signs in to
  /// the app. When it does and the profile has no name yet, it is written
  /// the same way as at sign-up ([saveMyName]); the e-mail may be a private
  /// relay address Apple makes, and is kept as Apple gives it.
  ///
  /// [ready] is what the caller must have done before the session is taken
  /// (the device's notes): started before the tap's popup and awaited only
  /// after Apple answers, so nothing is waited for between the tap and the
  /// popup — a browser blocks a window opened after a wait (139).
  Future<User?> signInWithApple({Future<void>? ready}) async {
    final client = _requireClient();
    final rawNonce = newNonce();
    final AuthorizationCredentialAppleID credential;
    final ask = appleWebPlatform ? _askAppleWebCredential : _appleCredential;
    try {
      credential = await ask(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw StateError(appleFailed);
    } on SignInWithAppleCredentialsException catch (e) {
      // The website's popup closed by the person: nothing to say.
      if (appleWebPopupClosed(e.message)) return null;
      if (appleWebPopupBlocked(e.message)) throw StateError(appleWebBlocked);
      throw StateError(appleFailed);
    } on SignInWithAppleNotSupportedException catch (e) {
      if (appleWebPopupBlocked(e.message)) throw StateError(appleWebBlocked);
      throw StateError(appleFailed);
    } on SignInWithAppleException {
      throw StateError(appleFailed);
    }
    if (ready != null) {
      try {
        await ready;
      } catch (_) {}
    }
    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError(appleFailed);
    }
    final response = await client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
    final user = response.user;
    if (user == null) {
      throw StateError(appleFailed);
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

  /// Whether the signed-in person signed in with Apple at least once (130):
  /// their account deletion must revoke Apple's token.
  bool get signedInWithApple {
    final user = currentUser;
    final providers = user?.appMetadata['providers'];
    return (providers is List && providers.contains('apple')) ||
        (user?.identities?.any((i) => i.provider == 'apple') ?? false);
  }

  /// Apple's sheet once more, at « Supprimer mon compte » (130): a fresh
  /// authorization code, which the account Worker trades with Apple for a
  /// token and revokes (App Review 5.1.1(v)). Null when this is not the
  /// iPhone app, the person did not sign in with Apple, or closed the
  /// sheet — the deletion then goes on and the Worker logs it.
  ///
  /// On the website (139), Apple's popup for the Services ID: its code is
  /// the Services ID's, and the Worker is told so ([appleCodeClient]).
  ///
  /// On the website only once [warmAppleWeb] has heard that « Connexion
  /// Apple sur le site » is on: with it off the Services ID may not be
  /// made yet, and Apple's window would only show an error — the deletion
  /// then goes on without a code, as before 139.
  Future<String?> appleReauthorizationCode() async {
    if (!signedInWithApple) return null;
    if (!appleSignInPlatform && !appleWebPlatform) return null;
    if (appleWebPlatform && _appleWebReady != true) return null;
    final ask = appleWebPlatform ? _askAppleWebCredential : _appleCredential;
    try {
      final credential = await ask(
        scopes: const [],
        nonce: sha256.convert(utf8.encode(newNonce())).toString(),
      );
      final code = credential.authorizationCode;
      return code.isEmpty ? null : code;
    } on SignInWithAppleException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// On the website, for somebody who signed in with Apple (139): Apple's
  /// script fetched ahead of « Supprimer mon compte », so the popup that
  /// asks for the fresh code opens within the confirmation's tap — a popup
  /// opened after a download is blocked by the browser. Nothing elsewhere.
  /// The switch is asked first ([appleWebAvailable], which fetches the
  /// script when it is on): nobody downloads Apple's script, or sees its
  /// window, while the website's Apple sign-in is off.
  void warmAppleWeb() {
    if (appleWebPlatform && signedInWithApple) {
      unawaited(appleWebAvailable().then((on) {
        _appleWebReady = on;
      }, onError: (Object _) {}));
    }
  }

  /// Whose code [appleReauthorizationCode] gives (139): 'web' (the
  /// Services ID's, from the website's popup) or 'app' (bf.kaj.app's, from
  /// the iPhone's sheet). The account Worker trades it with that client id
  /// first, then the other.
  String get appleCodeClient => appleWebPlatform ? 'web' : 'app';

  /// Apple's popup on the website (Sign in with Apple JS, usePopup): the
  /// Services ID, the answer posted back to `<this page's origin>/connexion`
  /// (a return URL of the Services ID — marakaj.com's and www's), the
  /// hashed nonce sealed into the identity token as on the iPhone.
  Future<AuthorizationCredentialAppleID> _askAppleWebCredential({
    required List<AppleIDAuthorizationScopes> scopes,
    required String nonce,
  }) async {
    final stand = appleWebCredential;
    if (stand != null) return stand(scopes: scopes, nonce: nonce);
    if (!await ensureAppleJs()) {
      throw const SignInWithAppleNotSupportedException(message: 'Sign in with Apple JS did not load');
    }
    return SignInWithApple.getAppleIDCredential(
      scopes: scopes,
      nonce: nonce,
      webAuthenticationOptions: WebAuthenticationOptions(
        clientId: appleWebServicesId,
        redirectUri: Uri.parse('${_webOrigin()}/connexion'),
      ),
    );
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
