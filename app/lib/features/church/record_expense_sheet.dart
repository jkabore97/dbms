import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/local_db.dart';
import 'entry_controls.dart';

/// Money going out.
///
/// The mirror of RecordContributionSheet, deliberately: the same keypad in the
/// same place, the same one required field, the same offline promise. Someone
/// who has learned to record an offering already knows how to record a bill.
///
/// What is not mirrored is the colour. Everything on this sheet that can carry
/// it is orange, matching the outgoing rows on the home screen and the button
/// that opens it, because the one mistake this flow must not allow is a person
/// recording an expense while believing they are recording a gift.
class RecordExpenseSheet extends StatefulWidget {
  const RecordExpenseSheet({
    super.key,
    required this.db,
    required this.orgId,
  });

  final LocalDb db;
  final String orgId;

  @override
  State<RecordExpenseSheet> createState() => _RecordExpenseSheetState();
}

/// The seeded chart of accounts, codes 5000–5060 (`seed_church_accounts()` in
/// 002_church_profile.sql). A picker rather than a text field: free text would
/// give seven spellings of "Loyer" within a month and a set of books nobody
/// can total by category.
///
/// The keys are what the server posts to `record_expense(p_expense_code)`; the
/// values are what the user reads, here and afterwards in the day's list.
const churchExpenseAccounts = <String, String>{
  '5000': 'Eau et électricité',
  '5010': 'Loyer',
  '5020': 'Salaires',
  '5030': 'Entretien',
  '5040': 'Œuvres sociales',
  '5050': 'Fournitures',
  '5060': 'Événements',
};

class _RecordExpenseSheetState extends State<RecordExpenseSheet> {
  final _currency = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: 'FCFA',
    decimalDigits: 0,
  );

  String _digits = '';

  /// Defaults to Fournitures for the same reason the contribution sheet
  /// defaults to Offrande: the amount is the only thing that must be typed,
  /// and the most general category is the least wrong to land on. It is one
  /// tap to change and every option is on screen.
  String _code = '5050';

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

    // Writes the outbox row and the local entry in one transaction and returns
    // immediately — no spinner waiting on a network that may not be there.
    await widget.db.recordExpense(
      orgId: widget.orgId,
      amount: _amount,
      expenseCode: _code,
      expenseName: churchExpenseAccounts[_code]!,
      method: _method,
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Colors.orange.shade800;

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

            // Says what this sheet is before any number is typed. The
            // contribution sheet needs no such banner: it is the default act,
            // and this is the one that has to announce itself.
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_upward, size: 20, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    'Dépense',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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

            // Wrapped, not scrolled: seven categories past the right edge is
            // how everything ends up filed under whichever one was visible.
            ChoiceChipRow(
              values: churchExpenseAccounts,
              selected: _code,
              onSelect: (v) => setState(() => _code = v),
              wrap: true,
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
            const SizedBox(height: 16),

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
                    : const Text(
                        'Enregistrer la dépense',
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
