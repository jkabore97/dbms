import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';

/// Recording a sale, with a customer standing there.
///
/// Two rules shape this screen and neither is negotiable:
///
/// The basket carries one `client_uuid`, generated when the sheet opens and
/// reused for every attempt. `record_sale()` returns the original sale for a
/// repeated uuid, so tapping the button twice, or a retry after a timeout,
/// cannot sell the same goods twice. Generating it per attempt would defeat
/// the whole mechanism, which is why it is created in `initState` and never
/// reassigned.
///
/// A line can be a product from the shelf or a name typed on the spot.
/// Refusing to sell something because it was never entered would make the
/// catalogue more important than the customer, and the catalogue is the part
/// that can be fixed later.
class SaleSheet extends StatefulWidget {
  const SaleSheet({
    super.key,
    required this.orgId,
    required this.retail,
    this.products = const [],
  });

  final String orgId;
  final RetailRepository retail;

  /// What is on the shelves, for the picker. An empty list is not an error —
  /// a shop with no catalogue yet still sells things.
  final List<Product> products;

  @override
  State<SaleSheet> createState() => _SaleSheetState();
}

class _SaleSheetState extends State<SaleSheet> {
  final _lines = <SaleLineDraft>[];
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();

  /// One per basket, not one per attempt. See the class comment.
  late final String _clientUuid = const Uuid().v4();

  String _method = 'cash';
  Product? _picked;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  double get _total =>
      _lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

  double? get _draftQuantity => double.tryParse(
      _quantityController.text.trim().replaceAll(',', '.'));
  double? get _draftPrice =>
      double.tryParse(_priceController.text.trim().replaceAll(',', '.'));

  bool get _canAddLine {
    final name = _picked?.name ?? _nameController.text.trim();
    final quantity = _draftQuantity;
    return name.isNotEmpty &&
        quantity != null &&
        quantity > 0 &&
        (_draftPrice ?? 0) >= 0 &&
        _priceController.text.trim().isNotEmpty;
  }

  void _addLine() {
    if (!_canAddLine) return;
    setState(() {
      _lines.add(SaleLineDraft(
        productId: _picked?.id,
        name: _picked?.name ?? _nameController.text.trim(),
        quantity: _draftQuantity!,
        unitPrice: _draftPrice!,
      ));
      _picked = null;
      _nameController.clear();
      _quantityController.text = '1';
      _priceController.clear();
      _error = null;
    });
  }

  void _pick(Product product) {
    setState(() {
      _picked = product;
      _nameController.text = product.name;
      if (product.salePrice > 0) {
        _priceController.text = product.salePrice.toStringAsFixed(0);
      }
    });
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      setState(() => _error = 'Ajoutez au moins un article.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.retail.recordSale(
        orgId: widget.orgId,
        lines: _lines,
        method: _method,
        clientUuid: _clientUuid,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouvelle vente', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),

            if (widget.products.isNotEmpty) ...[
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.products.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final product = widget.products[i];
                    return ChoiceChip(
                      label: Text(product.name),
                      selected: _picked?.id == product.id,
                      onSelected: _busy ? null : (_) => _pick(product),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _nameController,
              enabled: !_busy,
              onChanged: (_) => setState(() => _picked = null),
              decoration: const InputDecoration(
                labelText: 'Article',
                hintText: 'Sucre 1kg',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    enabled: !_busy,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Quantité',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Prix unitaire',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _canAddLine && !_busy ? _addLine : null,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter au panier'),
            ),

            if (_lines.isNotEmpty) ...[
              const SizedBox(height: 20),
              ..._lines.asMap().entries.map((entry) {
                final line = entry.value;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(line.name),
                  subtitle: Text('${_trim(line.quantity)} × '
                      '${line.unitPrice.toStringAsFixed(0)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(line.lineTotal.toStringAsFixed(0),
                          style: theme.textTheme.titleMedium),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Retirer',
                        onPressed: _busy
                            ? null
                            : () => setState(() => _lines.removeAt(entry.key)),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: theme.textTheme.titleMedium),
                  Text(
                    _total.toStringAsFixed(0),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Espèces')),
                ButtonSegment(value: 'mobile_money', label: Text('Mobile')),
                ButtonSegment(value: 'bank', label: Text('Banque')),
              ],
              selected: {_method},
              onSelectionChanged:
                  _busy ? null : (s) => setState(() => _method = s.first),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],

            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _lines.isEmpty || _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer la vente',
                        style: TextStyle(fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';
}
