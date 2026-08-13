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
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient? _client;

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
  /// [phone] must already be in E.164 form (+22670000000); [normalizePhone]
  /// does that.
  Future<void> sendPhoneOtp(String phone) async {
    final client = _requireClient();
    await client.auth.signInWithOtp(phone: phone, shouldCreateUser: false);
  }

  /// The same SMS, for somebody who does not have an account yet.
  ///
  /// The name travels in `data`, which Supabase writes to
  /// `auth.users.raw_user_meta_data`; the trigger in 004 copies it into
  /// `profiles` the moment the account exists. So the person who invites them
  /// later sees a name in the members list instead of a phone number.
  Future<void> sendSignUpOtp(String phone, {String? fullName}) async {
    final client = _requireClient();
    final name = fullName?.trim();
    await client.auth.signInWithOtp(
      phone: phone,
      shouldCreateUser: true,
      data: (name == null || name.isEmpty) ? null : {'full_name': name},
    );
  }

  Future<AuthResponse> verifyPhoneOtp({
    required String phone,
    required String token,
  }) {
    final client = _requireClient();
    return client.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
  }

  // ----------------------------------------------------------------
  // Email + password — the secondary route
  // ----------------------------------------------------------------

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    final client = _requireClient();
    return client.auth.signInWithPassword(email: email, password: password);
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
          .update({'full_name': name}).eq('id', userId);
    } catch (_) {
      // Offline, or the profile row has not been mirrored across yet. The
      // account is what matters and the account is already made.
    }
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
