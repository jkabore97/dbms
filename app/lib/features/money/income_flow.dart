import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/association/books_start.dart';
import '../../core/association/members.dart';
import '../../core/db/local_db.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/money/money_types.dart';
import '../../core/reports/models.dart' show ChurchMember, accountLabel;
import '../../core/reports/reports_repository.dart';
import '../church/members/member_form_screen.dart';
import '../common/step_flow.dart';
import 'money_steps.dart';
import 'money_types_ui.dart';

/// « Recette », one entry at a time (115) — an association's money in
/// (a legacy 'church' org is an association and gets the same).
///
/// What it is (Cotisation, Don, Vente, Autre, then the association's own
/// types, 149, and « Ajouter un type de recette ») → the name, for « Autre » →
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
///
/// The association's own types (149) are income accounts of its chart: a
/// card files the entry under the account's name exactly as « Autre » does
/// (record_entry → ensure_account when the signal comes), so it works
/// offline the same way, and the books, the reports and the analyses count
/// it. The list is kept on the phone (MoneyTypesBook): step 1 shows it with
/// no signal. The names « Autre » was given before are accounts already —
/// they are cards now, and can be hidden from « Gérer les types ».
class IncomeFlow extends StatefulWidget {
  const IncomeFlow({
    super.key,
    required this.db,
    required this.orgId,
    this.currency = 'XOF',
    this.reports,
    this.store,
    this.books,
    this.canAddMembers = false,
    this.types,
    this.canEditTypes = false,
  });

  /// The types' server (149). Null: [reports], which is it in the app.
  final MoneyTypesApi? types;

  /// « Ajouter un type de recette » and « Gérer les types »: for the people
  /// who record (canWriteTypes) — never an observer.
  final bool canEditTypes;

  final LocalDb db;

  /// « Ajouter un membre » in « De qui ? » (148): somebody not on the list
  /// yet is added there and picked — for those who may write the list.
  final bool canAddMembers;
  final String orgId;
  final String currency;

  /// The members list (online, best effort). Null: a name is typed.
  final ReportsRepository? reports;
  final FlowStore? store;

  /// The usual cotisation (134): « Cotisation » fills its amount with it,
  /// still editable. Null: [reports] (which knows it), else none.
  final BooksStartApi? books;

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

  /// The memo (optional), apart from the entry's name: what the old
  /// recording sheet's « Note » kept (batch 115).
  final _memo = TextEditingController();
  String? _kind;
  String _method = 'cash';
  ChurchMember? _member;
  List<ChurchMember> _members = const [];

  /// The association's own types (149), as last read.
  MoneyTypesList _types = const MoneyTypesList(types: []);
  late final MoneyTypesBook _book =
      MoneyTypesBook(api: widget.types ?? widget.reports, db: widget.db);

  /// The account a type card files under, and what the card says — kept
  /// apart from the list so a draft restored offline still has them.
  String? _typeName;
  String? _typeLabel;

  /// The association's usual cotisation (134), and the amount it last put
  /// in the field — only that is replaced or taken back.
  ContributionDefault? _usual;
  String? _filled;

  NumberFormat get _money => moneyFormat(widget.currency);
  double get _value => parseAmount(_amount.text, currency: widget.currency) ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
    // Apart from the phone's categories: the server answers on its own.
    _loadUsual();
  }

  @override
  void dispose() {
    _otherName.dispose();
    _who.dispose();
    _amount.dispose();
    _memo.dispose();
    super.dispose();
  }

  /// The phone's copy at once, then the server's when it answers.
  Future<void> _loadTypes() async {
    final kept = await _book.cached(widget.orgId);
    if (mounted) setState(() => _types = kept);
    final fresh = await _book.load(widget.orgId);
    if (mounted) setState(() => _types = fresh);
  }

  Future<void> _load() async {
    unawaited(_loadTypes());
    final reports = widget.reports;
    if (reports == null) return;
    // The server's list, or with no signal the one this phone last read
    // (148's MembersBook): a gift recorded offline is still attributed.
    try {
      final list = await MembersBook(reports, widget.db).load(widget.orgId);
      if (mounted) {
        setState(() {
          _list = list;
          _members = [for (final m in list.members) m.asChurchMember];
        });
      }
    } catch (_) {
      // No signal and no copy: the name is typed.
    }
  }

  MembersList? _list;

  /// « Ajouter un membre »: the form, then the new member picked.
  Future<void> _addMember() async {
    final reports = widget.reports;
    if (reports == null) return;
    final saved = await Navigator.of(context).push<AssociationMember>(
      MaterialPageRoute(
        builder: (_) => MemberFormScreen(
          api: reports,
          orgId: widget.orgId,
          others: _list?.members ?? const [],
          notesKept: _list?.serverReady ?? true,
          single: true,
        ),
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      final m = saved.asChurchMember;
      _members = [..._members.where((x) => x.id != m.id), m]
        ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
      _member = m;
      _who.clear();
    });
  }

  /// The usual cotisation: this run's last answer at once, the server's
  /// when it comes (a server without 134 answers nothing).
  Future<void> _loadUsual() async {
    final known = BooksStart.lastKnown[widget.orgId]?.contribution;
    if (known != null && mounted) setState(() => _usual = known);
    final api = widget.books ??
        ((widget.reports?.isConfigured ?? false) ? widget.reports : null);
    if (api == null) return;
    try {
      final start = await api.booksStart(widget.orgId);
      if (start != null && mounted) {
        setState(() => _usual = start.contribution);
        if (_kind == 'cotisation') _prefill();
      }
    } catch (_) {
      // No signal: the amount is typed.
    }
  }

  /// « Cotisation » chosen: the usual amount, unless something else was typed.
  void _prefill() {
    final usual = _usual;
    if (usual == null) return;
    final text = usual.amount == usual.amount.roundToDouble()
        ? usual.amount.toInt().toString()
        : usual.amount.toString();
    if (_amount.text.isEmpty || _amount.text == _filled) {
      _amount.text = text;
      _filled = text;
    }
  }

  void _choose(String? kind) {
    if (kind == _addKind) {
      _addType();
      return;
    }
    setState(() {
      _kind = kind;
      final type = kind != null && kind.startsWith('type:') ? _typeOf(kind) : null;
      _typeName = type?.name;
      _typeLabel = type?.display;
      if (kind == 'cotisation') {
        _prefill();
      } else if (_filled != null && _amount.text == _filled) {
        _amount.clear();
        _filled = null;
      }
    });
  }

  static const _addKind = '__add_type__';

  MoneyType? _typeOf(String kind) {
    final id = kind.substring('type:'.length);
    for (final t in _types.types) {
      if (t.id == id) return t;
    }
    return null;
  }

  bool get _isType => _kind?.startsWith('type:') ?? false;

  /// « Ajouter un type de recette »: the form, then the new card chosen.
  Future<void> _addType() async {
    final added = await showAddTypeSheet(context,
        book: _book, orgId: widget.orgId, current: _types, direction: 'in');
    if (added == null || !mounted) return;
    setState(() => _types = MoneyTypesList(
        types: [..._types.types.where((t) => t.id != added.id), added],
        serverReady: _types.serverReady,
        fromPhone: _types.fromPhone));
    _choose('type:${added.id}');
  }

  /// « Gérer les types »: the list, then step 1 read again.
  Future<void> _manage() async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ManageTypesScreen(
          book: _book, orgId: widget.orgId, direction: 'in', canEdit: widget.canEditTypes),
    ));
    if (!mounted) return;
    final fresh = await _book.load(widget.orgId);
    if (!mounted) return;
    setState(() {
      _types = fresh;
      if (_isType && _typeOf(_kind!) == null) _kind = null;
    });
  }

  String _usualLine(ContributionDefault c) {
    final amount = _money.format(c.amount);
    return switch (c.period) {
      ContributionPeriod.week => context.tr('Cotisation habituelle : {amount} par semaine', {'amount': amount}),
      ContributionPeriod.month => context.tr('Cotisation habituelle : {amount} par mois', {'amount': amount}),
      ContributionPeriod.year => context.tr('Cotisation habituelle : {amount} par an', {'amount': amount}),
    };
  }

  String _kindLabel(String kind) => switch (kind) {
        'cotisation' => context.tr('Cotisation'),
        'don' => context.tr('Don'),
        'vente' => context.tr('Vente'),
        _ => context.tr('Autre'),
      };

  String get _category => _kind == 'autre'
      ? _otherName.text.trim()
      : _isType
          ? (_typeName ?? '')
          : (incomeKinds[_kind] ?? '');

  /// What the entry is called: the type's card, « Autre »'s name, a
  /// built-in card's word.
  String get _what => _isType
      ? (_typeLabel ?? accountLabel(_category))
      : _kind == 'autre'
          ? accountLabel(_category)
          : _kindLabel(_kind ?? '');

  String get _whoName => _member?.fullName ?? _who.text.trim();

  /// « Cotisation — Awa Ouédraogo », « Location de la salle ».
  String get _label {
    final what = _what;
    return _whoName.isEmpty ? what : '$what — $_whoName';
  }

  Map<String, Object?> _save() => {
        'kind': _kind,
        'type_name': _typeName,
        'type_label': _typeLabel,
        'other': _otherName.text,
        'member': _member == null
            ? null
            : {'id': _member!.id, 'name': _member!.fullName},
        'who': _who.text,
        'amount': _amount.text,
        'method': _method,
        'memo': _memo.text,
      };

  void _restore(Map<String, Object?> a) => setState(() {
        _kind = a['kind'] as String?;
        _typeName = a['type_name'] as String?;
        _typeLabel = a['type_label'] as String?;
        if ((_kind?.startsWith('type:') ?? false) && _typeName == null) {
          _kind = null;
        }
        _otherName.text = (a['other'] as String?) ?? '';
        final m = a['member'];
        _member = m is Map
            ? ChurchMember(id: '${m['id']}', fullName: '${m['name']}')
            : null;
        _who.text = (a['who'] as String?) ?? '';
        _amount.text = (a['amount'] as String?) ?? '';
        _method = (a['method'] as String?) ?? 'cash';
        _memo.text = (a['memo'] as String?) ?? '';
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
      memo: _memo.text.trim().isEmpty ? null : _memo.text.trim(),
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
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowChoice<String>(
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
                  icon: Icons.edit_note_outlined, detail: context.tr('Vous lui donnez un nom')),
              for (final t in _types.cards('in'))
                FlowOption('type:${t.id}', t.display,
                    icon: typeIcon(t), detail: t.description),
              if (widget.canEditTypes)
                FlowOption(_addKind, context.tr('Ajouter un type de recette'),
                    icon: Icons.add_circle_outline,
                    detail: context.tr('Loyer de salle, kermesse… : sa propre carte, son compte')),
            ],
            value: _kind,
            onChanged: _choose,
            onLongPress: widget.canEditTypes
                ? (v) {
                    if (v.startsWith('type:')) _manage();
                  }
                : null,
              ),
              if (widget.canEditTypes && _types.manageable('in').isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('income-manage-types'),
                    onPressed: _manage,
                    icon: const Icon(Icons.tune),
                    label: Text(context.tr('Gérer les types de recette')),
                  ),
                ),
            ],
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
              if (widget.canAddMembers && widget.reports != null) ...[
                OutlinedButton.icon(
                  key: const Key('income-add-member'),
                  onPressed: _addMember,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(context.tr('Ajouter un membre')),
                ),
                const SizedBox(height: 12),
              ],
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
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowNumberField(
                key: const Key('income-amount'),
                controller: _amount,
                suffix: currencySymbol(widget.currency),
                currency: widget.currency,
                onChanged: (_) => setState(() {}),
              ),
              if (_kind == 'cotisation' && _usual != null) ...[
                const SizedBox(height: 10),
                Text(_usualLine(_usual!),
                    key: const Key('income-usual'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium),
              ],
            ],
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
        FlowStep(
          id: 'memo',
          title: context.tr('Une note ?'),
          help: context.tr('Ce qui aidera à s\'en souvenir : pour quel mois, quelle occasion…'),
          optional: true,
          builder: (_) => TextField(
            key: const Key('income-memo'),
            controller: _memo,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
      ],
      summary: (_) => FlowSummary(rows: [
        FlowSummaryRow(
            context.tr('Recette'),
            _what,
            step: _kind == 'autre' ? 'other' : 'kind'),
        if (_whoName.isNotEmpty)
          FlowSummaryRow(context.tr('De'), _whoName, step: 'who'),
        FlowSummaryRow(context.tr('Montant'), _money.format(_value),
            step: 'amount', bold: true),
        FlowSummaryRow(context.tr('Reçue'), moneyMethodLabel(context, _method),
            step: 'method'),
        if (_memo.text.trim().isNotEmpty)
          FlowSummaryRow(context.tr('Note'), _memo.text.trim(), step: 'memo'),
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
