import 'package:flutter/material.dart';

import '../../core/nav/app_scope.dart';
import '../common/step_flow.dart';
import '../retail/article_flow.dart';
import 'production_flow.dart';

import '../cauris/path_card.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/format/money.dart';
import 'package:intl/intl.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/production/production_repository.dart';
import '../../core/retail/retail_repository.dart';
import '../../l10n/strings.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../common/keyboard_sheet.dart';

/// The transformation tool: ingredients in, a product out, and the app doing
/// the division the maker used to do in her head.
///
/// The list shows each past run with what it consumed and what one unit came
/// out costing. « Nouvelle production » opens [ProductionFlow], one question
/// a screen — the server moves the counts and the cost, and every later sale
/// of the product carries that cost as its margin base.
class ProductionScreen extends StatefulWidget {
  const ProductionScreen({
    super.key,
    required this.org,
    required this.production,
    required this.retail,
    this.access = OrgAccess.allEdit,
    this.addIngredients,
  });

  /// Production's way to its ingredients when none is marked yet (115):
  /// W1's article flow with « Utilisé en production » ticked, by default;
  /// a test hands its own.
  final Future<void> Function(BuildContext context)? addIngredients;

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
  NumberFormat get _money => moneyFormat(widget.org.currency);
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

  Future<void> _edit(ProductionRun run) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditRunSheet(production: widget.production, run: run),
    );
    if (saved == true) await _load();
  }

  Future<void> _create({ProductionRun? repeat}) async {
    // Locked (089): what was kept is read, nothing new is written.
    if (PathGate.locks(context, widget.org, 'production')) {
      return PathGate.guard(context, widget.org, 'production', () {});
    }
    // One question a screen (115): what was made, what went in, how much,
    // the price — the same record_production() the old sheet wrote.
    final made = await StepFlow.push(
      context,
      ProductionFlow(
        org: widget.org,
        production: widget.production,
        retail: widget.retail,
        recentNames: _recentNames,
        repeat: repeat,
        addIngredients: widget.addIngredients ?? _addIngredients,
      ),
    );
    if (made == true && mounted) await _load();
  }

  /// The article flow, « Utilisé en production » ticked (W1's ArticleFlow);
  /// articles only — a farm's supplies stay with Réception.
  Future<void> _addIngredients(BuildContext context) => ArticleFlow.open(
        context,
        org: widget.org,
        retail: widget.retail,
        capture: AppScope.maybeOf(context)?.capture,
        ingredient: true,
      );

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final dates = DateFormat('d MMM', intlLocale());
    return Scaffold(
      appBar: AppBar(actions: const [bellRoom], title: Text(strings.production)),
      floatingActionButton: !widget.access.canEdit('production')
          ? null
          : FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.precision_manufacturing_outlined),
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
                          KajCard(
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
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      // Correcting a wrong output count or a
                                      // mistyped name. The ingredients stay;
                                      // the server re-derives the unit cost.
                                      TextButton.icon(
                                        onPressed: () => _edit(r),
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 18),
                                        label: Text(context.tr('Modifier')),
                                      ),
                                      // Day two of any real bakery: the same
                                      // cakes as yesterday. One tap brings the
                                      // whole recipe back; only the quantities
                                      // are left to confirm.
                                      TextButton.icon(
                                        onPressed: () => _create(repeat: r),
                                        icon:
                                            const Icon(Icons.replay, size: 18),
                                        label: Text(strings.makeAgain),
                                      ),
                                    ],
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

/// Correcting a past run: the output count and its name. The ingredients are
/// not touched here — a wrong ingredient is a fresh run, not a correction —
/// and the server re-derives the unit cost from the unchanged total.
class _EditRunSheet extends StatefulWidget {
  const _EditRunSheet({required this.production, required this.run});

  final ProductionRepository production;
  final ProductionRun run;

  @override
  State<_EditRunSheet> createState() => _EditRunSheetState();
}

class _EditRunSheetState extends State<_EditRunSheet> {
  late final _quantity = TextEditingController(
    text: widget.run.quantity.toStringAsFixed(0),
  );
  late final _name = TextEditingController(text: widget.run.productName);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = double.tryParse(_quantity.text.trim().replaceAll(',', '.'));
    final name = _name.text.trim();
    if (qty == null || qty <= 0) {
      setState(() => _error = context.tr('Entrez la quantité produite.'));
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = context.tr('Entrez le nom du produit.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.production
          .updateRun(widget.run.runId, quantity: qty, productName: name);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('Enregistrer la correction')),
          ),
        ],
      ),
      children: [
          Text(context.tr('Corriger la production'), style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            context.tr('Les ingrédients ne changent pas. Le coût unitaire est recalculé.'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: context.tr('Produit'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: context.tr('Quantité produite'),
              border: const OutlineInputBorder(),
            ),
          ),
      ],
    );
  }
}
