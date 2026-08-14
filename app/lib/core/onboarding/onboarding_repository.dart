import 'package:supabase_flutter/supabase_flutter.dart';

/// Getting into the app: saying who you are, and then either joining a
/// business or asking for one.
///
/// The two routes are deliberately different shapes, and the difference is
/// the point.
///
/// **An employee joins something that already exists.** They fill in the
/// form, then enter the code their manager sent them. The code is what grants
/// access — nothing about completing the form does — so somebody who fills in
/// every field and has no code belongs to no business and can see nothing.
///
/// **A manager asks for a business to exist.** They fill in the same form,
/// describe the business, and wait for somebody at Kaj-consulting to look at
/// it. `create_org()` has been platform-admin-only since 010 and stays that
/// way: whether a new tenant appears is a decision, not a form submission.
class OnboardingRepository {
  OnboardingRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  String? get currentUserId => _client?.auth.currentUser?.id;

  // ----------------------------------------------------------------
  // Who somebody is
  // ----------------------------------------------------------------

  /// Whether there is enough on file to put on a contract.
  ///
  /// False on any failure, including a database that has not run 017 yet.
  /// Being wrong costs one extra prompt; the server decides for real.
  Future<bool> isProfileComplete() async {
    final client = _client;
    if (client == null) return false;
    try {
      final result = await client.rpc('profile_is_complete');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> myProfile() async {
    final client = _client;
    final id = currentUserId;
    if (client == null || id == null) return null;
    try {
      final row = await client
          .from('profiles')
          .select('first_name, middle_name, last_name, date_of_birth, '
              'title, phone, full_name')
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile({
    required String firstName,
    required String lastName,
    String? middleName,
    DateTime? dateOfBirth,
    String? title,
    String? phone,
  }) async {
    final client = _requireClient();
    await client.rpc('save_my_profile', params: {
      'p_first_name': firstName,
      'p_last_name': lastName,
      if (middleName != null && middleName.isNotEmpty)
        'p_middle_name': middleName,
      if (dateOfBirth != null) 'p_date_of_birth': _date(dateOfBirth),
      if (title != null && title.isNotEmpty) 'p_title': title,
      if (phone != null && phone.isNotEmpty) 'p_phone': phone,
    });
  }

  // ----------------------------------------------------------------
  // Asking for a business
  // ----------------------------------------------------------------

  Future<String> applyForOrg({
    required String name,
    required String slug,
    required String profile,
    String currency = 'XOF',
    String? description,
    String? phone,
    String? email,
  }) async {
    final client = _requireClient();
    final id = await client.rpc('apply_for_org', params: {
      'p_name': name,
      'p_slug': slug,
      'p_profile': profile,
      'p_currency': currency,
      if (description != null && description.isNotEmpty)
        'p_description': description,
      if (phone != null && phone.isNotEmpty) 'p_phone': phone,
      if (email != null && email.isNotEmpty) 'p_email': email,
    });
    return id as String;
  }

  /// The applicant's own application, or null if they never made one.
  Future<OrgApplication?> myApplication() async {
    final client = _client;
    if (client == null) return null;
    try {
      final rows = await client.rpc('my_org_application') as List<dynamic>;
      if (rows.isEmpty) return null;
      return OrgApplication.fromRow(
          Map<String, dynamic>.from(rows.first as Map));
    } catch (_) {
      // A database without 017 yet. Treated as "never applied", which is what
      // it looks like from here.
      return null;
    }
  }

  // ----------------------------------------------------------------
  // The platform's queue
  // ----------------------------------------------------------------

  /// Refused server-side for anyone who is not a platform admin — it raises
  /// rather than returning an empty list, so somebody not entitled gets an
  /// error instead of the false impression of an empty queue.
  Future<List<OrgApplication>> pendingApplications() async {
    final client = _requireClient();
    final rows = await client.rpc('pending_org_applications') as List<dynamic>;
    return rows
        .map((r) => OrgApplication.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Creates the business and makes the applicant its owner, in one
  /// transaction. Returns the new org's id.
  Future<String> approve(String applicationId, {String? note}) async {
    final client = _requireClient();
    final id = await client.rpc('approve_org_application', params: {
      'p_application_id': applicationId,
      if (note != null && note.isNotEmpty) 'p_note': note,
    });
    return id as String;
  }

  /// The reason is required by the server, not just by this form: a rejection
  /// somebody cannot act on produces the same application again next week.
  Future<void> reject(String applicationId, String reason) async {
    final client = _requireClient();
    await client.rpc('reject_org_application', params: {
      'p_application_id': applicationId,
      'p_note': reason,
    });
  }

  // ----------------------------------------------------------------
  // Inviting somebody
  // ----------------------------------------------------------------

  /// Issues an invitation and hands back everything needed to send it.
  ///
  /// The business's name comes back with the code so the app can compose the
  /// message without a second round trip — which matters, because the sharing
  /// sheet opens immediately after this returns.
  Future<Invitation> invite({
    required String orgId,
    String role = 'employee',
    String? fullName,
    String? title,
    String? phone,
    String visibility = 'full',
    int validDays = 14,
    String? note,
  }) async {
    final client = _requireClient();
    final rows = await client.rpc('invite_employee', params: {
      'p_org_id': orgId,
      'p_role': role,
      if (fullName != null && fullName.isNotEmpty) 'p_full_name': fullName,
      if (title != null && title.isNotEmpty) 'p_title': title,
      if (phone != null && phone.isNotEmpty) 'p_phone': phone,
      'p_visibility': visibility,
      'p_valid_days': validDays,
      if (note != null && note.isNotEmpty) 'p_note': note,
    }) as List<dynamic>;

    if (rows.isEmpty) {
      throw StateError("L'invitation n'a pas été créée.");
    }
    return Invitation.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
}

/// Somebody asking for a business to exist.
class OrgApplication {
  const OrgApplication({
    required this.id,
    required this.name,
    required this.slug,
    required this.profile,
    this.status = 'pending',
    this.applicant,
    this.applicantId,
    this.currency = 'XOF',
    this.contactPhone,
    this.contactEmail,
    this.description,
    this.decisionNote,
    this.createdAt,
    this.reviewedAt,
    this.orgId,
  });

  final String id;
  final String name;
  final String slug;
  final String profile;
  final String status;

  /// Filled on the platform's queue; null on the applicant's own view, where
  /// they already know who they are.
  final String? applicant;
  final String? applicantId;

  final String currency;
  final String? contactPhone;
  final String? contactEmail;
  final String? description;

  /// Why it was refused. Required of the reviewer, so it is never null on a
  /// rejected application.
  final String? decisionNote;

  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String? orgId;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory OrgApplication.fromRow(Map<String, dynamic> row) {
    DateTime? when(Object? v) =>
        v == null ? null : DateTime.tryParse('$v')?.toLocal();

    return OrgApplication(
      id: row['id'] as String,
      name: (row['name'] as String?) ?? '',
      slug: (row['slug'] as String?) ?? '',
      profile: (row['profile'] as String?) ?? 'generic',
      status: (row['status'] as String?) ?? 'pending',
      applicant: row['applicant'] as String?,
      applicantId: row['applicant_id'] as String?,
      currency: (row['currency'] as String?) ?? 'XOF',
      contactPhone: row['contact_phone'] as String?,
      contactEmail: row['contact_email'] as String?,
      description: row['description'] as String?,
      decisionNote: row['decision_note'] as String?,
      createdAt: when(row['created_at']),
      reviewedAt: when(row['reviewed_at']),
      orgId: row['org_id'] as String?,
    );
  }
}

/// A code a manager sends somebody, and what is needed to send it.
class Invitation {
  const Invitation({
    required this.id,
    required this.code,
    required this.orgName,
    this.expiresAt,
  });

  final String id;
  final String code;
  final String orgName;
  final DateTime? expiresAt;

  /// The message that actually gets sent. WhatsApp is where this conversation
  /// happens, so the code is on its own line and the instruction is short
  /// enough to read on a lock screen.
  String get message =>
      'Bonjour ! Vous êtes invité(e) à rejoindre « $orgName » sur Kaj.\n\n'
      '1. Installez l\'application\n'
      '2. Créez votre compte\n'
      '3. Entrez ce code :\n\n'
      '$code\n\n'
      "Le code expire dans ${expiresAt == null ? 'quelques jours' : '${expiresAt!.difference(DateTime.now()).inDays} jours'}.";

  factory Invitation.fromRow(Map<String, dynamic> row) => Invitation(
        id: row['invitation_id'] as String,
        code: row['code'] as String,
        orgName: (row['org_name'] as String?) ?? '',
        expiresAt: row['expires_at'] == null
            ? null
            : DateTime.tryParse('${row['expires_at']}')?.toLocal(),
      );
}
