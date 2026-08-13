// What the app knows about who is using it and which businesses they belong
// to. Both of these are cached on the device, because Ignace can go weeks
// without signal and the app has to know who he is the whole time.

/// One business the signed-in user belongs to.
///
/// This is one row per org, not one per membership: someone who is both a
/// department supervisor and an org-wide observer still runs one business.
class OrgSummary {
  const OrgSummary({
    required this.id,
    required this.name,
    required this.profile,
    this.slug,
    this.currency = 'XOF',
    this.roles = const [],
    this.visibility = 'full',
  });

  final String id;
  final String name;

  /// 'church' | 'farm' | 'retail' | 'generic' — decides which home screen the
  /// user lands on. Unknown values fall through to the generic screen rather
  /// than crashing, so adding a profile server-side never breaks old builds.
  final String profile;

  final String? slug;
  final String currency;
  final List<String> roles;

  /// 'full' | 'summary' — an investor granted summary visibility sees totals,
  /// not the individual entries behind them.
  final String visibility;

  bool get isObserverOnly =>
      roles.isNotEmpty && roles.every((r) => r == 'observer');

  /// Whether to offer this person the administration screens.
  ///
  /// Deliberately the same role list as `is_org_admin()` in 004. This decides
  /// whether a menu entry is drawn and nothing more — every admin action is
  /// refused server-side by that function regardless of what the client
  /// believes, so a stale cached role list cannot become a privilege.
  /// `platform_admin` is in this list and it is not decoration.
  ///
  /// `my_orgs()` has returned that single role for a platform admin since
  /// 010 — they are a member of no business and see all of them — and this
  /// predicate only ever knew the three membership roles. The result was that
  /// the person who runs the platform was treated as a non-admin of every
  /// business on it: no Administration, no Personnel, no way to invite
  /// anybody. Everything gated on `isAdmin` was invisible to exactly the
  /// account most likely to need it.
  bool get isAdmin => roles.any((r) =>
      r == 'owner' ||
      r == 'super_admin' ||
      r == 'admin' ||
      r == 'platform_admin');

  /// Whether to offer this person the console — the activity log and the shape
  /// of the database.
  ///
  /// Narrower than [isAdmin] on purpose, and narrower than the server, which
  /// gates the console's functions on `is_org_admin()` and so admits a plain
  /// admin too. The log says what every colleague has been doing and the
  /// database view says what the business is made of; neither is something to
  /// put one tap from a home screen for everybody who can invite an employee.
  /// Widening it is a one-line change here; a rule that started wide is not
  /// one that can be narrowed later without taking something away.
  bool get isSuperAdmin => roles.any(
      (r) => r == 'owner' || r == 'super_admin' || r == 'platform_admin');

  /// The row shape returned by the `my_orgs()` RPC in 004_rls_policies.sql.
  factory OrgSummary.fromRpc(Map<String, dynamic> row) {
    return OrgSummary(
      id: row['org_id'] as String,
      name: row['name'] as String,
      profile: (row['profile'] as String?) ?? 'generic',
      slug: row['slug'] as String?,
      currency: (row['default_currency'] as String?) ?? 'XOF',
      roles: (row['roles'] as List?)?.map((r) => r.toString()).toList() ?? [],
      visibility: (row['visibility'] as String?) ?? 'full',
    );
  }

  factory OrgSummary.fromCache(Map<String, Object?> row) {
    final roles = (row['roles'] as String?) ?? '';
    return OrgSummary(
      id: row['org_id'] as String,
      name: row['name'] as String,
      profile: (row['profile'] as String?) ?? 'generic',
      slug: row['slug'] as String?,
      currency: (row['currency'] as String?) ?? 'XOF',
      roles: roles.isEmpty ? const [] : roles.split(','),
      visibility: (row['visibility'] as String?) ?? 'full',
    );
  }

  Map<String, Object?> toCache() => {
        'org_id': id,
        'name': name,
        'profile': profile,
        'slug': slug,
        'currency': currency,
        'roles': roles.join(','),
        'visibility': visibility,
      };
}

/// Who this device belongs to, as last confirmed by the server.
///
/// The PIN fields are what make offline re-entry possible: the access token
/// expires within the hour and cannot be refreshed without signal, so after
/// that the PIN is the only thing standing between a lost phone and a
/// congregation's giving records.
class LocalIdentity {
  const LocalIdentity({
    required this.userId,
    this.displayName,
    this.phone,
    this.email,
    this.pinSalt,
    this.pinHash,
    this.orgsRefreshedAt,
  });

  final String userId;
  final String? displayName;
  final String? phone;
  final String? email;
  final String? pinSalt;
  final String? pinHash;
  final DateTime? orgsRefreshedAt;

  bool get hasPin => pinSalt != null && pinHash != null;

  /// What to call this person on screen when there is no full name yet.
  String get label => displayName?.trim().isNotEmpty == true
      ? displayName!
      : (phone ?? email ?? 'Utilisateur');

  LocalIdentity copyWith({
    String? displayName,
    String? phone,
    String? email,
    String? pinSalt,
    String? pinHash,
    DateTime? orgsRefreshedAt,
  }) {
    return LocalIdentity(
      userId: userId,
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      pinSalt: pinSalt ?? this.pinSalt,
      pinHash: pinHash ?? this.pinHash,
      orgsRefreshedAt: orgsRefreshedAt ?? this.orgsRefreshedAt,
    );
  }

  factory LocalIdentity.fromRow(Map<String, Object?> row) {
    final refreshed = row['orgs_refreshed_at'] as String?;
    return LocalIdentity(
      userId: row['user_id'] as String,
      displayName: row['display_name'] as String?,
      phone: row['phone'] as String?,
      email: row['email'] as String?,
      pinSalt: row['pin_salt'] as String?,
      pinHash: row['pin_hash'] as String?,
      orgsRefreshedAt: refreshed == null ? null : DateTime.parse(refreshed),
    );
  }

  Map<String, Object?> toRow() => {
        'id': 1,
        'user_id': userId,
        'display_name': displayName,
        'phone': phone,
        'email': email,
        'pin_salt': pinSalt,
        'pin_hash': pinHash,
        'orgs_refreshed_at': orgsRefreshedAt?.toIso8601String(),
      };
}
