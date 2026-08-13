import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../capture/barcode_sheet.dart';
import '../../core/errors.dart';

/// The shelves: what the shop sells, what it has, what it is worth.
///
/// Adding a product and receiving a delivery are the same act here, and that
/// is deliberate. A shopkeeper unpacking a box is not thinking "first define a
/// product, then record stock"; she is thinking "twenty sugar came in, they
/// cost 500 each". So one sheet takes the name, the quantity and the cost, and
/// the server does `ensure_product()` then `receive_products()` — the second of
/// which books the money as a purchase.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({
    super.key,
    required this.org,
    required this.retail,
    this.capture,
  });

  final OrgSummary org;
  final RetailRepository retail;

  /// Needed for `product_by_barcode()`. Null hides the scan button: scanning
  /// a code and being told nothing is worse than not offering it.
  final CaptureRepository? capture;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late final NumberFormat _money = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: widget.org.currency,
    decimalDigits: 0,
  );

  List<Product> _products = const [];
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
      final products = await widget.retail.products(widget.org.id);
      if (!mounted) return;
      setState(() {
        _products = products;
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

  Future<void> _addStock() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReceiveSheet(org: widget.org, retail: widget.retail),
    );
    if (added == true) await _load();
  }

  /// Scan a code and go to what it is. A code this shop has never seen opens
  /// the stock-entry sheet with the barcode already in it, which is the whole
  /// point: the number is read once, by the camera, and never typed.
  Future<void> _scan() async {
    final capture = widget.capture;
    if (capture == null) return;

    final code = await BarcodeSheet.scan(context, title: 'Scanner un article');
    if (code == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    for (final product in _products) {
      if (product.barcode == code) {
        messenger.showSnackBar(SnackBar(
          content:
              Text('${product.name} — ${product.quantity.toStringAsFixed(0)} '
                  'en stock'),
        ));
        return;
      }
    }

    try {
      final row = await capture.productByBarcode(widget.org.id, code);
      if (!mounted) return;

      if (row != null) {
        messenger.showSnackBar(
            SnackBar(content: Text('${row['name']} — déjà en stock')));
        return;
      }

      final added = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ReceiveSheet(
          org: widget.org,
          retail: widget.retail,
          barcode: code,
        ),
      );
      if (added == true) await _load();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stockValue =
        _products.fold<double>(0, (sum, p) => sum + p.quantity * p.costPrice);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Articles'),
        actions: [
          if (widget.capture != null)
            IconButton(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Scanner un code-barres',
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStock,
        icon: const Icon(Icons.add),
        label: const Text('Entrée de stock'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (_products.isNotEmpty) ...[
              Text('Valeur du stock : ${_money.format(stockValue)}',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
            ],
            if (!_loading && _products.isEmpty && _error == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    const Text(
                      "Aucun article pour l'instant.\n"
                      'Enregistrez une entrée de stock, ou vendez directement '
                      "— l'article sera créé tout seul.",
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ..._products.map((p) => Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    title: Text(p.name),
                    subtitle: Text([
                      '${_trim(p.quantity)} en stock',
                      if (p.salePrice > 0) _money.format(p.salePrice),
                      if (p.expiresOn != null)
                        'expire le ${DateFormat('d MMM', 'fr_FR').format(p.expiresOn!)}',
                    ].join(' · ')),
                    trailing: p.isLow
                        ? Chip(
                            label: const Text('bas'),
                            backgroundColor: theme.colorScheme.errorContainer,
                          )
                        : null,
                  ),
                )),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';
}

/// A delivery arriving. Creates the product if it is new.
class _ReceiveSheet extends StatefulWidget {
  const _ReceiveSheet({
    required this.org,
    required this.retail,
    this.barcode,
  });

  final OrgSummary org;
  final RetailRepository retail;

  /// Carried in from a scan. The number is read once, by the camera, and
  /// never typed — which is the only reason scanning an unknown code is
  /// better than not scanning at all.
  final String? barcode;

  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  final _name = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _cost = TextEditingController();
  final _price = TextEditingController();
  final _serial = TextEditingController();
  DateTime? _expiresOn;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _cost.dispose();
    _price.dispose();
    _serial.dispose();
    super.dispose();
  }

  double? get _qty =>
      double.tryParse(_quantity.text.trim().replaceAll(',', '.'));

  bool get _ready => _name.text.trim().isNotEmpty && (_qty ?? 0) > 0;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cost = double.tryParse(_cost.text.trim().replaceAll(',', '.'));
      final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));

      final productId = await widget.retail.ensureProduct(
        orgId: widget.org.id,
        name: _name.text.trim(),
        costPrice: cost,
        salePrice: price,
        barcode: widget.barcode,
        expiresOn: _expiresOn,
      );

      final serial = _serial.text.trim();
      if (serial.isNotEmpty) {
        await widget.retail.setSerial(productId, serial);
      }
      await widget.retail.receive(
        orgId: widget.org.id,
        productId: productId,
        quantity: _qty!,
        unitCost: cost,
        expiresOn: _expiresOn,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
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
            Text('Entrée de stock', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !_busy,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Article',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
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
                    controller: _cost,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Coût unitaire',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Prix de vente',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serial,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Numéro de série (facultatif)',
                // Only matters for the goods where it matters: a phone, a
                // radio, a panel. It is what a warranty claim is looked up by.
                helperText: 'Pour un téléphone, une radio, un panneau…',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.barcode != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.qr_code_2, size: 16),
                  const SizedBox(width: 6),
                  Text('Code-barres scanné : ${widget.barcode}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            DateTime.now().add(const Duration(days: 30)),
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 365)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) setState(() => _expiresOn = picked);
                    },
              icon: const Icon(Icons.event_outlined),
              label: Text(_expiresOn == null
                  ? "Date d'expiration (facultatif)"
                  : 'Expire le '
                      '${DateFormat('d MMMM y', 'fr_FR').format(_expiresOn!)}'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _ready && !_busy ? _save : null,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer', style: TextStyle(fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
