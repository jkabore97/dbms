import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/models.dart';
import '../../core/console/console_repository.dart';
import '../../core/console/models.dart';

/// What happened, and who did it.
///
/// The log's own guarantee is that nobody can edit it — RLS on `audit_log` has
/// a select policy and no insert, update or delete policy at all, so the only
/// writer is the trigger, which runs outside policy. This screen therefore has
/// no actions on it. There is nothing to do to a log entry; there is only
/// reading it.
///
/// Filters first, because a log is useless the moment it is long. Filtering by
/// person is offered before filtering by kind of change, because the question
/// that brings somebody here is almost always about a person.
class ActivityLogTab extends StatefulWidget {
  const ActivityLogTab({super.key, required this.console, required this.org});

  final ConsoleRepository console;
  final OrgSummary org;

  @override
  State<ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends State<ActivityLogTab> {
  static const _pageSize = 50;

  List<AuditEvent> _events = const [];
  List<AuditActor> _actors = const [];

  String? _table;
  String? _actorId;
  String? _action;

  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
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
      _exhausted = false;
    });
    try {
      final events = await widget.console.log(
        widget.org.id,
        limit: _pageSize,
        table: _table,
        actorId: _actorId,
        action: _action,
      );
      // The filter list is only worth fetching once and is cheap to keep.
      final actors = _actors.isEmpty
          ? await widget.console.actors(widget.org.id)
          : _actors;

      if (!mounted) return;
      setState(() {
        _events = events;
        _actors = actors;
        _exhausted = events.length < _pageSize;
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

  /// Keyset paging on the id, not an offset. The log grows at the top while
  /// somebody is reading down it, and an offset would show them the same row
  /// twice — which in an audit log reads as the same action having happened
  /// twice.
  Future<void> _loadMore() async {
    if (_loadingMore || _exhausted || _loading || _events.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final more = await widget.console.log(
        widget.org.id,
        limit: _pageSize,
        before: _events.last.id,
        table: _table,
        actorId: _actorId,
        action: _action,
      );
      if (!mounted) return;
      setState(() {
        _events = [..._events, ...more];
        _exhausted = more.length < _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _setFilter({
    String? table,
    String? actorId,
    String? action,
    bool clearTable = false,
    bool clearActor = false,
    bool clearAction = false,
  }) {
    setState(() {
      if (clearTable) _table = null;
      if (clearActor) _actorId = null;
      if (clearAction) _action = null;
      if (table != null) _table = table;
      if (actorId != null) _actorId = actorId;
      if (action != null) _action = action;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        _filters(theme),
        const Divider(height: 1),
        Expanded(child: _body(theme)),
      ],
    );
  }

  Widget _filters(ThemeData theme) {
    final hasFilter = _table != null || _actorId != null || _action != null;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (hasFilter)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.close, size: 16),
                label: const Text('Tout'),
                onPressed: () => _setFilter(
                  clearTable: true,
                  clearActor: true,
                  clearAction: true,
                ),
              ),
            ),

          // Who.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<String>(
              onSelected: (value) => value == '*'
                  ? _setFilter(clearActor: true)
                  : _setFilter(actorId: value),
              itemBuilder: (_) => [
                const PopupMenuItem(value: '*', child: Text('Tout le monde')),
                for (final actor in _actors)
                  if (actor.id != null)
                    PopupMenuItem(
                      value: actor.id!,
                      child: Text('${actor.label} (${actor.events})'),
                    ),
              ],
              child: Chip(
                avatar: const Icon(Icons.person_outline, size: 16),
                label: Text(_actorLabel()),
              ),
            ),
          ),

          // What kind of thing.
          for (final entry in auditTableLabels.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(entry.value),
                selected: _table == entry.key,
                onSelected: (on) => on
                    ? _setFilter(table: entry.key)
                    : _setFilter(clearTable: true),
              ),
            ),
        ],
      ),
    );
  }

  String _actorLabel() {
    if (_actorId == null) return 'Tout le monde';
    return _actors
        .firstWhere(
          (a) => a.id == _actorId,
          orElse: () => AuditActor(
            label: 'Quelqu\'un',
            events: 0,
            lastSeen: DateTime.now(),
          ),
        )
        .label;
  }

  Widget _body(ThemeData theme) {
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

    if (_events.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 100),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Rien à afficher. Le journal enregistre les changements '
                  "d'accès, de structure et de plan comptable à partir du "
                  'moment où il a été installé — il ne remonte pas plus loin.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400) _loadMore();
        return false;
      },
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          itemCount: _events.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == _events.length) {
              return _loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : const SizedBox(height: 48);
            }
            return _EventTile(event: _events[index]);
          },
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final AuditEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Green for something appearing, red for something disappearing, neutral
    // for something being altered. Revocation is the one an admin scanning a
    // log is looking for and it should be the one that catches the eye.
    final (icon, tint) = switch (event.action) {
      'insert' => (Icons.add_circle_outline, Colors.green.shade800),
      'delete' => (Icons.remove_circle_outline, theme.colorScheme.error),
      _ => (Icons.edit_outlined, theme.colorScheme.onSurfaceVariant),
    };

    final diff = event.diff;

    return ExpansionTile(
      leading: Icon(icon, color: tint),
      title: Text(
        '${auditActionLabel(event.action)} · '
        '${auditTableLabel(event.tableName)}'
        '${event.summary == null ? '' : ' — ${event.summary}'}',
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        '${event.actorLabel} · '
        '${DateFormat('d MMM y à HH:mm', 'fr_FR').format(event.at)}',
        style: theme.textTheme.bodySmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (diff.isNotEmpty)
                for (final change in diff)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodySmall,
                        children: [
                          TextSpan(
                            text: '${change.column} : ',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          TextSpan(
                            text: change.before,
                            style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const TextSpan(text: '  →  '),
                          TextSpan(
                            text: change.after,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
              else
                // An insert or a delete: `changed` holds the whole row rather
                // than a diff. Shown raw and unsorted-into-prose, because this
                // is the screen where somebody wants to see exactly what the
                // database recorded.
                for (final entry in event.changed.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            entry.key,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            '${entry.value ?? '—'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
