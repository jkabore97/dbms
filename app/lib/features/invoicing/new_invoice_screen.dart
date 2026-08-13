import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../../core/invoicing/models.dart';
import '../../core/phone/country_codes.dart';
import '../accounting/report_shell.dart';
import '../common/phone_field.dart';
import '../../core/errors.dart';

/// Composing one.
///
/// The shape follows what somebody actually has in front of them when they
/// raise an invoice: who it is for, then what they are being charged for, then
/// when it is due. Not a form with twenty fields — everything except the
/// customer's name and one priced line is optional, because an invoice that
/// cannot be raised until an address is known is an invoice that gets written
/// on paper instead.
///
/// Needs signal, and says so before anything is typed rather than after. See
/// [InvoicingRepository] for why invoicing is the one thing in this app that
/// is not offline-first.
class NewInvoiceScreen extends StatefulWidget {
  const NewInvoiceScreen({
    super.key,
    required this.org,
    required this.invoicing,
  });

  final OrgSummary org;
  final InvoicingRepository invoicing;

  @override
  State<NewInvoiceScreen> createState() => _NewInvoiceScreenState();
}

class _NewInvoiceScreenState extends State<NewInvoiceScreen> {
  final _customer = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _memo = TextEditingController();

  CountryCode _country = defaultCountry;

  /// Starts with one empty line, because an invoice with none is not a state
  /// anybody wants to be in and "add the first line" is a wasted tap.
  final List<_LineDraft> _lines = [_LineDraft()];

  int? _dueDays = 30;
  bool _saving = false;
  String? _error;

  late final _money = moneyFormat(widget.org.currency);

  @override
  void dispose() {
    _customer.dispose();
    _address.dispose();
    _phone.dispose();
    _memo.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  List<InvoiceLine> get _complete =>
      _lines.map((l) => l.toLine()).where((l) => l.isComplete).toList();

  double get _total =>
      _complete.fold<double>(0, (sum, line) => sum + line.amount);

  String? get _problem {
    if (_customer.text.trim().isEmpty) return 'Indiquez le client.';
    if (_complete.isEmpty) {
      return 'Ajoutez au moins une ligne avec une quantité et un prix.';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _problem;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final id = await widget.invoicing.create(
        orgId: widget.org.id,
        customerName: _customer.text.trim(),
        customerAddress: _address.text.trim(),
        customerPhone:
            _phone.text.trim().isEmpty ? null : _country.toE164(_phone.text),
        lines: _complete,
        dueDays: _dueDays,
        memo: _memo.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, id);
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

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle facture')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Text('Client', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _customer,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Nom du client',
              hintText: 'Hôtel Indépendance',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Adresse (facultatif)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          PhoneField(
            controller: _phone,
            country: _country,
            onCountry: (c) => setState(() => _country = c),
            labelText: 'Téléphone (facultatif)',
            hintText: '70 12 34 56',
            enabled: !_saving,
          ),

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('Lignes', style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() => _lines.add(_LineDraft())),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < _lines.length; i++)
            _LineEditor(
              key: ObjectKey(_lines[i]),
              draft: _lines[i],
              money: _money,
              onChanged: () => setState(() {}),
              // The last remaining line is not removable: an invoice needs
              // one, and an empty list is a dead end with no way out.
              onRemove: _lines.length == 1 || _saving
                  ? null
                  : () => setState(() {
                        _lines.removeAt(i).dispose();
                      }),
            ),

          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('Total', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    _money.format(_total),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          Text('Échéance', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          // Terms are agreed in days — "payable à 30 jours" — and the date is
          // what gets stored. Asking for the date would be asking somebody to
          // do the arithmetic the machine is for.
          Wrap(
            spacing: 8,
            children: [
              for (final days in [null, 7, 15, 30, 60])
                ChoiceChip(
                  label: Text(days == null ? 'À réception' : '$days jours'),
                  selected: _dueDays == days,
                  onSelected:
                      _saving ? null : (_) => setState(() => _dueDays = days),
                ),
            ],
          ),

          const SizedBox(height: 20),
          TextField(
            controller: _memo,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Note interne (facultatif)',
              helperText: "N'apparaît pas sur la facture.",
              border: OutlineInputBorder(),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving || _problem != null ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.receipt_long),
        label: const Text('Créer la facture'),
      ),
    );
  }
}

/// One line's controllers, kept together so removing a line disposes exactly
/// the three that belonged to it.
class _LineDraft {
  final description = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final price = TextEditingController();

  double get _qty =>
      double.tryParse(quantity.text.trim().replaceAll(',', '.')) ?? 0;
  double get _unit =>
      double.tryParse(price.text.trim().replaceAll(',', '.')) ?? 0;

  double get amount => _qty * _unit;

  InvoiceLine toLine() => InvoiceLine(
        description: description.text,
        quantity: _qty,
        unitPrice: _unit,
      );

  void dispose() {
    description.dispose();
    quantity.dispose();
    price.dispose();
  }
}

class _LineEditor extends StatelessWidget {
  const _LineEditor({
    super.key,
    required this.draft,
    required this.money,
    required this.onChanged,
    this.onRemove,
  });

  final _LineDraft draft;
  final NumberFormat money;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.description,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Désignation',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close),
                    tooltip: 'Retirer la ligne',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: draft.quantity,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Qté',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: draft.price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Prix unitaire',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    draft.amount > 0 ? money.format(draft.amount) : '—',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
