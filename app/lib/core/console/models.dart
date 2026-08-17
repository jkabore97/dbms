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
