import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import '../common/step_flow.dart';

/// What « Recette » and « Dépense » (115) both ask: how the money moved,
/// and which heading it goes under.

/// Espèces, Mobile Money, Banque — what the recording sheet offered, the
/// same three values record_entry() reads (007).
List<FlowOption<String>> moneyMethods(BuildContext context) => [
      FlowOption('cash', context.tr('Espèces'), icon: Icons.payments_outlined),
      FlowOption('mobile_money', context.tr('Mobile Money'),
          icon: Icons.phone_android_outlined),
      FlowOption('bank', context.tr('Banque'),
          icon: Icons.account_balance_outlined),
    ];

/// The method's word, for the summary.
String moneyMethodLabel(BuildContext context, String method) =>
    switch (method) {
      'mobile_money' => context.tr('Mobile Money'),
      'bank' => context.tr('Banque'),
      _ => context.tr('Espèces'),
    };

/// The chosen « Autre » tile, before its name is typed.
const otherHeading = '__other__';

/// A grid of big tiles, two to a row: one per heading, « Autre » next, and
/// — when [onAdd] is given — « Ajouter un type de dépense » last (149).
///
/// Rows of two whose height follows their content, so a name on two lines
/// and a description under it fit at 320 px with large text.
class HeadingTiles extends StatelessWidget {
  const HeadingTiles({
    super.key,
    required this.headings,
    required this.selected,
    required this.onSelect,
    this.labelFor,
    this.detailFor,
    this.onAdd,
    this.addLabel,
    this.onLongPress,
  });

  /// The names as the books hold them — what gets posted.
  final List<String> headings;
  final String? selected;
  final ValueChanged<String> onSelect;

  /// How a stored name is shown (the seeded chart is in English; a type
  /// renamed after use shows its label, 149).
  final String Function(String)? labelFor;

  /// A type's short description, under its name (149).
  final String? Function(String)? detailFor;

  /// « Ajouter un type de dépense » (149). Null draws no such tile.
  final VoidCallback? onAdd;
  final String? addLabel;

  /// A long press on a heading's tile (149: « Gérer »).
  final ValueChanged<String>? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile(String value, String label, IconData icon,
        {String? detail, VoidCallback? onTap, VoidCallback? onHold}) {
      final on = value == selected;
      return Material(
        color: on
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: on ? theme.colorScheme.primary : Colors.transparent,
              width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('heading-$value'),
          onTap: onTap ?? () => onSelect(value),
          onLongPress: onHold,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 30),
                  const SizedBox(height: 6),
                  Text(label,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (detail != null && detail.isNotEmpty)
                    Text(detail,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final tiles = <Widget>[
      for (final h in headings)
        tile(h, labelFor?.call(h) ?? h, headingIcon(labelFor?.call(h) ?? h),
            detail: detailFor?.call(h),
            onHold: onLongPress == null ? null : () => onLongPress!(h)),
      tile(otherHeading, context.tr('Autre'), Icons.edit_note_outlined),
      if (onAdd != null)
        tile('__add__', addLabel ?? context.tr('Ajouter'), Icons.add_circle_outline,
            onTap: onAdd),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 10),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A picture for a heading, read off its words — any business's chart, in
/// French or in the seeded English.
IconData headingIcon(String name) {
  final n = name.toLowerCase();
  bool has(List<String> words) => words.any(n.contains);
  if (has(['loyer', 'rent'])) return Icons.home_outlined;
  if (has(['transport', 'carburant', 'essence'])) return Icons.local_shipping_outlined;
  if (has(['salaire', 'main-d', 'salar'])) return Icons.groups_outlined;
  if (has(['eau', 'électricité', 'utilit'])) return Icons.bolt_outlined;
  if (has(['aliment'])) return Icons.grass_outlined;
  if (has(['vétérin', 'santé', 'médic'])) return Icons.medical_services_outlined;
  if (has(['semence'])) return Icons.spa_outlined;
  if (has(['engrais', 'traitement'])) return Icons.science_outlined;
  if (has(['achat', 'purchas', 'marchandise'])) return Icons.shopping_cart_outlined;
  if (has(['entretien', 'réparation', 'mainten'])) return Icons.build_outlined;
  if (has(['événement', 'event', 'fête'])) return Icons.celebration_outlined;
  if (has(['fourniture', 'suppl'])) return Icons.inventory_2_outlined;
  if (has(['social', 'œuvre', 'outreach'])) return Icons.volunteer_activism_outlined;
  if (has(['téléphone', 'crédit', 'internet'])) return Icons.phone_android_outlined;
  if (has(['cotisation'])) return Icons.savings_outlined;
  if (has(['don', 'gift'])) return Icons.redeem_outlined;
  if (has(['vente', 'sale'])) return Icons.sell_outlined;
  return Icons.receipt_long_outlined;
}
