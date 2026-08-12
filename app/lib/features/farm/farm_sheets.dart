import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/db/local_db.dart';
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
    this.currencySymbol = 'FCFA',
  });

  final LocalDb db;
  final String orgId;
  final String currencySymbol;

  @override
  State<ReceiveStockSheet> createState() => _ReceiveStockSheetState();
}

class _ReceiveStockSheetState extends State<ReceiveStockSheet> {
  late final NumberFormat _currency = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: widget.currencySymbol,
    decimalDigits: 0,
  );

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
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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

/// The morning collection.
class RecordEggsSheet extends StatefulWidget {
  const RecordEggsSheet({
    super.key,
    required this.db,
    required this.orgId,
    this.flocks = const [],
  });

  final LocalDb db;
  final String orgId;

  /// `{flockId: batchCode}` from the device's cache. Empty is fine — eggs can
  /// be recorded for the farm as a whole, which is what a single-house
  /// operation will always do.
  final List<Map<String, Object?>> flocks;

  @override
  State<RecordEggsSheet> createState() => _RecordEggsSheetState();
}

class _RecordEggsSheetState extends State<RecordEggsSheet> {
  String _digits = '';
  String _grade = 'normal';
  String? _flockId;
  bool _saving = false;

  int get _count => int.tryParse(_digits) ?? 0;

  @override
  void initState() {
    super.initState();
    if (widget.flocks.length == 1) {
      _flockId = widget.flocks.first['flock_id'] as String;
    }
  }

  Future<void> _save() async {
    if (_count <= 0 || _saving) return;
    setState(() => _saving = true);

    final flock = widget.flocks.cast<Map<String, Object?>?>().firstWhere(
          (f) => f?['flock_id'] == _flockId,
          orElse: () => null,
        );

    await widget.db.recordEggs(
      orgId: widget.orgId,
      eggCount: _count,
      flockId: _flockId,
      batchCode: flock?['batch_code'] as String?,
      grade: _grade,
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Colors.amber.shade800;

    return _SheetFrame(
      icon: Icons.egg_outlined,
      title: 'Ramassage',
      accent: accent,
      subtitle: "Production, pas recette : l'argent vient à la vente.",
      children: [
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
          child: Text('œufs', style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: 16),

        if (widget.flocks.length > 1) ...[
          Text('Bande', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final flock in widget.flocks)
                ChoiceChip(
                  label: Text(flock['batch_code'] as String),
                  selected: _flockId == flock['flock_id'],
                  onSelected: (_) =>
                      setState(() => _flockId = flock['flock_id'] as String),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Cracked eggs are counted apart because they sell for less or not at
        // all. A farm that counts them with the rest has a lay rate that looks
        // better than its income.
        ChoiceChipRow(
          values: eggGrades,
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

        _SaveButton(
          label: 'Enregistrer le ramassage',
          accent: accent,
          enabled: _count > 0,
          saving: _saving,
          onPressed: _save,
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
