import 'dart:async';
import '../../core/theme/kaj_card.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import 'package:intl/intl.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/retail/bulk_add.dart';
import '../../core/retail/models.dart';
import 'article_flow.dart';
import 'stock_attention.dart';
import '../common/attention_banner.dart';
import 'convert_dialog.dart';
import 'photo_quota.dart';
import 'product_photo.dart';
import '../../core/retail/retail_repository.dart';
import '../capture/barcode_sheet.dart';
import '../capture/capture_action.dart';
import '../admin/spots_card.dart';
import '../../core/nav/app_scope.dart';
import '../../core/errors.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../common/keyboard_sheet.dart';

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
    this.initialQuery,
  });

  /// What the search opens with: the article a « Stock bas » ring is about
  /// (099), so a tap on the bell lands on it.
  final String? initialQuery;

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

  /// Each article's picture, product id → photo key (079). Loaded beside
  /// the list, never in front of it: the shelves show first, the pictures
  /// fill in.
  Map<String, String> _photos = const {};

  /// List or cards, the owner's choice, remembered on this device.
  bool _cards = false;
  static const _viewKey = 'products_view';

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
    _search.text = widget.initialQuery?.trim() ?? '';
    _load();
    _readView();
  }

  Future<void> _readView() async {
    try {
      final v = await AppScope.read(context)?.db.readPref(_viewKey);
      if (mounted && v == 'cards') setState(() => _cards = true);
    } catch (_) {}
  }

  void _toggleView() {
    setState(() => _cards = !_cards);
    try {
      AppScope.read(context)?.db.writePref(_viewKey, _cards ? 'cards' : 'list');
    } catch (_) {}
  }

  Future<void> _loadPhotos() async {
    final photos = await widget.retail.photoKeys(widget.org.id);
    if (mounted) setState(() => _photos = photos);
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
        // The shelves hold goods; the services (098) have their own page.
        _products = [
          for (final p in products)
            if (!p.isService) p,
        ];
        _loading = false;
      });
      unawaited(_loadPhotos());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeError(error);
        _loading = false;
      });
    }
  }

  /// « Ajouter un article » (115): one entry at a time — a new article, or
  /// more of one already here (its name is enough).
  Future<void> _addStock() async {
    final added = await ArticleFlow.open(context,
        org: widget.org, retail: widget.retail, capture: widget.capture);
    if (added == true) await _load();
  }

  /// Twenty articles in one save: a box of lines, "nom quantité prix [coût]",
  /// for the shop being set up or the big market morning.
  Future<void> _bulkAdd() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
      useSafeArea: true,
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

    final code = await BarcodeSheet.scan(context, title: context.tr('Scanner un article'));
    if (code == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    for (final product in _products) {
      if (product.barcode == code) {
        messenger.showSnackBar(SnackBar(
          content: Text(context.tr('{name} — {n} en stock', {
            'name': product.name,
            'n': product.quantity.toStringAsFixed(0),
          })),
        ));
        return;
      }
    }

    try {
      final row = await capture.productByBarcode(widget.org.id, code);
      if (!mounted) return;

      if (row != null) {
        messenger.showSnackBar(
            SnackBar(content: Text(context.tr('{name} — déjà en stock', {'name': row['name']}))));
        return;
      }

      if (!mounted) return;
      final added = await ArticleFlow.open(context,
          org: widget.org,
          retail: widget.retail,
          capture: widget.capture,
          barcode: code);
      if (added == true) await _load();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  String _details(Product p) => [
        context.tr('{n} en stock', {'n': _trim(p.quantity)}),
        if (p.isIngredient) context.tr('ingrédient'),
        if (p.salePrice > 0) _money.format(p.salePrice),
        if (p.expiresOn != null)
          context.tr('expire le {date}', {'date': DateFormat('d MMM', intlLocale()).format(p.expiresOn!)}),
      ].join(' · ');

  /// The door to the vitrine, drawn on every article: the long press is a
  /// gesture nobody discovers, and "how do I put this in the window?" was
  /// the question. Filled when the article is already there, outlined when
  /// it is not; either way it opens the same sheet, where the switch and
  /// the photo are.
  Widget _vitrineButton(Product p, ThemeData theme) => IconButton(
        tooltip:
            p.isPublished ? context.tr('Sur la vitrine — modifier') : context.tr('Mettre sur la vitrine'),
        icon: Icon(
          p.isPublished ? Icons.storefront : Icons.storefront_outlined,
          color: p.isPublished
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        onPressed: widget.access.canEdit('products') ? () => _edit(p) : null,
      );

  /// « Rupture » at zero, « Bientôt épuisé » under the alert level (122):
  /// the rows the bar's red number counts.
  Widget? _stockChip(Product p) {
    final label = stockChip(context, p);
    return label == null
        ? null
        : AttentionChip(
            key: ValueKey('product-chip-${p.id}'),
            label: label,
            soft: p.quantity > 0);
  }

  /// « Ajouter du stock » on an article (122): the same entry as « Ajouter
  /// un article », opened on it — its name is enough for the flow to know
  /// it and add what arrived.
  Future<void> _restock(Product p) async {
    final added = await ArticleFlow.open(context,
        org: widget.org,
        retail: widget.retail,
        capture: widget.capture,
        initialName: p.name);
    if (added == true) await _load();
  }

  bool get _canRestock => widget.access.canEdit('products');

  // Long press, not tap, on purpose: a thumb scrolling the shelves must not
  // fall into a sheet that changes prices. And only for those the owner lets
  // edit at all.
  VoidCallback? _editGesture(Product p) =>
      widget.access.canEdit('products') ? () => _edit(p) : null;

  Widget _row(Product p, ThemeData theme) => KajCard(
        key: ValueKey('product-row-${p.id}'),
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest,
        child: ListTile(
          contentPadding: const EdgeInsets.only(left: 10, right: 4),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox.square(
              dimension: 52,
              child: ProductPhoto(
                name: p.name,
                photoKey: _photos[p.id],
                capture: widget.capture,
              ),
            ),
          ),
          title: Text(p.name),
          subtitle: p.quantity <= 0 && _canRestock
              // At zero, its own way back on the shelf (122).
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_details(p)),
                    TextButton.icon(
                      key: ValueKey('product-restock-${p.id}'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _restock(p),
                      icon: const Icon(Icons.add_box_outlined, size: 18),
                      label: Text(context.tr('Ajouter du stock')),
                    ),
                  ],
                )
              : Text(_details(p)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?_stockChip(p),
              _vitrineButton(p, theme),
            ],
          ),
          onLongPress: _editGesture(p),
        ),
      );

  Widget _card(Product p, ThemeData theme) => KajCard(
        key: ValueKey('product-card-${p.id}'),
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerHighest,
        child: InkWell(
          onLongPress: _editGesture(p),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProductPhoto(
                      name: p.name,
                      photoKey: _photos[p.id],
                      capture: widget.capture,
                      letterSize: 40,
                    ),
                    if (_stockChip(p) case final chip?)
                      Positioned(left: 6, top: 6, child: chip),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 0, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _details(p),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (p.quantity <= 0 && _canRestock)
                      IconButton(
                        key: ValueKey('product-restock-${p.id}'),
                        tooltip: context.tr('Ajouter du stock'),
                        onPressed: () => _restock(p),
                        icon: const Icon(Icons.add_box_outlined),
                      ),
                    _vitrineButton(p, theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

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
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Articles')),
        actions: [
          IconButton(
            key: const Key('products-view'),
            onPressed: _toggleView,
            icon: Icon(_cards ? Icons.view_list_outlined : Icons.grid_view),
            tooltip: _cards ? context.tr('Afficher en liste') : context.tr('Afficher en cartes'),
          ),
          if (widget.access.canEdit('products'))
            IconButton(
              onPressed: _bulkAdd,
              icon: const Icon(Icons.playlist_add),
              tooltip: context.tr('Ajout multiple'),
            ),
          if (widget.capture != null)
            IconButton(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: context.tr('Scanner un code-barres'),
            ),
          bellRoom,
        ],
      ),
      floatingActionButton: widget.access.canEdit('products')
          ? FloatingActionButton.extended(
              onPressed: _addStock,
              key: const Key('products-add'),
              icon: const Icon(Icons.add),
              label: Text(context.tr('Ajouter un article')),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        // Slivers, so a shop of two hundred articles builds — and fetches
        // the pictures of — only the ones on screen.
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  if (_products.isNotEmpty) ...[
                    // Why « Articles » has a red number (122), on top.
                    StockAttention(
                      products: _products,
                      place: context.tr('Articles'),
                      onRestock: _canRestock ? _restock : null,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // The count the owner asked for: how many articles
                        // the shop carries, and — next to it — how many items
                        // sit behind them in total. While a search narrows
                        // the list the article part says "shown / total" so
                        // the number on screen is never mistaken for the
                        // whole shelf; the item total always counts the
                        // whole shelf, not the filtered view.
                        Flexible(
                          child: Text(
                            '${_search.text.trim().isEmpty ? (_products.length > 1 ? context.tr('{n} articles', {'n': _products.length}) : context.tr('{n} article', {'n': _products.length})) : context.tr('{shown} / {n} articles', {'shown': visible.length, 'n': _products.length})}'
                                ' · ${context.tr('{n} en stock', {'n': _trim(totalItems)})}',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Text(context.tr('Valeur : {value}', {'value': _money.format(stockValue)}),
                            style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: context.tr('Rechercher un article…'),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: context.tr('Effacer'),
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
                          Text(
                            context.tr('Aucun article pour l\'instant.\nEnregistrez une entrée de stock, ou vendez directement — l\'article sera créé tout seul.'),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: _cards
                  ? SliverGrid(
                      // Two across on a phone, more on a tablet or a desk.
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.74,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _card(visible[i], theme),
                        childCount: visible.length,
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _row(visible[i], theme),
                        childCount: visible.length,
                      ),
                    ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
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
      setState(() => _error = context.tr('Écrivez au moins une ligne.'));
      return;
    }
    if (lines.any((l) => !l.ok)) {
      // Saving around a broken line would silently drop what somebody
      // typed; the preview already points at it.
      setState(() => _error = context.tr('Corrigez les lignes en rouge avant d\'enregistrer.'));
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
              '${context.tr('{n} ligne(s) déjà enregistrée(s) — retirez-les du texte avant de réessayer.', {'n': _saved})}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = parseBulkLines(_text.text);
    final good = lines.where((l) => l.ok).length;

    return KeyboardSheet(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      // The fields scroll; the button stays above the keyboard (A6).
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy || good == 0 ? null : _save,
                child: _busy
                    ? Text(context.tr('Enregistrement… {_saved}/{good}', {'_saved': _saved, 'good': good}))
                    : Text(context.tr('Enregistrer {good} article(s)', {'good': good}),
                        style: const TextStyle(fontSize: 17)),
              ),
            ),
        ],
      ),
      children: [
            Text(context.tr('Ajout multiple'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              context.tr('Un article par ligne : nom quantité prix (coût facultatif). Exemple : Savon 20 300 200'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              enabled: !_busy,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.tr('Savon 20 300\nSucre 1kg 10 600 450\nHuile 2,5 1500'),
                border: const OutlineInputBorder(),
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
                          '${l.costPrice != null ? context.tr(' (coût {costPrice})', {'costPrice': l.costPrice}) : ''}',
                          style: theme.textTheme.bodySmall,
                        )
                      : Text(
                          context.tr('Ligne {lineNumber} : {error}', {'lineNumber': l.lineNumber, 'error': l.error}),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                ),
            ],
      ],
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

  /// Mara's switchboard hid production for this business (104).
  bool get _productionHidden =>
      AppScope.maybeOf(context)?.session.accessFor(widget.org.id).isHidden('production') ??
      false;
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

  /// The article has a photo on the server: changing it takes no new place
  /// among the ten a Basic business keeps (100).
  bool _hasPhoto = false;

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
      if (mounted) setState(() => _hasPhoto = true);
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
    // Every place taken on Basic (100): one more first, or nothing.
    if (!await photoAllowed(context, widget.org, hasPhoto: _hasPhoto) || !mounted) {
      return;
    }
    final picked = await CaptureAction.pick(context, orgId: widget.org.id, photos: capture);
    if (picked == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final scope = AppScope.read(context);
    setState(() => _photoBusy = true);
    try {
      final id = await CaptureAction.hang(
        capture,
        orgId: widget.org.id,
        productId: widget.product.id,
        name: widget.product.name,
        photo: picked,
        hadPhoto: _hasPhoto,
      );
      if (id == null) {
        // Queued for later: the bytes are safe, but with no server id there
        // is nothing to hang on the article yet. Filing it from Documents
        // once it lands is the honest path, so say exactly that.
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(
          content: Text(context.tr('Photo gardée, en attente de réseau. Une fois envoyée, liez-la à l\'article depuis Documents.')),
        ));
        return;
      }
      await scope?.session.reloadFeatures(widget.org.id);
      if (!mounted) return;
      setState(() {
        _photoBytes = picked.bytes;
        _photoKnown = true;
        _hasPhoto = true;
      });
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr('Photo de l\'article enregistrée.')),
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

    return KeyboardSheet(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      // The fields scroll; the button stays above the keyboard (A6).
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
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
                    : Text(context.tr('Enregistrer'), style: const TextStyle(fontSize: 17)),
              ),
            ),
        ],
      ),
      children: [
            Text(widget.product.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              context.tr('{n} en stock — le stock bouge par les entrées, les ventes et la production',
                  {'n': _EditProductSheetState._plain(widget.product.quantity)}),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: context.tr('Nom du produit'),
                // Renaming cannot rewrite history — receipts snapshot names.
                helperText: context.tr('Les ventes déjà faites gardent l\'ancien nom.'),
                border: const OutlineInputBorder(),
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
                    decoration: InputDecoration(
                      labelText: context.tr('Prix de vente'),
                      border: const OutlineInputBorder(),
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
                      labelText: context.tr('Coût unitaire'),
                      border: const OutlineInputBorder(),
                      // Goods bought in another currency: convert, and the
                      // field receives the home-currency figure.
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.currency_exchange, size: 20),
                        tooltip: context.tr('Payé dans une autre monnaie'),
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
                context.tr('Attention : vendu en dessous de ce que ça coûte ({cost}).',
                    {'cost': _EditProductSheetState._plain(cost)}),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _low,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.tr('Seuil d\'alerte stock bas (facultatif)'),
                border: const OutlineInputBorder(),
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
                  ? context.tr('Date d\'expiration (facultatif)')
                  : context.tr('Expire le {date}',
                      {'date': DateFormat('d MMMM y', intlLocale()).format(_expiresOn!)})),
            ),
            const SizedBox(height: 4),
            // Production's own option: gone with production once Mara's
            // switchboard hid it (104) — unless the article already is an
            // ingredient, which must stay undoable (an ingredient is kept
            // off the till).
            if (!_productionHidden || widget.product.isIngredient)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isIngredient,
                onChanged:
                    _busy ? null : (v) => setState(() => _isIngredient = v),
                title: Text(context.tr('Ingrédient de production')),
                subtitle: Text(
                    context.tr('Caché de la vente, proposé en premier en production.')),
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
                                semanticLabel: context.tr('Photo de l\'article'))
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
                              ? context.tr('Ajouter une photo')
                              : context.tr('Changer la photo')),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('La photo paraît sur la vitrine et dans la recherche.'),
                          style: theme.textTheme.bodySmall,
                        ),
                        PhotoCounter(org: widget.org, hasPhoto: _hasPhoto),
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
              title: Text(context.tr('Afficher sur la vitrine en ligne')),
              subtitle: Text(
                  context.tr('Visible du public, avec sa photo et son prix, si la vitrine de la boutique est ouverte.')),
            ),
            // A spot on the street for this article (071), for the person
            // who pays for it; the sheet checks photo, price and stock.
            if (widget.org.isAdmin &&
                widget.product.isPublished &&
                AppScope.maybeOf(context) != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          final scope = AppScope.read(context)!;
                          SpotSheet.open(context,
                              orgId: widget.org.id,
                              admin: scope.admin,
                              retail: widget.retail,
                              isPro: widget.org.isPro,
                              productId: widget.product.id);
                        },
                  icon: const Icon(Icons.campaign_outlined),
                  label: Text(context.tr('Mettre cet article en avant')),
                ),
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
              decoration: InputDecoration(
                labelText: context.tr('Description pour la vitrine (facultatif)'),
                hintText: context.tr('Taille, goût, origine — ce que le client demande au comptoir.'),
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.canArchive) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : _archive,
                icon: Icon(Icons.delete_outline,
                    color: theme.colorScheme.error),
                label: Text(context.tr('Retirer de la boutique'),
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
      ],
    );
  }

  /// "Deleting", the honest way: the product leaves the shelves and the sale
  /// sheet; every sale, delivery and production it ever touched stays.
  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // The keyboard up on a small phone: the dialog scrolls (A6).
        scrollable: true,
        title: Text(context.tr('Retirer {name} ?', {'name': widget.product.name})),
        content: Text(
            context.tr('Le produit disparaîtra des listes et de la vente. L\'historique de ses ventes et de son stock est conservé.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('Annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('Retirer')),
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
