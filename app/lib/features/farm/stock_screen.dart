import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/db/local_db.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../accounting/report_shell.dart';
import '../church/entry_controls.dart' show promptForName;
import 'farm_sheets.dart';

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
      label: 'Seuil (${item.unit})',
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
        const SnackBar(content: Text("Le seuil n'a pas pu être enregistré.")),
      );
    }
  }

  Future<void> _record(Widget sheet) async {
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => sheet,
    );
    if (recorded == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final low = _items.where((i) => i.belowReorder).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        actions: [
          if (_canWrite)
            IconButton(
              tooltip: 'Perte',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _record(MoveStockSheet(
                db: widget.db,
                orgId: widget.org.id,
                kind: 'wasted',
              )),
            ),
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _record(ReceiveStockSheet(
                db: widget.db,
                orgId: widget.org.id,
                currencySymbol:
                    widget.org.currency == 'XOF' ? 'FCFA' : widget.org.currency,
              )),
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Réception'),
            )
          : null,
      body: ReportBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        isEmpty: _items.isEmpty,
        emptyMessage: widget.org.visibility == 'summary'
            ? 'Votre accès porte sur les totaux. Le détail du stock ne vous '
                'est pas communiqué.'
            : 'Aucun article pour le moment. Le premier est créé tout seul, '
                'à la première réception.',
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
                            ? 'Il reste peu de ${low.first.name}.'
                            : '${low.length} articles presque épuisés.',
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
