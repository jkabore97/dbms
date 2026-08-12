import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/local_db.dart';
import 'entry_controls.dart';

/// The recording flow.
///
/// One required field: the amount. Everything else has a sensible default
/// (offering, cash) so the fastest possible path is: tap, type number, save.
/// Each additional required field is a person who gives up and reaches for
/// the paper notebook instead.
class RecordContributionSheet extends StatefulWidget {
  const RecordContributionSheet({
    super.key,
    required this.db,
    required this.orgId,
  });

  final LocalDb db;
  final String orgId;

  @override
  State<RecordContributionSheet> createState() =>
      _RecordContributionSheetState();
}

class _RecordContributionSheetState extends State<RecordContributionSheet> {
  final _currency = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: 'FCFA',
    decimalDigits: 0,
  );

  String _digits = '';
  String _kind = 'offering';
  String _method = 'cash';
  bool _saving = false;

  double get _amount => double.tryParse(_digits) ?? 0;

  void _tapDigit(String d) {
    if (_digits.length >= 12) return;
    setState(() => _digits = (_digits + d).replaceFirst(RegExp(r'^0+'), ''));
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Future<void> _save() async {
    if (_amount <= 0 || _saving) return;
    setState(() => _saving = true);

    await widget.db.recordContribution(
      orgId: widget.orgId,
      amount: _amount,
      kind: _kind,
      method: _method,
    );

    if (!mounted) return;
    Navigator.pop(context, true);
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
          const SizedBox(height: 20),

          // The amount, as large as the screen allows.
          Center(
            child: Text(
              _digits.isEmpty ? _currency.format(0) : _currency.format(_amount),
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: _digits.isEmpty ? Colors.grey.shade400 : null,
              ),
            ),
          ),
          const SizedBox(height: 20),

          ChoiceChipRow(
            values: const {
              'offering': 'Offrande',
              'tithe': 'Dîme',
              'special': 'Collecte',
              'donation': 'Don',
            },
            selected: _kind,
            onSelect: (v) => setState(() => _kind = v),
          ),
          const SizedBox(height: 8),
          ChoiceChipRow(
            values: const {
              'cash': 'Espèces',
              'mobile_money': 'Mobile Money',
              'bank': 'Banque',
            },
            selected: _method,
            onSelect: (v) => setState(() => _method = v),
          ),
          const SizedBox(height: 16),

          AmountKeypad(onDigit: _tapDigit, onBackspace: _backspace),
          const SizedBox(height: 16),

          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _amount > 0 && !_saving ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Enregistrer',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
    );
  }
}
