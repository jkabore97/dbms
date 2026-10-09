import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/nav/router.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/nav/app_scope.dart';
import '../capture/capture_action.dart';
import '../retail/article_flow.dart';
import '../retail/photo_quota.dart';
import '../retail/product_photo.dart';
import '../retail/stock_attention.dart';
import '../common/attention_banner.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../common/keyboard_sheet.dart';

/// What the farm sells on its vitrine (083): « À vendre ».
///
/// A farm grows what it sells, so this is not a shop's shelf: no barcode, no
/// purchase price, no delivery note booked as a purchase. Each line is what
/// a buyer asks across the fence — what it is, how much, by what (the tray,
/// the kg, the head), how many there are, and, for a batch still growing,
/// from which day. They are articles underneath, so orders, the basket,
/// delivery and payment work exactly as they do for a shop.
class ForSaleScreen extends StatefulWidget {
  const ForSaleScreen({
    super.key,
    required this.org,
    required this.retail,
    this.capture,
  });

  final OrgSummary org;
  final RetailRepository retail;
  final CaptureRepository? capture;

  @override
  State<ForSaleScreen> createState() => _ForSaleScreenState();
}

class _ForSaleScreenState extends State<ForSaleScreen> {
  List<Product> _items = const [];
  Map<String, String> _photos = const {};
  bool _loading = true;
  String? _error;

  bool get _canWrite => !widget.org.isObserverOnly;

  /// « À vendre sur la vitrine » hidden by Mara's switchboard (110): the list
  /// stays — the farm still sells at the farm — but nothing here reaches the
  /// vitrine, and it says so.
  bool get _offVitrine =>
      AppScope.maybeOf(context)?.session.accessFor(widget.org.id).isHidden('for_sale') ??
      false;

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
      final items = await widget.retail.products(widget.org.id);
      final photos = await widget.retail.photoKeys(widget.org.id);
      if (!mounted) return;
      setState(() {
        // What the farm grows; its services (098) have their own page.
        _items = [
          for (final p in items)
            if (!p.isService) p,
        ];
        _photos = photos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  /// « Mettre en vente » (115): the « Ajouter un produit » flow, one entry
  /// at a time, already on « pour vendre ».
  Future<void> _add() async {
    final saved = await ArticleFlow.open(context,
        org: widget.org,
        retail: widget.retail,
        capture: widget.capture,
        forSale: true);
    if (saved == true) await _load();
  }

  /// « Ajouter du stock » on an article (122): the same flow, on it — its
  /// name is enough for the flow to add what is ready.
  Future<void> _restock(Product p) async {
    final saved = await ArticleFlow.open(context,
        org: widget.org,
        retail: widget.retail,
        capture: widget.capture,
        forSale: true,
        initialName: p.name);
    if (saved == true) await _load();
  }

  /// What is already for sale: its price, its count, its photo, its words.
  Future<void> _open(Product product) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ForSaleSheet(
        org: widget.org,
        retail: widget.retail,
        capture: widget.capture,
        product: product,
        hasPhoto: _photos.containsKey(product.id),
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(widget.org.currency);
    final slug = widget.org.slug;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('À vendre')),
        actions: [
          if (slug != null && slug.isNotEmpty)
            TextButton.icon(
              key: const Key('see-vitrine'),
              onPressed: () => context.push(Routes.storefront(slug)),
              icon: const Icon(Icons.storefront_outlined),
              label: Text(context.tr('Ma vitrine')),
            ),
          bellRoom,
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              key: const Key('for-sale-add'),
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: Text(context.tr('Mettre en vente')),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            // Why « À vendre » has a red number (122), on top.
            if (!_loading && _error == null)
              StockAttention(
                products: _items,
                place: context.tr('À vendre'),
                onRestock: _canWrite ? _restock : null,
              ),
            if (_offVitrine)
              KajCard(
                key: const Key('for-sale-off-vitrine'),
                child: ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: Text(context.tr('Pas sur la vitrine pour le moment')),
                  subtitle: Text(context.tr('Mara a retiré vos produits de la vitrine. Gardez-les ici : vous les vendez toujours à la ferme.')),
                ),
              )
            else
            Text(
              context.tr('Œufs, volailles, récoltes : ce que vous mettez ici, avec sa photo et son prix, est sur votre vitrine. Les clients commandent, viennent le chercher à la ferme ou se le font livrer.'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    context.push(Routes.orgSettings(widget.org.id)),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(context.tr('Ouvrir ou régler la vitrine')),
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (_items.isEmpty)
              KajCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    context.tr('Rien en vente pour le moment. « Mettre en vente » : un plateau d\'œufs, un sac de maïs, une pintade…'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              )
            else
              for (final p in _items)
                KajCard(
                  key: ValueKey(p.id),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    onTap: _canWrite ? () => _open(p) : null,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: ProductPhoto(
                          name: p.name,
                          photoKey: _photos[p.id],
                          capture: widget.capture,
                        ),
                      ),
                    ),
                    title: Text(p.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: p.quantity <= 0 && _canWrite
                        // At zero, its own way back (122).
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_line(p, money)),
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
                        : Text(_line(p, money)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (stockChip(context, p) case final chip?)
                          AttentionChip(
                              key: ValueKey('product-chip-${p.id}'),
                              label: chip,
                              soft: p.quantity > 0),
                        if (!_offVitrine) ...[
                          const SizedBox(width: 6),
                          Icon(
                      p.isPublished
                          ? Icons.storefront
                          : Icons.visibility_off_outlined,
                      color: p.isPublished
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      semanticLabel:
                          p.isPublished ? context.tr('Sur la vitrine') : context.tr('Pas sur la vitrine'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static String _line(Product p, NumberFormat money) {
    final price = p.unit == null
        ? money.format(p.salePrice)
        : '${money.format(p.salePrice)} / ${p.unit}';
    final today = DateUtils.dateOnly(DateTime.now());
    final from = p.availableFrom;
    final when = from != null && from.isAfter(today)
        ? 'à partir du ${DateFormat('dd/MM').format(from)}'
        : '${_plain(p.quantity)} disponible${p.quantity > 1 ? 's' : ''}';
    return '$price · $when';
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';
}

/// One thing for sale: new or edited. Saved in one go.
class ForSaleSheet extends StatefulWidget {
  const ForSaleSheet({
    super.key,
    required this.org,
    required this.retail,
    this.capture,
    required this.product,
    this.hasPhoto = false,
  });

  final OrgSummary org;
  final RetailRepository retail;

  /// The article has a photo already: a new one takes no new place (100).
  final bool hasPhoto;
  final CaptureRepository? capture;

  /// What is edited. A new one is the « Ajouter un produit » flow (115).
  final Product product;

  @override
  State<ForSaleSheet> createState() => _ForSaleSheetState();
}

class _ForSaleSheetState extends State<ForSaleSheet> {
  /// The units a farm sells by, offered as one tap; anything else is typed.
  static const units = ['pièce', 'plateau', 'kg', 'sac', 'tête', 'litre'];

  late final _name = TextEditingController(text: widget.product.name);
  late final _price = TextEditingController(
      text: widget.product.salePrice == 0
          ? ''
          : _plain(widget.product.salePrice));
  late final _quantity = TextEditingController(
      text: _plain(widget.product.quantity));
  late final _unit = TextEditingController(text: widget.product.unit ?? '');
  late final _description =
      TextEditingController(text: widget.product.description ?? '');
  late DateTime? _availableFrom = widget.product.availableFrom;
  late bool _published = widget.product.isPublished;

  PickedPhoto? _photo;
  bool _busy = false;
  String? _error;

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(' ', '').replaceAll(',', '.'));

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _quantity.dispose();
    _unit.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    // Every place taken on Basic (100): one more first, or nothing.
    if (!await photoAllowed(context, widget.org, hasPhoto: widget.hasPhoto) || !mounted) {
      return;
    }
    final picked =
        await CaptureAction.pick(context, orgId: widget.org.id, photos: widget.capture);
    if (picked == null || !mounted) return;
    setState(() => _photo = picked);
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _availableFrom ?? today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Disponible à partir du',
    );
    if (picked != null) setState(() => _availableFrom = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = _num(_price);
    if (name.isEmpty || price == null || price < 0) {
      setState(() => _error = context.tr('Un nom et un prix, s\'il vous plaît.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = widget.product.id;
      await widget.retail.updateProduct(
        id,
        name: name,
        salePrice: price,
        quantity: _num(_quantity) ?? 0,
        unit: _unit.text,
        availableFrom: _availableFrom,
        clearAvailableFrom: _availableFrom == null,
        isPublished: _published,
        description: _description.text,
      );
      final capture = widget.capture;
      final photo = _photo;
      if (photo != null && capture != null) {
        final doc = await CaptureAction.hang(
          capture,
          orgId: widget.org.id,
          productId: id,
          name: name,
          photo: photo,
          hadPhoto: widget.hasPhoto,
        );
        if (doc != null) {
          if (mounted) await AppScope.read(context)?.session.reloadFeatures(widget.org.id);
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final product = widget.product;
    setState(() => _busy = true);
    try {
      await widget.retail.archiveProduct(product.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeError(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyboardSheet(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      // The fields scroll; the button stays above the keyboard (A6).
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('for-sale-save'),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(context.tr('Enregistrer'),
                        style: const TextStyle(fontSize: 16)),
              ),
            ),
        ],
      ),
      children: [
            Text(context.tr('Modifier'),
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: [
                InkWell(
                  key: const Key('for-sale-photo'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.capture == null || _busy ? null : _pickPhoto,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 76,
                      height: 76,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: _photo != null
                          ? Image.memory(_photo!.bytes, fit: BoxFit.cover)
                          : const Icon(Icons.add_a_photo_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    key: const Key('for-sale-name'),
                    controller: _name,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: context.tr('Quoi ?'),
                      hintText: context.tr('Œufs frais, poulets de chair…'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            PhotoCounter(org: widget.org, hasPhoto: widget.hasPhoto),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('for-sale-price'),
                    controller: _price,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr('Prix ({currency})', {'currency': widget.org.currency}),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('for-sale-unit'),
                    controller: _unit,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: context.tr('Par'),
                      hintText: context.tr('plateau, kg…'),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final u in units)
                  ChoiceChip(
                    label: Text(u),
                    selected: _unit.text.trim() == u,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _unit.text = u),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('for-sale-quantity'),
              controller: _quantity,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.tr('Combien en avez-vous ?'),
                suffixText: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              key: const Key('for-sale-later'),
              contentPadding: EdgeInsets.zero,
              value: _availableFrom != null,
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v) {
                        _pickDate();
                      } else {
                        setState(() => _availableFrom = null);
                      }
                    },
              title: Text(context.tr('Pas encore prêt')),
              subtitle: Text(_availableFrom == null
                  ? context.tr('Une bande ou une récolte à venir : les clients commandent à l\'avance.')
                  : 'Disponible à partir du '
                      '${DateFormat('dd/MM/yyyy').format(_availableFrom!)}'),
            ),
            TextField(
              controller: _description,
              enabled: !_busy,
              maxLength: 300,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: context.tr('En deux mots (facultatif)'),
                hintText: context.tr('Poulets fermiers de 2 kg, nourris au maïs.'),
                border: const OutlineInputBorder(),
              ),
            ),
            // Not offered while Mara keeps the farm's products off its
            // vitrine (110); the choice already made is kept.
            if (!(AppScope.maybeOf(context)
                    ?.session
                    .accessFor(widget.org.id)
                    .isHidden('for_sale') ??
                false))
            SwitchListTile(
              key: const Key('for-sale-published'),
              contentPadding: EdgeInsets.zero,
              value: _published,
              onChanged:
                  _busy ? null : (v) => setState(() => _published = v),
              title: Text(context.tr('Sur la vitrine')),
            ),
            ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _remove,
                child: Text(context.tr('Retirer de la vente')),
              ),
            ],
      ],
    );
  }
}
