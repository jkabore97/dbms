import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/db/local_db.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../accounting/report_shell.dart';
import '../church/entry_controls.dart' show promptForName;
import '../../core/nav/app_scope.dart';
import '../retail/article_flow.dart';
import 'farm_flows.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// What is in the store, and what is about to run out.
///
/// The reorder threshold is the only editable thing here and it is the reason
/// the screen exists. A count nobody acts on is bookkeeping; a count with a
/// line under it is a warning, and the difference between the two is one
/// number that somebody has to set once per item.
///
/// The counts come from the server because they are computed from every
/// movement ever made, most of which happened on other people's phones. The
/// device knows only its own share, so showing a cached figure as if it were
/// current would be worse than saying there is no signal.
class StockScreen extends StatefulWidget {
  const StockScreen({
    super.key,
    required this.db,
    required this.org,
    this.farm,
  });

  final LocalDb db;
  final OrgSummary org;
  final FarmRepository? farm;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<StockItem> _items = const [];
  bool _loading = true;
  Object? _error;

  bool get _canWrite => !widget.org.isObserverOnly;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final farm = widget.farm;
    if (farm == null || !farm.isConfigured) {
      setState(() {
        _loading = false;
        _error = StateError(
          "Cette version de l'application a été compilée sans serveur.",
        );
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await farm.stockOnHand(widget.org.id);
      // Mirrored to the device so the recording sheets keep offering the real
      // item names once the signal goes.
      await widget.db.cacheFarmItems(
        widget.org.id,
        items.map((i) => i.toCache()).toList(),
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _setReorder(StockItem item) async {
    // `promptForName` is the same shape and the same lifetime problem: the
    // dialog owns its controller, because showDialog's future completes while
    // the route is still animating out and still building the field.
    final text = await promptForName(
      context,
      title: item.name,
      label: context.tr('Seuil ({unit})', {'unit': item.unit}),
      hint: 'Prévenir en dessous de ce nombre',
      initial:
          item.reorderLevel == null ? '' : trimQuantity(item.reorderLevel!),
    );

    if (text == null) return;

    final level = double.tryParse(text.trim().replaceAll(',', '.'));
    if (level == null) return;

    // A threshold of zero is the way to make an item stop shouting: it warns
    // only once the last one is gone. Setting it back to "no threshold at all"
    // is not offered, because the two are indistinguishable to anybody reading
    // the list and one fewer state is one fewer thing to explain.

    try {
      await widget.farm!.setReorderLevel(item.id, level);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Le seuil n\'a pas pu être enregistré.'))),
      );
    }
  }

  /// Réception, Perte (115): one entry at a time, on this phone first.
  Future<void> _record(Future<bool?> flow) async {
    if (await flow == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final low = _items.where((i) => i.belowReorder).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Stock')),
        actions: [
          if (_canWrite)
            IconButton(
              tooltip: context.tr('Perte'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _record(FarmStockFlow.use(context,
                  db: widget.db, org: widget.org, wasted: true)),
            ),
        ],
      ),
      // « Ajouter » (115): first « C'est pour vendre » (an article, « À
      // vendre ») or « C'est une fourniture » (on to « Réception », here).
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              key: const Key('stock-add'),
              onPressed: () {
                final scope = AppScope.maybeOf(context);
                _record(scope == null
                    ? FarmStockFlow.receive(context, db: widget.db, org: widget.org)
                    : ArticleFlow.open(context,
                        org: widget.org,
                        retail: scope.retail,
                        capture: scope.capture,
                        db: widget.db));
              },
              icon: const Icon(Icons.add),
              label: Text(context.tr('Ajouter')),
            )
          : null,
      body: ReportBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        isEmpty: _items.isEmpty,
        emptyMessage: widget.org.visibility == 'summary'
            ? context.tr('Votre accès porte sur les totaux. Le détail du stock ne vous est pas communiqué.')
            : context.tr('Aucun article pour le moment. Le premier est créé tout seul, à la première réception.'),
        child: ListView(
          children: [
            if (low.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        low.length == 1
                            ? context.tr('Il reste peu de {name}.', {'name': low.first.name})
                            : context.tr('{length} articles presque épuisés.', {'length': low.length}),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            for (final item in _items)
              _ItemTile(
                item: item,
                canEdit: _canWrite,
                onSetReorder: () => _setReorder(item),
              ),
            const SizedBox(height: 96),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.canEdit,
    required this.onSetReorder,
  });

  final StockItem item;
  final bool canEdit;
  final VoidCallback onSetReorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: item.belowReorder
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          item.belowReorder ? Icons.warning_amber : Icons.inventory_2_outlined,
          size: 20,
          color: item.belowReorder
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(item.name),
      subtitle: Text(
        [
          if (item.reorderLevel != null)
            'seuil ${trimQuantity(item.reorderLevel!)} ${item.unit}'
          else
            'aucun seuil',
          if (item.lastMovement != null)
            'dernier mouvement ${DateFormat('d MMM', 'fr_FR').format(item.lastMovement!)}',
        ].join(' · '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            item.quantityLabel,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: item.belowReorder ? theme.colorScheme.error : null,
            ),
          ),
          Text(item.unit, style: theme.textTheme.bodySmall),
        ],
      ),
      onTap: canEdit ? onSetReorder : null,
    );
  }
}
