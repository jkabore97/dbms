import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/access/plan_terms.dart';
import '../../../core/console/command_center.dart';
import '../../../core/errors.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/router.dart';
import '../../../core/theme/kaj_card.dart';
import '../../../core/theme/mara_mark.dart';
import '../../courier/courier_words.dart' show courierReasonLabel;
import 'settings_section.dart';

/// Journal (104, 105): every change the platform made — a setting, a gift,
/// a tool opened, a message, an archive, a switch, a fiche — newest first,
/// with « Annuler » on those that can be taken back.
class JournalSection extends StatefulWidget {
  const JournalSection({
    super.key,
    required this.center,
    this.orgId,
    this.embedded = false,
    this.onUndone,
  });

  final CommandCenterRepository center;

  /// One business's lines only — its fiche's Journal (106); null: all.
  final String? orgId;

  /// Inside another page (the fiche's tab): no top bar of its own.
  final bool embedded;

  /// After an « Annuler »: the page around reads the business again.
  final VoidCallback? onUndone;

  @override
  State<JournalSection> createState() => _JournalSectionState();
}

enum _Show { all, undoable, undone }

class _JournalSectionState extends State<JournalSection> {
  static const _page = 50;

  final List<JournalEntry> _entries = [];
  bool _loading = true;
  bool _more = true;
  String? _error;
  String? _busy;
  _Show _show = _Show.all;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.center.journal(
        orgId: widget.orgId,
        limit: _page,
        before: reset || _entries.isEmpty ? null : _entries.last.at,
        beforeId: reset || _entries.isEmpty ? null : _entries.last.id,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _entries.clear();
        // Never the same line twice, whatever the page boundary.
        final seen = {for (final e in _entries) e.id};
        _entries.addAll(page.where((e) => !seen.contains(e.id)));
        _more = page.length == _page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _undo(JournalEntry e) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.tr('Annuler cette action ?')),
        content: Text(_title(context, e)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(context.tr('Retour')),
          ),
          FilledButton(
            key: const Key('journal-undo-confirm'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.tr('Annuler l\'action')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final done = context.tr('Action annulée.');
    setState(() => _busy = e.id);
    try {
      await widget.center.undo(e.id);
      messenger.showSnackBar(SnackBar(content: Text(done)));
      await _load(reset: true);
      widget.onUndone?.call();
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(err))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// The line: a setting by its name, the rest as the server wrote it.
  String _title(BuildContext context, JournalEntry e) {
    if (e.kind == 'setting') {
      final key = '${e.after?['key'] ?? e.before?['key'] ?? ''}';
      SettingDef? def;
      for (final d in platformSettingDefs) {
        if (d.key == key) def = d;
      }
      if (def != null) {
        return context.tr('{name} : {before} → {after}', {
          'name': settingLabel(context, key),
          'before': settingValueText(context, def, e.before?['value']),
          'after': settingValueText(context, def, e.after?['value']),
        });
      }
    }
    // A tool's price and wait in cauris (108), said in the reader's words.
    if (e.kind == 'cauris_cost') {
      final f = '${e.after?['feature'] ?? e.before?['feature'] ?? ''}';
      return context.tr('Cauris, {tool} : {c0} → {c1} cauris, attente {d0} → {d1} jours', {
        'tool': f == 'pro_all' ? context.tr('Mara Pro complet') : PlanTerms.labelOf(f),
        'c0': e.before?['cost'] ?? '',
        'c1': e.after?['cost'] ?? '',
        'd0': e.before?['min_days'] ?? '',
        'd1': e.after?['min_days'] ?? '',
      });
    }
    // A courier's dossier decided (112): who, and what was said.
    if (e.kind == 'courier') {
      final status = '${e.after?['status'] ?? ''}';
      return context.tr('Livreur {name} : {decision}', {
        'name': e.after?['name'] ?? e.before?['name'] ?? '',
        'decision': status == 'approved'
            ? context.tr('approuvé')
            : context.tr('à corriger ({reason})',
                {'reason': courierReasonLabel(context, e.after?['reason'] as String?).toLowerCase()}),
      });
    }
    return translate(context.trLanguage, e.summary);
  }

  static IconData _icon(String kind) => switch (kind) {
        'setting' => Icons.tune,
        'cauris_gift' => Icons.redeem_outlined,
        'unlock_gift' => Icons.lock_open_outlined,
        'message' => Icons.campaign_outlined,
        'archive' => Icons.archive_outlined,
        'restore' => Icons.unarchive_outlined,
        'feature_rule' => Icons.toggle_on_outlined,
        'kind_setting' => Icons.category_outlined,
        'application' || 'application_form' => Icons.inbox_outlined,
        'identity' => Icons.badge_outlined,
        'vitrine' => Icons.storefront_outlined,
        'plan' => Icons.workspace_premium_outlined,
        'cauris_cost' => Icons.sell_outlined,
        'courier' => Icons.delivery_dining_outlined,
        'report' => Icons.flag_outlined,
        _ => Icons.edit_note,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = [
      for (final e in _entries)
        if (_show == _Show.all ||
            (_show == _Show.undoable && e.undoable) ||
            (_show == _Show.undone && e.undoneAt != null))
          e,
    ];
    final when = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(
        title: Text(context.tr('Journal')),
        actions: [
          IconButton(
            tooltip: context.tr('Actualiser'),
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final (s, label) in [
                  (_Show.all, context.tr('Tout')),
                  (_Show.undoable, context.tr('À annuler')),
                  (_Show.undone, context.tr('Annulées')),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _show == s,
                    onSelected: (_) => setState(() => _show = s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (!_loading && shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text(context.tr('Rien dans le journal pour l\'instant.'))),
              ),
            for (final e in shown)
              KajCard(
                key: Key('journal-${e.id}'),
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                color: e.undoneAt != null
                    ? theme.colorScheme.surfaceContainerLow
                    : theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: maraDeep,
                        child: Icon(_icon(e.kind), size: 18, color: maraCaramel),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _title(context, e),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration:
                                    e.undoneAt != null ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              children: [
                                Text(
                                  [?e.actor, when.format(e.at)].join(' · '),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                                if (e.orgId != null && e.orgName != null && widget.orgId == null)
                                  InkWell(
                                    onTap: () => context.push(Routes.consoleOrg(e.orgId!)),
                                    child: Text(
                                      e.orgName!,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: maraBrown,
                                          fontWeight: FontWeight.w700,
                                          decoration: TextDecoration.underline),
                                    ),
                                  ),
                              ],
                            ),
                            if (e.undoneAt != null)
                              Text(
                                context.tr('Annulée par {who} le {date}', {
                                  'who': e.undoneBy ?? 'Mara',
                                  'date': when.format(e.undoneAt!),
                                }),
                                style: theme.textTheme.bodySmall?.copyWith(color: maraBrown),
                              ),
                          ],
                        ),
                      ),
                      if (e.undoable)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _busy == e.id
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : OutlinedButton(
                                  key: Key('journal-undo-${e.id}'),
                                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 40)),
                                  onPressed: _busy != null ? null : () => _undo(e),
                                  child: Text(context.tr('Annuler')),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            if (_loading) const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            if (!_loading && _more && _entries.isNotEmpty)
              Center(
                child: TextButton(
                  onPressed: () => _load(),
                  child: Text(context.tr('Plus ancien')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
