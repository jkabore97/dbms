import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../../core/invoicing/models.dart';
import '../accounting/report_shell.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';

/// Invoicing, for whichever business is open.
///
/// This screen used to be `features/farm/invoices_screen.dart`, reachable from
/// the farm's home screen and nowhere else — because 009 built invoicing
/// inside the farm migration for Ignace selling trays to a hotel. The tables
/// were never farm-specific and neither is the need: a shop bills a
/// wholesaler, a church bills a hall hire, and both were being told to keep
/// doing it on paper.
///
/// It shows everything issued rather than only what is unpaid. The old screen
/// was built on `outstanding_invoices()`, which answers the collections
/// question — and means an invoice disappears from the app the moment it is
/// paid, so nobody can re-send a copy of it afterwards.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({
    super.key,
    required this.org,
    required this.invoicing,
  });

  final OrgSummary org;
  final InvoicingRepository invoicing;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<InvoiceSummary> _invoices = const [];
  BillingDetails _billing = const BillingDetails();
  bool _loading = true;
  Object? _error;

  /// False shows only what is still owed, which is the collections view.
  bool _showAll = true;

  bool get _canWrite => !widget.org.isObserverOnly;

  NumberFormat get _money => moneyFormat(widget.org.currency);
  final _date = DateFormat('d MMM y', 'fr_FR');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.invoicing.isConfigured) {
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
      final invoices = await widget.invoicing.list(widget.org.id);
      // Best-effort: a database that has not run 020 yet has no billing
      // columns, and the list is still worth showing without them.
      BillingDetails billing = const BillingDetails();
      try {
        billing = await widget.invoicing.billingDetails(widget.org.id);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _billing = billing;
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

  Future<void> _openNew() async {
    final id = await context
        .push<String>(Routes.inside(widget.org.id, 'factures/nouvelle'));
    if (id == null || !mounted) return;
    // Straight to the document: raising an invoice and sending it are one
    // errand, and a list is not what somebody wanted when they pressed create.
    await _openDocument(id);
  }

  Future<void> _openDocument(String id) async {
    // The id is in the path, so this page can be linked and reloaded.
    await context.push(Routes.inside(widget.org.id, 'factures/$id'));
    if (mounted) await _load();
  }

  Future<void> _openBilling() async {
    final changed = await context
        .push<bool>(Routes.inside(widget.org.id, 'factures/facturation'));
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _showAll
        ? _invoices
        : _invoices.where((i) => i.outstanding > 0).toList();
    final owed = _invoices
        .where((i) => !i.cancelled)
        .fold<double>(0, (sum, i) => sum + i.outstanding);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Factures'),
        actions: [
          if (widget.org.isAdmin)
            IconButton(
              onPressed: _openBilling,
              icon: const Icon(Icons.storefront_outlined),
              tooltip: 'En-tête de facture',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _Failed(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    children: [
                      // Said before the first invoice, not after it has been
                      // sent: a document with no address and no tax number is
                      // one the customer's accountant hands straight back.
                      if (widget.org.isAdmin && _billing.isEmpty)
                        Card(
                          color: theme.colorScheme.tertiaryContainer,
                          child: ListTile(
                            leading: const Icon(Icons.info_outline),
                            title: const Text("En-tête incomplet"),
                            subtitle: const Text(
                              'Ajoutez votre adresse et votre numéro IFU : '
                              'sans eux, un client ne peut pas comptabiliser '
                              'votre facture.',
                            ),
                            onTap: _openBilling,
                          ),
                        ),

                      if (owed > 0) ...[
                        const SizedBox(height: 8),
                        Card(
                          color: theme.colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Reste à encaisser',
                                    style: theme.textTheme.labelLarge),
                                const SizedBox(height: 4),
                                Text(
                                  _money.format(owed),
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('Toutes')),
                          ButtonSegment(value: false, label: Text('Impayées')),
                        ],
                        selected: {_showAll},
                        onSelectionChanged: (s) =>
                            setState(() => _showAll = s.first),
                      ),
                      const SizedBox(height: 12),

                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              _invoices.isEmpty
                                  ? 'Aucune facture pour le moment.'
                                  : 'Tout est payé.',
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        )
                      else
                        for (final invoice in shown)
                          _InvoiceTile(
                            invoice: invoice,
                            money: _money,
                            date: _date,
                            onTap: () => _openDocument(invoice.id),
                          ),
                    ],
                  ),
                ),
      floatingActionButton: _canWrite && widget.invoicing.isConfigured
          ? FloatingActionButton.extended(
              onPressed: _openNew,
              icon: const Icon(Icons.add),
              label: const Text('Facturer'),
            )
          : null,
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({
    required this.invoice,
    required this.money,
    required this.date,
    required this.onTap,
  });

  final InvoiceSummary invoice;
  final NumberFormat money;
  final DateFormat date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (Color colour, String label) = switch (invoice) {
      _ when invoice.cancelled => (theme.colorScheme.outline, 'Annulée'),
      _ when invoice.isPaid => (Colors.green.shade700, 'Payée'),
      _ when invoice.isOverdue => (
          theme.colorScheme.error,
          'En retard de ${invoice.daysOverdue} j'
        ),
      _ when invoice.isPartlyPaid => (Colors.orange.shade800, 'Partiel'),
      _ => (theme.colorScheme.primary, 'À encaisser'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: colour.withValues(alpha: 0.15),
          child: Icon(Icons.receipt_long, color: colour, size: 20),
        ),
        title: Text(
          invoice.customerName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: invoice.cancelled ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          '${invoice.number} · ${date.format(invoice.issuedOn)}\n$label',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              money.format(invoice.total),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (!invoice.cancelled &&
                invoice.outstanding > 0 &&
                invoice.paid > 0)
              Text(
                'reste ${money.format(invoice.outstanding)}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(describeError(error), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
