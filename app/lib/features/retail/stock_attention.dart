import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import '../../core/retail/models.dart';
import '../common/attention_banner.dart';

/// The articles the bar's red number counts on « Articles » and on the
/// farm's « À vendre » (115's home_counts): goods at zero, or at or under
/// their alert level — out of stock first.
List<Product> stockFlagged(List<Product> products) {
  final out = [
    for (final p in products)
      if (!p.isService && p.quantity <= 0) p,
  ];
  final low = [
    for (final p in products)
      if (!p.isService && p.quantity > 0 && p.isLow) p,
  ];
  return [...out, ...low];
}

/// « Rupture » at zero, « Bientôt épuisé » under the alert level; null for
/// an article with stock enough.
String? stockChip(BuildContext context, Product p) {
  if (p.isService) return null;
  if (p.quantity <= 0) return context.tr('Rupture');
  if (p.isLow) return context.tr('Bientôt épuisé');
  return null;
}

/// The banner on top of the articles (122): « 1 article en rupture de
/// stock : Farine », each article with « Ajouter du stock » ([onRestock],
/// null for somebody who may not add stock), and why the number stays.
/// [place] is the bar's word for the page: « Articles », « À vendre ».
class StockAttention extends StatelessWidget {
  const StockAttention({
    super.key,
    required this.products,
    required this.place,
    this.onRestock,
  });

  final List<Product> products;
  final String place;
  final void Function(Product p)? onRestock;

  @override
  Widget build(BuildContext context) {
    final flagged = stockFlagged(products);
    if (flagged.isEmpty) return const SizedBox.shrink();
    final out = flagged.where((p) => p.quantity <= 0).length;
    final n = flagged.length;
    final names = attentionNames(context, [for (final p in flagged) p.name]);
    final String title;
    if (out == n) {
      title = n == 1
          ? context.tr('1 article en rupture de stock : {names}', {'names': names})
          : context.tr('{n} articles en rupture de stock : {names}', {'n': n, 'names': names});
    } else if (out == 0) {
      title = n == 1
          ? context.tr('1 article presque épuisé : {names}', {'names': names})
          : context.tr('{n} articles presque épuisés : {names}', {'n': n, 'names': names});
    } else {
      title = context.tr('{n} articles à réapprovisionner : {names}', {'n': n, 'names': names});
    }
    return AttentionBanner(
      key: const Key('stock-attention'),
      icon: Icons.inventory_2_outlined,
      title: title,
      stays: context.tr('Le chiffre rouge sur « {place} » reste tant que ces articles ne sont pas réapprovisionnés : ouvrir cette page ne l\'efface pas.', {'place': place}),
      items: [
        for (final p in flagged)
          AttentionItem(
            id: p.id,
            label: p.name,
            chip: stockChip(context, p),
            chipSoft: p.quantity > 0,
            detail: p.quantity <= 0
                ? context.tr('Plus rien en stock')
                : context.tr('Reste {q} (alerte à {low})',
                    {'q': _plain(p.quantity), 'low': _plain(p.lowStockAt ?? 0)}),
            actionLabel: onRestock == null ? null : context.tr('Ajouter du stock'),
            onAction: onRestock == null ? null : () => onRestock!(p),
          ),
      ],
    );
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';
}
