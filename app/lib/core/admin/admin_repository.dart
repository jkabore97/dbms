import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../rates/currency_rates.dart';
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
  AdminRepository(
    this._client, {
    String accountAdminUrl = '',
    http.Client? httpClient,
  })  : _accountUrl = _trimSlash(accountAdminUrl),
        _http = httpClient ?? http.Client();

  final SupabaseClient? _client;

  /// The account Worker's origin, from `--dart-define=ACCOUNT_ADMIN_URL`. Empty
  /// until the Worker is deployed and the app rebuilt to know its address, in
  /// which case the password-reset and delete-account actions stay hidden — the
  /// same "deployed dormant" posture the camera and the handwriting reader take.
  final String _accountUrl;
  final http.Client _http;

  bool get isConfigured => _client != null;

  /// Whether admin-set passwords and account deletion are available at all —
  /// i.e. whether the account Worker's address was compiled in.
  bool get canManageAccounts => _client != null && _accountUrl.isNotEmpty;

  String? get currentUserId => _client?.auth.currentUser?.id;

  static String _trimSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  // ----------------------------------------------------------------
  // The business itself
  // ----------------------------------------------------------------

  static const _orgColumns =
      'id, name, slug, profile, default_currency, custom_domain';

  Future<Map<String, dynamic>> fetchOrg(String orgId) async {
    final client = _requireClient();
    try {
      final row = await client
          .from('orgs')
          .select('$_orgColumns, theme')
          .eq('id', orgId)
          .single();
      return Map<String, dynamic>.from(row);
    } on PostgrestException catch (error) {
      // 42703 is "column does not exist": this database has not run 022 yet.
      // The app deploys on a push to main and the migrations are applied by
      // hand afterwards, so being one migration ahead is a normal state, not
      // an exceptional one — and asking for a colour that does not exist yet
      // must not take the whole settings screen down with it.
      if (error.code != '42703') rethrow;
      final row = await client
          .from('orgs')
          .select(_orgColumns)
          .eq('id', orgId)
          .single();
      return Map<String, dynamic>.from(row);
    }
  }

  /// The business's Wave handle (037), or null when unset — or when the column
  /// does not exist yet, since the app can run one migration ahead of the
  /// database, the same reason fetchOrg tolerates a missing `theme`.
  Future<String?> waveMerchant(String orgId) async {
    final client = _requireClient();
    try {
      final row = await client
          .from('orgs')
          .select('wave_merchant')
          .eq('id', orgId)
          .maybeSingle();
      final value = row?['wave_merchant'] as String?;
      return (value != null && value.trim().isNotEmpty) ? value : null;
    } on PostgrestException catch (error) {
      if (error.code == '42703') return null; // database not on 037 yet
      rethrow;
    }
  }

  /// Sets (or clears, with null) the business's Wave handle. Admin-only,
  /// enforced by set_org_wave() server-side.
  Future<void> setWaveMerchant(String orgId, String? merchant) async {
    final client = _requireClient();
    await client.rpc('set_org_wave', params: {
      'p_org_id': orgId,
      'p_merchant': merchant,
    });
  }

  // ----------------------------------------------------------------
  // À la une (054): the paid spots on the welcome page. Platform only, and
  // the server is the one that says so.
  // ----------------------------------------------------------------

  /// Every article currently in a window, with its shop and its spot's end
  /// date if it has one — what the platform chooses from.
  Future<List<FeaturedCandidate>> featuredCandidates() async {
    final rows = await _requireClient().rpc('platform_featured_candidates')
        as List<dynamic>;
    return rows
        .map((r) =>
            FeaturedCandidate.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Puts an article à la une until [until], or takes it down with null.
  Future<void> setProductFeatured(String productId, DateTime? until) async {
    await _requireClient().rpc('set_product_featured', params: {
      'p_product_id': productId,
      'p_until': until?.toUtc().toIso8601String(),
    });
  }

  // ----------------------------------------------------------------
  // Exchange rates (039). Direct table ops: RLS lets members read and only
  // admins write, so there is nothing to wrap. Missing table (a database not
  // yet on 039) reads as "no rates", same posture as the Wave column.
  // ----------------------------------------------------------------

  Future<List<CurrencyRate>> currencyRates(String orgId) async {
    final client = _requireClient();
    try {
      final rows = await client
          .from('org_currency_rates')
          .select('currency, rate')
          .eq('org_id', orgId)
          .order('currency');
      return (rows as List)
          .map((r) => CurrencyRate.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (error) {
      if (error.code == '42P01') return const []; // database not on 039 yet
      rethrow;
    }
  }

  /// Sets 1 [currency] = [rate] in the business's home currency. Upsert, so
  /// editing a rate is the same call as adding one.
  Future<void> setCurrencyRate(String orgId, String currency, double rate) async {
    final client = _requireClient();
    await client.from('org_currency_rates').upsert({
      'org_id': orgId,
      'currency': currency.toUpperCase(),
      'rate': rate,
      'updated_by': currentUserId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> removeCurrencyRate(String orgId, String currency) async {
    final client = _requireClient();
    await client
        .from('org_currency_rates')
        .delete()
        .eq('org_id', orgId)
        .eq('currency', currency.toUpperCase());
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
    // Trainers (038) hold an observer membership so they can read to advise,
    // but they are the platform's people, not the business's — so they are
    // kept out of the roster. The filter degrades gracefully on a database that
    // has not run 038 yet (42703), where there are no trainers to exclude.
    try {
      final rows = await client
          .from('memberships')
          .select(
            'id, user_id, role, scope_kind, scope_id, visibility, '
            'profiles(full_name, phone, first_name, middle_name, last_name, date_of_birth, title)',
          )
          .eq('org_id', orgId)
          .eq('is_trainer', false);
      return _members(rows as List);
    } on PostgrestException catch (error) {
      if (error.code != '42703') rethrow;
      final rows = await client
          .from('memberships')
          .select(
            'id, user_id, role, scope_kind, scope_id, visibility, '
            'profiles(full_name, phone, first_name, middle_name, last_name, date_of_birth, title)',
          )
          .eq('org_id', orgId);
      return _members(rows as List);
    }
  }

  List<Member> _members(List rows) => rows
      .map((r) => Member.fromRow(Map<String, dynamic>.from(r as Map)))
      .toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  /// Revoking a grant, not deleting a person. Someone who holds two roles
  /// keeps the other one.
  Future<void> revokeMembership(String membershipId) async {
    final client = _requireClient();
    await client.from('memberships').delete().eq('id', membershipId);
  }

  /// Changes a member's responsibility. Owner-of-the-org only, and never the
  /// owner's own role — the server (044) enforces both.
  Future<void> setMembershipRole(String membershipId, String role) async {
    final client = _requireClient();
    await client.rpc('set_membership_role', params: {
      'p_membership_id': membershipId,
      'p_role': role,
    });
  }

  /// Edits another member's own information — names, phone, date of birth,
  /// title. Runs through admin_save_member_profile (046), which lets an admin
  /// edit only someone they outrank; the server is the enforcement.
  Future<void> saveMemberProfile(
    String userId, {
    required String firstName,
    required String lastName,
    String? middleName,
    DateTime? dateOfBirth,
    String? title,
    String? phone,
  }) async {
    final client = _requireClient();
    await client.rpc('admin_save_member_profile', params: {
      'p_user_id': userId,
      'p_first_name': firstName,
      'p_last_name': lastName,
      if (middleName != null && middleName.isNotEmpty) 'p_middle_name': middleName,
      if (dateOfBirth != null) 'p_date_of_birth': _dateOnly(dateOfBirth),
      if (title != null && title.isNotEmpty) 'p_title': title,
      if (phone != null && phone.isNotEmpty) 'p_phone': phone,
    });
  }

  static String _dateOnly(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Sets a new password for another user — an admin resetting an employee's.
  /// Goes through the account Worker, the one holder of the service-role key;
  /// the Worker re-checks with the server that the caller may manage this user
  /// before it acts. [canManageAccounts] gates whether this is even offered.
  Future<void> setUserPassword(String userId, String password) async {
    await _accountPost('/v1/users/$userId/password', {'password': password});
  }

  /// Deletes a user's account outright: they are removed from the database and
  /// signed out, and their next sign-in lands on the waiting page. Same Worker,
  /// same server-side re-check (can_delete_user), which refuses an owner, the
  /// caller themselves, and any cross-tenant deletion.
  Future<void> deleteUserAccount(String userId) async {
    await _accountPost('/v1/users/$userId/delete', const {});
  }

  Future<void> _accountPost(String path, Map<String, dynamic> body) async {
    if (_accountUrl.isEmpty) {
      throw StateError(
        "La gestion des comptes n'est pas configurée sur cette installation.",
      );
    }
    final token = _client?.auth.currentSession?.accessToken;
    if (token == null) {
      throw StateError('Connectez-vous d\'abord.');
    }
    final response = await _http.post(
      Uri.parse('$_accountUrl$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode >= 400) {
      throw StateError(_accountError(response));
    }
  }

  static String _accountError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return "L'opération a échoué. Réessayez.";
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
          'expires_at': DateTime.now().toUtc().add(validFor).toIso8601String(),
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
    final name =
        await client.rpc('invitation_preview', params: {'p_code': code});
    return name as String?;
  }

  /// Turns a code into a membership. Idempotent server-side, so a double tap
  /// or a retry after a dropped connection is harmless.
  ///
  /// Returns the org id that was joined.
  Future<String> claimInvitation(String code) async {
    final client = _requireClient();
    final orgId =
        await client.rpc('claim_invitation', params: {'p_code': code});
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

  /// The palette this business shows everybody who opens it.
  ///
  /// Its own call rather than another argument on [updateOrg] because the two
  /// are used at different moments: the settings form is filled in once, and
  /// this fires while somebody is trying colours out. Passing null clears it,
  /// which puts the business back on its profile's colour.
  Future<void> setOrgTheme({required String orgId, String? theme}) async {
    final client = _requireClient();
    await client.rpc('set_org_theme', params: {
      'p_org_id': orgId,
      // Sent explicitly rather than omitted: omitting it would take the
      // function's default, which is also null, but only by luck. Clearing a
      // colour is a thing the caller asked for, not an absence.
      'p_theme': (theme == null || theme.isEmpty) ? null : theme,
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

  /// Freeze a business, or thaw it (049). Platform admin only — the server
  /// refuses anyone else. A frozen business goes read-only for its members;
  /// its data is untouched, and thawing restores writes exactly.
  Future<void> setOrgSuspended(String orgId, bool suspend) async {
    final client = _requireClient();
    await client.rpc('set_org_suspended',
        params: {'p_org_id': orgId, 'p_suspend': suspend});
  }

  /// The vitrine switch and its blurb (052). A database that has not run 052
  /// yet reads as "closed" — the same posture as the Wave column, because the
  /// app runs one migration ahead of the database by design.
  Future<({bool enabled, String? blurb, double? lat, double? lng})> storefront(
      String orgId) async {
    final client = _requireClient();
    double? num_(Object? v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
    try {
      final row = await client
          .from('orgs')
          .select('storefront_enabled, storefront_blurb, lat, lng')
          .eq('id', orgId)
          .maybeSingle();
      return (
        enabled: row?['storefront_enabled'] == true,
        blurb: row?['storefront_blurb'] as String?,
        lat: num_(row?['lat']),
        lng: num_(row?['lng']),
      );
    } on PostgrestException catch (error) {
      // 052 or 053 not run yet: closed, unplaced.
      if (error.code == '42703') {
        return (enabled: false, blurb: null, lat: null, lng: null);
      }
      rethrow;
    }
  }

  /// Opens or closes the vitrine and sets its blurb. Admin-only, enforced by
  /// set_storefront(). The blurb is always sent — an empty string clears it —
  /// so the field on screen is exactly what the street reads.
  Future<void> setStorefront(String orgId,
      {required bool enabled, String? blurb}) async {
    final client = _requireClient();
    await client.rpc('set_storefront', params: {
      'p_org_id': orgId,
      'p_enabled': enabled,
      'p_blurb': blurb ?? '',
    });
  }

  /// Places the shop on the vitrine map, or lifts it off with both nulls.
  /// Admin-only, both-or-neither and inside the world — all enforced by
  /// set_storefront_location() (053).
  Future<void> setStorefrontLocation(String orgId,
      {double? lat, double? lng}) async {
    final client = _requireClient();
    await client.rpc('set_storefront_location', params: {
      'p_org_id': orgId,
      'p_lat': lat,
      'p_lng': lng,
    });
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

  // ----------------------------------------------------------------
  // The owner's dial (031): who sees what, who edits what
  // ----------------------------------------------------------------

  /// The rules as stored: `{tier: {feature: access}}`. Absent entries mean
  /// the preserving default ('edit', reports 'view').
  Future<Map<String, Map<String, String>>> featureRules(String orgId) async {
    final client = _requireClient();
    final rows = await client
        .from('org_feature_rules')
        .select('tier, feature, access')
        .eq('org_id', orgId);
    final out = <String, Map<String, String>>{};
    for (final r in rows as List) {
      final row = Map<String, dynamic>.from(r as Map);
      out.putIfAbsent(row['tier'] as String, () => {})[
          row['feature'] as String] = row['access'] as String;
    }
    return out;
  }

  /// The dial as it applies to one tier — what a non-admin member's own screens
  /// read on open. Empty when there is no client (offline) or the server is
  /// older than 031: exactly the "business that never touched the dial" answer,
  /// which is what an untouched or unreachable dial should look like. The
  /// dangerous actions are refused at the database regardless, so an offline
  /// employee seeing a tool they cannot use is a hidden menu entry, not a hole.
  Future<Map<String, String>> featureRulesForTier(
      String orgId, String tier) async {
    final client = _client;
    if (client == null) return const {};
    try {
      final rows = await client
          .from('org_feature_rules')
          .select('feature, access')
          .eq('org_id', orgId)
          .eq('tier', tier);
      return {
        for (final r in rows as List)
          (r as Map)['feature'] as String: r['access'] as String,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Writes the whole dial in one save. Explicit rows for every feature and
  /// tier, so what the owner saw on screen is exactly what is stored.
  Future<void> saveFeatureRules(
    String orgId,
    Map<String, Map<String, String>> rules,
  ) async {
    final client = _requireClient();
    await client.from('org_feature_rules').upsert([
      for (final tier in rules.entries)
        for (final feature in tier.value.entries)
          {
            'org_id': orgId,
            'tier': tier.key,
            'feature': feature.key,
            'access': feature.value,
            'updated_by': currentUserId,
          },
    ]);
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

/// One article the platform may put à la une (054): what it is, whose it is,
/// and until when it is on the welcome page, if it is.
class FeaturedCandidate {
  const FeaturedCandidate({
    required this.productId,
    required this.name,
    required this.price,
    required this.shopName,
    required this.shopSlug,
    this.currency = 'XOF',
    this.featuredUntil,
  });

  final String productId;
  final String name;
  final double price;
  final String shopName;
  final String shopSlug;
  final String currency;
  final DateTime? featuredUntil;

  /// On the welcome page right now: a date, and one still ahead.
  bool get live =>
      featuredUntil != null && featuredUntil!.isAfter(DateTime.now());

  factory FeaturedCandidate.fromRow(Map<String, dynamic> row) {
    final raw = row['sale_price'];
    final until = row['featured_until'] as String?;
    return FeaturedCandidate(
      productId: row['product_id'] as String,
      name: row['name'] as String,
      price: raw == null
          ? 0.0
          : (raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0),
      shopName: (row['shop_name'] as String?) ?? '',
      shopSlug: (row['shop_slug'] as String?) ?? '',
      currency: (row['currency'] as String?) ?? 'XOF',
      featuredUntil: until == null ? null : DateTime.tryParse(until)?.toLocal(),
    );
  }
}
