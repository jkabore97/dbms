import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/db/local_db.dart';

/// What this phone is still holding.
///
/// The app has always shown a pending count in the app bar, which answers "is
/// anything waiting" and nothing else. It cannot answer the question that
/// actually matters when something has gone wrong: waiting because there is no
/// signal, or waiting because the server keeps refusing it?
///
/// Those are opposite situations. The first is normal, expected and needs no
/// action — it is what the whole offline design is for. The second means work
/// somebody believes is saved is never going to arrive, and until now the
/// reason was written to `outbox.last_error`, a column nothing ever read.
///
/// So this tab distinguishes them, and shows the refusals verbatim. The
/// message will be in English and will mention a Postgres constraint, which is
/// not for the person recording offerings — it is for whoever they phone, and
/// it is the difference between "the app is broken" and a fix.
class DeviceTab extends StatefulWidget {
  const DeviceTab({super.key, required this.db, required this.org});

  final LocalDb db;
  final OrgSummary org;

  @override
  State<DeviceTab> createState() => _DeviceTabState();
}

class _DeviceTabState extends State<DeviceTab> {
  ({int pending, int stuck, int sent})? _health;
  List<Map<String, Object?>> _failed = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final health = await widget.db.outboxHealth();
    final failed = await widget.db.failedActions();
    if (!mounted) return;
    setState(() {
      _health = health;
      _failed = failed;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading || _health == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final health = _health!;
    // Waiting with no attempt behind it is the normal offline state. Waiting
    // after an attempt is the one worth alarming on.
    final waiting = health.pending - health.stuck;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: health.stuck > 0
                ? theme.colorScheme.errorContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("File d'envoi", style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          label: 'Envoyé',
                          value: '${health.sent}',
                        ),
                      ),
                      Expanded(
                        child: _Stat(
                          label: 'En attente de réseau',
                          value: '$waiting',
                        ),
                      ),
                      Expanded(
                        child: _Stat(
                          label: 'Refusé',
                          value: '${health.stuck}',
                          tint: health.stuck > 0
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    health.stuck > 0
                        ? "Des enregistrements ont été refusés par le serveur. "
                            "Ils ne partiront pas tout seuls : montrez cet "
                            'écran à la personne qui gère le serveur.'
                        : waiting > 0
                            ? 'Rien de refusé. Ce qui reste partira dès que le '
                                'réseau reviendra.'
                            : 'Tout ce qui a été enregistré sur cet appareil '
                                'est arrivé au serveur.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),

          if (_failed.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Refusés', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final row in _failed) _FailureTile(row: row),
          ],

          const SizedBox(height: 24),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cet appareil', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _Fact(label: 'Activité ouverte', value: widget.org.name),
                  _Fact(
                    label: 'Rôles',
                    value: widget.org.roles.join(', '),
                  ),
                  _Fact(label: 'Visibilité', value: widget.org.visibility),
                  _Fact(label: 'Monnaie', value: widget.org.currency),
                  _Fact(label: 'Profil', value: widget.org.profile),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.tint});

  final String label;
  final String value;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: tint,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FailureTile extends StatelessWidget {
  const _FailureTile({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final action = row['action'] as String;
    final attempts = row['attempts'] as int? ?? 0;
    final error = (row['last_error'] as String?) ?? 'Raison inconnue';
    final created = DateTime.parse(row['created_at'] as String).toLocal();

    // The label the person typed, so the row is recognisable as a thing that
    // happened rather than as an RPC name and a uuid.
    String? label;
    try {
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      label = payload['p_label'] as String?;
    } catch (_) {
      // A payload this device cannot parse is itself worth showing, and the
      // rest of the tile still says everything that matters.
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.errorContainer,
      child: ExpansionTile(
        shape: const Border(),
        title: Text(
          label ?? action,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$action · ${DateFormat('d MMM à HH:mm', 'fr_FR').format(created)} · '
          '$attempts tentative${attempts > 1 ? 's' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SelectableText(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
