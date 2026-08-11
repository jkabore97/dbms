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
