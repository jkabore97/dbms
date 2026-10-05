import 'package:flutter/material.dart';

import '../../core/theme/kaj_card.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart';
import '../../core/retail/retail_repository.dart';

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
          ? 'Tout est déjà sur la vitrine.'
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
    return KajCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Votre vitrine : $score %',
                      style: theme.textTheme.titleMedium),
                ),
                if (score == 100)
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 8,
                semanticsLabel: 'Vitrine complète à $score pour cent',
              ),
            ),
            const SizedBox(height: 12),
            for (final step in list.steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      step.done
                          ? Icons.check_circle_outline
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: step.done
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(step.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: step.done
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.onSurface,
                            decoration:
                                step.done ? TextDecoration.lineThrough : null,
                          )),
                    ),
                  ],
                ),
              ),
            if (list.published == 0 && list.open) ...[
              const SizedBox(height: 8),
              Text(
                "Tant qu'aucun article n'est publié, la vitrine n'apparaît pas "
                "dans l'annuaire.",
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            if (list.unpublished > 0 && widget.retail != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _publishAll,
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: Text('Tout publier (${list.unpublished})'),
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
