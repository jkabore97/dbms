import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/models.dart';
import '../../core/console/console_repository.dart';
import '../../core/console/models.dart';

/// What the database actually holds for this business.
///
/// Every table that carries any of their data, what it is for in plain words,
/// how many rows of it are theirs, and — one tap in — what the table is made
/// of, including which columns point at which other tables.
///
/// Two things it deliberately is not.
///
/// It is not a query tool. No row of anybody's data appears anywhere on this
/// screen; the counts are counts and the columns are structure. A super admin
/// who needs to read rows has the rest of the app, which is bounded by RLS,
/// and a screen that ran arbitrary SQL would be a way around every policy in
/// the project wearing the costume of a diagnostic.
///
/// It is not global. `org_database_overview()` counts with a WHERE clause per
/// table that somebody had to write and can be pointed at, rather than looping
/// over the catalog — which would have handed one client's row counts to
/// another client's admin, and there would have been no clause to check.
class DatabaseTab extends StatefulWidget {
  const DatabaseTab({super.key, required this.console, required this.org});

  final ConsoleRepository console;
  final OrgSummary org;

  @override
  State<DatabaseTab> createState() => _DatabaseTabState();
}

class _DatabaseTabState extends State<DatabaseTab> {
  List<DatabaseTable> _tables = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tables = await widget.console.databaseOverview(widget.org.id);
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _inspect(DatabaseTable table) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StructureSheet(
        console: widget.console,
        orgId: widget.org.id,
        table: table,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40),
              const SizedBox(height: 16),
              Text(
                AuthRepository.describeError(_error!),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final total = _tables.fold<int>(0, (sum, t) => sum + t.rowCount);
    final numbers = NumberFormat.decimalPattern('fr_FR');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.org.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${numbers.format(total)} lignes réparties sur '
                    '${_tables.length} tables',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          for (final table in _tables)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(top: 8),
              color: theme.colorScheme.surfaceContainerHighest,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        table.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      numbers.format(table.rowCount),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: table.rowCount == 0
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(table.purpose),
                    const SizedBox(height: 4),
                    Text(
                      [
                        // The real table name, because a super admin reading
                        // this is often about to go and look at it directly.
                        table.name,
                        if (table.lastChange != null)
                          'modifié le ${DateFormat('d MMM', 'fr_FR').format(table.lastChange!)}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                onTap: () => _inspect(table),
              ),
            ),

          const SizedBox(height: 24),
          Text(
            "Les nombres ci-dessus ne comptent que les lignes de cette "
            "activité. Aucune donnée d'une autre activité n'est visible ici, "
            'à aucun niveau de privilège.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// One table's structure. Columns, types, what may be empty, and what points
/// where — which is the part that turns a column list into a map of how the
/// schema fits together.
class _StructureSheet extends StatefulWidget {
  const _StructureSheet({
    required this.console,
    required this.orgId,
    required this.table,
  });

  final ConsoleRepository console;
  final String orgId;
  final DatabaseTable table;

  @override
  State<_StructureSheet> createState() => _StructureSheetState();
}

class _StructureSheetState extends State<_StructureSheet> {
  List<TableColumn> _columns = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final columns = await widget.console.tableColumns(
        widget.orgId,
        widget.table.name,
      );
      if (!mounted) return;
      setState(() {
        _columns = columns;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.table.label, style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  widget.table.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(widget.table.purpose, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            AuthRepository.describeError(_error!),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        itemCount: _columns.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _ColumnTile(column: _columns[index]),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ColumnTile extends StatelessWidget {
  const _ColumnTile({required this.column});

  final TableColumn column;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      leading: column.isKey
          ? Icon(Icons.key, size: 18, color: theme.colorScheme.primary)
          : column.references != null
              ? Icon(
                  Icons.link,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : const SizedBox(width: 18),
      title: Text(
        column.name,
        style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
      ),
      subtitle: Text(
        [
          column.dataType,
          if (!column.isNullable) 'obligatoire',
          if (column.hasDefault) 'valeur par défaut',
          if (column.references != null) '→ ${column.references}',
        ].join(' · '),
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
