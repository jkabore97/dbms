import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/errors.dart';
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
  });

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

  Future<void> _create() async {
    final made = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewProductionSheet(
        org: widget.org,
        production: widget.production,
        retail: widget.retail,
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
      floatingActionButton: FloatingActionButton.extended(
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
  });

  final OrgSummary org;
  final ProductionRepository production;
  final RetailRepository retail;

  @override
  State<_NewProductionSheet> createState() => _NewProductionSheetState();
}

class _IngredientRow {
  Product? product;
  final quantity = TextEditingController();

  void dispose() => quantity.dispose();
}

class _NewProductionSheetState extends State<_NewProductionSheet> {
  final _name = TextEditingController();
  final _quantity = TextEditingController();
  final List<_IngredientRow> _rows = [_IngredientRow()];
  List<Product> _products = const [];
  bool _busy = false;
  String? _error;
  late final _money = NumberFormat.decimalPattern('fr_FR');

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await widget.retail.products(widget.org.id);
      if (mounted) setState(() => _products = products);
    } catch (_) {
      // The dropdowns stay empty and saving says why; the sheet itself
      // should not crash for a fetch the save will repeat anyway.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
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
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
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
                      child: DropdownButtonFormField<Product>(
                        initialValue: row.product,
                        isExpanded: true,
                        decoration:
                            InputDecoration(labelText: strings.ingredient),
                        items: [
                          for (final p in _products)
                            DropdownMenuItem(value: p, child: Text(p.name)),
                        ],
                        onChanged: _busy
                            ? null
                            : (p) => setState(() => row.product = p),
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
