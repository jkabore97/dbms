import 'package:supabase_flutter/supabase_flutter.dart';

/// The platform admin's second step (migration 077): a six-digit code from
/// an authenticator app, on top of the password.
///
/// The database is what insists — its pre-request gate refuses a platform
/// admin's token below aal2 on every call but my_two_step(). This class is
/// only how the app finds out what to ask, and asks it.
class TwoStep {
  TwoStep(this._client);

  final SupabaseClient? _client;

  /// Whether this account must pass, whether it has an app enrolled, and
  /// whether this token has passed. "Not required" when there is no server,
  /// or a database before 077.
  Future<TwoStepStatus> status() async {
    final client = _client;
    if (client == null || client.auth.currentSession == null) {
      return TwoStepStatus.none;
    }
    try {
      final v = await client.rpc('my_two_step');
      if (v is! Map) return TwoStepStatus.none;
      return TwoStepStatus(
        required: v['required'] == true,
        enrolled: v['enrolled'] == true,
        passed: v['passed'] == true,
        on: v['on'] == true,
      );
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return TwoStepStatus.none;
      // The gate itself answered: held to it and not passed. Whether an app
      // is enrolled, the token's own factor list says.
      if (isGateRefusal(e)) {
        return TwoStepStatus(
          required: true,
          enrolled: _hasVerifiedFactor(client),
          passed: false,
          on: true,
        );
      }
      rethrow;
    }
  }

  /// A refusal from 077's gate, wherever it surfaces.
  static bool isGateRefusal(Object e) =>
      e is PostgrestException &&
      (e.hint == 'two_step_required' ||
          e.message.contains('deux étapes requise'));

  static bool _hasVerifiedFactor(SupabaseClient client) =>
      (client.auth.currentUser?.factors ?? const <Factor>[]).any(
        (f) =>
            f.factorType == FactorType.totp &&
            f.status == FactorStatus.verified,
      );

  /// Starts adding an authenticator app. Any half-finished attempt from
  /// before is removed first: Supabase refuses a second unverified factor
  /// with the same name, and an abandoned one helps nobody.
  Future<TwoStepEnrollment> enroll({String? label}) async {
    final client = _client!;
    for (final f in client.auth.currentUser?.factors ?? const <Factor>[]) {
      if (f.status != FactorStatus.verified) {
        try {
          await client.auth.mfa.unenroll(f.id);
        } catch (_) {}
      }
    }
    final stamp = DateTime.now().toIso8601String().substring(0, 16);
    final r = await client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'Mara',
      friendlyName: 'Mara ${label ?? ''} $stamp'.replaceAll(RegExp(r'\s+'), ' '),
    );
    final totp = r.totp!;
    return TwoStepEnrollment(
      factorId: r.id,
      secret: totp.secret,
      uri: totp.uri,
    );
  }

  /// The enrolled app's factor, to ask its code at sign-in.
  Future<String?> verifiedFactorId() async {
    final client = _client;
    if (client == null) return null;
    final list = await client.auth.mfa.listFactors();
    return list.totp.isEmpty ? null : list.totp.first.id;
  }

  /// Checks a six-digit code. On success the session is aal2 from here on,
  /// across refreshes, until it is signed out.
  Future<void> verify(String factorId, String code) async {
    await _client!.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code.trim(),
    );
  }

  /// The platform's switch (078): whether a platform admin must pass the
  /// second step at all. Off by default. Switching it off again is refused
  /// by the gate below aal2, so it can only be undone by someone who has
  /// passed — the switch is not a way round it.
  Future<void> setRequired(bool on) async {
    await _client!.rpc('set_platform_setting',
        params: {'p_key': 'admin_two_step', 'p_value': on});
  }

  /// Writes « Validation en deux étapes activée » into the account's history
  /// (075). Best-effort: the factor is what counts.
  Future<void> logEnabled() async {
    try {
      await _client?.rpc(
        'log_security_event',
        params: {'p_kind': 'two_step_enabled', 'p_detail': null},
      );
    } catch (_) {}
  }
}

class TwoStepStatus {
  const TwoStepStatus({
    required this.required,
    required this.enrolled,
    required this.passed,
    this.on = false,
  });

  /// Whether the platform has switched the second step on (078).
  final bool on;

  static const none = TwoStepStatus(
    required: false,
    enrolled: false,
    passed: false,
  );

  final bool required;
  final bool enrolled;
  final bool passed;

  /// Whether the app must stop at the code screen.
  bool get mustAsk => required && !passed;
}

class TwoStepEnrollment {
  const TwoStepEnrollment({
    required this.factorId,
    required this.secret,
    required this.uri,
  });

  final String factorId;

  /// The key, for typing into the app by hand. Never logged.
  final String secret;

  /// otpauth://… — the QR code, and the link that opens the app on a phone.
  final String uri;
}
