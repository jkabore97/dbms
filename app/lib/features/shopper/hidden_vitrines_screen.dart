import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/local_db.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/storefront/hidden_vitrines.dart';
import '../storefront/shop_style.dart';

/// « Vitrines masquées » (batch 150): the vitrines hidden on this device,
/// each with « Afficher à nouveau ». Reached from the shopper's profile and,
/// for somebody with no account, from the street's foot — the hiding is
/// the device's, so is the list.
class HiddenVitrinesScreen extends StatefulWidget {
  const HiddenVitrinesScreen({super.key, required this.db});

  final LocalDb db;

  @override
  State<HiddenVitrinesScreen> createState() => _HiddenVitrinesScreenState();
}

class _HiddenVitrinesScreenState extends State<HiddenVitrinesScreen> {
  late final _hidden = HiddenVitrines(widget.db);
  List<HiddenVitrine>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _hidden.list();
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _show(HiddenVitrine h) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final said = context.tr('{name} est de nouveau visible dans la rue.', {'name': h.name});
    final undo = context.tr('Annuler');
    await _hidden.show(h.slug);
    await _load();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(said),
        action: SnackBarAction(
          label: undo,
          onPressed: () async {
            await _hidden.hide(h.slug, name: h.name);
            if (mounted) await _load();
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return ShopPage(
      title: context.tr('Vitrines masquées'),
      leading: IconButton(
        tooltip: context.tr('Retour'),
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.canPop() ? context.pop() : context.go(Routes.directory),
      ),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : ShopScroll(
              footer: ShopWidth(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: const ShopFooter(),
                ),
              ),
              children: [
                ShopWidth(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      key: const Key('hidden-list'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),
                        Text(
                          context.tr('Les vitrines que vous avez masquées n\'apparaissent plus dans la rue, sur ce téléphone.'),
                          style: const TextStyle(fontSize: 15, color: ShopStyle.mist),
                        ),
                        const SizedBox(height: 16),
                        if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Column(
                              children: [
                                const Icon(Icons.visibility_outlined, size: 40, color: ShopStyle.mist),
                                const SizedBox(height: 12),
                                Text(
                                  context.tr('Aucune vitrine masquée.'),
                                  key: const Key('hidden-none'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, color: ShopStyle.ink),
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: () => context.go(Routes.directory),
                                  child: Text(context.tr('Voir les vitrines')),
                                ),
                              ],
                            ),
                          )
                        else
                          for (final h in rows)
                            Container(
                              key: Key('hidden-${h.slug}'),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: ShopStyle.line),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              // A name and its button side by side; a long name
                              // or a large text size puts the button under it.
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.visibility_off_outlined, color: ShopStyle.mist),
                                      const SizedBox(width: 10),
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxWidth: MediaQuery.sizeOf(context).width - 110),
                                        child: Text(h.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: ShopStyle.ink)),
                                      ),
                                    ],
                                  ),
                                  OutlinedButton(
                                    key: Key('hidden-show-${h.slug}'),
                                    onPressed: () => _show(h),
                                    child: Semantics(
                                      label: context.tr('Afficher à nouveau {name}', {'name': h.name}),
                                      excludeSemantics: true,
                                      child: Text(context.tr('Afficher à nouveau')),
                                    ),
                                  ),
                                ],
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
