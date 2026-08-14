import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/local_db.dart';
import '../../core/reports/models.dart' show accountLabel;
import 'entry_controls.dart';

/// Recording money, in either direction, by the name the person gives it.
///
/// This replaces the two mirrored sheets it grew out of. Those two files were
/// held in step by a comment saying they had to feel like the same machine —
/// same keypad in the same place, same chips behaving the same way — which was
/// true and was going to stay true for exactly as long as somebody remembered
/// to edit both. It is one widget now, and the differences that are real are
/// arguments: the direction, the colour, the words on the button.
///
/// The order of the fields is the whole design and it is deliberate:
///
///   1. THE AMOUNT, as large as the screen allows. Still the only required
///      field. The fast path is unchanged and is still tap, type number, save.
///   2. THE NAME, pre-filled from the category and editable. This is what the
///      entry IS, in the words of whoever recorded it, and it is what every
///      list and report shows afterwards. It sits above the fold because it is
///      the thing this sheet gained and it must not read as an afterthought.
///   3. THE CATEGORY, as chips, with "Autre…" at the end. The chips are the
///      accounts the books already hold, so choosing one posts the exact name
///      it is filed under and cannot open a duplicate.
///   4. THE DETAILS, folded away. Everything nobody predicted lives here, and
///      it is closed by default because the person recording a Sunday offering
///      while forty people wait should never see it.
class RecordEntrySheet extends StatefulWidget {
  const RecordEntrySheet({
    super.key,
    required this.db,
    required this.orgId,
    required this.direction,
    this.currencySymbol = 'FCFA',
  });

  final LocalDb db;
  final String orgId;

  /// 'in' | 'out'
  final String direction;

  final String currencySymbol;

  bool get isIncome => direction == 'in';

  @override
  State<RecordEntrySheet> createState() => _RecordEntrySheetState();
}

class _RecordEntrySheetState extends State<RecordEntrySheet> {
  late final NumberFormat _currency = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: widget.currencySymbol,
    decimalDigits: 0,
  );

  final _nameController = TextEditingController();
  final _noteController = TextEditingController();

  String _digits = '';
  String _method = 'cash';

  /// The account name as the books hold it, or null before the categories have
  /// loaded. Never shown directly — [accountLabel] translates the seeded
  /// English chart on the way to the screen.
  String? _category;

  List<String> _categories = const [];
  List<Characteristic> _characteristics = const [];

  /// True while the person has not touched the name field. Until they do, it
  /// tracks whichever category is selected, so choosing "Loyer" fills in
  /// "Loyer" and the fast path needs no typing at all. The moment they edit
  /// it, it is theirs and nothing overwrites it.
  bool _nameIsAuto = true;

  bool _detailsOpen = false;
  bool _loading = true;
  bool _saving = false;

  double get _amount => double.tryParse(_digits) ?? 0;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameEdited);
    _loadCategories();
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameEdited);
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onNameEdited() {
    // Only a change that disagrees with the auto-fill counts as the person
    // taking the field over; the auto-fill itself goes through the same
    // listener.
    final expected = _category == null ? '' : accountLabel(_category!);
    if (_nameIsAuto && _nameController.text != expected) {
      setState(() => _nameIsAuto = false);
    }
  }

  Future<void> _loadCategories() async {
    final names = await widget.db.categoriesFor(widget.orgId, widget.direction);
    if (!mounted) return;
    setState(() {
      _categories = names;
      _loading = false;
      if (names.isNotEmpty) _select(names.first);
    });
  }

  void _select(String name) {
    _category = name;
    if (_nameIsAuto) {
      // Assigning to the controller fires the listener, which is why
      // _onNameEdited compares against what the auto-fill would be.
      _nameController.text = accountLabel(name);
    }
  }

  Future<void> _addCategory() async {
    final name = await promptForName(
      context,
      title: widget.isIncome ? 'Nouvelle recette' : 'Nouvelle dépense',
      label: 'Nom de la catégorie',
      hint: widget.isIncome ? 'Vente de terrain' : 'Réparation du toit',
    );
    if (name == null || !mounted) return;

    setState(() {
      // Case-insensitively already there: select it rather than offering the
      // same category twice under two spellings.
      final existing = _categories.firstWhere(
        (c) => c.toLowerCase() == name.toLowerCase(),
        orElse: () => '',
      );
      if (existing.isEmpty) {
        _categories = [..._categories, name];
        _select(name);
      } else {
        _select(existing);
      }
    });
  }

  void _tapDigit(String d) {
    if (_digits.length >= 12) return;
    setState(() => _digits = (_digits + d).replaceFirst(RegExp(r'^0+'), ''));
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  /// The name to save. Falls back to the category, then to a plain word, so an
  /// entry can never end up nameless — the server refuses one that is.
  String get _label {
    final typed = _nameController.text.trim();
    if (typed.isNotEmpty) return typed;
    final category = _category;
    if (category != null) return accountLabel(category);
    return widget.isIncome ? 'Recette' : 'Dépense';
  }

  Future<void> _save() async {
    if (_amount <= 0 || _saving) return;
    setState(() => _saving = true);

    // Half-typed rows are dropped rather than saved as {"": "Kaboré"}. A row
    // with a name and no value is kept: "Facture" on its own says something.
    final details = <String, String>{
      for (final c in _characteristics)
        if (c.name.trim().isNotEmpty) c.name.trim(): c.value.trim(),
    };

    final note = _noteController.text.trim();

    // Writes the outbox row and the local entry in one transaction and returns
    // immediately — no spinner waiting on a network that may not be there.
    await widget.db.recordEntry(
      orgId: widget.orgId,
      amount: _amount,
      direction: widget.direction,
      label: _label,
      category: _category,
      method: _method,
      memo: note.isEmpty ? null : note,
      details: details,
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Orange for money out, everywhere it can be carried: the button that
    // opened this sheet, the arrows on the rows it produces, the amount, the
    // save button. The one mistake this flow must not allow is a person
    // recording an expense while believing they are recording a gift.
    final accent =
        widget.isIncome ? theme.colorScheme.primary : Colors.orange.shade800;

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
                  Icon(
                    widget.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 20,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isIncome ? 'Recette' : 'Dépense',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 1. The amount, as large as the screen allows.
            Center(
              child: Text(
                _digits.isEmpty
                    ? _currency.format(0)
                    : _currency.format(_amount),
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _digits.isEmpty ? Colors.grey.shade400 : accent,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. The name.
            TextField(
              controller: _nameController,
              enabled: !_saving,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: "Nom de l'entrée",
                hintText: widget.isIncome
                    ? 'Offrande du dimanche'
                    : 'Réparation du toit',
                border: const OutlineInputBorder(),
                suffixIcon: _nameController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _nameController.clear();
                          _nameIsAuto = false;
                        }),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // 3. The category.
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else
              CategoryChips(
                categories: _categories,
                selected: _category,
                labelFor: accountLabel,
                onSelect: (name) => setState(() => _select(name)),
                onAddNew: _addCategory,
              ),
            const SizedBox(height: 12),

            ChoiceChipRow(
              values: const {
                'cash': 'Espèces',
                'mobile_money': 'Mobile Money',
                'bank': 'Banque',
              },
              selected: _method,
              onSelect: (v) => setState(() => _method = v),
            ),
            const SizedBox(height: 8),

            // 4. Everything nobody predicted, folded away.
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                initiallyExpanded: _detailsOpen,
                onExpansionChanged: (open) =>
                    setState(() => _detailsOpen = open),
                title: Text(
                  'Détails',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                children: [
                  TextField(
                    controller: _noteController,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      hintText: 'Ce qu\'il faut se rappeler de cette entrée',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CharacteristicsEditor(
                    values: _characteristics,
                    enabled: !_saving,
                    onChanged: (v) => setState(() => _characteristics = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            AmountKeypad(onDigit: _tapDigit, onBackspace: _backspace),
            const SizedBox(height: 16),

            SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _amount > 0 && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.isIncome
                            ? 'Enregistrer la recette'
                            : 'Enregistrer la dépense',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
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
