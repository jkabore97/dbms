import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';

/// One thing a red number on the bar is counting (122): its name, a word
/// for what is wrong with it, and the one button that fixes it.
class AttentionItem {
  const AttentionItem({
    required this.label,
    this.chip,
    this.chipSoft = false,
    this.detail,
    this.actionLabel,
    this.onAction,
    this.id,
  });

  final String label;

  /// « Rupture », « Bientôt épuisé », « En retard »… drawn red.
  final String? chip;

  /// The lighter chip, for what is on the way rather than there.
  final bool chipSoft;

  /// A second line: an amount, a date.
  final String? detail;

  /// « Ajouter du stock », « Répondre »… Null with [onAction]: no button.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// For the keys of the row and its button.
  final String? id;
}

/// Why the red number on the bar (122): on top of the page it leads to,
/// said in plain words — « 1 article en rupture de stock : Farine » — the
/// items it counts, each with its button, and that the number stays until
/// the reason is gone (opening the page does not clear it). Draws nothing
/// when nothing is counted.
class AttentionBanner extends StatelessWidget {
  const AttentionBanner({
    super.key,
    required this.title,
    required this.items,
    this.stays,
    this.icon = Icons.error_outline,
    this.shown = 5,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  /// The reason, whole: « 2 commandes attendent votre réponse ».
  final String title;
  final List<AttentionItem> items;

  /// « Le chiffre rouge reste tant que… »: what makes it go.
  final String? stays;
  final IconData icon;

  /// How many items are listed; the rest are « et 3 autres ».
  final int shown;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rest = items.length - shown;
    return Container(
      key: const Key('attention-banner'),
      margin: margin,
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.error.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The bar's own red dot, so the eye ties the two together.
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: scheme.onError),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  key: const Key('attention-title'),
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in items.take(shown))
            Padding(
              key: item.id == null ? null : Key('attention-item-${item.id}'),
              padding: const EdgeInsets.only(left: 36, top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(item.label,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            if (item.chip != null)
                              AttentionChip(label: item.chip!, soft: item.chipSoft),
                          ],
                        ),
                        if (item.detail != null)
                          Text(item.detail!,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (item.actionLabel != null && item.onAction != null)
                    TextButton(
                      key: item.id == null ? null : Key('attention-action-${item.id}'),
                      onPressed: item.onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onErrorContainer,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(item.actionLabel!,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          if (rest > 0)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 4),
              child: Text(context.tr('… et {n} autre(s), plus bas dans la liste', {'n': rest}),
                  style: theme.textTheme.bodySmall),
            ),
          if (stays != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                stays!,
                key: const Key('attention-stays'),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The red word on a flagged row: « Rupture », « Bientôt épuisé ».
class AttentionChip extends StatelessWidget {
  const AttentionChip({super.key, required this.label, this.soft = false});

  final String label;

  /// Lighter for « bientôt »: on the way, not there yet.
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: soft ? scheme.errorContainer : scheme.error,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: soft ? scheme.onErrorContainer : scheme.onError,
        ),
      ),
    );
  }
}

/// « Farine, Sucre et 2 autres » — the names a title can carry.
String attentionNames(BuildContext context, List<String> names, {int max = 3}) {
  if (names.length <= max) return names.join(', ');
  return context.tr('{names} et {n} autre(s)',
      {'names': names.take(max).join(', '), 'n': names.length - max});
}
