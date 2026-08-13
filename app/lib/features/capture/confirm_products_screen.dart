import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/capture/invoice_reading.dart';
import '../../core/retail/retail_repository.dart';

/// The screen M5's demo is actually about: *she photographs a delivery invoice
/// and the products are in the system without typing.*
///
/// What arrives here is what the phone read off the paper. What leaves is
/// stock on the shelves and a purchase in the books. In between there is
/// exactly one deliberate act — the person looks at the list and presses one
/// button — which is the "confirms with one tap rather than typing" the plan
/// asks for.
///
/// Three things this screen refuses to do.
///
/// **It does not save anything on its own.** Nothing is written until the
/// button is pressed. A reading that quietly became stock would put a wrong
/// count in the books that nobody chose.
///
/// **It does not hide what it is unsure about.** A line whose numbers did not
/// multiply out is marked, because that is the line most likely to be wrong
/// and the one worth reading before pressing.
///
/// **It does not pretend a wrong line must be deleted.** Every field is
/// editable and every line can be unticked. Correcting one number is faster
/// than typing nine lines, which is the whole value being offered.
class ConfirmProductsScreen extends StatefulWidget {
  const ConfirmProductsScreen({
    super.key,
    required this.org,
    required this.retail,
    required this.lines,
    this.capture,
    this.documentId,
  });

  final OrgSummary org;
  final RetailRepository retail;

  /// What was read. Never empty — the caller does not open this screen when
  /// the reading found nothing.
  final List<InvoiceLine> lines;

  /// Used to link the photograph to the first product created, so the
  /// delivery note stays attached to what arrived on it.
  final CaptureRepository? capture;
  final String? documentId;

  @override
  State<ConfirmProductsScreen> createState() => _ConfirmProductsScreenState();
}

class _ConfirmProductsScreenState extends State<ConfirmProductsScreen> {
  late final List<_Row> _rows = widget.lines
      .map((l) => _Row(
            line: l,
            name: TextEditingController(text: l.name),
            quantity: TextEditingController(
                text: _plain(l.quantity)),
            cost: TextEditingController(text: _plain(l.unitCost)),
          ))
      .toList();

  late final NumberFormat _money = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: widget.org.currency,
    decimalDigits: 0,
  );

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final row in _rows) {
      row.name.dispose();
      row.quantity.dispose();
      row.cost.dispose();
    }
    super.dispose();
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static double? _read(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Iterable<_Row> get _selected => _rows.where((r) => r.include);

  double get _total => _selected.fold<double>(0, (sum, r) {
        final q = _read(r.quantity) ?? 0;
        final c = _read(r.cost) ?? 0;
        return sum + q * c;
      });

  bool get _canSave =>
      !_saving &&
      _selected.isNotEmpty &&
      _selected.every((r) =>
          r.name.text.trim().isNotEmpty &&
          (_read(r.quantity) ?? 0) > 0 &&
          (_read(r.cost) ?? -1) >= 0);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    const uuid = Uuid();
    var created = 0;
    String? firstProductId;

    try {
      for (final row in _selected) {
        final productId = await widget.retail.ensureProduct(
          orgId: widget.org.id,
          name: row.name.text.trim(),
          costPrice: _read(row.cost),
        );
        firstProductId ??= productId;

        // `receive_products` both raises the count and books the purchase as
        // an expense, which is the same treatment the farm gives feed: the
        // day the goods arrive is the day the money is gone.
        //
        // The client_uuid is minted once per line and kept across retries, so
        // this loop failing on line four and being pressed again does not
        // deliver the first three twice. That guarantee is real as of 016 and
        // was not before it: `receive_products` used to pass the client_uuid
        // to the ledger and still add to `quantity` unconditionally, so a
        // retry counted the goods twice and the money once. test_delivery.sql
        // is what noticed.
        await widget.retail.receive(
          orgId: widget.org.id,
          productId: productId,
          quantity: _read(row.quantity)!,
          unitCost: _read(row.cost),
          clientUuid: row.clientUuid ??= uuid.v4(),
        );
        created++;
      }

      // The delivery note stays attached to what arrived on it.
      final capture = widget.capture;
      final documentId = widget.documentId;
      if (capture != null && documentId != null && firstProductId != null) {
        try {
          await capture.file(
            documentId: documentId,
            kind: 'invoice',
            productId: firstProductId,
          );
        } catch (_) {
          // The stock is in. Failing to link the photograph is not worth
          // undoing that, and the picture is still in the gallery.
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$created article${created > 1 ? 's' : ''} '
            'ajouté${created > 1 ? 's' : ''} au stock.'),
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Partial success is the honest thing to say. Some lines are already
        // in, and pressing again is safe because each carries its own
        // client_uuid — so the message says both.
        _error = created == 0
            ? '$error'
            : '$created ligne${created > 1 ? 's' : ''} enregistrée'
                '${created > 1 ? 's' : ''}, puis : $error\n'
                'Réessayez : les lignes déjà enregistrées ne seront pas '
                'comptées deux fois.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unsure = _rows.where((r) => !r.line.checked).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Articles lus')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _canSave ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_shopping_cart),
            label: Text(_selected.isEmpty
                ? 'Aucune ligne sélectionnée'
                : 'Ajouter ${_selected.length} article'
                    '${_selected.length > 1 ? 's' : ''} — '
                    '${_money.format(_total)}'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            '${_rows.length} ligne${_rows.length > 1 ? 's' : ''} '
            'lue${_rows.length > 1 ? 's' : ''} sur la photo.',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Rien n’est enregistré tant que vous n’avez pas appuyé sur le '
            'bouton. Corrigez ce qui est faux, décochez ce qui n’en est pas.',
            style: theme.textTheme.bodySmall,
          ),

          if (unsure > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.help_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$unsure ligne${unsure > 1 ? 's' : ''} dont le calcul '
                      'ne tombe pas juste. Vérifiez-${unsure > 1 ? 'les' : 'la'} '
                      'avant d’enregistrer.',
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!),
            ),
          ],

          const SizedBox(height: 16),
          for (final row in _rows) _lineCard(row, theme),
        ],
      ),
    );
  }

  Widget _lineCard(_Row row, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: row.include,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => row.include = v ?? false),
                ),
                Expanded(
                  child: TextField(
                    controller: row.name,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Article',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (!row.line.checked)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.help_outline,
                        size: 20, color: theme.colorScheme.tertiary),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: row.quantity,
                      enabled: !_saving,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Quantité',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: row.cost,
                      enabled: !_saving,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        // Cost, not shelf price. A supplier's price used as
                        // the selling price would zero the margin silently.
                        labelText: 'Prix d’achat',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row {
  _Row({
    required this.line,
    required this.name,
    required this.quantity,
    required this.cost,
  });

  final InvoiceLine line;
  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController cost;

  bool include = true;

  /// Minted on the first attempt and kept across retries, so a loop that
  /// fails halfway can be pressed again without doubling the delivery.
  String? clientUuid;
}
