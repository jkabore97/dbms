import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/production/picker_order.dart';
import '../../core/production/production_repository.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../../l10n/strings.dart';

/// The transformation tool: ingredients in, a product out, and the app doing
/// the division the maker used to do in her head.
///
/// The list shows each past run with what it consumed and what one unit came
/// out costing. The sheet records a new one: name what was made, how many,
/// and which products went into it — the server moves the counts and the
/// cost, and every later sale of the product carries that cost as its margin
/// base.
class ProductionScreen extends StatefulWidget {
  const ProductionScreen({
    super.key,
    required this.org,
    required this.production,
    required this.retail,
    this.access = OrgAccess.allEdit,
  });

  /// The owner's dial: at 'view' the history reads, nothing records.
  final OrgAccess access;

  final OrgSummary org;
  final ProductionRepository production;
  final RetailRepository retail;

  @override
  State<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen> {
  List<ProductionRun> _runs = const [];
  bool _loading = true;
  String? _error;
  late final _money = NumberFormat.decimalPattern('fr_FR');
  late final _qty = NumberFormat.decimalPattern('fr_FR');

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
      final runs = await widget.production.history(widget.org.id);
      if (!mounted) return;
      setState(() {
        _runs = runs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  /// Lowercased ingredient names from the runs on screen — what this
  /// business actually cooks with, used to float those products to the top
  /// of the picker. No schema, no extra fetch: the history is already here.
  Set<String> get _recentNames => {
        for (final r in _runs)
          for (final i in r.inputs) i.name.trim().toLowerCase(),
      };

  Future<void> _create({ProductionRun? repeat}) async {
    final made = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewProductionSheet(
        org: widget.org,
        production: widget.production,
        retail: widget.retail,
        recentNames: _recentNames,
        repeat: repeat,
      ),
    );
    if (made == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final dates = DateFormat('d MMM', 'fr_FR');
    return Scaffold(
      appBar: AppBar(title: Text(strings.production)),
      floatingActionButton: !widget.access.canEdit('production')
          ? null
          : FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.soup_kitchen_outlined),
        label: Text(strings.newProduction),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _runs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(strings.noProduction,
                            textAlign: TextAlign.center),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        for (final r in _runs)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_qty.format(r.quantity)} × ${r.productName}',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${strings.unitCostIs(_money.format(r.unitCost))} · '
                                    '${dates.format(r.occurredAt.toLocal())}',
                                  ),
                                  if (r.inputs.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      r.inputs
                                          .map((i) =>
                                              '${_qty.format(i.quantity)} ${i.name}')
                                          .join(' · '),
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  if (widget.access.canEdit('production'))
                                  Align(
                                    alignment: Alignment.centerRight,
                                    // Day two of any real bakery: the same
                                    // cakes as yesterday. One tap brings the
                                    // whole recipe back; only the quantities
                                    // are left to confirm.
                                    child: TextButton.icon(
                                      onPressed: () => _create(repeat: r),
                                      icon: const Icon(Icons.replay, size: 18),
                                      label: Text(strings.makeAgain),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}

class _NewProductionSheet extends StatefulWidget {
  const _NewProductionSheet({
    required this.org,
    required this.production,
    required this.retail,
    this.recentNames = const {},
    this.repeat,
  });

  final OrgSummary org;
  final ProductionRepository production;
  final RetailRepository retail;

  /// Lowercased ingredient names from recent runs; floats them to the top
  /// of the picker.
  final Set<String> recentNames;

  /// A past run to make again: prefills the product, the quantity and the
  /// whole ingredient list, leaving only the numbers to confirm.
  final ProductionRun? repeat;

  @override
  State<_NewProductionSheet> createState() => _NewProductionSheetState();
}

class _IngredientRow {
  Product? product;
  final quantity = TextEditingController();

  void dispose() => quantity.dispose();
}

class _NewProductionSheetState extends State<_NewProductionSheet> {
  late final _name = TextEditingController(text: widget.repeat?.productName);
  late final _quantity = TextEditingController(
      text: widget.repeat == null ? null : _plain(widget.repeat!.quantity));
  final _salePrice = TextEditingController();
  late final List<_IngredientRow> _rows = [
    if (widget.repeat == null || widget.repeat!.inputs.isEmpty)
      _IngredientRow()
    else
      for (final i in widget.repeat!.inputs)
        _IngredientRow()..quantity.text = _plain(i.quantity),
  ];
  List<Product> _products = const [];
  bool _busy = false;
  String? _error;
  late final _money = NumberFormat.decimalPattern('fr_FR');

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await widget.retail.products(widget.org.id);
      if (!mounted) return;
      setState(() {
        _products = orderForPicking(products, widget.recentNames);
        // A repeated run arrives with names; resolve them to today's
        // products. One that vanished since (renamed, archived) leaves its
        // row unselected with the quantity kept — visible, not silent.
        final repeat = widget.repeat;
        if (repeat != null) {
          for (var i = 0; i < repeat.inputs.length && i < _rows.length; i++) {
            final wanted = repeat.inputs[i].name.trim().toLowerCase();
            for (final p in _products) {
              if (p.name.trim().toLowerCase() == wanted) {
                _rows[i].product = p;
                break;
              }
            }
          }
        }
      });
    } catch (_) {
      // The picker stays empty and saving says why; the sheet itself
      // should not crash for a fetch the save will repeat anyway.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _salePrice.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// What one unit will cost, from what is typed so far — the same division
  /// the server will do, shown before saving so the maker sees the number
  /// the sale price has to beat.
  double? get _estimatedUnitCost {
    final made = double.tryParse(_quantity.text.trim().replaceAll(',', '.'));
    if (made == null || made <= 0) return null;
    var total = 0.0;
    var any = false;
    for (final r in _rows) {
      final p = r.product;
      final q =
          double.tryParse(r.quantity.text.trim().replaceAll(',', '.'));
      if (p == null || q == null || q <= 0) continue;
      total += q * p.costPrice;
      any = true;
    }
    if (!any) return null;
    return total / made;
  }

  Future<void> _save() async {
    final strings = Strings.of(context);
    final quantity =
        double.tryParse(_quantity.text.trim().replaceAll(',', '.'));
    final inputs = <ProductionInputDraft>[
      for (final r in _rows)
        if (r.product != null)
          ProductionInputDraft(
            productId: r.product!.id,
            quantity: double.tryParse(
                    r.quantity.text.trim().replaceAll(',', '.')) ??
                0,
          ),
    ];
    if (_name.text.trim().isEmpty) {
      setState(() => _error = strings.enterProductMade);
      return;
    }
    if (quantity == null || quantity <= 0) {
      setState(() => _error = strings.enterQuantityMade);
      return;
    }
    if (inputs.isEmpty || inputs.any((i) => i.quantity <= 0)) {
      setState(() => _error = strings.enterIngredients);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.production.record(
        orgId: widget.org.id,
        productName: _name.text.trim(),
        quantity: quantity,
        inputs: inputs,
      );
      await _setSalePrice();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  /// The searchable picker one ingredient row opens. The list arrives
  /// already ordered by [orderForPicking] — recently cooked with on top —
  /// and narrows as letters are typed.
  Future<void> _pickFor(_IngredientRow row) async {
    final picked = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPicker(products: _products),
    );
    if (picked != null && mounted) {
      setState(() => row.product = picked);
    }
  }

  double? get _typedSalePrice =>
      double.tryParse(_salePrice.text.trim().replaceAll(',', '.'));

  /// The shelf price, set in the same gesture as the making. The run is the
  /// primary record — if this second write fails, the production stands and
  /// the price can still be set from the Articles screen, so a failure here
  /// is deliberately not allowed to undo a run already recorded.
  Future<void> _setSalePrice() async {
    final price = _typedSalePrice;
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
    } catch (_) {
      // See above: the run is recorded; the price stays editable in Articles.
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final estimate = _estimatedUnitCost;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.newProduction,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: strings.whatWasMade,
                hintText: strings.whatWasMadeHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: strings.quantityMade),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _salePrice,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: strings.salePriceOptional,
                suffixText: widget.org.currency,
              ),
            ),
            const SizedBox(height: 16),
            Text(strings.ingredientsUsed,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final row in _rows)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      // Not a dropdown, on purpose: at two hundred articles
                      // a dropdown is a wall. Tapping opens a search — three
                      // typed letters beat any amount of scrolling.
                      child: InkWell(
                        onTap: _busy ? null : () => _pickFor(row),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: strings.ingredient,
                            suffixIcon: const Icon(Icons.arrow_drop_down),
                          ),
                          isEmpty: row.product == null,
                          child: Text(row.product?.name ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: row.quantity,
                        enabled: !_busy,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration:
                            InputDecoration(labelText: strings.quantity),
                      ),
                    ),
                    if (_rows.length > 1)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _rows.remove(row);
                                  row.dispose();
                                }),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed:
                    _busy ? null : () => setState(() => _rows.add(_IngredientRow())),
                icon: const Icon(Icons.add),
                label: Text(strings.addIngredient),
              ),
            ),
            if (estimate != null) ...[
              const SizedBox(height: 8),
              Text(
                strings.estimatedUnitCost(
                    '${_money.format(estimate)} ${widget.org.currency}'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600),
              ),
              // The comparison the whole sheet exists to make possible: the
              // price she is about to charge against what one unit costs her.
              if (_typedSalePrice != null && _typedSalePrice! < estimate) ...[
                const SizedBox(height: 4),
                Text(
                  strings.belowUnitCost,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(strings.save),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A shelf you search instead of scroll: a text field and the products that
/// match, ordered with the recently-cooked-with on top. Tapping one returns
/// it to the ingredient row that opened the picker.
class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.products});

  final List<Product> products;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final q = _search.text.trim().toLowerCase();
    final matches = q.isEmpty
        ? widget.products
        : widget.products
            .where((p) => p.name.toLowerCase().contains(q))
            .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: strings.searchProduct,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(strings.noProductFound,
                            textAlign: TextAlign.center),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, i) {
                        final p = matches[i];
                        return ListTile(
                          title: Text(p.name),
                          trailing: p.isIngredient
                              ? const Icon(Icons.soup_kitchen_outlined,
                                  size: 18)
                              : null,
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
