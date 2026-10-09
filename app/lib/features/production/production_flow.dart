import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/production/picker_order.dart';
import '../../core/production/production_repository.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../common/step_flow.dart';

/// « Production », one question a screen (115) — for a shop and a farm (an
/// association has no production tool). What you made → what you used →
/// how much of each → how many you made → the price, if you want one →
/// the summary with what it cost, through the same `record_production()`
/// (026) the sheet it replaces wrote: the server moves the counts and the
/// cost, online only as before.
///
/// What is cooked with is the articles marked « Utilisé en production »
/// (products.is_ingredient), recently used ones first ([orderForPicking]).
/// With none marked, the step says how to mark them and opens the article
/// flow with that box already ticked ([addIngredients]); back here, the
/// list is read again and the flow goes on where it was.
class ProductionFlow extends StatefulWidget {
  const ProductionFlow({
    super.key,
    required this.org,
    required this.production,
    required this.retail,
    this.recentNames = const {},
    this.repeat,
    this.addIngredients,
    this.store,
  });

  final OrgSummary org;
  final ProductionRepository production;
  final RetailRepository retail;

  /// Lowercased ingredient names from the history on screen.
  final Set<String> recentNames;

  /// « Refaire »: a past run's name, quantity and ingredients, prefilled.
  final ProductionRun? repeat;

  /// Opens the article flow with « Utilisé en production » ticked; resolves
  /// when it closes. Null: the button is not drawn.
  final Future<void> Function(BuildContext context)? addIngredients;

  /// The draft's store (tests); the device's preferences by default.
  final FlowStore? store;

  @override
  State<ProductionFlow> createState() => _ProductionFlowState();
}

class _ProductionFlowState extends State<ProductionFlow> {
  final _flow = StepFlowController();
  final _name = TextEditingController();
  final _made = TextEditingController();
  final _price = TextEditingController();
  final _search = TextEditingController();

  /// Ingredient id → its quantity field, in the order they were picked.
  final Map<String, TextEditingController> _used = {};

  /// Names of a repeated run not found among today's articles.
  List<String> _missing = const [];

  List<Product> _products = const [];
  bool _loading = true;
  bool _all = false;
  String? _loadError;

  NumberFormat get _money => moneyFormat(widget.org.currency);
  late final _qty = NumberFormat.decimalPattern('fr_FR');

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';

  @override
  void initState() {
    super.initState();
    final r = widget.repeat;
    if (r != null) {
      _name.text = r.productName;
      _made.text = _plain(r.quantity);
    }
    _load(first: true);
  }

  @override
  void dispose() {
    for (final c in [_name, _made, _price, _search, ..._used.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final products = await widget.retail.products(widget.org.id);
      if (!mounted) return;
      setState(() {
        // A service (098) is never cooked with.
        _products = orderForPicking(
            [for (final p in products) if (!p.isService) p], widget.recentNames);
        _loading = false;
        if (first) _resolveRepeat();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = context.tr('Les articles ne se chargent pas. Vérifiez la connexion.');
      });
    }
  }

  /// A repeated run arrives with names: today's articles of those names,
  /// with the quantities of the last time. One gone since is said.
  void _resolveRepeat() {
    final r = widget.repeat;
    if (r == null || _used.isNotEmpty) return;
    final missing = <String>[];
    for (final i in r.inputs) {
      final wanted = i.name.trim().toLowerCase();
      final p = _products
          .where((p) => p.name.trim().toLowerCase() == wanted)
          .firstOrNull;
      if (p == null) {
        missing.add(i.name);
      } else {
        _used[p.id] = TextEditingController(text: _plain(i.quantity));
      }
    }
    _missing = missing;
  }

  Product? _product(String id) =>
      _products.where((p) => p.id == id).firstOrNull;

  double? _num(TextEditingController c) => FlowNumberField.read(c);

  bool get _anyMarked => _products.any((p) =>
      p.isIngredient || widget.recentNames.contains(p.name.trim().toLowerCase()));

  /// What the list shows: the marked and the recently used, or all.
  List<Product> get _choices {
    final q = _search.text.trim().toLowerCase();
    final made = _name.text.trim().toLowerCase();
    return [
      for (final p in _products)
        if ((_all ||
                p.isIngredient ||
                _used.containsKey(p.id) ||
                widget.recentNames.contains(p.name.trim().toLowerCase())) &&
            p.name.trim().toLowerCase() != made &&
            (q.isEmpty || p.name.toLowerCase().contains(q)))
          p,
    ];
  }

  void _toggle(Product p) => setState(() {
        final c = _used.remove(p.id);
        if (c != null) {
          c.dispose();
        } else {
          _used[p.id] = TextEditingController();
        }
      });

  bool get _quantitiesValid =>
      _used.isNotEmpty && _used.values.every((c) => (_num(c) ?? 0) > 0);

  double get _totalCost {
    var total = 0.0;
    _used.forEach((id, c) {
      total += (_num(c) ?? 0) * (_product(id)?.costPrice ?? 0);
    });
    return total;
  }

  double? get _unitCost {
    final made = _num(_made);
    if (made == null || made <= 0) return null;
    return _totalCost / made;
  }

  String _unitOf(Product p) =>
      (p.unit ?? '').trim().isEmpty ? '' : ' ${p.unit!.trim()}';

  Future<void> _addIngredients() async {
    final open = widget.addIngredients;
    if (open == null) return;
    await open(context);
    if (mounted) await _load();
  }

  Future<bool> _save() async {
    final made = _num(_made)!;
    await widget.production.record(
      orgId: widget.org.id,
      productName: _name.text.trim(),
      quantity: made,
      inputs: [
        for (final e in _used.entries)
          ProductionInputDraft(productId: e.key, quantity: _num(e.value)!),
      ],
    );
    await _setSalePrice();
    return true;
  }

  /// The shelf price, set in the same gesture. The run is the record: if
  /// this second write fails the production stands, and the price is still
  /// set from Articles — never allowed to undo a run already written.
  Future<void> _setSalePrice() async {
    final price = _num(_price);
    if (price == null || price <= 0) return;
    try {
      final made = _name.text.trim().toLowerCase();
      final products = await widget.retail.products(widget.org.id);
      for (final p in products) {
        if (p.name.trim().toLowerCase() == made) {
          await widget.retail.updateProduct(p.id, salePrice: price);
          return;
        }
      }
    } catch (_) {}
  }

  void _again() {
    setState(() {
      _name.clear();
      _made.clear();
      _price.clear();
      for (final c in _used.values) {
        c.dispose();
      }
      _used.clear();
      _missing = const [];
    });
    _flow.restart();
  }

  Map<String, Object?> _toJson() => {
        'name': _name.text,
        'made': _made.text,
        'price': _price.text,
        'used': {for (final e in _used.entries) e.key: e.value.text},
      };

  void _fromJson(Map<String, Object?> a) => setState(() {
        _name.text = (a['name'] as String?) ?? '';
        _made.text = (a['made'] as String?) ?? '';
        _price.text = (a['price'] as String?) ?? '';
        for (final c in _used.values) {
          c.dispose();
        }
        _used.clear();
        final used = a['used'];
        if (used is Map) {
          used.forEach((k, v) =>
              _used['$k'] = TextEditingController(text: '${v ?? ''}'));
        }
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cur = _money.currencySymbol;
    final unit = _unitCost;
    final price = _num(_price);
    return StepFlow(
      title: context.tr('Production'),
      controller: _flow,
      store: widget.store,
      draft: FlowDraft(
          key: 'production:${widget.org.id}', save: _toJson, restore: _fromJson),
      steps: [
        FlowStep(
          id: 'made',
          title: context.tr('Qu\'avez-vous fabriqué ?'),
          help: context.tr('Le produit fini : pain, savon, jus, aliment…'),
          isValid: () => _name.text.trim().isNotEmpty,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('production-name'),
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.titleLarge,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.tr('Ex. Gâteaux, Savon liquide'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        FlowStep(
          id: 'inputs',
          title: context.tr('Qu\'avez-vous utilisé ?'),
          help: context.tr('Touchez chaque ingrédient.'),
          isValid: () => _used.isNotEmpty,
          builder: (_) => _inputsStep(theme),
        ),
        FlowStep(
          id: 'quantities',
          title: context.tr('Combien de chaque ?'),
          isValid: () => _quantitiesValid,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, e) in _used.entries.indexed) ...[
                _quantityRow(theme, e.key, e.value, autofocus: i == 0),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
        FlowStep(
          id: 'output',
          title: context.tr('Combien de {name} avez-vous fait ?',
              {'name': _name.text.trim()}),
          isValid: () => (_num(_made) ?? 0) > 0,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowNumberField(
                key: const Key('production-made'),
                controller: _made,
                onChanged: (_) => setState(() {}),
              ),
              if (unit != null) ...[
                const SizedBox(height: 16),
                Text(
                  context.tr('Un coûte {cost}', {'cost': _money.format(unit)}),
                  key: const Key('production-unit-cost'),
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
        FlowStep(
          id: 'price',
          title: context.tr('À combien le vendrez-vous ?'),
          help: context.tr('Le prix d\'un, sur l\'étagère et la vitrine.'),
          optional: true,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowNumberField(
                key: const Key('production-price'),
                controller: _price,
                suffix: cur,
                onChanged: (_) => setState(() {}),
              ),
              if (unit != null) ...[
                const SizedBox(height: 12),
                Text(context.tr('Un vous coûte {cost}', {'cost': _money.format(unit)})),
                // The comparison the flow is for: the price against the cost.
                if (price != null && price > 0 && price < unit) ...[
                  const SizedBox(height: 6),
                  Text(context.tr('Ce prix est en dessous de ce que vous coûte un.'),
                      key: const Key('production-below-cost'),
                      style: TextStyle(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600)),
                ],
              ],
            ],
          ),
        ),
      ],
      summary: (_) => FlowSummary(
        rows: [
          FlowSummaryRow(context.tr('Fabriqué'),
              '${_qty.format(_num(_made) ?? 0)} × ${_name.text.trim()}',
              step: 'made', bold: true),
          for (final e in _used.entries)
            FlowSummaryRow(
                _product(e.key)?.name ?? '—',
                '${_qty.format(_num(e.value) ?? 0)}'
                '${_product(e.key) == null ? '' : _unitOf(_product(e.key)!)}',
                step: 'quantities'),
          FlowSummaryRow(context.tr('Coût total'),
              _money.format(_totalCost)),
          FlowSummaryRow(context.tr('Coût d\'un'),
              unit == null ? '—' : _money.format(unit),
              bold: true),
          if (price != null && price > 0)
            FlowSummaryRow(context.tr('Prix de vente'),
                _money.format(price), step: 'price'),
        ],
        footer: _totalCost == 0
            ? Text(
                context.tr('Vos ingrédients n\'ont pas de prix d\'achat : le coût est compté à 0. Notez leur prix d\'achat dans Articles.'),
                style: theme.textTheme.bodySmall)
            : null,
      ),
      onSave: _save,
      done: (_) => FlowDone(
        message: context.tr('{qty} × {name} fabriqués', {
          'qty': _qty.format(_num(_made) ?? 0),
          'name': _name.text.trim(),
        }),
        details: unit == null
            ? null
            : Text(
                context.tr('Un coûte {cost}. Le stock de vos ingrédients a baissé, celui de {name} a monté.',
                    {'cost': _money.format(unit), 'name': _name.text.trim()}),
                textAlign: TextAlign.center),
        actions: [
          FlowAction(
            key: const Key('production-again'),
            label: context.tr('Fabriquer autre chose'),
            icon: Icons.precision_manufacturing_outlined,
            onPressed: _again,
          ),
        ],
      ),
    );
  }

  Widget _inputsStep(ThemeData theme) {
    if (_loading && _products.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null && _products.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_loadError!),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
        ],
      );
    }
    final choices = _choices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_anyMarked) ...[
          Container(
            key: const Key('production-none-marked'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('Ajoutez d\'abord vos ingrédients comme articles et cochez « Utilisé en production ».'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(context.tr('Ensuite revenez ici : vous continuez où vous étiez.'),
                    style: theme.textTheme.bodyMedium),
                if (widget.addIngredients != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      key: const Key('production-add-ingredient'),
                      onPressed: _addIngredients,
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('Ajouter un ingrédient')),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_missing.isNotEmpty) ...[
          Text(
            context.tr('Plus dans vos articles : {names}', {'names': _missing.join(', ')}),
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],
        if (_all || _products.length > 8)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.tr('Chercher un article'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        for (final p in choices) ...[
          _IngredientTile(
            product: p,
            picked: _used.containsKey(p.id),
            stock: '${_qty.format(p.quantity)}${_unitOf(p)}',
            onTap: () => _toggle(p),
          ),
          const SizedBox(height: 8),
        ],
        if (choices.isEmpty && _anyMarked)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.tr('Aucun article trouvé.'),
                textAlign: TextAlign.center),
          ),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                key: const Key('production-all'),
                onPressed: () => setState(() => _all = !_all),
                icon: Icon(_all ? Icons.filter_list : Icons.list),
                label: Text(_all
                    ? context.tr('Seulement les ingrédients')
                    : context.tr('Voir tous mes articles')),
              ),
            ),
            if (_anyMarked && widget.addIngredients != null)
              Expanded(
                child: TextButton.icon(
                  key: const Key('production-add-ingredient'),
                  onPressed: _addIngredients,
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('Ajouter un ingrédient')),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _quantityRow(ThemeData theme, String id, TextEditingController c,
      {bool autofocus = false}) {
    final p = _product(id);
    final typed = _num(c) ?? 0;
    final over = p != null && typed > p.quantity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(p?.name ?? '—',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          key: Key('production-qty-$id'),
          controller: c,
          autofocus: autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: theme.textTheme.titleLarge,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            suffixText: p == null ? null : _unitOf(p).trim(),
            border: const OutlineInputBorder(),
            helperText: p == null
                ? null
                : context.tr('En stock : {n}', {'n': '${_qty.format(p.quantity)}${_unitOf(p)}'}),
          ),
        ),
        if (over)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                context.tr('Plus que votre stock : il passera en dessous de zéro.'),
                style: TextStyle(color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}

class _IngredientTile extends StatelessWidget {
  const _IngredientTile({
    required this.product,
    required this.picked,
    required this.stock,
    required this.onTap,
  });

  final Product product;
  final bool picked;
  final String stock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: picked
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: picked ? theme.colorScheme.primary : Colors.transparent,
            width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('production-pick-${product.id}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(picked ? Icons.check_box : Icons.check_box_outline_blank,
                    color: picked ? theme.colorScheme.primary : null),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(context.tr('En stock : {n}', {'n': stock}),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (product.isIngredient)
                  const Icon(Icons.precision_manufacturing_outlined, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
