import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';

/// Undoing a transaction the honest way.
///
/// The rule this screen exists to make usable: you do not delete a sale or a
/// purchase — deleting would break the books and the trail. You *reverse* it,
/// which posts a compensating movement dated today that cancels the original
/// in both the stock count and the ledger, so accounting, analysis and reports
/// all correct themselves. A test left behind, or a mistake found weeks later,
/// is fixed here without rewriting the past.
///
/// Owner/admin only — the server enforces it; this keeps the buttons off a
/// clerk's screen. Both lists on one page because "was it a sale or a delivery"
/// is exactly what a person is unsure of when they come looking to undo one.
class CorrectionsScreen extends StatefulWidget {
  const CorrectionsScreen({super.key, required this.org, required this.retail});

  final OrgSummary org;
  final RetailRepository retail;

  @override
  State<CorrectionsScreen> createState() => _CorrectionsScreenState();
}

class _CorrectionsScreenState extends State<CorrectionsScreen> {
  NumberFormat get _money => moneyFormat(widget.org.currency);

  List<SaleSummary> _sales = const [];
  List<Delivery> _deliveries = const [];
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
      final sales = await widget.retail.recentSales(widget.org.id);
      final deliveries = await widget.retail.recentDeliveries(widget.org.id);
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _deliveries = deliveries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeError(error);
        _loading = false;
      });
    }
  }

  /// Confirms the reversal and takes an optional reason, so the correction
  /// carries why it was made — the thing an auditor (or a future you) asks.
  Future<void> _confirmAndReverse({
    required String title,
    required String detail,
    required Future<void> Function(String? reason) run,
  }) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail),
            const SizedBox(height: 8),
            const Text(
              "L'opération n'est pas supprimée : une écriture inverse "
              "l'annule dans le stock et dans la comptabilité.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Raison (facultatif)',
                hintText: 'ex. données de test',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Corriger'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (ok != true) return;

    try {
      await run(reason.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correction enregistrée.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeError(error))),
      );
    }
  }

  String _method(String m) => switch (m) {
        'cash' => 'Espèces',
        'mobile_money' => 'Mobile',
        'wave' => 'Wave',
        'bank' => 'Banque',
        'credit' => 'Crédit',
        _ => m,
      };

  String _when(DateTime d) => DateFormat('d MMM y', 'fr_FR').format(d);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Corrections')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    "Annulez une vente ou un achat entré par erreur — ou des "
                    "données de test. Rien n'est effacé : la comptabilité et "
                    "les analyses se corrigent d'elles-mêmes.",
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),

                  // Sales.
                  Text('Ventes', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_sales.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Aucune vente.'),
                    )
                  else
                    ..._sales.map(_saleTile),

                  const SizedBox(height: 24),

                  // Deliveries / purchases.
                  Text('Entrées de stock', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_deliveries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Aucune entrée de stock.'),
                    )
                  else
                    ..._deliveries.map(_deliveryTile),

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _saleTile(SaleSummary s) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          _money.format(s.total),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: s.reversed ? TextDecoration.lineThrough : null,
            color: s.reversed ? theme.colorScheme.outline : null,
          ),
        ),
        subtitle: Text([
          _method(s.method),
          _when(s.occurredAt),
          if (s.note != null && s.note!.isNotEmpty) s.note!,
        ].join(' · ')),
        trailing: s.reversed
            ? Chip(
                label: const Text('Corrigé'),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              )
            : OutlinedButton(
                onPressed: () => _confirmAndReverse(
                  title: 'Corriger cette vente ?',
                  detail:
                      'Vente de ${_money.format(s.total)} du ${_when(s.occurredAt)}. '
                      'Les articles retournent en stock.',
                  run: (reason) =>
                      widget.retail.recordReturn(s.id, note: reason),
                ),
                child: const Text('Corriger'),
              ),
      ),
    );
  }

  Widget _deliveryTile(Delivery d) {
    final theme = Theme.of(context);
    final qty = d.quantity == d.quantity.roundToDouble()
        ? d.quantity.round().toString()
        : '${d.quantity}';
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          d.productName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: d.reversed ? TextDecoration.lineThrough : null,
            color: d.reversed ? theme.colorScheme.outline : null,
          ),
        ),
        subtitle: Text([
          '$qty × ${_money.format(d.unitCost)} = ${_money.format(d.lineTotal)}',
          _when(d.receivedAt),
        ].join(' · ')),
        trailing: d.reversed
            ? Chip(
                label: const Text('Corrigé'),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              )
            : OutlinedButton(
                onPressed: () => _confirmAndReverse(
                  title: 'Corriger cette entrée ?',
                  detail: '$qty ${d.productName} entré(s) le '
                      '${_when(d.receivedAt)}. Le stock est retiré et '
                      "l'achat est annulé dans les comptes.",
                  run: (reason) =>
                      widget.retail.reverseReceipt(d.id, reason: reason),
                ),
                child: const Text('Corriger'),
              ),
      ),
    );
  }
}
