import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../accounting/report_shell.dart';

/// Who has not paid.
///
/// A church is paid when it is paid. A farm delivers thirty trays to a hotel
/// and gets paid in three weeks, and the money is real income the day it is
/// invoiced — which is why the ledger needs a receivable and why this screen
/// is not the same thing as the cash balance.
///
/// Server-only, deliberately. An invoice number has to be unique within the
/// business, an invoice creates a debt, and a payment settles one; none of the
/// three is something a disconnected device should decide on its own. This is
/// the one part of the farm module that is not offline-first, and it is the
/// part Ignace does sitting down rather than standing in a poultry house.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key, required this.org, this.farm});

  final OrgSummary org;
  final FarmRepository? farm;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<OutstandingInvoice> _invoices = const [];
  bool _loading = true;
  Object? _error;

  bool get _canWrite => !widget.org.isObserverOnly;

  late final NumberFormat _money = moneyFormat(widget.org.currency);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final farm = widget.farm;
    if (farm == null || !farm.isConfigured) {
      setState(() {
        _loading = false;
        _error = StateError(
          "Cette version de l'application a été compilée sans serveur.",
        );
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final invoices = await farm.outstandingInvoices(widget.org.id);
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final draft = await showModalBottomSheet<_InvoiceDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewInvoiceSheet(),
    );
    if (draft == null) return;

    try {
      await widget.farm!.createInvoice(
        orgId: widget.org.id,
        customerName: draft.customer,
        customerPhone: draft.phone,
        dueOn: draft.dueOn,
        lines: draft.lines,
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("La facture n'a pas pu être créée. Vérifiez le réseau."),
        ),
      );
    }
  }

  Future<void> _pay(OutstandingInvoice invoice) async {
    final result = await showDialog<({double amount, String method})>(
      context: context,
      builder: (_) => _PaymentDialog(invoice: invoice, money: _money),
    );
    if (result == null || result.amount <= 0) return;

    try {
      await widget.farm!.recordInvoicePayment(
        invoiceId: invoice.id,
        amount: result.amount,
        method: result.method,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().contains('too much')
                ? 'Ce montant dépasse ce qui reste dû sur cette facture.'
                : "Le règlement n'a pas pu être enregistré.",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var owed = 0.0;
    var overdue = 0.0;
    for (final invoice in _invoices) {
      owed += invoice.outstanding;
      if (invoice.isOverdue) overdue += invoice.outstanding;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Factures')),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Facture'),
            )
          : null,
      body: ReportBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        isEmpty: _invoices.isEmpty,
        emptyMessage: widget.org.visibility == 'summary'
            ? 'Votre accès porte sur les totaux. Le détail des factures ne '
                'vous est pas communiqué.'
            : 'Aucune facture impayée. Tout est réglé.',
        child: ListView(
          children: [
            Card(
              elevation: 0,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              color: overdue > 0
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Total dû',
                        amount: owed,
                        money: _money,
                        emphasis: true,
                      ),
                    ),
                    if (overdue > 0)
                      Expanded(
                        child: StatTile(
                          label: 'En retard',
                          amount: overdue,
                          money: _money,
                          tint: theme.colorScheme.error,
                          emphasis: true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final invoice in _invoices)
              _InvoiceTile(
                invoice: invoice,
                money: _money,
                canWrite: _canWrite,
                onPay: () => _pay(invoice),
              ),
            const SizedBox(height: 96),
          ],
        ),
      ),
    );
  }
}

/// Recording what a customer paid. Owns its controller for the same reason
/// every other dialog in this app now does: `showDialog`'s future completes
/// while the route is still animating out and still building the field.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.invoice, required this.money});

  final OutstandingInvoice invoice;
  final NumberFormat money;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _controller = TextEditingController(
    // Pre-filled with the whole outstanding amount: paying in full is the
    // common case and should need no typing.
    text: widget.invoice.outstanding.round().toString(),
  );

  String _method = 'cash';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;

    return AlertDialog(
      title: Text('Règlement ${invoice.number}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${invoice.customerName} doit '
            '${widget.money.format(invoice.outstanding)}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Montant reçu',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          // A part payment is the normal case, not the exception — which is
          // why payments are rows in 009 and not a paid/unpaid flag.
          Wrap(
            spacing: 8,
            children: [
              for (final entry in const {
                'cash': 'Espèces',
                'mobile_money': 'Mobile Money',
                'bank': 'Banque',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _method == entry.key,
                  onSelected: (_) => setState(() => _method = entry.key),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final amount =
                double.tryParse(_controller.text.trim().replaceAll(',', '.'));
            if (amount == null) return;
            Navigator.pop(context, (amount: amount, method: _method));
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({
    required this.invoice,
    required this.money,
    required this.canWrite,
    required this.onPay,
  });

  final OutstandingInvoice invoice;
  final NumberFormat money;
  final bool canWrite;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: invoice.isOverdue
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          invoice.isOverdue ? Icons.schedule : Icons.receipt_long_outlined,
          size: 20,
          color: invoice.isOverdue
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(invoice.customerName),
      subtitle: Text(
        [
          invoice.number,
          if (invoice.isOverdue)
            '${invoice.daysOverdue} jours de retard'
          else if (invoice.dueOn != null)
            'échéance ${DateFormat('d MMM', 'fr_FR').format(invoice.dueOn!)}',
          // Says the invoice is half settled without needing a second line.
          if (invoice.isPartlyPaid) '${money.format(invoice.paid)} déjà reçu',
        ].join(' · '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            money.format(invoice.outstanding),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: invoice.isOverdue ? theme.colorScheme.error : null,
            ),
          ),
          if (canWrite)
            Text(
              'Encaisser',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
        ],
      ),
      onTap: canWrite ? onPay : null,
    );
  }
}

class _InvoiceDraft {
  const _InvoiceDraft({
    required this.customer,
    required this.lines,
    this.phone,
    this.dueOn,
  });

  final String customer;
  final String? phone;
  final DateTime? dueOn;
  final List<InvoiceLineDraft> lines;
}

class _NewInvoiceSheet extends StatefulWidget {
  const _NewInvoiceSheet();

  @override
  State<_NewInvoiceSheet> createState() => _NewInvoiceSheetState();
}

class _NewInvoiceSheetState extends State<_NewInvoiceSheet> {
  final _customerController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descriptionController =
      TextEditingController(text: "Plateaux d'œufs");
  final _quantityController = TextEditingController(text: '30');
  final _priceController = TextEditingController();

  /// Three weeks is what a hotel actually takes, and a default that matches
  /// reality is a default nobody has to think about.
  DateTime _dueOn = DateTime.now().add(const Duration(days: 21));

  final List<InvoiceLineDraft> _lines = [];

  @override
  void dispose() {
    _customerController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  double get _total => _lines.fold(0, (sum, l) => sum + l.amount);

  bool get _valid =>
      _customerController.text.trim().isNotEmpty && _lines.isNotEmpty;

  void _addLine() {
    final quantity =
        double.tryParse(_quantityController.text.trim().replaceAll(',', '.')) ??
            0;
    final price =
        double.tryParse(_priceController.text.trim().replaceAll(',', '.')) ?? 0;
    final description = _descriptionController.text.trim();

    if (quantity <= 0 || price <= 0 || description.isEmpty) return;

    setState(() {
      _lines.add(InvoiceLineDraft(
        description: description,
        quantity: quantity,
        unitPrice: price,
      ));
      _priceController.clear();
    });
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouvelle facture', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              "Le montant devient une recette aujourd'hui et une créance "
              "jusqu'au règlement.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _customerController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Client',
                hintText: 'Hôtel Indépendance',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Text('Échéance', style: theme.textTheme.labelLarge),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dueOn,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _dueOn = picked);
                  },
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(DateFormat('d MMM y', 'fr_FR').format(_dueOn)),
                ),
              ],
            ),
            const Divider(),

            for (final line in _lines)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(line.description),
                subtitle: Text(
                  '${trimQuantity(line.quantity)} × ${line.unitPrice.round()}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(line.amount.round().toString()),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _lines.remove(line)),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Article',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantité',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Prix unitaire',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addLine(),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _addLine,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),

            const SizedBox(height: 16),
            if (_lines.isNotEmpty)
              Text(
                'Total ${_total.round()}',
                textAlign: TextAlign.right,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 12),

            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _valid
                    ? () => Navigator.pop(
                          context,
                          _InvoiceDraft(
                            customer: _customerController.text.trim(),
                            phone: _phoneController.text.trim().isEmpty
                                ? null
                                : _phoneController.text.trim(),
                            dueOn: _dueOn,
                            lines: List.of(_lines),
                          ),
                        )
                    : null,
                child: const Text('Créer la facture'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
