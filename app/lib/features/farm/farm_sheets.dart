import 'package:flutter/material.dart';
import '../../core/format/money.dart';
import 'package:flutter/services.dart';

import 'package:uuid/uuid.dart';

import '../../core/db/local_db.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../church/entry_controls.dart';

/// The four things Ignace records, and the one rule they all obey: they work
/// with no signal.
///
/// That is not a nice-to-have for this module, it is the module. Ignace is the
/// user the offline architecture was built for; a recording screen that needs
/// the network is a screen he stops using in favour of the notebook that
/// always works. So every sheet here writes to `LocalDb` and returns, and none
/// of them has a spinner waiting on a server.
///
/// They share the church module's keypad and chips deliberately. Somebody who
/// has learned to record an offering already knows how to record twenty sacks
/// of feed, and a second, subtly different keypad is how that person gets
/// slower rather than faster.

/// Feed, medicine or supplies arriving. The one farm sheet that moves money.
class ReceiveStockSheet extends StatefulWidget {
  const ReceiveStockSheet({
    super.key,
    required this.db,
    required this.orgId,
    this.currency = 'XOF',
  });

  final LocalDb db;
  final String orgId;
  final String currency;

  @override
  State<ReceiveStockSheet> createState() => _ReceiveStockSheetState();
}

class _ReceiveStockSheetState extends State<ReceiveStockSheet> {
  NumberFormat get _currency => moneyFormat(widget.currency);

  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();

  String _costDigits = '';
  String _unit = 'sac';
  String? _item;
  List<String> _items = const [];
  bool _loading = true;
  bool _saving = false;

  double get _quantity =>
      double.tryParse(_quantityController.text.replaceAll(',', '.')) ?? 0;

  double get _unitCost => double.tryParse(_costDigits) ?? 0;

  double get _total => _quantity * _unitCost;

  bool get _valid => _quantity > 0 && (_item?.trim().isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final names = await widget.db.farmItemNames(widget.orgId);
    if (!mounted) return;
    setState(() {
      _items = names;
      _item = names.isEmpty ? null : names.first;
      _loading = false;
    });
  }

  Future<void> _addItem() async {
    final name = await promptForName(
      context,
      title: 'Nouvel article',
      label: "Nom de l'article",
      hint: 'Aliment ponte',
    );
    if (name == null || !mounted) return;

    setState(() {
      final existing = _items.firstWhere(
        (i) => i.toLowerCase() == name.toLowerCase(),
        orElse: () => '',
      );
      if (existing.isEmpty) _items = [..._items, name];
      _item = existing.isEmpty ? name : existing;
    });
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);

    final note = _noteController.text.trim();

    await widget.db.receiveStock(
      orgId: widget.orgId,
      itemName: _item!,
      quantity: _quantity,
      // A delivery logged without a price is still a delivery — the invoice is
      // often in the truck — and 009 posts no journal entry for it either.
      unitCost: _unitCost > 0 ? _unitCost : null,
      unit: _unit,
      memo: note.isEmpty ? null : note,
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Colors.orange.shade800;

    return _SheetFrame(
      icon: Icons.local_shipping_outlined,
      title: 'Réception',
      accent: accent,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          )
        else
          CategoryChips(
            categories: _items,
            selected: _item,
            onSelect: (name) => setState(() => _item = name),
            onAddNew: _addItem,
          ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _quantityController,
                enabled: !_saving,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  labelText: 'Quantité',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<String>(
                initialValue: _unit,
                decoration: const InputDecoration(
                  labelText: 'Unité',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final unit in farmUnits)
                    DropdownMenuItem(value: unit, child: Text(unit)),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _unit = value ?? 'sac'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Prix par $_unit', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Center(
          child: Text(
            _costDigits.isEmpty
                ? _currency.format(0)
                : _currency.format(_unitCost),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: _costDigits.isEmpty ? Colors.grey.shade400 : accent,
            ),
          ),
        ),
        if (_total > 0)
          Center(
            child: Text(
              'Total ${_currency.format(_total)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          Center(
            child: Text(
              'Laissez à zéro si vous ne connaissez pas encore le prix',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
        const SizedBox(height: 12),
        AmountKeypad(
          onDigit: (d) => setState(() {
            if (_costDigits.length < 12) {
              _costDigits = (_costDigits + d).replaceFirst(RegExp(r'^0+'), '');
            }
          }),
          onBackspace: () => setState(() {
            if (_costDigits.isNotEmpty) {
              _costDigits = _costDigits.substring(0, _costDigits.length - 1);
            }
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          enabled: !_saving,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Note',
            hintText: 'Livraison SODEPAL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        _SaveButton(
          label: 'Enregistrer la réception',
          accent: accent,
          enabled: _valid,
          saving: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// Feed eaten, or something spoiled. No money: it left when the sacks arrived.
class MoveStockSheet extends StatefulWidget {
  const MoveStockSheet({
    super.key,
    required this.db,
    required this.orgId,
    this.kind = 'consumed',
  });

  final LocalDb db;
  final String orgId;

  /// 'consumed' | 'wasted'
  final String kind;

  @override
  State<MoveStockSheet> createState() => _MoveStockSheetState();
}

class _MoveStockSheetState extends State<MoveStockSheet> {
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();

  String _unit = 'sac';
  String? _item;
  List<String> _items = const [];
  bool _loading = true;
  bool _saving = false;

  bool get _isWaste => widget.kind == 'wasted';

  double get _quantity =>
      double.tryParse(_quantityController.text.replaceAll(',', '.')) ?? 0;

  bool get _valid => _quantity > 0 && (_item?.trim().isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final names = await widget.db.farmItemNames(widget.orgId);
    if (!mounted) return;
    setState(() {
      _items = names;
      _item = names.isEmpty ? null : names.first;
      _loading = false;
    });
  }

  Future<void> _addItem() async {
    final name = await promptForName(
      context,
      title: 'Nouvel article',
      label: "Nom de l'article",
    );
    if (name == null || !mounted) return;
    setState(() {
      if (!_items.any((i) => i.toLowerCase() == name.toLowerCase())) {
        _items = [..._items, name];
      }
      _item = name;
    });
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);

    final note = _noteController.text.trim();

    await widget.db.moveStock(
      orgId: widget.orgId,
      itemName: _item!,
      quantity: _quantity,
      kind: widget.kind,
      unit: _unit,
      memo: note.isEmpty ? null : note,
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        _isWaste ? Theme.of(context).colorScheme.error : Colors.brown.shade600;

    return _SheetFrame(
      icon: _isWaste ? Icons.delete_outline : Icons.restaurant_outlined,
      title: _isWaste ? 'Perte' : 'Consommation',
      accent: accent,
      subtitle: "Le compte bouge, l'argent non : il est parti à la livraison.",
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          )
        else
          CategoryChips(
            categories: _items,
            selected: _item,
            onSelect: (name) => setState(() => _item = name),
            onAddNew: _addItem,
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _quantityController,
                enabled: !_saving,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  labelText: 'Quantité',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<String>(
                initialValue: _unit,
                decoration: const InputDecoration(
                  labelText: 'Unité',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final unit in farmUnits)
                    DropdownMenuItem(value: unit, child: Text(unit)),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _unit = value ?? 'sac'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _noteController,
          enabled: !_saving,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Note',
            hintText: _isWaste ? 'Sac éventré' : 'Poulailler 2',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        if (!_isWaste)
          Text(
            'Compter ce qui est distribué chaque jour est ce qui permet de '
            "savoir lundi que l'aliment finira jeudi.",
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        const SizedBox(height: 16),
        _SaveButton(
          label: _isWaste ? 'Enregistrer la perte' : 'Enregistrer',
          accent: accent,
          enabled: _valid,
          saving: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// The daily gathering, whatever it is that gets gathered.
///
/// This was `RecordEggsSheet`, and the big button on the farm home screen said
/// "Ramassage". Both were built when the only farm in the app was a poultry
/// house, and both quietly told every other kind of farmer that the app was
/// not for them: a market gardener lifting tomatoes and a goat keeper have a
/// morning collection too, and there was nowhere to put it.
///
/// So the button says **Récolte** and the first question on the sheet is
/// *what* — eggs, or any crop currently in the ground. The subject is picked
/// rather than assumed, which is the whole of the change; everything below it
/// (the big number, the keypad, the grades) is the same sheet it always was,
/// because that part was never the problem.
///
/// Two things worth knowing about what happens on save.
///
/// **Eggs still go through the outbox and crops do not.** `recordEggs` writes
/// to this device and syncs later; `record_harvest()` is a server call. That
/// asymmetry is real and it is visible on screen — the crop list is only
/// offered when the server answered — rather than hidden behind a button that
/// fails at the field gate. Eggs are what gets counted at six in the morning
/// with no signal, and eggs are the path that works then.
///
/// **Neither posts to the ledger.** Harvesting is not earning: the money
/// arrives at the sale, through `record_farm_sale()`, and counting it twice
/// would be the oldest bookkeeping mistake there is.
class RecordHarvestSheet extends StatefulWidget {
  const RecordHarvestSheet({
    super.key,
    required this.db,
    required this.orgId,
    this.farm,
  });

  final LocalDb db;
  final String orgId;

  /// Null in a build with no server. The crops in the ground cannot be listed
  /// from one device, so the sheet says so rather than offering an empty pick.
  final FarmRepository? farm;

  @override
  State<RecordHarvestSheet> createState() => _RecordHarvestSheetState();
}

/// What is being gathered — a crop currently in the ground. Eggs used to be a
/// second case here; they are now kept as ordinary stock (Réception / Stock)
/// like anything else the farm stores, so this sheet is crops only.
class _Subject {
  const _Subject.crop(this.cycle);

  final CropCycle cycle;

  String get label => cycle.crop;

  /// What the big number is counting, written under it.
  String get unit => cycle.unit;

  /// The second line on the chip: which variety, which plot.
  String? get detail {
    final parts = [cycle.variety, cycle.plotName]
        .where((p) => p != null && p.isNotEmpty)
        .cast<String>();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Map<String, String> get grades => harvestGrades;
  String get defaultGrade => 'first';
}

class _RecordHarvestSheetState extends State<RecordHarvestSheet> {
  String _digits = '';
  String _grade = 'first';
  bool _saving = false;
  String? _error;

  /// Null until the subject is settled, which for most farms happens
  /// immediately: one thing to gather means nothing to ask.
  _Subject? _subject;

  List<CropCycle> _crops = const [];
  bool _loadingCrops = false;

  /// The keypad types digits; a crop's quantity may have a decimal part, so
  /// the digits are read as thousandths of the unit only when the subject
  /// allows it. Eggs stay integers, which is what they are.
  double get _quantity {
    final raw = int.tryParse(_digits) ?? 0;
    return raw.toDouble();
  }

  int get _count => int.tryParse(_digits) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadCrops();
  }

  /// Best-effort and never blocking: a database without 019 simply shows the
  /// "nothing in the ground" message rather than an error.
  Future<void> _loadCrops() async {
    final farm = widget.farm;
    if (farm == null || !farm.isConfigured) return;
    setState(() => _loadingCrops = true);
    try {
      final crops = await farm.cropCycles(widget.orgId);
      if (!mounted) return;
      setState(() {
        _crops = crops.where((c) => c.isOpen).toList();
        _loadingCrops = false;
        // A farm with no birds and one crop in the ground should not have to
        // choose anything either.
        if (_subject == null && _crops.length == 1) {
          _select(_Subject.crop(_crops.first));
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCrops = false);
    }
  }

  void _select(_Subject subject) {
    setState(() {
      _subject = subject;
      _grade = subject.defaultGrade;
    });
  }

  Future<void> _save() async {
    final subject = _subject;
    if (subject == null || _quantity <= 0 || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final farm = widget.farm;
      if (farm == null) throw StateError('Pas de serveur.');
      await farm.recordHarvest(
        orgId: widget.orgId,
        cropCycleId: subject.cycle.id,
        quantity: _quantity,
        unit: subject.cycle.unit,
        grade: _grade,
        clientUuid: const Uuid().v4(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Enregistrement impossible. La récolte d\'une culture demande '
            'le réseau.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subject = _subject;
    final accent = Colors.green.shade700;

    return _SheetFrame(
      icon: Icons.eco_outlined,
      title: 'Récolte',
      accent: accent,
      subtitle: "Production, pas recette : l'argent vient à la vente.",
      children: [
        ..._subjectPicker(theme, accent),
        if (subject != null) ...[
          Center(
            child: Text(
              _digits.isEmpty ? '0' : '$_count',
              style: theme.textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: _digits.isEmpty ? Colors.grey.shade400 : accent,
              ),
            ),
          ),
          Center(
            child: Text(subject.unit, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 16),

          // Bruised tomatoes are counted apart from first-grade for a reason:
          // they sell for less or not at all, and counting them with the rest
          // makes a yield look better than the income it produces.
          ChoiceChipRow(
            values: subject.grades,
            selected: _grade,
            onSelect: (v) => setState(() => _grade = v),
          ),
          const SizedBox(height: 16),

          AmountKeypad(
            onDigit: (d) => setState(() {
              if (_digits.length < 6) {
                _digits = (_digits + d).replaceFirst(RegExp(r'^0+'), '');
              }
            }),
            onBackspace: () => setState(() {
              if (_digits.isNotEmpty) {
                _digits = _digits.substring(0, _digits.length - 1);
              }
            }),
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!),
            ),
            const SizedBox(height: 16),
          ],

          _SaveButton(
            label: 'Enregistrer la récolte',
            accent: accent,
            enabled: _quantity > 0,
            saving: _saving,
            onPressed: _save,
          ),
        ],
      ],
    );
  }

  /// The question this sheet exists to ask. Hidden entirely when there is only
  /// one possible answer, because a farm with one flock and no fields should
  /// not have to confirm what it is doing every morning.
  List<Widget> _subjectPicker(ThemeData theme, Color accent) {
    final options = <_Subject>[
      for (final crop in _crops) _Subject.crop(crop),
    ];

    if (options.length < 2 && !_loadingCrops) {
      if (options.isEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              "Rien à récolter pour l'instant. Ouvrez une culture dans "
              '« Élevage et cultures » — cela demande le réseau.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ];
      }
      return const [];
    }

    return [
      Text('Que récoltez-vous ?', style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in options)
            ChoiceChip(
              selected: _isSelected(option),
              onSelected: (_) => _select(option),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(option.label),
                  if (option.detail != null)
                    Text(
                      option.detail!,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          if (_canAddCrop)
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Autre…'),
              onPressed: _saving ? null : _addCrop,
            ),
          if (_loadingCrops)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      const SizedBox(height: 20),
    ];
  }

  /// The list of things to gather is not a fixed menu, and it must not be: a
  /// farmer who starts picking okra in April cannot wait for a release to say
  /// so. "Autre…" opens a cycle from a name and selects it, so the thing being
  /// harvested is recorded in the same breath as the harvest.
  ///
  /// Needs the server, because a crop cycle is a row other people's phones
  /// have to see. Offered only when there is one.
  bool _isSelected(_Subject option) {
    final subject = _subject;
    if (subject == null) return false;
    return subject.cycle.id == option.cycle.id;
  }

  bool get _canAddCrop => widget.farm?.isConfigured ?? false;

  Future<void> _addCrop() async {
    final created = await showDialog<CropCycle>(
      context: context,
      builder: (_) => _NewCropDialog(farm: widget.farm!, orgId: widget.orgId),
    );
    if (created == null || !mounted) return;
    setState(() => _crops = [..._crops, created]);
    _select(_Subject.crop(created));
  }
}

/// Naming the thing being harvested, in as few words as it takes.
///
/// Deliberately smaller than the full crop sheet in "Élevage et cultures":
/// that one plans a cycle — planting date, expected yield, expected harvest.
/// This one is opened by somebody standing over a basket, and asks only what
/// is in it and what it is measured in. `open_crop_cycle()` finds or creates
/// the plot from its name, so nothing has to be defined first.
class _NewCropDialog extends StatefulWidget {
  const _NewCropDialog({required this.farm, required this.orgId});

  final FarmRepository farm;
  final String orgId;

  @override
  State<_NewCropDialog> createState() => _NewCropDialogState();
}

class _NewCropDialogState extends State<_NewCropDialog> {
  final _crop = TextEditingController();
  final _plot = TextEditingController();
  String _unit = 'kg';
  bool _saving = false;
  String? _error;

  static const _units = <String, String>{
    'kg': 'Kilogrammes',
    'sac': 'Sacs',
    'panier': 'Paniers',
    'litre': 'Litres',
    'pièce': 'Pièces',
  };

  @override
  void dispose() {
    _crop.dispose();
    _plot.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final crop = _crop.text.trim();
    if (crop.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.farm.openCropCycle(
        orgId: widget.orgId,
        crop: crop,
        plotName: _plot.text.trim(),
        unit: _unit,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        CropCycle(
          id: id,
          crop: crop,
          plotName: _plot.text.trim().isEmpty ? null : _plot.text.trim(),
          unit: _unit,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Impossible pour le moment. Cela demande le réseau.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Que récoltez-vous ?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _crop,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Culture',
                hintText: 'Tomate, gombo, maïs…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _plot,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Parcelle (facultatif)',
                hintText: 'Derrière la maison',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _unit,
              decoration: const InputDecoration(
                labelText: 'Compté en',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final entry in _units.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: _saving ? null : (v) => setState(() => _unit = v!),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Ajouter'),
        ),
      ],
    );
  }
}

/// Birds died, were weighed, vaccinated, or left alive.
///
/// Mortality is why this sheet is opened every day, and it is the number the
/// farm is actually run on: a rate that changes is the earliest warning there
/// is, days before the eggs drop and weeks before the money does.
class FlockEventSheet extends StatefulWidget {
  const FlockEventSheet({
    super.key,
    required this.db,
    required this.orgId,
    required this.flockId,
    required this.batchCode,
    this.alive,
    this.kind = 'mortality',
  });

  final LocalDb db;
  final String orgId;
  final String flockId;
  final String batchCode;

  /// As the server last reported it. Used only to warn, never to refuse —
  /// this device may be a fortnight behind, and 009 makes the real check.
  final int? alive;

  final String kind;

  @override
  State<FlockEventSheet> createState() => _FlockEventSheetState();
}

class _FlockEventSheetState extends State<FlockEventSheet> {
  final _noteController = TextEditingController();

  late String _kind = widget.kind;
  String _digits = '';
  bool _saving = false;

  double get _quantity => double.tryParse(_digits) ?? 0;

  /// Warn, do not block. The device's idea of how many birds are alive can be
  /// two weeks stale, and refusing a real death because a cached count
  /// disagrees would teach somebody the app is wrong about the farm.
  bool get _suspicious {
    final alive = widget.alive;
    if (alive == null) return false;
    return _kind == 'mortality' || _kind == 'sold' ? _quantity > alive : false;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_quantity <= 0 || _saving) return;
    setState(() => _saving = true);

    final note = _noteController.text.trim();

    await widget.db.recordFlockEvent(
      orgId: widget.orgId,
      flockId: widget.flockId,
      batchCode: widget.batchCode,
      kind: _kind,
      quantity: _quantity,
      note: note.isEmpty ? null : note,
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _kind == 'mortality'
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    final unit = switch (_kind) {
      'weight' => 'grammes',
      'vaccination' => 'doses',
      _ => 'oiseaux',
    };

    return _SheetFrame(
      icon: Icons.pets_outlined,
      title: widget.batchCode,
      accent: accent,
      subtitle: widget.alive == null
          ? null
          : '${widget.alive} oiseaux au dernier point',
      children: [
        ChoiceChipRow(
          values: flockEventLabels,
          selected: _kind,
          onSelect: (v) => setState(() => _kind = v),
          wrap: true,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _digits.isEmpty ? '0' : _digits,
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: _digits.isEmpty ? Colors.grey.shade400 : accent,
            ),
          ),
        ),
        Center(child: Text(unit, style: theme.textTheme.bodyMedium)),
        const SizedBox(height: 8),
        if (_suspicious)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Plus que le dernier effectif connu '
                    '(${widget.alive}). Vérifiez le chiffre — le serveur '
                    'refusera si la bande est plus petite.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        AmountKeypad(
          onDigit: (d) => setState(() {
            if (_digits.length < 6) {
              _digits = (_digits + d).replaceFirst(RegExp(r'^0+'), '');
            }
          }),
          onBackspace: () => setState(() {
            if (_digits.isNotEmpty) {
              _digits = _digits.substring(0, _digits.length - 1);
            }
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          enabled: !_saving,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Note',
            hintText: 'Chaleur, Newcastle, poulailler 2…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        _SaveButton(
          label: 'Enregistrer',
          accent: accent,
          enabled: _quantity > 0,
          saving: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------
// The shell all four share
// ----------------------------------------------------------------

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.icon,
    required this.title,
    required this.accent,
    required this.children,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Fonctionne sans connexion',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.label,
    required this.accent,
    required this.enabled,
    required this.saving,
    required this.onPressed,
  });

  final String label;
  final Color accent;
  final bool enabled;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
        ),
        onPressed: enabled && !saving ? onPressed : null,
        child: saving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
