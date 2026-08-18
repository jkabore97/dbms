import 'package:flutter/material.dart';
import '../../core/format/money.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/retail/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/retail/retail_repository.dart';
import '../capture/barcode_sheet.dart';
import '../../core/errors.dart';

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
    this.currency = 'XOF',
    this.capture,
    this.products = const [],
    this.canCredit = true,
    this.initialMethod = 'cash',
    this.orgName = '',
  });

  /// The shop's name, printed on the Wave receipt. Empty is fine — the receipt
  /// falls back to a generic heading.
  final String orgName;

  /// Whether "Crédit" is offered at all — the owner's dial from 031. The
  /// server refuses regardless; this keeps the refused button off screen.
  final bool canCredit;

  /// Which payment method the sheet opens on. 'credit' when the carnet opens
  /// it, so recording a credit sale there picks real products and moves stock
  /// instead of writing a free-text line unrelated to the inventory.
  final String initialMethod;

  final String orgId;

  /// The business's currency, so the cart shows the same money everything else
  /// does — not bare numbers while every other screen shows FCFA.
  final String currency;

  final RetailRepository retail;

  /// What is on the shelves, for the picker. An empty list is not an error —
  /// a shop with no catalogue yet still sells things.
  final List<Product> products;

  /// Only needed for `product_by_barcode()`. Null hides the scan button —
  /// scanning a code and being told nothing is worse than not offering it.
  final CaptureRepository? capture;

  @override
  State<SaleSheet> createState() => _SaleSheetState();
}

class _SaleSheetState extends State<SaleSheet> {
  final _lines = <SaleLineDraft>[];
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _customerController = TextEditingController();

  /// One per basket, not one per attempt. See the class comment.
  late final String _clientUuid = const Uuid().v4();

  NumberFormat get _money => moneyFormat(widget.currency);

  late String _method = widget.initialMethod;
  Product? _picked;
  bool _busy = false;
  String? _error;

  /// The business's Wave handle, fetched once on open. Null while loading and
  /// null when the owner has set none — either way, Wave is not offered.
  String? _waveMerchant;

  @override
  void initState() {
    super.initState();
    _loadWave();
  }

  Future<void> _loadWave() async {
    try {
      final merchant = await widget.retail.waveMerchant(widget.orgId);
      if (mounted) setState(() => _waveMerchant = merchant);
    } catch (_) {
      // A shop with no Wave handle, or an offline open, simply has no Wave
      // button. It is never the reason a sale cannot be recorded.
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _customerController.dispose();
    super.dispose();
  }

  /// The shelf without the kitchen: flagged ingredients stay out of the
  /// picker so a thumb cannot sell the production flour at 0 F. Typing the
  /// name still works — the flag is a signpost, not a rule.
  late final List<Product> _sellable =
      widget.products.where((p) => !p.isIngredient).toList();

  double get _total =>
      _lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

  double? get _draftQuantity =>
      double.tryParse(_quantityController.text.trim().replaceAll(',', '.'));
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

  /// Scan, look up, and either select the product or say the shop has never
  /// seen this code. Nothing is created here: a barcode is an identifier, not
  /// a product, and inventing one from a number is how a shop ends up with
  /// "6001234567890" on a shelf label.
  Future<void> _scan() async {
    final capture = widget.capture;
    if (capture == null) return;

    final code = await BarcodeSheet.scan(context, title: 'Scanner un article');
    if (code == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    // Fast path: this basket's own list is usually the right answer and needs
    // no round trip, which matters at a counter with two bars of signal.
    for (final product in widget.products) {
      if (product.barcode == code) {
        _pick(product);
        return;
      }
    }

    try {
      final row = await capture.productByBarcode(widget.orgId, code);
      if (!mounted) return;

      if (row == null) {
        messenger.showSnackBar(SnackBar(
          content: Text('Code $code inconnu dans cette boutique. '
              'Ajoutez l’article depuis Articles.'),
        ));
        return;
      }

      setState(() {
        _picked = null;
        _nameController.text = (row['name'] as String?) ?? '';
        final price = row['sale_price'];
        if (price != null) {
          _priceController.text =
              (price is num ? price : num.tryParse('$price') ?? 0)
                  .toStringAsFixed(0);
        }
      });
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
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
    if (_method == 'credit' && _customerController.text.trim().isEmpty) {
      setState(() => _error = 'Entrez le nom du client pour un crédit.');
      return;
    }
    if (_method == 'wave') {
      return _saveWave();
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
        customerName:
            _method == 'credit' ? _customerController.text.trim() : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The Wave path: show the QR for the customer to scan, take the sender's
  /// name, record the sale, confirm it, and hand back a receipt. Nothing is
  /// recorded if the payment sheet is dismissed — a QR shown is not a sale.
  Future<void> _saveWave() async {
    final merchant = _waveMerchant;
    if (merchant == null) return;

    final sender = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => WavePaymentSheet(
        merchant: merchant,
        amount: _total,
        currency: widget.currency,
      ),
    );
    if (sender == null || !mounted) return; // dismissed — no sale

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saleId = await widget.retail.recordSale(
        orgId: widget.orgId,
        lines: _lines,
        method: 'wave',
        clientUuid: _clientUuid,
      );
      await widget.retail.confirmWavePayment(saleId: saleId, sender: sender);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => WaveReceiptDialog(
            shopName: widget.orgName,
            total: _total,
            currency: widget.currency,
            sender: sender,
          ),
        );
      }
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
            Row(
              children: [
                Expanded(
                  child:
                      Text('Nouvelle vente', style: theme.textTheme.titleLarge),
                ),
                if (widget.capture != null)
                  IconButton(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'Scanner un code-barres',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_sellable.isNotEmpty) ...[
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _sellable.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final product = _sellable[i];
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
                      '${_money.format(line.unitPrice)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_money.format(line.lineTotal),
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
                    _money.format(_total),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(value: 'cash', label: Text('Espèces')),
                const ButtonSegment(
                    value: 'mobile_money', label: Text('Mobile')),
                if (_waveMerchant != null)
                  const ButtonSegment(
                    value: 'wave',
                    label: Text('Wave'),
                    icon: Icon(Icons.qr_code_2),
                  ),
                const ButtonSegment(value: 'bank', label: Text('Banque')),
                if (widget.canCredit)
                  const ButtonSegment(value: 'credit', label: Text('Crédit')),
              ],
              selected: {_method},
              onSelectionChanged:
                  _busy ? null : (s) => setState(() => _method = s.first),
            ),
            if (_method == 'credit') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customerController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Nom du client',
                  // The same sale as always — the goods leave, the day's
                  // totals count it — only the money waits in the carnet.
                  helperText: 'La vente ira dans le carnet de crédit.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
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
                    : Text(
                        _method == 'wave'
                            ? 'Payer avec Wave'
                            : 'Enregistrer la vente',
                        style: const TextStyle(fontSize: 17)),
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

/// The Wave payment step: the customer scans, pays, and the shopkeeper types
/// the name Wave shows for the payer before confirming.
///
/// Returns the sender's name on confirm, or null when dismissed. It records
/// nothing itself — the sale is written only after this returns a name, so a
/// customer who walks away leaves no sale behind.
class WavePaymentSheet extends StatefulWidget {
  const WavePaymentSheet({
    super.key,
    required this.merchant,
    required this.amount,
    required this.currency,
  });

  /// The business's Wave handle, encoded into the QR the customer scans.
  final String merchant;
  final double amount;
  final String currency;

  @override
  State<WavePaymentSheet> createState() => _WavePaymentSheetState();
}

class _WavePaymentSheetState extends State<WavePaymentSheet> {
  final _senderController = TextEditingController();
  NumberFormat get _money => moneyFormat(widget.currency);

  @override
  void dispose() {
    _senderController.dispose();
    super.dispose();
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
          Text('Paiement Wave', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Faites scanner ce code au client, puis entrez son nom Wave.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              // qr_flutter draws it on device — nothing is fetched, so the code
              // shows with no signal, which is the whole point at a counter.
              child: QrImageView(
                data: widget.merchant,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _money.format(widget.amount),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _senderController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Nom de l\'expéditeur Wave',
              helperText: 'Le nom qui apparaît sur le paiement Wave.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _senderController.text.trim().isEmpty
                        ? null
                        : () => Navigator.of(context)
                            .pop(_senderController.text.trim()),
                    icon: const Icon(Icons.check),
                    label: const Text('Paiement reçu'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The receipt for a confirmed Wave payment — carrying the sender's name, which
/// is the record a shopkeeper wants when a payment is later queried.
class WaveReceiptDialog extends StatelessWidget {
  const WaveReceiptDialog({
    super.key,
    required this.shopName,
    required this.total,
    required this.currency,
    required this.sender,
  });

  final String shopName;
  final double total;
  final String currency;
  final String sender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(currency);
    final now = DateTime.now();
    final stamp = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    return AlertDialog(
      icon: const Icon(Icons.check_circle_outline, color: Color(0xFF0E7A63), size: 40),
      title: const Text('Paiement Wave reçu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shopName.isNotEmpty)
            Text(shopName, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _row(context, 'Montant', money.format(total), bold: true),
          _row(context, 'Payé par', sender),
          _row(context, 'Méthode', 'Wave'),
          _row(context, 'Date', stamp),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Terminer'),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool bold = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(value,
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }
}
