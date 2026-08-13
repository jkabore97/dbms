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
  'church_members': 'Fidèles',
};

String auditTableLabel(String table) => auditTableLabels[table] ?? table;

const auditActionLabels = <String, String>{
  'insert': 'Créé',
  'update': 'Modifié',
  'delete': 'Supprimé',
};

String auditActionLabel(String action) => auditActionLabels[action] ?? action;
