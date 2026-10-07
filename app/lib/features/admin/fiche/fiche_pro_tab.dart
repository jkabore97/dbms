import 'package:flutter/material.dart';

import '../../../core/access/plan_terms.dart';
import '../../../core/auth/models.dart';
import '../../../core/cauris/cauris_repository.dart';
import '../../../core/console/command_center.dart';
import '../../../core/console/fiche_repository.dart';
import '../../../core/console/models.dart';
import '../../../core/errors.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/app_scope.dart';
import '../../../core/theme/kaj_card.dart';
import '../../../core/theme/mara_mark.dart';
import '../cauris_gifts_screen.dart' show OrgGifts;
import 'fiche_widgets.dart';

/// Pro et cauris: the plan (065) the platform puts the business on, until
/// a date; its wallet and the platform's gifts (100's, through 105's
/// journal: the console's own « Offrir » panel); the tools open now, until
/// when, and whether they were paid or given. A plan saved here is a
/// journal line too (106's trigger) — « Annuler » follows it.
class FicheProTab extends StatefulWidget {
  const FicheProTab({
    super.key,
    required this.overview,
    required this.org,
    required this.center,
    required this.onChanged,
  });

  final OrgOverview overview;
  final OrgSummary org;
  final CommandCenterRepository center;
  final VoidCallback onChanged;

  @override
  State<FicheProTab> createState() => _FicheProTabState();
}

class _FicheProTabState extends State<FicheProTab> {
  late String _plan = widget.overview.planRaw == 'pro' ? 'pro' : 'free';
  late DateTime? _until = widget.overview.planUntil;
  late final _note = TextEditingController(text: widget.overview.planNote ?? '');
  bool _saving = false;
  String? _error;

  OrgOverview get _o => widget.overview;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _until ?? DateTime(now.year, now.month + 1, now.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _until = picked);
  }

  Future<void> _savePlan() async {
    final scope = AppScope.maybeOf(context);
    if (scope == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await scope.admin.setOrgPlan(_o.id,
          plan: _plan, until: _plan == 'pro' ? _until : null, note: _note.text);
      // set_org_plan returns nothing: its line is the newest « plan » one.
      String? id;
      try {
        final page = await widget.center.journal(orgId: _o.id, limit: 5);
        for (final e in page) {
          if (e.kind == 'plan' && e.undoable) {
            id = e.id;
            break;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() => _saving = false);
      showUndoBar(
        context,
        center: widget.center,
        actionId: id,
        done: _plan == 'pro'
            ? context.tr('{name} est sur Mara Pro.', {'name': _o.name})
            : context.tr('{name} est sur Mara (gratuit).', {'name': _o.name}),
        onUndone: widget.onChanged,
      );
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(e);
      });
    }
  }

  bool get _planDirty =>
      _plan != (_o.planRaw == 'pro' ? 'pro' : 'free') ||
      (_plan == 'pro' && _until != _o.planUntil) ||
      _note.text.trim() != (_o.planNote ?? '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AppScope.maybeOf(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final plan = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FicheHeading(context.tr('Formule')),
        KajCard(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _o.isPro
                      ? (_o.planUntil == null
                          ? context.tr('Mara Pro, sans date de fin')
                          : context.tr('Mara Pro jusqu\'au {date}',
                              {'date': dayLine(context, _o.planUntil!)}))
                      : context.tr('Mara (gratuit)'),
                  key: const Key('pro-plan-now'),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (_o.isPro && _o.planRaw != 'pro')
                  Text(context.tr('Ouvert par « Mara Pro complet », pas par la formule.'),
                      style: theme.textTheme.bodySmall),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  key: const Key('pro-plan-choice'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'free', label: Text(context.tr('Gratuit'))),
                    ButtonSegment(
                        value: 'pro',
                        icon: const Icon(Icons.workspace_premium_outlined),
                        label: Text(context.tr('Mara Pro'))),
                  ],
                  selected: {_plan},
                  onSelectionChanged:
                      _saving ? null : (s) => setState(() => _plan = s.first),
                ),
                if (_plan == 'pro') ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('pro-plan-until'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _saving ? null : _pickUntil,
                    icon: const Icon(Icons.event),
                    label: Text(_until == null
                        ? context.tr('Sans date de fin')
                        : context.tr('Payé jusqu\'au {date}', {'date': dayLine(context, _until!)})),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  enabled: !_saving,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: context.tr('Note (vue par Mara seulement)'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    key: const Key('pro-plan-save'),
                    style: FilledButton.styleFrom(
                        backgroundColor: maraDeep, foregroundColor: maraPaper),
                    onPressed: _saving || !_planDirty ? null : _savePlan,
                    child: Text(context.tr('Enregistrer la formule'),
                        style: const TextStyle(fontSize: 17)),
                  ),
                ),
              ],
            ),
          ),
        ),
        FicheHeading(context.tr('Outils ouverts')),
        KajCard(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: _o.unlocks.isEmpty
              ? ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(context.tr('Aucun outil ouvert en ce moment')),
                )
              : Column(
                  children: [
                    for (final (i, u) in _o.unlocks.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 56),
                      ListTile(
                        key: Key('pro-unlock-${u.feature}'),
                        leading: Icon(u.gift ? Icons.redeem_outlined : Icons.lock_open,
                            color: u.gift ? maraBrown : maraGreen),
                        title: Text(u.feature == 'pro_all'
                            ? context.tr('Mara Pro complet')
                            : PlanTerms.labelOf(u.feature)),
                        subtitle: Text([
                          context.tr('jusqu\'au {date}', {'date': dayLine(context, u.until)}),
                          u.gift ? context.tr('Offert par Mara') : context.tr('Payé en cauris'),
                        ].join(' · ')),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );

    final gifts = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FicheHeading(context.tr('Cauris et cadeaux')),
        if (scope != null)
          OrgGifts(
            org: OrgRow(
              id: _o.id,
              name: _o.name,
              slug: _o.slug,
              profile: _o.profile,
              currency: _o.currency,
              memberCount: _o.members,
            ),
            admin: scope.admin,
            cauris: CaurisRepository(scope.auth.client),
            onGiven: widget.onChanged,
          ),
      ],
    );

    return ListView(
      key: const Key('fiche-pro'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        FicheWidth(
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: plan),
                    const SizedBox(width: 20),
                    Expanded(child: gifts),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [plan, gifts],
                ),
        ),
      ],
    );
  }
}
