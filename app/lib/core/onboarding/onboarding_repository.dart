import 'package:supabase_flutter/supabase_flutter.dart';

import 'application_form.dart';

/// Getting into the app: saying who you are, and then joining a business —
/// or, since 111, creating one's own (business_creation.dart).
///
/// **An employee joins something that already exists.** They fill in the
/// form, then enter the code their manager sent them. The code is what grants
/// access — nothing about completing the form does — so somebody who fills in
/// every field and has no code belongs to no business and can see nothing.
///
/// **Somebody starting a business creates it** (create_my_business, 111):
/// no request, no wait. The creation page Mara shapes — its welcome, its
/// kinds, its questions — is 107's application form, read and written here.
/// The request path of before (apply_for_org, the approval) stays on the
/// server for an older app; nothing here calls it.
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
  // The creation page (107's form, which shapes 111's creation)
  // ----------------------------------------------------------------

  /// The creation page Mara set (107), or null for the page of origin —
  /// also on a database before 107 or with no signal. [strict] is the
  /// editor's: a failure is said rather than read as « no page », so a save
  /// cannot write over a page it never read.
  Future<ApplicationForm?> applicationForm({bool strict = false}) async {
    final client = _client;
    if (client == null) return null;
    try {
      return ApplicationForm.fromJson(await client.rpc('application_form'));
    } catch (_) {
      if (strict) rethrow;
      return null;
    }
  }

  /// Sets the creation page (the platform's; 107 checks it and keeps it in
  /// a clean shape). Null or an empty form returns it to today's. Returns
  /// the journal line for « Annuler », or null when nothing changed.
  Future<String?> setApplicationForm(ApplicationForm? form) async {
    final client = _requireClient();
    final id = await client.rpc('platform_set_application_form', params: {
      'p_form': form == null || form.isEmpty ? null : form.toJson(),
    });
    return id as String?;
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
      'Bonjour ! Vous êtes invité(e) à rejoindre « $orgName » sur Mara.\n\n'
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
