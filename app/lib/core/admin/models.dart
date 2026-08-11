// The shapes the admin screens read and write. All of these live behind RLS —
// every one of them is a row the server will refuse to hand over unless the
// caller administers the org it belongs to, so nothing here is cached on the
// device the way the ledger is.

/// A location or logical unit inside a business: a farm site, a church campus,
/// a shop branch.
class Entity {
  const Entity({
    required this.id,
    required this.orgId,
    required this.name,
    this.kind,
    this.departments = const [],
  });

  final String id;
  final String orgId;
  final String name;

  /// Profile-defined and free-form: 'farm_site' | 'branch' | 'campus'.
  final String? kind;

  final List<Department> departments;

  factory Entity.fromRow(Map<String, dynamic> row) {
    final nested = (row['departments'] as List?) ?? const [];
    return Entity(
      id: row['id'] as String,
      orgId: row['org_id'] as String,
      name: row['name'] as String,
      kind: row['kind'] as String?,
      departments: nested
          .map((d) => Department.fromRow(Map<String, dynamic>.from(d as Map)))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
    );
  }
}

/// A sub-unit inside an entity: the poultry department, the choir, the till.
class Department {
  const Department({
    required this.id,
    required this.entityId,
    required this.name,
  });

  final String id;
  final String entityId;
  final String name;

  factory Department.fromRow(Map<String, dynamic> row) {
    return Department(
      id: row['id'] as String,
      entityId: row['entity_id'] as String,
      name: row['name'] as String,
    );
  }
}

/// One membership row, joined to the person holding it.
///
/// Deliberately one row per grant rather than one per person: "Manager, Poultry
/// Dept" and "Observer, Farm A" are two different things to revoke, and
/// collapsing them into a single row would hide that.
class Member {
  const Member({
    required this.membershipId,
    required this.userId,
    required this.role,
    required this.scopeKind,
    required this.scopeId,
    required this.visibility,
    this.fullName,
    this.phone,
  });

  final String membershipId;
  final String userId;
  final String role;
  final String scopeKind;
  final String scopeId;
  final String visibility;
  final String? fullName;
  final String? phone;

  /// What to call someone whose profile has no name yet — which is everyone,
  /// on the day they are invited.
  String get label {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return phone ?? 'Sans nom';
  }

  factory Member.fromRow(Map<String, dynamic> row) {
    final profile = row['profiles'] as Map?;
    return Member(
      membershipId: row['id'] as String,
      userId: row['user_id'] as String,
      role: row['role'] as String,
      scopeKind: row['scope_kind'] as String,
      scopeId: row['scope_id'] as String,
      visibility: (row['visibility'] as String?) ?? 'full',
      fullName: profile?['full_name'] as String?,
      phone: profile?['phone'] as String?,
    );
  }
}

/// An invitation that has not become a membership yet.
class Invitation {
  const Invitation({
    required this.id,
    required this.orgId,
    required this.code,
    required this.role,
    required this.scopeKind,
    required this.scopeId,
    required this.expiresAt,
    this.phone,
    this.email,
    this.claimedAt,
  });

  final String id;
  final String orgId;
  final String code;
  final String role;
  final String scopeKind;
  final String scopeId;
  final DateTime expiresAt;
  final String? phone;
  final String? email;
  final DateTime? claimedAt;

  bool get isClaimed => claimedAt != null;
  bool get isExpired => !isClaimed && expiresAt.isBefore(DateTime.now());
  bool get isOpen => !isClaimed && !isExpired;

  factory Invitation.fromRow(Map<String, dynamic> row) {
    final claimed = row['claimed_at'] as String?;
    return Invitation(
      id: row['id'] as String,
      orgId: row['org_id'] as String,
      code: row['code'] as String,
      role: row['role'] as String,
      scopeKind: row['scope_kind'] as String,
      scopeId: row['scope_id'] as String,
      expiresAt: DateTime.parse(row['expires_at'] as String).toLocal(),
      phone: row['phone'] as String?,
      email: row['email'] as String?,
      claimedAt: claimed == null ? null : DateTime.parse(claimed).toLocal(),
    );
  }
}

/// The roles an admin may hand out, in the order they are offered.
///
/// `super_admin` is deliberately absent: it exists in the schema for
/// Kaj-consulting's own staff, and an org admin has no business minting one
/// from a phone.
const adminGrantableRoles = <String, String>{
  'admin': 'Administrateur',
  'manager': 'Responsable',
  'supervisor': 'Superviseur',
  'employee': 'Employé',
  'approver': 'Approbateur',
  'observer': 'Observateur',
};

/// Every role, for displaying grants that were made elsewhere — by hand, or by
/// Kaj-consulting.
const roleLabels = <String, String>{
  'owner': 'Propriétaire',
  'super_admin': 'Super administrateur',
  ...adminGrantableRoles,
};

String roleLabel(String role) => roleLabels[role] ?? role;

String scopeKindLabel(String kind) => switch (kind) {
      'org' => "Toute l'activité",
      'entity' => 'Site',
      'department' => 'Département',
      _ => kind,
    };
