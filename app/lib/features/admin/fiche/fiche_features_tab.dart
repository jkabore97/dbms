import 'package:flutter/material.dart';

import '../../../core/console/command_center.dart';
import '../../../core/console/fiche_repository.dart';
import '../../../core/errors.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/theme/kaj_card.dart';
import '../../../core/theme/mara_mark.dart';
import 'fiche_widgets.dart';

/// Fonctions: 104's switchboard for this one business — each tool it has,
/// « Par défaut » (today's), « Visible » or « Masquée », until a date if
/// said. What it comes to and why (its kind's rule, its own, the
/// catalog). A tool the business paid for is drawn locked: « Payée — ne
/// peut pas être masquée » (the server refuses it the same). Each change
/// is a journal line with « Annuler »; the owner is told.
class FicheFeaturesTab extends StatefulWidget {
  const FicheFeaturesTab({
    super.key,
    required this.overview,
    required this.fiche,
    required this.center,
    required this.onChanged,
  });

  final OrgOverview overview;
  final FicheRepository fiche;
  final CommandCenterRepository center;
  final VoidCallback onChanged;

  @override
  State<FicheFeaturesTab> createState() => _FicheFeaturesTabState();
}

class _FicheFeaturesTabState extends State<FicheFeaturesTab> {
  List<FeatureBoardRow>? _rows;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.fiche.board(widget.overview.id);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _set(FeatureBoardRow row, String state) async {
    final choice = await showModalBottomSheet<({DateTime? until, String? note})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RuleSheet(
        row: row,
        state: state,
        orgName: widget.overview.name,
        ownerName: widget.overview.owner?.name,
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = row.key);
    try {
      final id = await widget.fiche.setFeature(widget.overview.id, row.key, state,
          until: choice.until, note: choice.note);
      if (!mounted) return;
      showUndoBar(
        context,
        center: widget.center,
        actionId: id,
        done: context.tr('« {label} » : {state}. Le propriétaire est prévenu.', {
          'label': row.label,
          'state': _stateWord(context, state),
        }),
        onUndone: widget.onChanged,
      );
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
        setState(() => _busy = null);
      }
    }
  }

  /// A rule left from the business's former kind: cleared, with « Annuler ».
  Future<void> _clear(FeatureBoardRow row) async {
    setState(() => _busy = row.key);
    try {
      final id = await widget.fiche.setFeature(widget.overview.id, row.key, 'default');
      if (!mounted) return;
      showUndoBar(
        context,
        center: widget.center,
        actionId: id,
        done: context.tr('« {label} » : réglage retiré.', {'label': context.tr(row.label)}),
        onUndone: widget.onChanged,
      );
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
        setState(() => _busy = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final groups = <String, List<FeatureBoardRow>>{};
    final leftovers = <FeatureBoardRow>[];
    for (final r in rows ?? const <FeatureBoardRow>[]) {
      if (r.leftover) {
        leftovers.add(r);
      } else {
        (groups[r.group] ??= []).add(r);
      }
    }
    return ListView(
      key: const Key('fiche-features'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        FicheWidth(
          max: 860,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MaraAsBanner(
                title: context.tr('Ce que {name} voit', {'name': widget.overview.name}),
                line: context.tr('« Par défaut » est ce que voit aujourd\'hui chaque activité de ce type. Une fonction payée ne se masque jamais.'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                )
              else if (rows == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              for (final e in groups.entries) ...[
                FicheHeading(context.tr(e.key)),
                KajCard(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (i, r) in e.value.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _FeatureRow(
                          row: r,
                          busy: _busy == r.key,
                          onSet: (s) => _set(r, s),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              // Left from the kind it was: decides nothing, cleared here.
              if (leftovers.isNotEmpty) ...[
                FicheHeading(context.tr('Laissé par son ancien type d\'activité')),
                KajCard(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (i, r) in leftovers.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          key: Key('feature-leftover-${r.key}'),
                          minVerticalPadding: 12,
                          title: Text(context.tr(r.label),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(context.tr('Ce type d\'activité n\'a pas cette fonction : ce réglage ne change rien.')),
                          trailing: TextButton(
                            onPressed: _busy == r.key ? null : () => _clear(r),
                            child: Text(context.tr('Retirer')),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _stateWord(BuildContext context, String state) => switch (state) {
      'hidden' => context.tr('masquée'),
      'visible' => context.tr('visible'),
      _ => context.tr('par défaut'),
    };

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.row, required this.busy, required this.onSet});

  final FeatureBoardRow row;
  final bool busy;
  final void Function(String state) onSet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = row;
    final source = switch (r.source) {
      'org' => context.tr('Réglé pour cette activité'),
      'kind' => context.tr('Réglé pour tout le type d\'activité'),
      _ => context.tr('Par défaut'),
    };
    final until = r.until == null
        ? ''
        : context.tr(' jusqu\'au {date}', {'date': dayLine(context, r.until!)});
    final control = SegmentedButton<String>(
      key: Key('feature-${r.key}'),
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: 'default', label: Text(context.tr('Par défaut'))),
        ButtonSegment(value: 'visible', label: Text(context.tr('Visible'))),
        ButtonSegment(
          value: 'hidden',
          enabled: !r.paid,
          label: Text(context.tr('Masquée')),
          icon: r.paid ? const Icon(Icons.lock_outline, size: 16) : null,
        ),
      ],
      selected: {r.state},
      onSelectionChanged: busy
          ? null
          : (s) {
              if (s.first != r.state) onSet(s.first);
            },
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(context.tr(r.label),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            _Effective(hidden: r.hidden),
          ],
        ),
        const SizedBox(height: 2),
        Text('$source$until',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (r.paid)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              context.tr('Payée — ne peut pas être masquée'),
              key: Key('feature-paid-${r.key}'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: maraGreen, fontWeight: FontWeight.w700),
            ),
          ),
        if (r.note != null)
          Text('« ${r.note} »', style: theme.textTheme.bodySmall),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= 620
            ? Row(
                children: [
                  Expanded(child: text),
                  const SizedBox(width: 12),
                  control,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [text, const SizedBox(height: 10), control],
              ),
      ),
    );
  }
}

class _Effective extends StatelessWidget {
  const _Effective({required this.hidden});

  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final colour = hidden ? const Color(0xFFB03B3B) : maraGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        hidden ? context.tr('Masquée') : context.tr('Visible'),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: colour, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Before a switch moves: until when (optional), a word, and who is told.
class _RuleSheet extends StatefulWidget {
  const _RuleSheet({
    required this.row,
    required this.state,
    required this.orgName,
    this.ownerName,
  });

  final FeatureBoardRow row;
  final String state;
  final String orgName;
  final String? ownerName;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  final _note = TextEditingController();
  DateTime? _until;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _until ?? today.add(const Duration(days: 30)),
      firstDate: today.add(const Duration(days: 1)),
      lastDate: today.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _until = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.state;
    final title = switch (s) {
      'hidden' => context.tr('Masquer « {label} » pour {name} ?',
          {'label': widget.row.label, 'name': widget.orgName}),
      'visible' => context.tr('Rendre « {label} » visible pour {name} ?',
          {'label': widget.row.label, 'name': widget.orgName}),
      _ => context.tr('Remettre « {label} » par défaut pour {name} ?',
          {'label': widget.row.label, 'name': widget.orgName}),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              widget.ownerName == null
                  ? context.tr('Le propriétaire est prévenu sur sa cloche.')
                  : context.tr('{who} est prévenu(e) sur sa cloche.', {'who': widget.ownerName}),
              style: theme.textTheme.bodyMedium,
            ),
            if (s != 'default') ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('rule-until'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _pick,
                icon: const Icon(Icons.event),
                label: Text(_until == null
                    ? context.tr('Sans date de fin')
                    : context.tr('Jusqu\'au {date}', {'date': dayLine(context, _until!)})),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('rule-note'),
                controller: _note,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: context.tr('Pourquoi (pour le journal, facultatif)'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('rule-save'),
                style: FilledButton.styleFrom(
                    backgroundColor: maraDeep, foregroundColor: maraPaper),
                onPressed: () => Navigator.of(context).pop((
                  until: _until,
                  note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                )),
                child: Text(context.tr('Enregistrer'), style: const TextStyle(fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
