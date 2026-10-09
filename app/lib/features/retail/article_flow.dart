import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/db/local_db.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/retail/stock_rule.dart';
import '../capture/capture_action.dart';
import '../common/step_flow.dart';
import '../farm/farm_flows.dart';
import 'convert_dialog.dart';
import 'photo_quota.dart';

/// « Ajouter un article », one entry at a time (115) — for the shop and,
/// with the same steps, for the farm. One article or many: « Ajouter un
/// autre » starts again, « Terminé » goes back.
///
/// Photo (taken, chosen, or « Choisir dans Photos », 114) → name → selling
/// price → buying price (optional) → how many, and by what → the low-stock
/// alert (optional) → « Sur la vitrine ? » → « Utilisé en production ? » →
/// (the shop) expiry and serial number, (the farm) « pas encore prêt » →
/// the summary → « Enregistrer ».
///
/// A name the business already carries is that article: the flow says so,
/// skips what is already set (price, alert, vitrine, production) and adds
/// what arrived to its stock — the shop's « Entrée de stock », which this
/// flow replaces with its one-form sheet.
///
/// Writes through what existed: ensure_product() (idempotent by name),
/// receive_products() for what was bought (it books the purchase), and the
/// article's own row for the rest. A farm's article with no buying price
/// was grown, not bought: its count is set by hand and no purchase is
/// booked — as « À vendre » always did. Online, as both sheets were.
///
/// The farm keeps two kinds of things, and so does this flow's first step
/// on a farm: « C'est pour vendre » — an article (« À vendre », orders, the
/// vitrine, the till) — or « C'est une fourniture » — feed, medicine,
/// supplies, the items its animals consume (009's items and stock
/// movements). A supply hands over to the farm's « Réception » (W4's
/// FarmStockFlow.receive), whose first delivery creates the item, offline
/// as always. No row of either kind is converted.
class ArticleFlow extends StatefulWidget {
  const ArticleFlow({
    super.key,
    required this.org,
    required this.retail,
    this.capture,
    this.forSale = false,
    this.ingredient = false,
    this.initialName,
    this.initialQuantity,
    this.barcode,
    this.store,
  });

  final OrgSummary org;
  final RetailRepository retail;

  /// For the photo and « Choisir dans Photos ». Null: no photo step.
  final CaptureRepository? capture;

  /// The farm, opened from « À vendre »: no « pour vendre / fourniture »
  /// question — it is for sale.
  final bool forSale;

  /// « Utilisé en production ? » starts on Oui (Production's « Ajoutez
  /// d'abord vos ingrédients », W3).
  final bool ingredient;

  /// A refused offline sale's « Corriger le stock » (101): the article the
  /// server named and the number missing. A scanned code never seen: the
  /// code.
  final String? initialName;
  final double? initialQuantity;
  final String? barcode;

  final FlowStore? store;

  bool get farm => org.profile == 'farm';

  /// Opens the flow; on a farm, « C'est une fourniture » goes on to the
  /// farm's « Réception » ([db] is the phone's outbox it writes to). True
  /// once something was saved.
  static Future<bool?> open(
    BuildContext context, {
    required OrgSummary org,
    required RetailRepository retail,
    CaptureRepository? capture,
    LocalDb? db,
    bool forSale = false,
    bool ingredient = false,
    String? initialName,
    double? initialQuantity,
    String? barcode,
    FlowStore? store,
  }) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        fullscreenDialog: true,
        builder: (_) => ArticleFlow(
          org: org,
          retail: retail,
          capture: capture,
          // No phone outbox here: nothing to hand a supply to.
          forSale: forSale || db == null,
          ingredient: ingredient,
          initialName: initialName,
          initialQuantity: initialQuantity,
          barcode: barcode,
          store: store,
        ),
      ),
    );
    if (result == supply && db != null && context.mounted) {
      return FarmStockFlow.receive(context, db: db, org: org);
    }
    return result == true;
  }

  /// What the flow closes with when the farm's thing is a supply.
  static const supply = 'supply';

  @override
  State<ArticleFlow> createState() => _ArticleFlowState();
}

class _ArticleFlowState extends State<ArticleFlow> {
  final _flow = StepFlowController();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _quantity = TextEditingController();
  final _low = TextEditingController();
  final _serial = TextEditingController();
  String _unit = '';
  bool? _published;
  late bool _isIngredient = widget.ingredient;
  DateTime? _expiresOn;
  DateTime? _availableFrom;
  PickedPhoto? _photo;
  String? _kind; // the farm: 'sell' | supply

  /// The business's articles, to know a name already carried.
  List<Product> _products = const [];

  String _savedName = '';
  bool _photoWaits = false;

  bool get _farm => widget.farm;
  NumberFormat get _money => moneyFormat(widget.org.currency);

  static const _shopUnits = ['pièce', 'kg', 'litre', 'paquet', 'sac', 'carton'];
  static const _farmUnits = ['pièce', 'plateau', 'kg', 'sac', 'tête', 'litre'];

  bool _hidden(String feature) =>
      AppScope.maybeOf(context)?.session.accessFor(widget.org.id).isHidden(feature) ??
      false;

  /// The article of that name already on the shelves, if any.
  Product? get _existing {
    final n = _name.text.trim().toLowerCase();
    if (n.isEmpty) return null;
    for (final p in _products) {
      if (!p.isService && p.name.trim().toLowerCase() == n) return p;
    }
    return null;
  }

  bool get _vitrineOffered => !(_farm && _hidden('for_sale'));
  bool get _productionOffered => !_hidden('production') || widget.ingredient;

  @override
  void initState() {
    super.initState();
    _reset();
    _loadProducts();
  }

  void _reset() {
    _name.text = widget.initialName?.trim() ?? '';
    _price.clear();
    _cost.clear();
    _quantity.text =
        widget.initialQuantity == null ? '' : stockQty(widget.initialQuantity!);
    _low.clear();
    _serial.clear();
    _unit = '';
    _published = null;
    _isIngredient = widget.ingredient;
    _expiresOn = null;
    _availableFrom = null;
    _photo = null;
    _kind = _farm && !widget.forSale ? null : 'sell';
  }

  Future<void> _loadProducts() async {
    try {
      final products = await widget.retail.products(widget.org.id);
      if (mounted) setState(() => _products = products);
    } catch (_) {
      // No list: every name is new to the flow; ensure_product still finds
      // the one already there.
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _cost, _quantity, _low, _serial]) {
      c.dispose();
    }
    super.dispose();
  }

  // ----------------------------------------------------------------
  // The draft (the photo is not kept: it is taken again)
  // ----------------------------------------------------------------

  Map<String, Object?> _save() => {
        'kind': _kind,
        'name': _name.text,
        'price': _price.text,
        'cost': _cost.text,
        'qty': _quantity.text,
        'unit': _unit,
        'low': _low.text,
        'published': _published,
        'ingredient': _isIngredient,
        'serial': _serial.text,
        'expires': _expiresOn?.toIso8601String(),
        'available': _availableFrom?.toIso8601String(),
      };

  void _restore(Map<String, Object?> a) {
    setState(() {
      _reset();
      if (a.isEmpty) return;
      final kind = a['kind'];
      if (kind == 'sell') _kind = 'sell';
      _name.text = '${a['name'] ?? _name.text}';
      _price.text = '${a['price'] ?? ''}';
      _cost.text = '${a['cost'] ?? ''}';
      _quantity.text = '${a['qty'] ?? _quantity.text}';
      _unit = '${a['unit'] ?? ''}';
      _low.text = '${a['low'] ?? ''}';
      final published = a['published'];
      _published = published is bool ? published : null;
      final ingredient = a['ingredient'];
      _isIngredient = ingredient is bool ? ingredient : widget.ingredient;
      _serial.text = '${a['serial'] ?? ''}';
      _expiresOn = DateTime.tryParse('${a['expires'] ?? ''}');
      _availableFrom = DateTime.tryParse('${a['available'] ?? ''}');
    });
  }

  // ----------------------------------------------------------------
  // Saving
  // ----------------------------------------------------------------

  double? _num(TextEditingController c) => FlowNumberField.read(c);

  bool get _publishedValue => _published ?? _farm;

  Future<bool> _record() async {
    final existing = _existing;
    final name = existing?.name ?? _name.text.trim();
    final price = _num(_price);
    final cost = _num(_cost);
    final qty = _num(_quantity) ?? 0;
    final retail = widget.retail;
    final orgId = widget.org.id;

    final id = await retail.ensureProduct(
      orgId: orgId,
      name: name,
      salePrice: existing == null ? price : null,
      costPrice: cost,
      barcode: widget.barcode,
      expiresOn: _farm ? null : _expiresOn,
    );
    final serial = _serial.text.trim();
    if (!_farm && serial.isNotEmpty) await retail.setSerial(id, serial);
    // A farm's produce with no buying price was grown, not bought: counted
    // by hand, no purchase booked (as « À vendre », 083). Anything bought
    // is received: the count rises and the purchase is booked.
    final handCount = _farm && cost == null && qty > 0;
    if (qty > 0 && !handCount) {
      await retail.receive(
        orgId: orgId,
        productId: id,
        quantity: qty,
        unitCost: cost,
        expiresOn: _farm ? null : _expiresOn,
      );
    }
    if (existing == null) {
      await retail.updateProduct(
        id,
        unit: _unit.isEmpty ? null : _unit,
        lowStockAt: _num(_low),
        isPublished: _vitrineOffered ? _publishedValue : null,
        isIngredient: _productionOffered ? _isIngredient : null,
        availableFrom: _farm ? _availableFrom : null,
        quantity: handCount ? qty : null,
      );
    } else if (handCount) {
      await retail.updateProduct(id, quantity: existing.quantity + qty);
    }
    final photo = _photo;
    final capture = widget.capture;
    _photoWaits = false;
    if (photo != null && capture != null) {
      final doc = await CaptureAction.hang(
        capture,
        orgId: orgId,
        productId: id,
        name: name,
        photo: photo,
        hadPhoto: existing != null,
      );
      _photoWaits = doc == null;
      if (doc != null && mounted) {
        await AppScope.read(context)?.session.reloadFeatures(orgId);
      }
    }
    _savedName = name;
    await _loadProducts();
    return true;
  }

  void _another() {
    setState(_reset);
    _flow.restart();
  }

  Future<void> _pickPhoto() async {
    final capture = widget.capture;
    if (capture == null) return;
    // Every place taken on Basic (100): one more first, or nothing.
    if (!await photoAllowed(context, widget.org, hasPhoto: _existing != null) ||
        !mounted) {
      return;
    }
    final picked =
        await CaptureAction.pick(context, orgId: widget.org.id, photos: capture);
    if (picked == null || !mounted) return;
    setState(() => _photo = picked);
  }

  Future<void> _pickDate({required bool expiry}) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: (expiry ? _expiresOn : _availableFrom) ??
          today.add(Duration(days: expiry ? 30 : 7)),
      firstDate: expiry ? today.subtract(const Duration(days: 365)) : today,
      lastDate: today.add(const Duration(days: 365 * 5)),
    );
    if (picked == null || !mounted) return;
    setState(() => expiry ? _expiresOn = picked : _availableFrom = picked);
    _flow.keep();
  }

  // ----------------------------------------------------------------
  // The steps
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final existing = _existing;
    // Before the farm's answer the steps of « pour vendre » are counted:
    // the step bar does not jump from 2 to 10.
    final sell = _kind != ArticleFlow.supply;
    return StepFlow(
      title: _farm ? context.tr('Ajouter un produit') : context.tr('Ajouter un article'),
      controller: _flow,
      store: widget.store,
      draft: FlowDraft(
          key: 'article:${widget.org.id}', save: _save, restore: _restore),
      steps: [
        FlowStep(
          id: 'kind',
          title: context.tr('C\'est pour quoi ?'),
          shown: () => _farm && !widget.forSale,
          isValid: () => _kind == 'sell',
          builder: (_) => FlowChoice<String>(
            options: [
              FlowOption('sell', context.tr('C\'est pour vendre'),
                  icon: Icons.storefront_outlined,
                  detail: context.tr('Œufs, poulets, légumes… — dans « À vendre », sur la vitrine et à la vente.')),
              FlowOption(ArticleFlow.supply, context.tr('C\'est une fourniture'),
                  icon: Icons.inventory_2_outlined,
                  detail: context.tr('Aliment, médicaments, matériel — ce que la ferme utilise : une réception de stock.')),
            ],
            value: _kind,
            onChanged: (v) {
              if (v == ArticleFlow.supply) {
                // On to « Réception » (the farm's supplies, offline).
                Navigator.of(context).pop(ArticleFlow.supply);
                return;
              }
              setState(() => _kind = v);
            },
          ),
        ),
        FlowStep(
          id: 'photo',
          title: context.tr('Une photo ?'),
          help: context.tr('Elle paraît sur la vitrine et dans la recherche.'),
          optional: true,
          shown: () =>
              sell && widget.capture != null && widget.capture!.isConfigured,
          builder: _photoStep,
        ),
        FlowStep(
          id: 'name',
          title: _farm ? context.tr('Quel produit ?') : context.tr('Quel article ?'),
          isValid: () => _name.text.trim().isNotEmpty,
          shown: () => sell,
          builder: _nameStep,
        ),
        FlowStep(
          id: 'price',
          title: context.tr('Prix de vente ?'),
          shown: () => sell && existing == null,
          isValid: () => (_num(_price) ?? -1) >= 0,
          builder: (_) => FlowNumberField(
            key: const Key('article-price'),
            controller: _price,
            suffix: widget.org.currency == 'XOF' ? 'FCFA' : widget.org.currency,
            hint: '0',
            onChanged: (_) => setState(() {}),
          ),
        ),
        FlowStep(
          id: 'cost',
          title: context.tr('Prix d\'achat ?'),
          help: _farm
              ? context.tr('Seulement si vous l\'avez acheté pour le revendre — ce que vous produisez n\'en a pas.')
              : context.tr('Ce qu\'un article vous coûte : il fait votre marge.'),
          optional: true,
          shown: () => sell,
          isValid: () => _cost.text.trim().isEmpty || (_num(_cost) ?? -1) >= 0,
          builder: _costStep,
        ),
        FlowStep(
          id: 'quantity',
          title: existing == null
              ? context.tr('Combien en avez-vous ?')
              : context.tr('Combien arrivent ?'),
          help: existing == null
              ? null
              : context.tr('Déjà en stock : {n}', {'n': stockQty(existing.quantity)}),
          shown: () => sell,
          isValid: () => _quantity.text.trim().isEmpty || (_num(_quantity) ?? -1) >= 0,
          builder: _quantityStep,
        ),
        FlowStep(
          id: 'alert',
          title: context.tr('Prévenir quand il en reste peu ?'),
          help: context.tr('En dessous de ce nombre, Mara vous prévient.'),
          optional: true,
          shown: () => sell && existing == null,
          isValid: () => _low.text.trim().isEmpty || (_num(_low) ?? -1) >= 0,
          builder: (_) => FlowNumberField(
            key: const Key('article-low'),
            controller: _low,
            hint: '5',
            suffix: _unit.isEmpty ? null : _unit,
            onChanged: (_) => setState(() {}),
          ),
        ),
        FlowStep(
          id: 'vitrine',
          title: context.tr('Sur la vitrine ?'),
          help: context.tr('Visible du public, avec sa photo et son prix, si votre vitrine est ouverte.'),
          shown: () => sell && existing == null && _vitrineOffered,
          builder: (_) => FlowChoice<bool>(
            options: [
              FlowOption(true, context.tr('Oui, sur la vitrine'), icon: Icons.storefront),
              FlowOption(false, context.tr('Non, pas pour l\'instant'), icon: Icons.storefront_outlined),
            ],
            value: _publishedValue,
            onChanged: (v) {
              setState(() => _published = v);
              _flow.keep();
            },
          ),
        ),
        FlowStep(
          id: 'production',
          title: context.tr('Utilisé en production ?'),
          help: context.tr('Un ingrédient est caché de la vente et proposé en premier en production.'),
          shown: () => sell && existing == null && _productionOffered,
          builder: (_) => FlowChoice<bool>(
            options: [
              FlowOption(false, context.tr('Non, je le vends'), icon: Icons.sell_outlined),
              FlowOption(true, context.tr('Oui, c\'est un ingrédient'), icon: Icons.blender_outlined),
            ],
            value: _isIngredient,
            onChanged: (v) {
              setState(() => _isIngredient = v);
              _flow.keep();
            },
          ),
        ),
        FlowStep(
          id: 'details',
          title: _farm ? context.tr('Déjà prêt ?') : context.tr('Autres détails'),
          help: _farm
              ? context.tr('Une bande ou une récolte à venir : les clients commandent à l\'avance.')
              : null,
          optional: true,
          shown: () => sell && (!_farm || existing == null),
          builder: _detailsStep,
        ),
      ],
      summary: _summary,
      onSave: _record,
      done: (_) => FlowDone(
        message: context.tr('{name} ajouté', {'name': _savedName}),
        details: _photoWaits
            ? Text(
                context.tr('Photo gardée, en attente de réseau. Une fois envoyée, liez-la à l\'article depuis Documents.'),
                textAlign: TextAlign.center)
            : null,
        actions: [
          FlowAction(
            key: const Key('article-another'),
            label: _farm
                ? context.tr('Ajouter un autre produit')
                : context.tr('Ajouter un autre article'),
            icon: Icons.add,
            primary: true,
            onPressed: _another,
          ),
        ],
      ),
    );
  }

  Widget _photoStep(BuildContext context) {
    final theme = Theme.of(context);
    final photo = _photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: InkWell(
            key: const Key('article-photo'),
            borderRadius: BorderRadius.circular(16),
            onTap: _pickPhoto,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 200,
                height: 200,
                color: theme.colorScheme.surfaceContainerHighest,
                child: photo != null
                    ? Image.memory(photo.bytes,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined))
                    : Icon(Icons.add_a_photo_outlined,
                        size: 56, color: theme.colorScheme.outline),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: OutlinedButton.icon(
            key: const Key('article-photo-pick'),
            onPressed: _pickPhoto,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(photo == null
                ? context.tr('Prendre ou choisir une photo')
                : context.tr('Changer la photo')),
          ),
        ),
        if (photo != null)
          TextButton(
            onPressed: () => setState(() => _photo = null),
            child: Text(context.tr('Sans photo')),
          ),
        PhotoCounter(org: widget.org),
      ],
    );
  }

  Widget _nameStep(BuildContext context) {
    final theme = Theme.of(context);
    final q = _name.text.trim().toLowerCase();
    final existing = _existing;
    final like = q.length < 2 || existing != null
        ? const <Product>[]
        : [
            for (final p in _products)
              if (!p.isService && p.name.toLowerCase().contains(q)) p,
          ].take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('article-name'),
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          style: theme.textTheme.titleLarge,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: _farm
                ? context.tr('Œufs frais, poulets de chair…')
                : context.tr('Sucre 1kg'),
            border: const OutlineInputBorder(),
          ),
        ),
        if (existing != null) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('article-known'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(context.tr(
                'Déjà dans vos {things} : {n} en stock. On ajoute à son stock.',
                {
                  'things': _farm ? context.tr('produits') : context.tr('articles'),
                  'n': stockQty(existing.quantity),
                })),
          ),
        ],
        for (final p in like)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(p.name),
            subtitle: Text(context.tr('{n} en stock', {'n': stockQty(p.quantity)})),
            onTap: () => setState(() => _name.text = p.name),
          ),
      ],
    );
  }

  Widget _costStep(BuildContext context) {
    final existing = _existing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowNumberField(
          key: const Key('article-cost'),
          controller: _cost,
          hint: existing != null && existing.costPrice > 0
              ? stockQty(existing.costPrice)
              : '0',
          suffix: widget.org.currency == 'XOF' ? 'FCFA' : widget.org.currency,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        // Bought in another currency: converted, the home figure lands here.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.currency_exchange, size: 20),
            label: Text(context.tr('Payé dans une autre monnaie')),
            onPressed: () async {
              final converted = await CurrencyConvertDialog.open(
                context,
                retail: widget.retail,
                orgId: widget.org.id,
                homeCurrency: widget.org.currency,
              );
              if (converted != null && mounted) {
                setState(() => _cost.text = converted.round().toString());
              }
            },
          ),
        ),
        if (_num(_price) != null &&
            _num(_cost) != null &&
            _num(_price)! < _num(_cost)!)
          Text(
            context.tr('Attention : vendu en dessous de ce que ça coûte.'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  Widget _quantityStep(BuildContext context) {
    final existing = _existing;
    final unit = existing?.unit ?? _unit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowNumberField(
          key: const Key('article-quantity'),
          controller: _quantity,
          hint: '0',
          suffix: unit.isEmpty ? null : unit,
          onChanged: (_) => setState(() {}),
        ),
        if (existing == null) ...[
          const SizedBox(height: 16),
          Text(context.tr('Compté en'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final u in _farm ? _farmUnits : _shopUnits)
                ChoiceChip(
                  key: ValueKey('article-unit-$u'),
                  label: Text(u, style: const TextStyle(fontSize: 16)),
                  selected: _unit == u,
                  onSelected: (on) {
                    setState(() => _unit = on ? u : '');
                    _flow.keep();
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _detailsStep(BuildContext context) {
    if (_farm) {
      return FlowChoice<bool>(
        options: [
          FlowOption(false, context.tr('Oui, prêt à vendre'), icon: Icons.check_circle_outline),
          FlowOption(true, context.tr('Pas encore prêt'),
              icon: Icons.event_outlined,
              detail: _availableFrom == null
                  ? null
                  : context.tr('Disponible à partir du {date}',
                      {'date': DateFormat('dd/MM/yyyy').format(_availableFrom!)})),
        ],
        value: _availableFrom != null,
        onChanged: (later) {
          if (later) {
            _pickDate(expiry: false);
          } else {
            setState(() => _availableFrom = null);
          }
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: OutlinedButton.icon(
            key: const Key('article-expiry'),
            onPressed: () => _pickDate(expiry: true),
            icon: const Icon(Icons.event_outlined),
            label: Text(_expiresOn == null
                ? context.tr('Date d\'expiration (facultatif)')
                : context.tr('Expire le {date}',
                    {'date': DateFormat('d MMMM y', 'fr_FR').format(_expiresOn!)})),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('article-serial'),
          controller: _serial,
          decoration: InputDecoration(
            labelText: context.tr('Numéro de série (facultatif)'),
            helperText: context.tr('Pour un téléphone, une radio, un panneau…'),
            border: const OutlineInputBorder(),
          ),
        ),
        if (widget.barcode != null) ...[
          const SizedBox(height: 12),
          Text(context.tr('Code-barres scanné : {barcode}', {'barcode': widget.barcode})),
        ],
      ],
    );
  }

  Widget _summary(BuildContext context) {
    final existing = _existing;
    final qty = _num(_quantity) ?? 0;
    final unit = existing?.unit ?? _unit;
    String yes(bool v) => v ? context.tr('Oui') : context.tr('Non');
    return FlowSummary(
      rows: [
        FlowSummaryRow(_farm ? context.tr('Produit') : context.tr('Article'),
            existing?.name ?? _name.text.trim(),
            step: 'name', bold: true),
        if (_photo != null) FlowSummaryRow(context.tr('Photo'), context.tr('Oui'), step: 'photo'),
        if (existing == null)
          FlowSummaryRow(context.tr('Prix de vente'), _money.format(_num(_price) ?? 0),
              step: 'price'),
        if (_num(_cost) != null)
          FlowSummaryRow(context.tr('Prix d\'achat'), _money.format(_num(_cost)!),
              step: 'cost'),
        FlowSummaryRow(
            existing == null ? context.tr('En stock') : context.tr('Arrivent'),
            '${stockQty(qty)}${unit.isEmpty ? '' : ' $unit'}',
            step: 'quantity'),
        if (existing != null)
          FlowSummaryRow(context.tr('Stock après'),
              stockQty(existing.quantity + qty)),
        if (existing == null && _num(_low) != null)
          FlowSummaryRow(context.tr('Alerte stock bas'), stockQty(_num(_low)!), step: 'alert'),
        if (existing == null && _vitrineOffered)
          FlowSummaryRow(context.tr('Sur la vitrine'), yes(_publishedValue), step: 'vitrine'),
        if (existing == null && _productionOffered)
          FlowSummaryRow(context.tr('Utilisé en production'), yes(_isIngredient),
              step: 'production'),
        if (_expiresOn != null && !_farm)
          FlowSummaryRow(context.tr('Expire le'),
              DateFormat('dd/MM/yyyy').format(_expiresOn!), step: 'details'),
        if (_serial.text.trim().isNotEmpty && !_farm)
          FlowSummaryRow(context.tr('Numéro de série'), _serial.text.trim(), step: 'details'),
        if (_availableFrom != null && _farm)
          FlowSummaryRow(context.tr('Disponible à partir du'),
              DateFormat('dd/MM/yyyy').format(_availableFrom!), step: 'details'),
      ],
      footer: _farm && _num(_cost) == null && qty > 0
          ? Text(context.tr('Produit par la ferme : compté, sans achat.'),
              style: Theme.of(context).textTheme.bodySmall)
          : null,
    );
  }
}
