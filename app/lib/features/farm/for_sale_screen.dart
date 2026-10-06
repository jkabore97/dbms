import 'dart:typed_data';

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
import '../capture/capture_action.dart';
import '../retail/product_photo.dart';

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
        _items = items;
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

  Future<void> _open([Product? product]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ForSaleSheet(
        org: widget.org,
        retail: widget.retail,
        capture: widget.capture,
        product: product,
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
        title: const Text('À vendre'),
        actions: [
          if (slug != null && slug.isNotEmpty)
            TextButton.icon(
              key: const Key('see-vitrine'),
              onPressed: () => context.push(Routes.storefront(slug)),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Ma vitrine'),
            ),
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              key: const Key('for-sale-add'),
              onPressed: () => _open(),
              icon: const Icon(Icons.add),
              label: const Text('Mettre en vente'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Text(
              'Œufs, volailles, récoltes : ce que vous mettez ici, avec sa '
              'photo et son prix, est sur votre vitrine. Les clients '
              'commandent, viennent le chercher à la ferme ou se le font '
              'livrer.',
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
                label: const Text('Ouvrir ou régler la vitrine'),
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
                    'Rien en vente pour le moment. « Mettre en vente » : un '
                    'plateau d\'œufs, un sac de maïs, une pintade…',
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
                    subtitle: Text(_line(p, money)),
                    trailing: Icon(
                      p.isPublished
                          ? Icons.storefront
                          : Icons.visibility_off_outlined,
                      color: p.isPublished
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      semanticLabel:
                          p.isPublished ? 'Sur la vitrine' : 'Pas sur la vitrine',
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
    this.product,
  });

  final OrgSummary org;
  final RetailRepository retail;
  final CaptureRepository? capture;
  final Product? product;

  @override
  State<ForSaleSheet> createState() => _ForSaleSheetState();
}

class _ForSaleSheetState extends State<ForSaleSheet> {
  /// The units a farm sells by, offered as one tap; anything else is typed.
  static const units = ['pièce', 'plateau', 'kg', 'sac', 'tête', 'litre'];

  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _price = TextEditingController(
      text: widget.product == null || widget.product!.salePrice == 0
          ? ''
          : _plain(widget.product!.salePrice));
  late final _quantity = TextEditingController(
      text: widget.product == null ? '' : _plain(widget.product!.quantity));
  late final _unit = TextEditingController(text: widget.product?.unit ?? '');
  late final _description =
      TextEditingController(text: widget.product?.description ?? '');
  late DateTime? _availableFrom = widget.product?.availableFrom;
  late bool _published = widget.product?.isPublished ?? true;

  Uint8List? _photo;
  String? _photoType;
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
    final picked = await CaptureAction.pick(context);
    if (picked == null || !mounted) return;
    setState(() {
      _photo = picked.bytes;
      _photoType = picked.contentType;
    });
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
      setState(() => _error = 'Un nom et un prix, s\'il vous plaît.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = widget.product?.id ??
          await widget.retail.ensureProduct(
              orgId: widget.org.id, name: name, salePrice: price);
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
      if (_photo != null && capture != null) {
        final doc = await capture.capture(
          orgId: widget.org.id,
          bytes: _photo!,
          contentType: _photoType ?? 'image/jpeg',
          kind: 'product_photo',
          caption: name,
        );
        if (doc != null) {
          await capture.file(documentId: doc, productId: id);
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
    if (product == null) return;
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
    final editing = widget.product != null;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Modifier' : 'Mettre en vente',
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
                          ? Image.memory(_photo!, fit: BoxFit.cover)
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
                    decoration: const InputDecoration(
                      labelText: 'Quoi ?',
                      hintText: 'Œufs frais, poulets de chair…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
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
                      labelText: 'Prix (${widget.org.currency})',
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
                    decoration: const InputDecoration(
                      labelText: 'Par',
                      hintText: 'plateau, kg…',
                      border: OutlineInputBorder(),
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
                labelText: 'Combien en avez-vous ?',
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
              title: const Text('Pas encore prêt'),
              subtitle: Text(_availableFrom == null
                  ? 'Une bande ou une récolte à venir : les clients '
                      'commandent à l\'avance.'
                  : 'Disponible à partir du '
                      '${DateFormat('dd/MM/yyyy').format(_availableFrom!)}'),
            ),
            TextField(
              controller: _description,
              enabled: !_busy,
              maxLength: 300,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'En deux mots (facultatif)',
                hintText: 'Poulets fermiers de 2 kg, nourris au maïs.',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              key: const Key('for-sale-published'),
              contentPadding: EdgeInsets.zero,
              value: _published,
              onChanged:
                  _busy ? null : (v) => setState(() => _published = v),
              title: const Text('Sur la vitrine'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 12),
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
                    : Text(editing ? 'Enregistrer' : 'Mettre en vente',
                        style: const TextStyle(fontSize: 16)),
              ),
            ),
            if (editing) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _remove,
                child: const Text('Retirer de la vente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
