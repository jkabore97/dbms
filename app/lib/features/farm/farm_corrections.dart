import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/farm/farm_repository.dart';

/// Correcting a farm entry after it was recorded — the app's version of
/// crossing a wrong number out in a notebook. Backed by the 033 update_
/// functions, which carry no ledger and so correct in place.
///
/// One sheet for all three kinds (flock events, herd events, harvests): each
/// is a "how many, of what, when" row, so the difference is only which labels
/// the kind offers and which update call the save makes. Reading is a plain
/// select (the tables are readable by anyone entitled to the home feed);
/// writing goes through the guarded function, so an observer's edit is refused
/// at the server even if this sheet were reached.
enum FarmEntryKind { flock, herd, harvest }

const _flockKinds = {
  'mortality': 'Mortalité',
  'weight': 'Pesée',
  'vaccination': 'Vaccination',
  'sold': 'Vendus',
};
const _herdKinds = {
  'mortality': 'Mortalité',
  'birth': 'Naissance',
  'weight': 'Pesée',
  'vaccination': 'Vaccination',
  'treatment': 'Traitement',
  'sold': 'Vendus',
};
const _harvestGrades = {
  'first': 'Premier choix',
  'second': 'Second choix',
  'damaged': 'Abîmé',
};

Future<void> showFarmCorrections(
  BuildContext context, {
  required String title,
  required FarmRepository farm,
  required FarmEntryKind kind,
  required String subjectId,
  required bool canWrite,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CorrectionsSheet(
      title: title,
      farm: farm,
      kind: kind,
      subjectId: subjectId,
      canWrite: canWrite,
    ),
  );
}

class _CorrectionsSheet extends StatefulWidget {
  const _CorrectionsSheet({
    required this.title,
    required this.farm,
    required this.kind,
    required this.subjectId,
    required this.canWrite,
  });

  final String title;
  final FarmRepository farm;
  final FarmEntryKind kind;
  final String subjectId;
  final bool canWrite;

  @override
  State<_CorrectionsSheet> createState() => _CorrectionsSheetState();
}

class _CorrectionsSheetState extends State<_CorrectionsSheet> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = switch (widget.kind) {
        FarmEntryKind.flock => await widget.farm.flockEvents(widget.subjectId),
        FarmEntryKind.herd => await widget.farm.herdEvents(widget.subjectId),
        FarmEntryKind.harvest =>
          await widget.farm.harvestsOf(widget.subjectId),
      };
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  String _dateField() => switch (widget.kind) {
        FarmEntryKind.flock => 'occurred_at',
        FarmEntryKind.herd => 'occurred_on',
        FarmEntryKind.harvest => 'harvested_on',
      };

  String _label(Map<String, dynamic> row) {
    switch (widget.kind) {
      case FarmEntryKind.flock:
        return _flockKinds[row['kind']] ?? row['kind'] as String;
      case FarmEntryKind.herd:
        return _herdKinds[row['kind']] ?? row['kind'] as String;
      case FarmEntryKind.harvest:
        return _harvestGrades[row['grade']] ?? row['grade'] as String;
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditEntrySheet(
        farm: widget.farm,
        kind: widget.kind,
        row: row,
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          Text(
            widget.canWrite
                ? 'Appui long sur une ligne pour la corriger.'
                : 'Lecture seule.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            )
          else if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('Aucune entrée pour l’instant.',
                  style: theme.textTheme.bodyMedium),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _rows.length,
                itemBuilder: (context, i) {
                  final row = _rows[i];
                  final qty = (row['quantity'] as num).toDouble();
                  final unit = row['unit'] as String?;
                  final date = DateTime.parse('${row[_dateField()]}').toLocal();
                  final note = row['note'] as String?;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${_label(row)} · '
                        '${qty.toStringAsFixed(0)}${unit == null ? '' : ' $unit'}'),
                    subtitle: Text([
                      DateFormat('d MMM y', 'fr_FR').format(date),
                      if (note != null && note.isNotEmpty) note,
                    ].join(' · ')),
                    trailing: widget.canWrite
                        ? const Icon(Icons.edit_outlined, size: 18)
                        : null,
                    onLongPress: widget.canWrite ? () => _edit(row) : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _EditEntrySheet extends StatefulWidget {
  const _EditEntrySheet({
    required this.farm,
    required this.kind,
    required this.row,
  });

  final FarmRepository farm;
  final FarmEntryKind kind;
  final Map<String, dynamic> row;

  @override
  State<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<_EditEntrySheet> {
  late final TextEditingController _quantity = TextEditingController(
    text: (widget.row['quantity'] as num).toDouble().toStringAsFixed(0),
  );
  late final TextEditingController _note =
      TextEditingController(text: (widget.row['note'] as String?) ?? '');
  late String _kind = widget.kind == FarmEntryKind.harvest
      ? widget.row['grade'] as String
      : widget.row['kind'] as String;
  bool _saving = false;
  String? _error;

  Map<String, String> get _options => switch (widget.kind) {
        FarmEntryKind.flock => _flockKinds,
        FarmEntryKind.herd => _herdKinds,
        FarmEntryKind.harvest => _harvestGrades,
      };

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = double.tryParse(_quantity.text.trim().replaceAll(',', '.'));
    if (qty == null) {
      setState(() => _error = 'Entrez un nombre.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = widget.row['id'] as String;
      final note = _note.text.trim();
      switch (widget.kind) {
        case FarmEntryKind.flock:
          await widget.farm
              .updateFlockEvent(id, quantity: qty, kind: _kind, note: note);
        case FarmEntryKind.herd:
          await widget.farm
              .updateHerdEvent(id, quantity: qty, kind: _kind, note: note);
        case FarmEntryKind.harvest:
          await widget.farm
              .updateHarvest(id, quantity: qty, grade: _kind, note: note);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(error);
      });
    }
  }

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Corriger l’entrée', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Text(widget.kind == FarmEntryKind.harvest ? 'Qualité' : 'Type',
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in _options.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _kind == entry.key,
                  onSelected:
                      _saving ? null : (_) => setState(() => _kind = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Quantité',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Note (optionnel)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enregistrer la correction'),
          ),
        ],
      ),
    );
  }
}
