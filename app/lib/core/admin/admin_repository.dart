import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Everything the admin screens do with the server, behind one door.
///
/// Unlike the ledger, none of this is offline-first and none of it is cached.
/// That is deliberate: administering an org means changing who can see a
/// business's books, and the only thing entitled to decide whether a change is
/// allowed is the server, through the policies in 004 and 005. A queued,
/// optimistic membership grant that the server later refuses would be a
/// security hole wearing the costume of a nice UX.
///
/// So every method here talks to Supabase directly, and every one of them is
/// expected to fail when there is no signal. The screens say so.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  String? get currentUserId => _client?.auth.currentUser?.id;

  // ----------------------------------------------------------------
  // The business itself
  // ----------------------------------------------------------------

  Future<Map<String, dynamic>> fetchOrg(String orgId) async {
    final client = _requireClient();
    final row = await client
        .from('orgs')
        .select('id, name, slug, profile, default_currency, custom_domain')
        .eq('id', orgId)
        .single();
    return Map<String, dynamic>.from(row);
  }

  /// Only the fields an org admin is allowed to change from a phone. `slug`
  /// and `profile` are absent on purpose: the slug is a live subdomain and the
  /// profile decides which home screen every member of the org lands on, so
  /// neither is a thing to fat-finger in a settings form.
  Future<void> updateOrg(
    String orgId, {
    required String name,
    required String currency,
  }) async {
    final client = _requireClient();
    await client
        .from('orgs')
        .update({'name': name, 'default_currency': currency})
        .eq('id', orgId);
  }

  // ----------------------------------------------------------------
  // Sites and departments
  // ----------------------------------------------------------------

  /// Entities with their departments nested, in one round trip.
  Future<List<Entity>> fetchStructure(String orgId) async {
    final client = _requireClient();
    final rows = await client
        .from('entities')
        .select('id, org_id, name, kind, departments(id, entity_id, name)')
        .eq('org_id', orgId)
        .order('name');
    return (rows as List)
        .map((r) => Entity.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> createEntity(String orgId, String name, {String? kind}) async {
    final client = _requireClient();
    await client.from('entities').insert({
      'org_id': orgId,
      'name': name,
      if (kind != null && kind.isNotEmpty) 'kind': kind,
    });
  }

  Future<void> renameEntity(String entityId, String name) async {
    final client = _requireClient();
    await client.from('entities').update({'name': name}).eq('id', entityId);
  }

  Future<void> createDepartment(String entityId, String name) async {
    final client = _requireClient();
    await client
        .from('departments')
        .insert({'entity_id': entityId, 'name': name});
  }

  Future<void> renameDepartment(String departmentId, String name) async {
    final client = _requireClient();
    await client
        .from('departments')
        .update({'name': name}).eq('id', departmentId);
  }

  // ----------------------------------------------------------------
  // People
  // ----------------------------------------------------------------

  /// Every grant in the org, joined to who holds it. The join is only visible
  /// because 004 lets an admin read their org's memberships and the profiles
  /// of people they share an org with.
  Future<List<Member>> fetchMembers(String orgId) async {
    final client = _requireClient();
    final rows = await client
        .from('memberships')
        .select(
          'id, user_id, role, scope_kind, scope_id, visibility, '
          'profiles(full_name, phone)',
        )
        .eq('org_id', orgId);
    return (rows as List)
        .map((r) => Member.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  /// Revoking a grant, not deleting a person. Someone who holds two roles
  /// keeps the other one.
  Future<void> revokeMembership(String membershipId) async {
    final client = _requireClient();
    await client.from('memberships').delete().eq('id', membershipId);
  }

  // ----------------------------------------------------------------
  // Invitations
  // ----------------------------------------------------------------

  Future<List<Invitation>> fetchInvitations(String orgId) async {
    final client = _requireClient();
    final rows = await client
        .from('pending_invitations')
        .select(
          'id, org_id, code, role, scope_kind, scope_id, phone, email, '
          'expires_at, claimed_at',
        )
        .eq('org_id', orgId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Invitation.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Issues an invitation and returns it, code and all.
  ///
  /// The code is left to the column default — `new_invitation_code()` in 005
  /// mints it server-side over a CSPRNG. The client never invents one, because
  /// a client-generated code is only as unguessable as the client.
  ///
  /// [phone] pins the invitation to one number: only that person can claim it,
  /// and they get it swept up automatically the next time they sign in.
  /// Leaving it null makes a bearer code — whoever holds it, claims it — which
  /// is the hand-it-over-in-person case the QR exists for.
  Future<Invitation> createInvitation({
    required String orgId,
    required String role,
    required String scopeKind,
    required String scopeId,
    String? phone,
    String? email,
    String visibility = 'full',
    Duration validFor = const Duration(days: 14),
  }) async {
    final client = _requireClient();
    final userId = currentUserId;
    if (userId == null) {
      throw StateError('Reconnectez-vous avant de créer une invitation.');
    }

    final row = await client
        .from('pending_invitations')
        .insert({
          'org_id': orgId,
          'role': role,
          'scope_kind': scopeKind,
          'scope_id': scopeId,
          'visibility': visibility,
          'phone': (phone != null && phone.isNotEmpty) ? phone : null,
          'email': (email != null && email.isNotEmpty) ? email : null,
          'expires_at':
              DateTime.now().toUtc().add(validFor).toIso8601String(),
          // The policy in 005 requires this to be the caller; sending it
          // explicitly keeps the failure a clear one rather than a null.
          'created_by': userId,
        })
        .select(
          'id, org_id, code, role, scope_kind, scope_id, phone, email, '
          'expires_at, claimed_at',
        )
        .single();

    return Invitation.fromRow(Map<String, dynamic>.from(row));
  }

  /// Withdraws an unclaimed invitation. A claimed one is the record of how
  /// somebody got in, and 005 will not delete it.
  Future<void> revokeInvitation(String invitationId) async {
    final client = _requireClient();
    await client.from('pending_invitations').delete().eq('id', invitationId);
  }

  // ----------------------------------------------------------------
  // The other side: joining
  // ----------------------------------------------------------------

  /// The business a code belongs to, or null if the code is unknown, spent or
  /// expired. Runs for anyone — this is the one thing 005 grants to `anon`,
  /// and it returns the name and nothing else.
  Future<String?> previewInvitation(String code) async {
    final client = _requireClient();
    final name = await client.rpc('invitation_preview', params: {'p_code': code});
    return name as String?;
  }

  /// Turns a code into a membership. Idempotent server-side, so a double tap
  /// or a retry after a dropped connection is harmless.
  ///
  /// Returns the org id that was joined.
  Future<String> claimInvitation(String code) async {
    final client = _requireClient();
    final orgId = await client.rpc('claim_invitation', params: {'p_code': code});
    return orgId as String;
  }

  /// The sign-in sweep: claims anything addressed to this person's phone or
  /// email with nothing to type. Returns how many orgs were newly joined.
  ///
  /// Never throws — this runs on a path where a failure must not stop someone
  /// signing in. A missed invitation is picked up on the next launch, or by
  /// typing the code.
  Future<int> claimMyInvitations() async {
    final client = _client;
    if (client == null) return 0;
    try {
      final n = await client.rpc('claim_my_invitations');
      return (n as int?) ?? 0;
    } catch (_) {
      return 0;
    }
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
}
