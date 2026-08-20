import '../admin/admin_repository.dart' show PlatformOrg;

// What the console reads: the activity log, and the shape of the data
// underneath it. Both come from 008_audit_log.sql and both are admin-only
// server-side, so nothing here is cached on the device.

/// One thing that happened, and who did it.
class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.at,
    required this.actorLabel,
    required this.action,
    required this.tableName,
    this.actorId,
    this.rowId,
    this.summary,
    this.changed = const {},
  });

  final int id;
  final DateTime at;

  /// The name as it read when the thing happened, not as it reads now. The log
  /// has to keep saying "Aminata revoked Salif" after Aminata has changed her
  /// name and Salif's profile has been deleted.
  final String actorLabel;

  final String? actorId;

  /// 'insert' | 'update' | 'delete'
  final String action;

  final String tableName;
  final String? rowId;
  final String? summary;

  /// For an update, `{column: [before, after]}` for the columns that moved.
  /// For an insert or a delete, the whole row.
  final Map<String, dynamic> changed;

  /// The columns that changed, as before/after pairs. Empty for an insert or a
  /// delete, where `changed` is a row rather than a diff.
  List<({String column, String before, String after})> get diff {
    if (action != 'update') return const [];
    final out = <({String column, String before, String after})>[];
    for (final entry in changed.entries) {
      final pair = entry.value;
      if (pair is List && pair.length == 2) {
        out.add((
          column: entry.key,
          before: _show(pair[0]),
          after: _show(pair[1]),
        ));
      }
    }
    out.sort((a, b) => a.column.compareTo(b.column));
    return out;
  }

  static String _show(Object? value) {
    if (value == null) return '—';
    final text = value.toString();
    return text.isEmpty ? '—' : text;
  }

  factory AuditEvent.fromRow(Map<String, dynamic> row) {
    final changed = row['changed'];
    return AuditEvent(
      id: (row['id'] as num).toInt(),
      at: DateTime.parse(row['at'] as String).toLocal(),
      actorLabel: (row['actor_label'] as String?) ?? 'Inconnu',
      actorId: row['actor_id'] as String?,
      action: row['action'] as String,
      tableName: row['table_name'] as String,
      rowId: row['row_id'] as String?,
      summary: row['summary'] as String?,
      changed: changed is Map ? Map<String, dynamic>.from(changed) : const {},
    );
  }
}

/// A person who has appeared in the log, for the filter.
class AuditActor {
  const AuditActor({
    required this.label,
    required this.events,
    required this.lastSeen,
    this.id,
  });

  final String? id;
  final String label;
  final int events;
  final DateTime lastSeen;

  factory AuditActor.fromRow(Map<String, dynamic> row) {
    return AuditActor(
      id: row['actor_id'] as String?,
      label: (row['actor_label'] as String?) ?? 'Système',
      events: (row['events'] as num).toInt(),
      lastSeen: DateTime.parse(row['last_seen'] as String).toLocal(),
    );
  }
}

/// One table, as it holds this business's data.
class DatabaseTable {
  const DatabaseTable({
    required this.name,
    required this.label,
    required this.purpose,
    required this.rowCount,
    this.lastChange,
  });

  /// The real table name. Shown as well as the friendly label, because a super
  /// admin reading this is often about to go and query it.
  final String name;

  final String label;
  final String purpose;
  final int rowCount;
  final DateTime? lastChange;

  factory DatabaseTable.fromRow(Map<String, dynamic> row) {
    final last = row['last_change'] as String?;
    return DatabaseTable(
      name: row['table_name'] as String,
      label: row['label'] as String,
      purpose: row['purpose'] as String,
      rowCount: (row['row_count'] as num).toInt(),
      lastChange: last == null ? null : DateTime.parse(last).toLocal(),
    );
  }
}

/// One column of one table.
class TableColumn {
  const TableColumn({
    required this.name,
    required this.dataType,
    required this.isNullable,
    required this.hasDefault,
    required this.isKey,
    this.references,
  });

  final String name;
  final String dataType;
  final bool isNullable;
  final bool hasDefault;
  final bool isKey;

  /// The table this column points at, when it is a foreign key. This is what
  /// turns a column list into a map of how the schema fits together.
  final String? references;

  factory TableColumn.fromRow(Map<String, dynamic> row) {
    return TableColumn(
      name: row['column_name'] as String,
      dataType: row['data_type'] as String,
      isNullable: row['is_nullable'] as bool? ?? true,
      hasDefault: row['has_default'] as bool? ?? false,
      isKey: row['is_key'] as bool? ?? false,
      references: row['references_table'] as String?,
    );
  }
}

/// The tables, in the words of the people who use them rather than the words
/// of the schema. Used for the log, where "memberships" means nothing to
/// anybody outside this repository.
const auditTableLabels = <String, String>{
  'orgs': 'Activité',
  'memberships': 'Accès',
  'entities': 'Sites',
  'departments': 'Départements',
  'accounts': 'Plan comptable',
  'pending_invitations': 'Invitations',
  'journal_entries': 'Écritures',
  'church_members': 'Membres',
};

String auditTableLabel(String table) => auditTableLabels[table] ?? table;

const auditActionLabels = <String, String>{
  'insert': 'Créé',
  'update': 'Modifié',
  'delete': 'Supprimé',
};

String auditActionLabel(String action) => auditActionLabels[action] ?? action;

/// The shape of the whole platform, in one row.
///
/// Read by the console before any business is listed. Page one of an
/// alphabetical list is not information; "eleven went quiet this month" is.
class PlatformOverview {
  const PlatformOverview({
    this.total = 0,
    this.active = 0,
    this.archived = 0,
    this.farms = 0,
    this.shops = 0,
    this.churches = 0,
    this.otherProfiles = 0,
    this.newThisWeek = 0,
    this.active7d = 0,
    this.silent30d = 0,
    this.neverActive = 0,
  });

  final int total;
  final int active;
  final int archived;
  final int farms;
  final int shops;
  final int churches;
  final int otherProfiles;
  final int newThisWeek;

  /// Recorded something in the last seven days. The health number.
  final int active7d;

  /// Alive once, silent for a month. The churn signal, and the reason this
  /// screen exists at all — it predicts a lost customer weeks ahead.
  final int silent30d;

  /// Onboarded and never used. A different failure with a different owner:
  /// this one belongs to whoever signed them up.
  final int neverActive;

  factory PlatformOverview.fromRow(Map<String, dynamic> row) {
    int n(String k) => (row[k] as num?)?.toInt() ?? 0;
    return PlatformOverview(
      total: n('total'),
      active: n('active'),
      archived: n('archived'),
      farms: n('farms'),
      shops: n('shops'),
      churches: n('churches'),
      otherProfiles: n('other_profiles'),
      newThisWeek: n('new_this_week'),
      active7d: n('active_7d'),
      silent30d: n('silent_30d'),
      neverActive: n('never_active'),
    );
  }
}

/// One row of the console's business list.
class OrgRow {
  const OrgRow({
    required this.id,
    required this.name,
    required this.slug,
    required this.profile,
    required this.currency,
    required this.memberCount,
    this.archivedAt,
    this.createdAt,
    this.lastActivityAt,
  });

  final String id;
  final String name;
  final String slug;
  final String profile;
  final String currency;
  final int memberCount;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? lastActivityAt;

  bool get isArchived => archivedAt != null;
  bool get neverActive => lastActivityAt == null;

  int? get daysSinceActivity => lastActivityAt == null
      ? null
      : DateTime.now().difference(lastActivityAt!).inDays;

  /// What the row's status pill says. Ordered by what a person scanning the
  /// list needs to notice first.
  OrgHealth get health {
    if (isArchived) return OrgHealth.archived;
    if (neverActive) return OrgHealth.neverStarted;
    final days = daysSinceActivity!;
    if (days >= 30) return OrgHealth.silent;
    if (days >= 7) return OrgHealth.slowing;
    return OrgHealth.healthy;
  }

  /// The shape the existing edit and delete dialogs take. Those screens are
  /// correct and well tested; only the list around them changed, so this
  /// converts rather than duplicating them.
  ///
  /// `entryCount` is deliberately not carried: the console no longer counts
  /// every journal entry per row — that count is what made the old screen
  /// unusable at scale. The delete dialog re-reads what it needs, and the
  /// server makes the real decision either way.
  PlatformOrg toPlatformOrg() => PlatformOrg(
        id: id,
        name: name,
        slug: slug,
        profile: profile,
        currency: currency,
        archivedAt: archivedAt,
        memberCount: memberCount,
        createdAt: createdAt,
      );

  factory OrgRow.fromRow(Map<String, dynamic> row) {
    DateTime? when(Object? v) => v == null ? null : DateTime.tryParse('$v');
    return OrgRow(
      id: row['org_id'] as String,
      name: (row['name'] as String?) ?? '',
      slug: (row['slug'] as String?) ?? '',
      profile: (row['profile'] as String?) ?? '',
      currency: (row['currency'] as String?) ?? 'XOF',
      memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
      archivedAt: when(row['archived_at']),
      createdAt: when(row['created_at']),
      lastActivityAt: when(row['last_activity_at']),
    );
  }
}

enum OrgHealth { healthy, slowing, silent, neverStarted, archived }

/// One page of businesses, plus how many the filter matched in total.
class OrgPage {
  const OrgPage({required this.rows, required this.total});

  final List<OrgRow> rows;

  /// How many businesses match the current filter, not how many are on this
  /// page. The pager is built on it.
  final int total;
}

/// A trainer account (038) and how many businesses they currently cover.
class Trainer {
  const Trainer({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.assignments,
  });

  final String userId;
  final String? fullName;
  final String? phone;
  final int assignments;

  String get label => (fullName != null && fullName!.trim().isNotEmpty)
      ? fullName!
      : (phone ?? 'Formateur');

  factory Trainer.fromRow(Map<String, dynamic> r) => Trainer(
        userId: r['user_id'] as String,
        fullName: r['full_name'] as String?,
        phone: r['phone'] as String?,
        assignments: (r['assignments'] as num?)?.toInt() ?? 0,
      );
}

/// One business a trainer covers.
class TrainerOrg {
  const TrainerOrg({
    required this.orgId,
    required this.name,
    required this.slug,
    required this.profile,
  });

  final String orgId;
  final String name;
  final String slug;
  final String profile;

  factory TrainerOrg.fromRow(Map<String, dynamic> r) => TrainerOrg(
        orgId: r['org_id'] as String,
        name: (r['name'] ?? '') as String,
        slug: (r['slug'] ?? '') as String,
        profile: (r['profile'] ?? '') as String,
      );
}

/// One account in the platform-wide directory (047), with its footprint —
/// how many businesses it belongs to — and whether it holds platform access.
class PlatformPerson {
  const PlatformPerson({
    required this.userId,
    required this.isPlatformAdmin,
    required this.businessCount,
    this.fullName,
    this.phone,
    this.email,
    this.title,
    this.createdAt,
  });

  final String userId;
  final bool isPlatformAdmin;
  final int businessCount;
  final String? fullName;
  final String? phone;
  final String? email;
  final String? title;
  final DateTime? createdAt;

  /// What to call someone whose profile has no name yet.
  String get label {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return email ?? phone ?? 'Sans nom';
  }

  factory PlatformPerson.fromRow(Map<String, dynamic> r) {
    final created = r['created_at'] as String?;
    return PlatformPerson(
      userId: r['user_id'] as String,
      isPlatformAdmin: (r['is_platform_admin'] as bool?) ?? false,
      businessCount: ((r['business_count'] as num?) ?? 0).toInt(),
      fullName: r['full_name'] as String?,
      phone: r['phone'] as String?,
      email: r['email'] as String?,
      title: r['title'] as String?,
      createdAt: (created != null && created.isNotEmpty)
          ? DateTime.tryParse(created)
          : null,
    );
  }
}

/// One business a person belongs to, and their role in it — the footprint a
/// moderator reads before acting on the account.
class PersonOrg {
  const PersonOrg({
    required this.orgId,
    required this.orgName,
    required this.profile,
    required this.role,
    this.archived = false,
  });

  final String orgId;
  final String orgName;
  final String profile;
  final String role;
  final bool archived;

  factory PersonOrg.fromRow(Map<String, dynamic> r) => PersonOrg(
        orgId: r['org_id'] as String,
        orgName: (r['org_name'] ?? '') as String,
        profile: (r['profile'] ?? '') as String,
        role: (r['role'] ?? '') as String,
        archived: (r['archived'] as bool?) ?? false,
      );
}

/// One entry in the platform-wide activity log (048): what changed, in which
/// business, and by whom — the moderator's view across every tenant.
class PlatformAuditEvent {
  const PlatformAuditEvent({
    required this.id,
    required this.at,
    required this.orgId,
    required this.orgName,
    required this.action,
    required this.tableName,
    this.actorId,
    this.actorLabel,
    this.rowId,
    this.summary,
  });

  final int id;
  final DateTime at;
  final String orgId;
  final String orgName;

  /// 'insert' | 'update' | 'delete'.
  final String action;
  final String tableName;
  final String? actorId;
  final String? actorLabel;
  final String? rowId;
  final String? summary;

  factory PlatformAuditEvent.fromRow(Map<String, dynamic> r) =>
      PlatformAuditEvent(
        id: ((r['id'] as num?) ?? 0).toInt(),
        at: DateTime.parse(r['at'] as String).toLocal(),
        orgId: r['org_id'] as String,
        orgName: (r['org_name'] ?? '') as String,
        action: (r['action'] ?? '') as String,
        tableName: (r['table_name'] ?? '') as String,
        actorId: r['actor_id'] as String?,
        actorLabel: r['actor_label'] as String?,
        rowId: r['row_id'] as String?,
        summary: r['summary'] as String?,
      );
}
