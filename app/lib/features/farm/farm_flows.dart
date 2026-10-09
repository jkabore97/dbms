import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/db/local_db.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/retail/stock_rule.dart';
import '../common/step_flow.dart';

/// The farm's stock, one entry at a time (115): « Réception » (feed,
/// medicine, supplies arriving), « Consommation » (given to the animals)
/// and « Perte » (spoiled, lost).
///
/// They replace the three sheets of 009 and keep the one rule those sheets
/// were built on: they work with no signal. Every save writes to this phone
/// (`LocalDb.receiveStock` / `moveStock` — the outbox, then
/// `receive_stock()` / `move_stock()` on the server) and returns at once.
/// The farm's supplies stay what they were — items and their movements —
/// apart from what it sells (« À vendre », articles).
class FarmStockFlow {
  FarmStockFlow._();

  /// « Réception ». True once something was recorded. [item] opens it on
  /// a supply already kept — « Ajouter du stock » on one running out (122).
  static Future<bool?> receive(
    BuildContext context, {
    required LocalDb db,
    required OrgSummary org,
    String? item,
  }) =>
      StepFlow.push(context, _ReceiveFlow(db: db, org: org, item: item));

  /// « Consommation » ([wasted] false) or « Perte » ([wasted] true). [farm]
  /// lists the groups of animals besides the flocks this phone knows, when
  /// there is signal; null leaves the flocks alone.
  static Future<bool?> use(
    BuildContext context, {
    required LocalDb db,
    required OrgSummary org,
    FarmRepository? farm,
    bool wasted = false,
  }) =>
      StepFlow.push(
          context, _UseFlow(db: db, org: org, farm: farm, wasted: wasted));
}

/// The words a supply is counted in, one tap each.
class FarmUnitChips extends StatelessWidget {
  const FarmUnitChips({
    super.key,
    required this.units,
    required this.value,
    required this.onChanged,
  });

  final List<String> units;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final u in units)
            ChoiceChip(
              key: Key('farm-unit-$u'),
              label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(u, style: const TextStyle(fontSize: 17)),
              ),
              selected: u == value,
              onSelected: (_) => onChanged(u),
            ),
        ],
      );
}

/// A day: today, yesterday, or one picked on the calendar.
class FarmDayChoice extends StatelessWidget {
  const FarmDayChoice({
    super.key,
    required this.value,
    required this.onChanged,
    this.helpText,
    this.future = false,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String? helpText;

  /// Days ahead may be picked (a harvest expected), not only days past.
  final bool future;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateUtils.dateOnly(value);
    final other = day != today && day != yesterday;
    final format = DateFormat('d MMMM y', Localizations.localeOf(context).toString());
    return FlowChoice<String>(
      options: [
        FlowOption('today', context.tr('Aujourd\'hui'), icon: Icons.today),
        FlowOption('yesterday', context.tr('Hier'), icon: Icons.history),
        FlowOption('other', context.tr('Un autre jour'),
            icon: Icons.event, detail: other ? format.format(day) : null),
      ],
      value: day == today ? 'today' : (day == yesterday ? 'yesterday' : 'other'),
      onChanged: (v) async {
        if (v == 'today') return onChanged(today);
        if (v == 'yesterday') return onChanged(yesterday);
        final picked = await showDatePicker(
          context: context,
          initialDate: day,
          firstDate: DateTime(today.year - 3),
          lastDate: future ? DateTime(today.year + 3) : today,
          helpText: helpText,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// The note every stock flow ends on, under the summary: nothing here waits
/// for the network.
class _OfflineLine extends StatelessWidget {
  const _OfflineLine();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('Fonctionne sans connexion : envoyé dès que le réseau revient.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
}

/// One supply as this phone last heard of it.
class _Supply {
  const _Supply(this.name, this.unit, this.onHand);
  final String name;
  final String unit;

  /// Null when the server never said (an item only known from this phone's
  /// own entries): no check here, the server's stands.
  final double? onHand;
}

Future<List<_Supply>> _supplies(LocalDb db, String orgId) async {
  final cached = await db.cachedFarmItems(orgId);
  if (cached.isNotEmpty) {
    return [
      for (final r in cached)
        _Supply(r['name'] as String, (r['unit'] as String?) ?? 'sac',
            (r['on_hand'] as num?)?.toDouble() ?? 0),
    ];
  }
  return [for (final n in await db.farmItemNames(orgId)) _Supply(n, 'sac', null)];
}

const _newItem = '__new__';

// ----------------------------------------------------------------
// Réception
// ----------------------------------------------------------------

class _ReceiveFlow extends StatefulWidget {
  const _ReceiveFlow({required this.db, required this.org, this.item});
  final LocalDb db;
  final OrgSummary org;
  final String? item;

  @override
  State<_ReceiveFlow> createState() => _ReceiveFlowState();
}

class _ReceiveFlowState extends State<_ReceiveFlow> {
  final _flow = StepFlowController();
  final _name = TextEditingController();
  final _quantity = TextEditingController();
  final _price = TextEditingController();
  final _supplier = TextEditingController();

  List<_Supply> _known = const [];
  late String? _item = widget.item;
  String _unit = 'sac';

  /// The expense account a priced delivery is booked to — 009 booked every
  /// one to « Aliment », medicine and seed included; the farm's chart has
  /// the right ones (019).
  String _category = 'Aliment';

  @override
  void initState() {
    super.initState();
    _supplies(widget.db, widget.org.id).then((s) {
      if (mounted) setState(() => _known = s);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _quantity, _price, _supplier]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isNew => _item == _newItem;
  String get _itemName => (_isNew ? _name.text : (_item ?? '')).trim();
  double get _qty => FlowNumberField.read(_quantity) ?? 0;
  double get _unitCost => FlowNumberField.read(_price) ?? 0;
  NumberFormat get _money => moneyFormat(widget.org.currency);

  _Supply? get _supply {
    for (final s in _known) {
      if (s.name == _item) return s;
    }
    return null;
  }

  /// A known item keeps its own unit: the server's item has one, and a
  /// delivery says nothing new about it.
  String get _shownUnit => _supply?.unit ?? _unit;

  Map<String, Object?> _save() => {
        'item': _item,
        'name': _name.text,
        'quantity': _quantity.text,
        'unit': _unit,
        'price': _price.text,
        'category': _category,
        'supplier': _supplier.text,
      };

  void _restore(Map<String, Object?> a) => setState(() {
        _item = a['item'] as String?;
        _name.text = (a['name'] as String?) ?? '';
        _quantity.text = (a['quantity'] as String?) ?? '';
        _unit = (a['unit'] as String?) ?? 'sac';
        _price.text = (a['price'] as String?) ?? '';
        _category = (a['category'] as String?) ?? 'Aliment';
        _supplier.text = (a['supplier'] as String?) ?? '';
      });

  Future<bool> _record() async {
    final supplier = _supplier.text.trim();
    await widget.db.receiveStock(
      orgId: widget.org.id,
      itemName: _itemName,
      quantity: _qty,
      // A delivery logged without a price is still a delivery — the invoice
      // is often in the truck — and 009 posts no journal entry for it.
      unitCost: _unitCost > 0 ? _unitCost : null,
      unit: _shownUnit,
      category: _category,
      memo: supplier.isEmpty
          ? null
          : context.tr('Fournisseur : {name}', {'name': supplier}),
    );
    return true;
  }

  static const _categories = [
    'Aliment',
    'Vétérinaire',
    'Semences',
    'Engrais et traitements',
    'Fournitures ferme',
  ];

  String _categoryLabel(String c) => switch (c) {
        'Aliment' => context.tr('Aliment des animaux'),
        'Vétérinaire' => context.tr('Médicaments, vaccins'),
        'Semences' => context.tr('Semences'),
        'Engrais et traitements' => context.tr('Engrais et traitements'),
        _ => context.tr('Autre fourniture'),
      };

  @override
  Widget build(BuildContext context) {
    final unit = _shownUnit;
    final total = _qty * _unitCost;
    return StepFlow(
      title: context.tr('Réception'),
      controller: _flow,
      draft: FlowDraft(
          key: 'farm_receive:${widget.org.id}', save: _save, restore: _restore),
      steps: [
        FlowStep(
          id: 'item',
          title: context.tr('Qu\'est-ce qui arrive ?'),
          isValid: () => _itemName.isNotEmpty,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowChoice<String>(
                options: [
                  for (final s in _known)
                    FlowOption(s.name, s.name,
                        icon: Icons.inventory_2_outlined,
                        detail: s.onHand == null
                            ? null
                            : context.tr('Il reste {n} {unit}',
                                {'n': trimQuantity(s.onHand!), 'unit': s.unit})),
                  FlowOption(_newItem, context.tr('Un nouvel article'),
                      icon: Icons.add),
                ],
                value: _item,
                onChanged: (v) => setState(() => _item = v),
              ),
              if (_isNew)
                TextField(
                  key: const Key('farm-new-item'),
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                    labelText: context.tr('Nom de l\'article'),
                    hintText: context.tr('Aliment ponte, vaccin, sciure…'),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
            ],
          ),
        ),
        FlowStep(
          id: 'quantity',
          title: context.tr('Combien ?'),
          isValid: () => _qty > 0,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowNumberField(
                key: const Key('farm-quantity'),
                controller: _quantity,
                suffix: unit,
                onChanged: (_) => setState(() {}),
              ),
              if (_isNew || _supply == null) ...[
                const SizedBox(height: 20),
                Text(context.tr('Compté en'),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                FarmUnitChips(
                  units: farmUnits,
                  value: _unit,
                  onChanged: (u) => setState(() => _unit = u),
                ),
              ],
            ],
          ),
        ),
        FlowStep(
          id: 'price',
          title: context.tr('Prix par {unit} ?', {'unit': unit}),
          help: context.tr('Laissez vide si vous ne connaissez pas encore le prix.'),
          optional: true,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowNumberField(
                key: const Key('farm-price'),
                controller: _price,
                suffix: widget.org.currency,
                decimal: false,
                onChanged: (_) => setState(() {}),
              ),
              if (total > 0) ...[
                const SizedBox(height: 12),
                Text(context.tr('Total {amount}', {'amount': _money.format(total)}),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ],
          ),
        ),
        FlowStep(
          id: 'category',
          title: context.tr('C\'est pour quoi ?'),
          help: context.tr('La dépense est rangée là.'),
          shown: () => _unitCost > 0,
          builder: (_) => FlowChoice<String>(
            options: [
              for (final c in _categories) FlowOption(c, _categoryLabel(c)),
            ],
            value: _category,
            onChanged: (v) => setState(() => _category = v),
          ),
        ),
        FlowStep(
          id: 'supplier',
          title: context.tr('Qui l\'a livré ?'),
          optional: true,
          builder: (_) => TextField(
            key: const Key('farm-supplier'),
            controller: _supplier,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
              hintText: context.tr('SODEPAL, Agri Supply, le vétérinaire…'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
      summary: (_) => FlowSummary(
        rows: [
          FlowSummaryRow(context.tr('Article'), _itemName, step: 'item'),
          FlowSummaryRow(context.tr('Quantité'), '${trimQuantity(_qty)} $unit',
              step: 'quantity'),
          FlowSummaryRow(
              context.tr('Prix'),
              _unitCost > 0
                  ? context.tr('{price} par {unit}',
                      {'price': _money.format(_unitCost), 'unit': unit})
                  : context.tr('Pas encore connu'),
              step: 'price'),
          if (total > 0) ...[
            FlowSummaryRow(context.tr('Total payé'), _money.format(total),
                bold: true),
            FlowSummaryRow(context.tr('Rangé dans'), _categoryLabel(_category),
                step: 'category'),
          ],
          if (_supplier.text.trim().isNotEmpty)
            FlowSummaryRow(context.tr('Fournisseur'), _supplier.text.trim(),
                step: 'supplier'),
        ],
        footer: const _OfflineLine(),
      ),
      onSave: _record,
      done: (_) => FlowDone(
        message: context.tr('{item} : {q} {unit} reçus',
            {'q': trimQuantity(_qty), 'unit': unit, 'item': _itemName}),
        actions: [
          FlowAction(
            key: const Key('farm-again'),
            label: context.tr('Une autre réception'),
            icon: Icons.add,
            primary: true,
            onPressed: () {
              _restore(const {});
              _flow.restart();
              _supplies(widget.db, widget.org.id).then((s) {
                if (mounted) setState(() => _known = s);
              });
            },
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// Consommation, Perte
// ----------------------------------------------------------------

/// Who ate it: a flock this phone knows (offline), or a group of animals
/// the server listed (with signal).
class _Eater {
  const _Eater(this.id, this.label);
  final String id;
  final String label;
}

class _UseFlow extends StatefulWidget {
  const _UseFlow({
    required this.db,
    required this.org,
    required this.wasted,
    this.farm,
  });
  final LocalDb db;
  final OrgSummary org;
  final FarmRepository? farm;
  final bool wasted;

  @override
  State<_UseFlow> createState() => _UseFlowState();
}

class _UseFlowState extends State<_UseFlow> {
  final _flow = StepFlowController();
  final _quantity = TextEditingController();
  final _note = TextEditingController();

  List<_Supply> _known = const [];
  bool _loaded = false;
  List<_Eater> _eaters = const [];
  String? _item;

  /// '' = the whole farm, no one batch.
  String _eater = '';
  String? _cause;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final supplies = await _supplies(widget.db, widget.org.id);
    final flocks = await widget.db.cachedFlocks(widget.org.id);
    if (!mounted) return;
    setState(() {
      _known = supplies;
      _loaded = true;
      _eaters = [
        for (final f in flocks)
          _Eater(f['flock_id'] as String, f['batch_code'] as String),
      ];
    });
    if (widget.wasted) return;
    // The other animals, when there is signal; never waited for.
    final farm = widget.farm;
    if (farm == null || !farm.isConfigured) return;
    try {
      final herds = await farm.herds(widget.org.id);
      if (!mounted) return;
      setState(() => _eaters = [
            ..._eaters,
            for (final h in herds)
              if (!_eaters.any((e) => e.label == h.label)) _Eater(h.id, h.label),
          ]);
    } catch (_) {}
  }

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _qty => FlowNumberField.read(_quantity) ?? 0;

  _Supply? get _supply {
    for (final s in _known) {
      if (s.name == _item) return s;
    }
    return null;
  }

  String get _unit => _supply?.unit ?? 'sac';

  /// Stock never goes below zero (101): what the server last said is on
  /// hand is checked here first, so most refusals never leave the phone.
  String? get _short {
    final s = _supply;
    final onHand = s?.onHand;
    if (s == null || onHand == null || _qty <= onHand) return null;
    return stockShortMessage(context.trLanguage, s.name, onHand);
  }

  String? get _eaterLabel {
    for (final e in _eaters) {
      if (e.id == _eater) return e.label;
    }
    return null;
  }

  List<String> get _causes => widget.wasted
      ? [
          context.tr('Abîmé'),
          context.tr('Mouillé'),
          context.tr('Périmé'),
          context.tr('Mangé par les rats'),
          context.tr('Volé'),
        ]
      : const [];

  /// What the movement's note says: the batch it went to, the cause, and
  /// any words typed. move_stock() keeps no batch of its own (009), so the
  /// note carries it — read in the day's list and in the history — rather
  /// than a new parameter an offline phone could send to a server without it.
  String? get _memo {
    final parts = [
      if (_eaterLabel != null) context.tr('Pour {name}', {'name': _eaterLabel}),
      ?_cause,
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Map<String, Object?> _save() => {
        'item': _item,
        'quantity': _quantity.text,
        'eater': _eater,
        'cause': _cause,
        'note': _note.text,
      };

  void _restore(Map<String, Object?> a) => setState(() {
        _item = a['item'] as String?;
        _quantity.text = (a['quantity'] as String?) ?? '';
        _eater = (a['eater'] as String?) ?? '';
        _cause = a['cause'] as String?;
        _note.text = (a['note'] as String?) ?? '';
      });

  Future<bool> _record() async {
    final short = _short;
    if (short != null) throw StateError(short);
    await widget.db.moveStock(
      orgId: widget.org.id,
      itemName: _item!,
      quantity: _qty,
      kind: widget.wasted ? 'wasted' : 'consumed',
      unit: _unit,
      memo: _memo,
    );
    return true;
  }

  Future<void> _receiveFirst() async {
    final saved = await FarmStockFlow.receive(context, db: widget.db, org: widget.org);
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wasted = widget.wasted;
    return StepFlow(
      title: wasted ? context.tr('Perte') : context.tr('Consommation'),
      controller: _flow,
      draft: FlowDraft(
          key: '${wasted ? 'farm_waste' : 'farm_use'}:${widget.org.id}',
          save: _save,
          restore: _restore),
      steps: [
        FlowStep(
          id: 'item',
          title: wasted
              ? context.tr('Qu\'est-ce qui est perdu ?')
              : context.tr('Qu\'est-ce qui est donné ?'),
          isValid: () => _supply != null,
          builder: (_) => !_loaded
              ? const LinearProgressIndicator()
              : _known.isEmpty
                  // Nothing received yet: nothing can leave (101). Say so,
                  // and open the delivery from here.
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          context.tr('Rien en stock pour le moment. Enregistrez d\'abord ce qui est arrivé.'),
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            key: const Key('farm-receive-first'),
                            onPressed: _receiveFirst,
                            icon: const Icon(Icons.local_shipping_outlined),
                            label: Text(context.tr('Enregistrer une réception')),
                          ),
                        ),
                      ],
                    )
                  : FlowChoice<String>(
                      options: [
                        for (final s in _known)
                          FlowOption(s.name, s.name,
                              icon: Icons.inventory_2_outlined,
                              detail: s.onHand == null
                                  ? null
                                  : context.tr('Il reste {n} {unit}', {
                                      'n': trimQuantity(s.onHand!),
                                      'unit': s.unit
                                    })),
                      ],
                      value: _item,
                      onChanged: (v) => setState(() => _item = v),
                    ),
        ),
        FlowStep(
          id: 'quantity',
          title: context.tr('Combien ?'),
          help: _supply?.onHand == null
              ? null
              : context.tr('Il reste {n} {unit}',
                  {'n': trimQuantity(_supply!.onHand!), 'unit': _unit}),
          isValid: () => _qty > 0 && _short == null,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowNumberField(
                key: const Key('farm-quantity'),
                controller: _quantity,
                suffix: _unit,
                onChanged: (_) => setState(() {}),
              ),
              if (_short != null) ...[
                const SizedBox(height: 12),
                Text(_short!,
                    key: const Key('move-stock-short'),
                    style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
        FlowStep(
          id: 'batch',
          title: context.tr('Pour quels animaux ?'),
          shown: () => !wasted && _eaters.isNotEmpty,
          builder: (_) => FlowChoice<String>(
            options: [
              for (final e in _eaters)
                FlowOption(e.id, e.label, icon: Icons.pets_outlined),
              FlowOption('', context.tr('Toute la ferme'),
                  icon: Icons.agriculture_outlined),
            ],
            value: _eater,
            onChanged: (v) => setState(() => _eater = v),
          ),
        ),
        FlowStep(
          id: 'note',
          title: wasted ? context.tr('Pourquoi ?') : context.tr('Une note ?'),
          optional: true,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_causes.isNotEmpty) ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in _causes)
                      ChoiceChip(
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(c, style: const TextStyle(fontSize: 16)),
                        ),
                        selected: _cause == c,
                        onSelected: (on) => setState(() => _cause = on ? c : null),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                key: const Key('farm-note'),
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: wasted
                      ? context.tr('Sac éventré')
                      : context.tr('Poulailler 2'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ],
      summary: (_) => FlowSummary(
        rows: [
          FlowSummaryRow(context.tr('Article'), _item ?? '', step: 'item'),
          FlowSummaryRow(context.tr('Quantité'), '${trimQuantity(_qty)} $_unit',
              step: 'quantity', bold: true),
          if (!wasted && _eaters.isNotEmpty)
            FlowSummaryRow(
                context.tr('Pour'), _eaterLabel ?? context.tr('Toute la ferme'),
                step: 'batch'),
          if (_memo != null && (wasted || _note.text.trim().isNotEmpty))
            FlowSummaryRow(context.tr('Note'), _memo!, step: 'note'),
        ],
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('Le compte bouge, l\'argent non : il est parti à la livraison.'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const _OfflineLine(),
          ],
        ),
      ),
      onSave: _record,
      done: (_) => FlowDone(
        message: wasted
            ? context.tr('Perte enregistrée : {item}, {q} {unit}',
                {'q': trimQuantity(_qty), 'unit': _unit, 'item': _item ?? ''})
            : context.tr('{item} : {q} {unit} donnés',
                {'q': trimQuantity(_qty), 'unit': _unit, 'item': _item ?? ''}),
        actions: [
          FlowAction(
            key: const Key('farm-again'),
            label: wasted
                ? context.tr('Une autre perte')
                : context.tr('Une autre consommation'),
            icon: Icons.add,
            primary: true,
            onPressed: () {
              _restore(const {});
              _flow.restart();
              _load();
            },
          ),
        ],
      ),
    );
  }
}
