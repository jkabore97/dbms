import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../core/format/money.dart';
import 'package:intl/intl.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/retail/bulk_add.dart';
import '../../core/retail/models.dart';
import 'convert_dialog.dart';
import '../../core/retail/retail_repository.dart';
import '../capture/barcode_sheet.dart';
import '../capture/capture_action.dart';
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
    this.access = OrgAccess.allEdit,
  });

  /// The owner's dial from 031. At 'view' the shelves are read-only: no
  /// receiving, no bulk add, no edit sheet — the server refuses price edits
  /// anyway; this keeps the refused gestures off screen.
  final OrgAccess access;

  final OrgSummary org;
  final RetailRepository retail;

  /// Needed for `product_by_barcode()`. Null hides the scan button: scanning
  /// a code and being told nothing is worse than not offering it.
  final CaptureRepository? capture;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  NumberFormat get _money => moneyFormat(widget.org.currency);

  List<Product> _products = const [];
  bool _loading = true;
  String? _error;

  /// The search box. Filtering happens on the device over the list already
  /// fetched — instant, and it works with no signal. At two hundred articles
  /// three typed letters beat any amount of scrolling.
  final _search = TextEditingController();

  List<Product> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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

  /// Twenty articles in one save: a box of lines, "nom quantité prix [coût]",
  /// for the shop being set up or the big market morning.
  Future<void> _bulkAdd() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BulkAddSheet(org: widget.org, retail: widget.retail),
    );
    if (added == true) await _load();
  }

  /// A product's prices, threshold and expiry, after it exists. The one thing
  /// deliberately absent is the count: stock moves through deliveries, sales
  /// and production so every movement stays on the record, not through a
  /// number silently overwritten here.
  Future<void> _edit(Product product) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditProductSheet(
        retail: widget.retail,
        org: widget.org,
        product: product,
        capture: widget.capture,
        // The archive button belongs to the person who answers for the
        // business; the server refuses everyone else anyway.
        canArchive: widget.org.isAdmin,
      ),
    );
    if (changed == true) await _load();
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
    // The count of articles is how many distinct lines the shop carries; the
    // count of items is how many things are actually on the shelves behind
    // them — 12 articles can be 340 units of stock. The owner asked to see both.
    final totalItems =
        _products.fold<double>(0, (sum, p) => sum + p.quantity);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Articles'),
        actions: [
          if (widget.access.canEdit('products'))
            IconButton(
              onPressed: _bulkAdd,
              icon: const Icon(Icons.playlist_add),
              tooltip: 'Ajout multiple',
            ),
          if (widget.capture != null)
            IconButton(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Scanner un code-barres',
            ),
        ],
      ),
      floatingActionButton: widget.access.canEdit('products')
          ? FloatingActionButton.extended(
              onPressed: _addStock,
              icon: const Icon(Icons.add),
              label: const Text('Entrée de stock'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (_products.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // The count the owner asked for: how many articles the shop
                  // carries, and — next to it — how many items sit behind them
                  // in total. While a search narrows the list the article part
                  // says "shown / total" so the number on screen is never
                  // mistaken for the whole shelf; the item total always counts
                  // the whole shelf, not the filtered view.
                  Text(
                    '${_search.text.trim().isEmpty ? '${_products.length} article'
                            '${_products.length > 1 ? 's' : ''}' : '${_visible.length} / ${_products.length} articles'}'
                        ' · ${_trim(totalItems)} en stock',
                    style: theme.textTheme.titleMedium,
                  ),
                  Text('Valeur : ${_money.format(stockValue)}',
                      style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Rechercher un article…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(_search.clear),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
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
            ..._visible.map((p) => Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    title: Text(p.name),
                    subtitle: Text([
                      '${_trim(p.quantity)} en stock',
                      if (p.isIngredient) 'ingrédient',
                      if (p.salePrice > 0) _money.format(p.salePrice),
                      if (p.expiresOn != null)
                        'expire le ${DateFormat('d MMM', 'fr_FR').format(p.expiresOn!)}',
                    ].join(' · ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (p.isLow)
                          Chip(
                            label: const Text('bas'),
                            backgroundColor: theme.colorScheme.errorContainer,
                          ),
                        // The door to the vitrine, drawn on the row: the
                        // long press below is a gesture nobody discovers,
                        // and "how do I put this in the window?" was the
                        // question. Filled when the article is already
                        // there, outlined when it is not; either way it
                        // opens the same sheet, where the switch and the
                        // photo are.
                        IconButton(
                          tooltip: p.isPublished
                              ? 'Sur la vitrine — modifier'
                              : 'Mettre sur la vitrine',
                          icon: Icon(
                            p.isPublished
                                ? Icons.storefront
                                : Icons.storefront_outlined,
                            color: p.isPublished
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          onPressed: widget.access.canEdit('products')
                              ? () => _edit(p)
                              : null,
                        ),
                      ],
                    ),
                    // Long press, not tap, on purpose: a thumb scrolling the
                    // shelves must not fall into a sheet that changes prices.
                    // And only for those the owner lets edit at all.
                    onLongPress: widget.access.canEdit('products')
                        ? () => _edit(p)
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

/// Twenty articles typed as twenty lines, saved in one gesture. Each line is
/// "nom quantité prix [coût]"; the preview shows exactly what will be saved
/// and names each line's problem in place, so nothing half-typed slips
/// through silently.
class _BulkAddSheet extends StatefulWidget {
  const _BulkAddSheet({required this.org, required this.retail});

  final OrgSummary org;
  final RetailRepository retail;

  @override
  State<_BulkAddSheet> createState() => _BulkAddSheetState();
}

class _BulkAddSheetState extends State<_BulkAddSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;
  int _saved = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final lines = parseBulkLines(_text.text);
    if (lines.isEmpty) {
      setState(() => _error = 'Écrivez au moins une ligne.');
      return;
    }
    if (lines.any((l) => !l.ok)) {
      // Saving around a broken line would silently drop what somebody
      // typed; the preview already points at it.
      setState(() => _error = 'Corrigez les lignes en rouge avant '
          "d'enregistrer.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _saved = 0;
    });
    try {
      for (final l in lines) {
        final productId = await widget.retail.ensureProduct(
          orgId: widget.org.id,
          name: l.name!,
          salePrice: l.salePrice,
          costPrice: l.costPrice,
        );
        await widget.retail.receive(
          orgId: widget.org.id,
          productId: productId,
          quantity: l.quantity!,
          unitCost: l.costPrice,
        );
        if (mounted) setState(() => _saved++);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      // _saved lines are in; the message says where it stopped so the rest
      // of the box can be saved again without doubling what got through —
      // ensure_product is idempotent by name and a re-receive is a new
      // delivery, so the honest advice is to delete the saved lines first.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '${describeError(error)}\n'
              '$_saved ligne(s) déjà enregistrée(s) — retirez-les du texte '
              'avant de réessayer.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = parseBulkLines(_text.text);
    final good = lines.where((l) => l.ok).length;

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
            Text('Ajout multiple', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Un article par ligne : nom quantité prix (coût facultatif). '
              'Exemple : Savon 20 300 200',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              enabled: !_busy,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Savon 20 300\nSucre 1kg 10 600 450\nHuile 2,5 1500',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: l.ok
                      ? Text(
                          '✓ ${l.name} — ${l.quantity} × ${l.salePrice}'
                          '${l.costPrice != null ? ' (coût ${l.costPrice})' : ''}',
                          style: theme.textTheme.bodySmall,
                        )
                      : Text(
                          'Ligne ${l.lineNumber} : ${l.error}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy || good == 0 ? null : _save,
                child: _busy
                    ? Text('Enregistrement… $_saved/$good')
                    : Text('Enregistrer $good article(s)',
                        style: const TextStyle(fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fixing a product after it exists: the shelf price typed wrong, the cost
/// that changed at the market, the alert threshold, the expiry date.
class _EditProductSheet extends StatefulWidget {
  const _EditProductSheet({
    required this.retail,
    required this.org,
    required this.product,
    this.capture,
    this.canArchive = false,
  });

  final RetailRepository retail;
  final OrgSummary org;
  final Product product;

  /// For the article's photograph. Null hides the photo section, the same
  /// courtesy as the scan button: no camera, no dead button.
  final CaptureRepository? capture;

  /// Owner/admin only. Hiding the button for everyone else is a courtesy;
  /// `archive_product()` makes the real check server-side.
  final bool canArchive;

  @override
  State<_EditProductSheet> createState() => _EditProductSheetState();
}

class _EditProductSheetState extends State<_EditProductSheet> {
  late final _name = TextEditingController(text: widget.product.name);
  late final _price = TextEditingController(
      text: widget.product.salePrice > 0
          ? _plain(widget.product.salePrice)
          : '');
  late final _cost = TextEditingController(
      text: widget.product.costPrice > 0
          ? _plain(widget.product.costPrice)
          : '');
  late final _low = TextEditingController(
      text: widget.product.lowStockAt == null
          ? ''
          : _plain(widget.product.lowStockAt!));
  late DateTime? _expiresOn = widget.product.expiresOn;
  late bool _isIngredient = widget.product.isIngredient;
  late bool _isPublished = widget.product.isPublished;
  late final _description =
      TextEditingController(text: widget.product.description ?? '');

  bool _busy = false;
  String? _error;

  /// The article's picture, as the vitrine will show it: what is already on
  /// the server at first, the newly taken one after. Loading it is
  /// best-effort — a placeholder is not an error.
  Uint8List? _photoBytes;
  bool _photoKnown = false;
  bool _photoBusy = false;

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final capture = widget.capture;
    if (capture == null) return;
    try {
      final key =
          await capture.productPhotoKey(widget.org.id, widget.product.id);
      if (key == null) {
        if (mounted) setState(() => _photoKnown = true);
        return;
      }
      final bytes = await capture.objectBytes(key);
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _photoKnown = true;
      });
    } catch (_) {
      if (mounted) setState(() => _photoKnown = true);
    }
  }

  /// Take or choose the article's picture, send it, and hang it on the
  /// article — from then on it is the photo the vitrine and the search show.
  Future<void> _changePhoto() async {
    final capture = widget.capture;
    if (capture == null) return;
    final picked = await CaptureAction.pick(context);
    if (picked == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _photoBusy = true);
    try {
      final id = await capture.capture(
        orgId: widget.org.id,
        bytes: picked.bytes,
        contentType: picked.contentType,
        kind: 'product_photo',
        caption: widget.product.name,
      );
      if (id == null) {
        // Queued for later: the bytes are safe, but with no server id there
        // is nothing to hang on the article yet. Filing it from Documents
        // once it lands is the honest path, so say exactly that.
        messenger.showSnackBar(const SnackBar(
          content: Text('Photo gardée, en attente de réseau. Une fois '
              'envoyée, liez-la à l\'article depuis Documents.'),
        ));
        return;
      }
      await capture.file(documentId: id, productId: widget.product.id);
      if (!mounted) return;
      setState(() {
        _photoBytes = picked.bytes;
        _photoKnown = true;
      });
      messenger.showSnackBar(const SnackBar(
        content: Text('Photo de l\'article enregistrée.'),
      ));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _cost.dispose();
    _low.dispose();
    _description.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.retail.updateProduct(
        widget.product.id,
        name: _name.text,
        salePrice: _parse(_price),
        costPrice: _parse(_cost),
        lowStockAt: _parse(_low),
        expiresOn: _expiresOn,
        isIngredient: _isIngredient,
        isPublished: _isPublished,
        // Sent only when it changed: before the database is on 064 the
        // column does not exist, and a price edit must still save.
        description: _description.text.trim() ==
                (widget.product.description ?? '')
            ? null
            : _description.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = _parse(_price);
    final cost = _parse(_cost) ?? widget.product.costPrice;

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
            Text(widget.product.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${_EditProductSheetState._plain(widget.product.quantity)} en stock '
              '— le stock bouge par les entrées, les ventes et la production',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Nom du produit',
                // Renaming cannot rewrite history — receipts snapshot names.
                helperText: "Les ventes déjà faites gardent l'ancien nom.",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Prix de vente',
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
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Coût unitaire',
                      border: const OutlineInputBorder(),
                      // Goods bought in another currency: convert, and the
                      // field receives the home-currency figure.
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.currency_exchange, size: 20),
                        tooltip: 'Payé dans une autre monnaie',
                        onPressed: _busy
                            ? null
                            : () async {
                                final converted =
                                    await CurrencyConvertDialog.open(
                                  context,
                                  retail: widget.retail,
                                  orgId: widget.org.id,
                                  homeCurrency: widget.org.currency,
                                );
                                if (converted != null && mounted) {
                                  setState(() => _cost.text =
                                      converted.round().toString());
                                }
                              },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (price != null && cost > 0 && price < cost) ...[
              const SizedBox(height: 8),
              Text(
                'Attention : vendu en dessous de ce que ça coûte '
                '(${_EditProductSheetState._plain(cost)}).',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _low,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Seuil d'alerte stock bas (facultatif)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _expiresOn ??
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
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isIngredient,
              onChanged:
                  _busy ? null : (v) => setState(() => _isIngredient = v),
              title: const Text('Ingrédient de production'),
              subtitle: const Text(
                  'Caché de la vente, proposé en premier en production.'),
            ),
            // The article's picture: the newest photo hung on the article is
            // what the vitrine, the à-la-une strip and the search all show.
            // Offered only in a build that knows where to send it: a button
            // that queues a photo nothing will ever send is a broken button.
            if (widget.capture != null && widget.capture!.isConfigured) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: _photoBytes != null
                            ? Image.memory(_photoBytes!,
                                fit: BoxFit.cover,
                                semanticLabel: "Photo de l'article")
                            : Icon(
                                _photoKnown
                                    ? Icons.image_outlined
                                    : Icons.hourglass_empty,
                                size: 26,
                                color: theme.colorScheme.outline,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              _busy || _photoBusy ? null : _changePhoto,
                          icon: _photoBusy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.photo_camera_outlined,
                                  size: 18),
                          label: Text(_photoBytes == null
                              ? 'Ajouter une photo'
                              : 'Changer la photo'),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'La photo paraît sur la vitrine et dans la '
                          'recherche.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            // The shop window: this article, visible to anyone with the
            // vitrine link — once the administrator has opened the vitrine in
            // the business settings. Off by default; the shop picks each one.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isPublished,
              onChanged:
                  _busy ? null : (v) => setState(() => _isPublished = v),
              title: const Text('Afficher sur la vitrine en ligne'),
              subtitle: const Text(
                  'Visible du public, avec sa photo et son prix, si la '
                  'vitrine de la boutique est ouverte.'),
            ),
            // What the shopkeeper would say across the counter, under the
            // name on the vitrine. Two sentences at most (300 characters,
            // the database's own limit); a tile that scrolls is a tile
            // nobody reads.
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              enabled: !_busy,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Description pour la vitrine (facultatif)',
                hintText: 'Taille, goût, origine — ce que le client demande '
                    'au comptoir.',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer', style: TextStyle(fontSize: 17)),
              ),
            ),
            if (widget.canArchive) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : _archive,
                icon: Icon(Icons.delete_outline,
                    color: theme.colorScheme.error),
                label: Text('Retirer de la boutique',
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Deleting", the honest way: the product leaves the shelves and the sale
  /// sheet; every sale, delivery and production it ever touched stays.
  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Retirer ${widget.product.name} ?'),
        content: const Text(
            'Le produit disparaîtra des listes et de la vente. '
            "L'historique de ses ventes et de son stock est conservé."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.retail.archiveProduct(widget.product.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(error);
        });
      }
    }
  }
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
                    decoration: InputDecoration(
                      labelText: 'Coût unitaire',
                      border: const OutlineInputBorder(),
                      // Goods bought in another currency: convert, and the
                      // field receives the home-currency figure.
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.currency_exchange, size: 20),
                        tooltip: 'Payé dans une autre monnaie',
                        onPressed: _busy
                            ? null
                            : () async {
                                final converted =
                                    await CurrencyConvertDialog.open(
                                  context,
                                  retail: widget.retail,
                                  orgId: widget.org.id,
                                  homeCurrency: widget.org.currency,
                                );
                                if (converted != null && mounted) {
                                  setState(() => _cost.text =
                                      converted.round().toString());
                                }
                              },
                      ),
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
