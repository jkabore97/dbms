import 'package:supabase_flutter/supabase_flutter.dart';

/// The Sécurité page's calls to the server (075). Every function answers
/// about the caller alone — their devices, their sessions, their history —
/// except the two an admin uses for their business's team.
class SecurityRepository {
  SecurityRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('La sécurité du compte a besoin d\'une connexion.');
    }
    return client;
  }

  static bool _missing(PostgrestException e) =>
      e.code == 'PGRST202' || e.code == '42883';

  /// Once per launch. True when this phone is new to the account (the
  /// server rings the account's other devices).
  Future<bool> registerDevice(String deviceId, String label) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return false;
    try {
      final v = await client.rpc('register_device',
          params: {'p_device_id': deviceId, 'p_label': label});
      return v == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<SignInSession>> sessions() async {
    try {
      final rows =
          await _requireClient().rpc('my_sessions') as List<dynamic>;
      return rows
          .map((r) => SignInSession.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      if (_missing(e)) return const [];
      rethrow;
    }
  }

  Future<void> closeSession(String sessionId) async {
    await _requireClient()
        .rpc('close_my_session', params: {'p_session_id': sessionId});
  }

  /// Every session but this one. Returns how many were closed.
  Future<int> closeOtherSessions() async {
    final v = await _requireClient().rpc('close_my_other_sessions');
    return v is num ? v.toInt() : 0;
  }

  Future<List<SecurityEvent>> events({int limit = 20}) async {
    try {
      final rows = await _requireClient()
          .rpc('my_security_events', params: {'p_limit': limit}) as List<dynamic>;
      return rows
          .map((r) => SecurityEvent.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      if (_missing(e)) return const [];
      rethrow;
    }
  }

  /// 'password_changed', 'pin_changed' or 'lock_changed'. Best-effort: the
  /// change itself never waits on its line in the history.
  Future<void> log(String kind, {String? detail}) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.rpc('log_security_event',
          params: {'p_kind': kind, 'p_detail': detail});
    } catch (_) {}
  }

  /// The strictest lock rule among this person's businesses; null when none
  /// set one, or on a database before 075.
  Future<int?> lockPolicy() async {
    final client = _client;
    if (client == null) return null;
    try {
      final v = await client.rpc('my_lock_policy');
      return v is num ? v.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  Future<int?> orgLockPolicy(String orgId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final v = await client
          .rpc('org_lock_policy', params: {'p_org_id': orgId});
      return v is num ? v.toInt() : null;
    } on PostgrestException catch (e) {
      if (_missing(e)) return null;
      rethrow;
    }
  }

  Future<void> setOrgLockPolicy(String orgId, int? minutes) async {
    await _requireClient().rpc('set_lock_policy',
        params: {'p_org_id': orgId, 'p_minutes': minutes});
  }

  /// A lost phone: closes every session of [userId]. Returns how many.
  Future<int> signOutMember(String orgId, String userId) async {
    final v = await _requireClient().rpc('sign_out_member',
        params: {'p_org_id': orgId, 'p_user_id': userId});
    return v is num ? v.toInt() : 0;
  }

  /// Checks [current] against the server, then sets [next]. The current
  /// password is asked first so a phone left open cannot be used to take
  /// the account.
  Future<void> changePassword({required String current, required String next}) async {
    final client = _requireClient();
    final email = client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw StateError('Ce compte n\'a pas d\'adresse e-mail pour vérifier '
          'le mot de passe actuel.');
    }
    try {
      await client.auth.signInWithPassword(email: email, password: current);
    } on AuthException {
      throw StateError('Mot de passe actuel incorrect.');
    }
    await client.auth.updateUser(UserAttributes(password: next));
    await log('password_changed');
  }
}

/// One place this account is signed in.
class SignInSession {
  const SignInSession({
    required this.id,
    required this.current,
    this.createdAt,
    this.lastUsed,
    this.userAgent,
    this.ip,
  });

  factory SignInSession.fromRow(Map<String, dynamic> r) => SignInSession(
        id: '${r['id']}',
        current: r['current'] == true,
        createdAt: _t(r['created_at']),
        lastUsed: _t(r['last_used']),
        userAgent: r['user_agent'] as String?,
        ip: r['ip'] as String?,
      );

  final String id;
  final bool current;
  final DateTime? createdAt;
  final DateTime? lastUsed;
  final String? userAgent;
  final String? ip;

  /// "Android · Chrome", from the browser's own description of itself —
  /// approximate, and said to be.
  String get label => describeUserAgent(userAgent);
}

/// A line of the account's security history.
class SecurityEvent {
  const SecurityEvent({required this.kind, required this.at, this.detail});

  factory SecurityEvent.fromRow(Map<String, dynamic> r) => SecurityEvent(
        kind: '${r['kind']}',
        detail: r['detail'] as String?,
        at: _t(r['at']) ?? DateTime.now(),
      );

  final String kind;
  final String? detail;
  final DateTime at;

  String get label => switch (kind) {
        'new_device' => 'Nouvel appareil${detail == null ? '' : ' : $detail'}',
        'password_changed' => 'Mot de passe changé',
        'pin_changed' => 'Code de l\'appareil changé',
        'lock_changed' => 'Verrouillage modifié${detail == null ? '' : ' : $detail'}',
        'session_closed' => 'Un appareil déconnecté',
        'signed_out_others' => 'Autres appareils déconnectés',
        'signed_out_by_admin' =>
          'Déconnecté partout par ${detail ?? 'un administrateur'}',
        _ => kind,
      };
}

DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// The system and the browser, from a user-agent string.
String describeUserAgent(String? ua) {
  final s = ua ?? '';
  if (s.isEmpty) return 'Appareil inconnu';
  final os = s.contains('Android')
      ? 'Android'
      : (s.contains('iPhone') || s.contains('iPad'))
          ? 'iPhone'
          : s.contains('Windows')
              ? 'Windows'
              : s.contains('Mac OS')
                  ? 'Mac'
                  : s.contains('Linux')
                      ? 'Linux'
                      : 'Appareil';
  final app = s.startsWith('Dart/') || s.contains('dart:io')
      ? 'application Kaj'
      : s.contains('Edg/')
          ? 'Edge'
          : s.contains('Firefox/')
              ? 'Firefox'
              : s.contains('Chrome/')
                  ? 'Chrome'
                  : s.contains('Safari/')
                      ? 'Safari'
                      : 'navigateur';
  return '$os · $app';
}
