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

  // ----------------------------------------------------------------
  // Running the platform
  // ----------------------------------------------------------------

  /// Whether the signed-in person carries `is_platform_admin` on their profile.
  ///
  /// Asked of the server rather than read from `my_orgs()`: a platform admin
  /// whose bypass lists every business still lists nothing at all when no
  /// business exists yet, and that is exactly the moment the Create Business
  /// screen has to be reachable.
  ///
  /// Never cached — see this class's doc comment — and false on any failure,
  /// including a server that has not run 010 yet, where the column does not
  /// exist. Being wrong here costs a hidden menu entry; `create_org` refuses
  /// on its own authority regardless of what the client believes.
  Future<bool> isPlatformAdmin() async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return false;
    try {
      final row = await client
          .from('profiles')
          .select('is_platform_admin')
          .eq('id', userId)
          .maybeSingle();
      return row?['is_platform_admin'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Creates a business and returns its id.
  ///
  /// `create_org` is SECURITY DEFINER and checks the platform-admin flag
  /// itself, so this call is refused server-side for everyone else however it
  /// is reached. It also makes the caller the new org's owner and seeds a
  /// starter chart of accounts.
  Future<String> createOrg({
    required String name,
    required String slug,
    required String profile,
    required String currency,
  }) async {
    final client = _requireClient();
    final id = await client.rpc('create_org', params: {
      'p_name': name,
      'p_slug': slug,
      'p_profile': profile,
      'p_currency': currency,
    });
    return id as String;
  }

  // ----------------------------------------------------------------
  // The lifecycle of a business (014)
  // ----------------------------------------------------------------

  /// Every business on the platform, archived ones included.
  ///
  /// Refused server-side for anyone who is not a platform admin — `all_orgs()`
  /// raises rather than returning an empty list, so a caller who is not
  /// entitled gets an error and not the false impression of an empty
  /// platform.
  Future<List<PlatformOrg>> allOrgs({bool includeArchived = true}) async {
    final client = _requireClient();
    final rows = await client.rpc('all_orgs', params: {
      'p_include_archived': includeArchived,
    }) as List<dynamic>;

    return rows
        .map((r) => PlatformOrg.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Changes a business. Null leaves a field alone rather than blanking it.
  ///
  /// Allowed for an org's own admins as well as a platform admin — renaming
  /// your own shop is not an escalation, and 004's policy already said so.
  ///
  /// This replaced a direct `orgs` UPDATE that took only a name and a
  /// currency. `slug` and `profile` were left out of that one so they could
  /// not be fat-fingered in a phone settings form, and the org settings screen
  /// still passes neither — but the rule now lives in `update_org()`, which
  /// validates the slug, refuses an unknown profile, and answers a refusal
  /// with a sentence instead of the silent zero-rows an RLS-blocked UPDATE
  /// returns.
  Future<void> updateOrg({
    required String orgId,
    String? name,
    String? slug,
    String? profile,
    String? currency,
  }) async {
    final client = _requireClient();
    await client.rpc('update_org', params: {
      'p_org_id': orgId,
      if (name != null && name.isNotEmpty) 'p_name': name,
      if (slug != null && slug.isNotEmpty) 'p_slug': slug,
      if (profile != null && profile.isNotEmpty) 'p_profile': profile,
      if (currency != null && currency.isNotEmpty) 'p_currency': currency,
    });
  }

  /// Puts a business away. Reversible, keeps every entry, and takes it off
  /// every member's home screen at once — which is why it is platform-admin
  /// only even though renaming is not.
  Future<void> archiveOrg(String orgId) async {
    final client = _requireClient();
    await client.rpc('archive_org', params: {'p_org_id': orgId});
  }

  Future<void> restoreOrg(String orgId) async {
    final client = _requireClient();
    await client.rpc('restore_org', params: {'p_org_id': orgId});
  }

  /// Destroys a business and everything in it. Permanent.
  ///
  /// [confirmName] must equal the business's own name; the server checks it
  /// rather than trusting the dialog, and refuses unless the business has
  /// already been archived. [force] is the second, deliberate act required
  /// when the books are not empty — without it the server refuses and says
  /// how many entries would be destroyed.
  Future<void> deleteOrg({
    required String orgId,
    required String confirmName,
    bool force = false,
  }) async {
    final client = _requireClient();
    await client.rpc('delete_org', params: {
      'p_org_id': orgId,
      'p_confirm_name': confirmName,
      'p_force': force,
    });
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

/// A business as the platform sees it, rather than as one of its members
/// does: with its size, and with whether it has been put away.
class PlatformOrg {
  const PlatformOrg({
    required this.id,
    required this.name,
    required this.slug,
    required this.profile,
    this.currency = 'XOF',
    this.archivedAt,
    this.memberCount = 0,
    this.entryCount = 0,
    this.createdAt,
  });

  final String id;
  final String name;
  final String slug;
  final String profile;
  final String currency;

  /// Null for a live business. Set means archived: still complete, still
  /// restorable, and off every member's home screen.
  final DateTime? archivedAt;

  final int memberCount;
  final int entryCount;
  final DateTime? createdAt;

  bool get isArchived => archivedAt != null;

  /// Whether deleting it would destroy anybody's history. Drives whether the
  /// delete dialog asks once or twice; the server makes the same test and is
  /// the one that decides.
  bool get hasBooks => entryCount > 0;

  factory PlatformOrg.fromRow(Map<String, dynamic> row) {
    DateTime? when(Object? v) =>
        v == null ? null : DateTime.tryParse('$v')?.toLocal();

    return PlatformOrg(
      id: row['org_id'] as String,
      name: row['name'] as String,
      slug: (row['slug'] as String?) ?? '',
      profile: (row['profile'] as String?) ?? 'generic',
      currency: (row['currency'] as String?) ?? 'XOF',
      archivedAt: when(row['archived_at']),
      memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
      entryCount: (row['entry_count'] as num?)?.toInt() ?? 0,
      createdAt: when(row['created_at']),
    );
  }
}
