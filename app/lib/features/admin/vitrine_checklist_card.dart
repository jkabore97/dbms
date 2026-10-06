import 'package:flutter/material.dart';

import '../../core/theme/kaj_card.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart';
import '../../core/retail/retail_repository.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// "Votre vitrine : 40 %" — what the window has and lacks (070).
///
/// The audit found every open vitrine missing its description, address and
/// phone, one photo in seventy articles, and a shop with 57 articles and
/// none published. Nothing had told the owners. This card does: a meter,
/// the next steps in order, and — when articles are waiting off the
/// vitrine — one button that publishes them all.
class VitrineChecklistCard extends StatefulWidget {
  const VitrineChecklistCard({
    super.key,
    required this.orgId,
    required this.admin,
    this.retail,
  });

  final String orgId;
  final AdminRepository admin;

  /// For "Tout publier"; null hides the button.
  final RetailRepository? retail;

  @override
  State<VitrineChecklistCard> createState() => _VitrineChecklistCardState();
}

class _VitrineChecklistCardState extends State<VitrineChecklistCard> {
  VitrineChecklist? _list;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.admin.vitrineChecklist(widget.orgId);
      if (mounted) setState(() => _list = list);
    } catch (_) {
      // No meter is better than a broken settings page.
    }
  }

  Future<void> _publishAll() async {
    final retail = widget.retail;
    if (retail == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final n = await retail.publishAll(widget.orgId);
      if (!mounted) return;
      setState(() => _message = n == 0
          ? context.tr('Tout est déjà sur la vitrine.')
          : '$n article${n > 1 ? 's' : ''} publié${n > 1 ? 's' : ''} sur la vitrine.');
      await _load();
    } catch (error) {
      if (mounted) setState(() => _message = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final score = list.score;
    const tiles = [
      (Icons.inventory_2, 'Articles'),
      (Icons.photo_camera, 'Photos'),
      (Icons.short_text, 'Présentation'),
      (Icons.call, 'Téléphone'),
      (Icons.home_work, 'Adresse'),
      (Icons.place, 'Carte'),
    ];
    final steps = list.steps;
    return KajCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Not a list to choose from: a meter, and six pictures that
            // light up as the window fills.
            Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(
                          value: score / 100,
                          strokeWidth: 6,
                          backgroundColor:
                              theme.colorScheme.primary.withValues(alpha: 0.12),
                          semanticsLabel: context.tr('Vitrine complète à {score} pour cent', {'score': score}),
                        ),
                      ),
                      Text(context.tr('{score} %', {'score': score}),
                          key: const Key('vitrine-score'),
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                      score == 100 ? context.tr('Vitrine complète') : context.tr('Remplissez votre vitrine'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var k = 0; k < tiles.length && k < steps.length; k++)
                  Expanded(
                    child: Column(
                      key: Key('vitrine-step-$k'),
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: steps[k].done
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(tiles[k].$1,
                                  size: 22,
                                  color: steps[k].done
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurfaceVariant),
                            ),
                            if (steps[k].done)
                              Positioned(
                                right: -4,
                                bottom: -4,
                                child: CircleAvatar(
                                  radius: 8,
                                  backgroundColor: Colors.green.shade600,
                                  child: const Icon(Icons.check,
                                      size: 11, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(context.tr(tiles[k].$2),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
              ],
            ),
            if (list.open && !list.public) ...[
              const SizedBox(height: 12),
              Row(
                key: const Key('vitrine-min'),
                children: [
                  Icon(Icons.visibility_off_outlined, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        context.tr('Visible du public dès {min} articles en vente : {n} / {min}.',
                            {'min': list.minItems, 'n': list.published}),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
            if (list.published == 0 && list.open) ...[
              const SizedBox(height: 8),
              Text(
                context.tr('Tant qu\'aucun article n\'est publié, la vitrine n\'apparaît pas dans l\'annuaire.'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            if (list.unpublished > 0 && widget.retail != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _publishAll,
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: Text(context.tr('Tout publier ({unpublished})', {'unpublished': list.unpublished})),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
