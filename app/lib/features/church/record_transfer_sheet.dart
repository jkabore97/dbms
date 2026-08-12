import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/local_db.dart';
import 'entry_controls.dart';

/// Money moved between two places the business already keeps it: cash banked
/// at the end of the week, a withdrawal for Monday's purchases, a mobile money
/// float topped up.
///
/// This exists because until now the app had two buttons and neither of them
/// was right for it. Recording a deposit as an expense from cash and a receipt
/// into the bank inflates both sides of the day by the same amount, and the
/// books end up saying the business earned money by moving its own money — a
/// church that banks its offering every Sunday would show double the income it
/// received. `record_transfer()` in 007 writes one entry that touches two
/// asset accounts and no income or expense account at all, and the day's
/// totals here skip it for the same reason.
///
/// Deliberately plainer than the recording sheet: no categories, because both
/// sides are accounts rather than categories, and no characteristics, because
/// there is nothing to say about a transfer that the two account names and the
/// amount do not already say.
class RecordTransferSheet extends StatefulWidget {
  const RecordTransferSheet({
    super.key,
    required this.db,
    required this.orgId,
    this.currencySymbol = 'FCFA',
  });

  final LocalDb db;
  final String orgId;
  final String currencySymbol;

  @override
  State<RecordTransferSheet> createState() => _RecordTransferSheetState();
}

/// The three places money sits, keyed by what `record_transfer()` accepts.
/// These three map to the codes 002 seeded, so a transfer posts to the
/// accounts a church's balances are already on rather than opening new ones.
const _places = <String, String>{
  'cash': 'Espèces',
  'mobile_money': 'Mobile Money',
  'bank': 'Banque',
};

class _RecordTransferSheetState extends State<RecordTransferSheet> {
  late final NumberFormat _currency = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: widget.currencySymbol,
    decimalDigits: 0,
  );

  final _labelController = TextEditingController();

  String _digits = '';
  String _from = 'cash';
  String _to = 'bank';
  bool _saving = false;

  double get _amount => double.tryParse(_digits) ?? 0;

  /// Both ends the same is a transfer that moves nothing, and the server
  /// refuses it. Caught here so the button is dead rather than the save.
  bool get _valid => _amount > 0 && _from != _to;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _tapDigit(String d) {
    if (_digits.length >= 12) return;
    setState(() => _digits = (_digits + d).replaceFirst(RegExp(r'^0+'), ''));
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  /// Picking a destination that is already the source swaps them rather than
  /// refusing. Somebody tapping "Espèces" on the second row has told you which
  /// way round they want it, and making them fix the first row themselves is
  /// pedantry.
  void _setFrom(String value) {
    setState(() {
      if (value == _to) _to = _from;
      _from = value;
    });
  }

  void _setTo(String value) {
    setState(() {
      if (value == _from) _from = _to;
      _to = value;
    });
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);

    await widget.db.recordTransfer(
      orgId: widget.orgId,
      amount: _amount,
      fromMethod: _from,
      toMethod: _to,
      label: _labelController.text,
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;

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
                  Icon(Icons.swap_horiz, size: 20, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    'Transfert',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                "Ni une recette ni une dépense : l'argent change de place.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),

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

            Text('De', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ChoiceChipRow(values: _places, selected: _from, onSelect: _setFrom),
            const SizedBox(height: 16),

            Text('Vers', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ChoiceChipRow(values: _places, selected: _to, onSelect: _setTo),
            const SizedBox(height: 16),

            TextField(
              controller: _labelController,
              enabled: !_saving,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: "Nom de l'entrée",
                hintText: 'Dépôt de la collecte du dimanche',
                helperText: _labelController.text.trim().isEmpty
                    ? 'Sans nom, ce sera « Transfert »'
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            AmountKeypad(onDigit: _tapDigit, onBackspace: _backspace),
            const SizedBox(height: 16),

            SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: theme.colorScheme.onTertiary,
                ),
                onPressed: _valid && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Enregistrer le transfert',
                        style: TextStyle(
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
