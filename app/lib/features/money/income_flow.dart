import 'package:flutter/material.dart';

import '../../core/db/local_db.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/reports/models.dart' show ChurchMember, accountLabel;
import '../../core/reports/reports_repository.dart';
import '../common/step_flow.dart';
import 'money_steps.dart';

/// « Recette », one entry at a time (115) — an association's money in
/// (a legacy 'church' org is an association and gets the same).
///
/// What it is (Cotisation, Don, Vente, Autre) → the name, for « Autre » →
/// who gave it (optional) → the amount → how → the summary →
/// « Enregistrer » → « C'est fait ».
///
/// The church words are gone from it, for every association and a legacy
/// church alike (the owner's decision): no « offrande », « dîme »,
/// « quête », « fidèles » offered anywhere. The books keep what was written
/// under them before (accounts are never renamed — the entries posted
/// against them would be rewritten); they are simply no longer suggested.
///
/// Written as the sheet it replaces wrote it: LocalDb.recordEntry, the
/// outbox and the day's entry in one transaction, offline, record_entry()
/// (007) when the signal comes. A member picked from the list is
/// attributed (p_member_id, the giving statement reads it); a name typed
/// for somebody not on the list is kept with the entry (its details and
/// the day's list) — the same as the sheet's free details did.
class IncomeFlow extends StatefulWidget {
  const IncomeFlow({
    super.key,
    required this.db,
    required this.orgId,
    this.currency = 'XOF',
    this.reports,
    this.store,
  });

  final LocalDb db;
  final String orgId;
  final String currency;

  /// The members list (online, best effort). Null: a name is typed.
  final ReportsRepository? reports;
  final FlowStore? store;

  @override
  State<IncomeFlow> createState() => _IncomeFlowState();
}

/// The four kinds, and the account each is filed under. « Don » files under
/// the seeded 'Donations' (shown « Dons »); the others open their account
/// by name the first time (record_entry → ensure_account).
const incomeKinds = {
  'cotisation': 'Cotisations',
  'don': 'Donations',
  'vente': 'Ventes',
};

/// The seeded church headings (002) — never offered again.
const churchHeadings = {'Tithes', 'Offerings', 'Special Collections'};

class _IncomeFlowState extends State<IncomeFlow> {
  final _flow = StepFlowController();
  final _otherName = TextEditingController();
  final _who = TextEditingController();
  final _amount = TextEditingController();
  String? _kind;
  String _method = 'cash';
  ChurchMember? _member;
  List<ChurchMember> _members = const [];
  List<String> _others = const [];

  NumberFormat get _money => moneyFormat(widget.currency);
  double get _value => parseAmount(_amount.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _otherName.dispose();
    _who.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final names = await widget.db.categoriesFor(widget.orgId, 'in');
    final kept = [
      for (final n in names)
        if (!churchHeadings.contains(n) && !incomeKinds.values.contains(n)) n,
    ];
    if (mounted) setState(() => _others = kept);
    final reports = widget.reports;
    if (reports == null || !reports.isConfigured) return;
    try {
      final members = await reports.members(widget.orgId);
      if (mounted) setState(() => _members = members);
    } catch (_) {
      // No signal: the name is typed.
    }
  }

  String _kindLabel(String kind) => switch (kind) {
        'cotisation' => context.tr('Cotisation'),
        'don' => context.tr('Don'),
        'vente' => context.tr('Vente'),
        _ => context.tr('Autre'),
      };

  String get _category =>
      _kind == 'autre' ? _otherName.text.trim() : (incomeKinds[_kind] ?? '');

  String get _whoName => _member?.fullName ?? _who.text.trim();

  /// « Cotisation — Awa Ouédraogo », « Location de la salle ».
  String get _label {
    final what =
        _kind == 'autre' ? accountLabel(_category) : _kindLabel(_kind ?? '');
    return _whoName.isEmpty ? what : '$what — $_whoName';
  }

  Map<String, Object?> _save() => {
        'kind': _kind,
        'other': _otherName.text,
        'member': _member == null
            ? null
            : {'id': _member!.id, 'name': _member!.fullName},
        'who': _who.text,
        'amount': _amount.text,
        'method': _method,
      };

  void _restore(Map<String, Object?> a) => setState(() {
        _kind = a['kind'] as String?;
        _otherName.text = (a['other'] as String?) ?? '';
        final m = a['member'];
        _member = m is Map
            ? ChurchMember(id: '${m['id']}', fullName: '${m['name']}')
            : null;
        _who.text = (a['who'] as String?) ?? '';
        _amount.text = (a['amount'] as String?) ?? '';
        _method = (a['method'] as String?) ?? 'cash';
      });

  Future<bool> _record() async {
    final typed = _member == null ? _who.text.trim() : '';
    await widget.db.recordEntry(
      orgId: widget.orgId,
      amount: _value,
      direction: 'in',
      label: _label,
      category: _category,
      method: _method,
      memberId: _member?.id,
      memberName: _whoName.isEmpty ? null : _whoName,
      details: typed.isEmpty ? const {} : {'De la part de': typed},
    );
    return true;
  }

  void _another() {
    _restore(const {});
    _flow.restart();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StepFlow(
      title: context.tr('Recette'),
      controller: _flow,
      store: widget.store,
      draft: FlowDraft(
          key: 'income:${widget.orgId}', save: _save, restore: _restore),
      steps: [
        FlowStep(
          id: 'kind',
          title: context.tr('Qu\'est-ce que c\'est ?'),
          isValid: () => _kind != null,
          builder: (_) => FlowChoice<String>(
            options: [
              FlowOption('cotisation', context.tr('Cotisation'),
                  icon: Icons.savings_outlined,
                  detail: context.tr('Ce qu\'un membre verse')),
              FlowOption('don', context.tr('Don'),
                  icon: Icons.redeem_outlined,
                  detail: context.tr('Un cadeau, sans contrepartie')),
              FlowOption('vente', context.tr('Vente'),
                  icon: Icons.sell_outlined,
                  detail: context.tr('Ce que l\'association a vendu')),
              FlowOption('autre', context.tr('Autre'),
                  icon: Icons.add, detail: context.tr('Vous lui donnez un nom')),
            ],
            value: _kind,
            onChanged: (v) => setState(() => _kind = v),
          ),
        ),
        FlowStep(
          id: 'other',
          title: context.tr('Quel nom pour cette recette ?'),
          shown: () => _kind == 'autre',
          isValid: () => _otherName.text.trim().isNotEmpty,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('income-other'),
                controller: _otherName,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.tr('Location de la salle'),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_others.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in _others)
                      ChoiceChip(
                        label: Text(accountLabel(o)),
                        selected: _otherName.text.trim() == o,
                        onSelected: (_) => setState(() => _otherName.text = o),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        FlowStep(
          id: 'who',
          title: context.tr('De qui ?'),
          optional: true,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_members.isNotEmpty) ...[
                for (final m in _members)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: _member?.id == m.id
                        ? theme.colorScheme.primaryContainer
                        : null,
                    child: ListTile(
                      key: Key('income-member-${m.id}'),
                      minTileHeight: 56,
                      leading: const Icon(Icons.person_outline),
                      title: Text(m.fullName),
                      trailing: _member?.id == m.id
                          ? Icon(Icons.check_circle,
                              color: theme.colorScheme.primary)
                          : null,
                      onTap: () => setState(() {
                        _member = _member?.id == m.id ? null : m;
                        _who.clear();
                      }),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              TextField(
                key: const Key('income-who'),
                controller: _who,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() => _member = null),
                decoration: InputDecoration(
                  labelText: _members.isEmpty
                      ? context.tr('Son nom')
                      : context.tr('Quelqu\'un d\'autre'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        FlowStep(
          id: 'amount',
          title: context.tr('Combien ?'),
          isValid: () => _value > 0,
          builder: (_) => FlowNumberField(
            key: const Key('income-amount'),
            controller: _amount,
            suffix: widget.currency == 'XOF' ? 'FCFA' : widget.currency,
            onChanged: (_) => setState(() {}),
          ),
        ),
        FlowStep(
          id: 'method',
          title: context.tr('Reçue comment ?'),
          builder: (_) => FlowChoice<String>(
            options: moneyMethods(context),
            value: _method,
            onChanged: (v) => setState(() => _method = v),
          ),
        ),
      ],
      summary: (_) => FlowSummary(rows: [
        FlowSummaryRow(
            context.tr('Recette'),
            _kind == 'autre' ? accountLabel(_category) : _kindLabel(_kind ?? ''),
            step: _kind == 'autre' ? 'other' : 'kind'),
        if (_whoName.isNotEmpty)
          FlowSummaryRow(context.tr('De'), _whoName, step: 'who'),
        FlowSummaryRow(context.tr('Montant'), _money.format(_value),
            step: 'amount', bold: true),
        FlowSummaryRow(context.tr('Reçue'), moneyMethodLabel(context, _method),
            step: 'method'),
      ], footer: Text(context.tr('Fonctionne sans connexion'),
          style: theme.textTheme.bodySmall)),
      saveLabel: context.tr('Enregistrer la recette'),
      onSave: _record,
      done: (_) => FlowDone(
        message: context.tr('{label} : {amount} reçu',
            {'label': _label, 'amount': _money.format(_value)}),
        actions: [
          FlowAction(
            key: const Key('income-another'),
            label: context.tr('Nouvelle recette'),
            icon: Icons.add,
            onPressed: _another,
          ),
        ],
      ),
    );
  }
}
