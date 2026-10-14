import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/retail/retail_repository.dart';

/// Articles already there, the vitrine still shut: a shop with 57 priced
/// articles was told to « add 5 » because none had « Sur la vitrine » on.
/// When the vitrine is short of its minimum and priced articles are ready
/// but hidden, one line says so and one button puts them all on it (070's
/// publish_all_products). Draws nothing otherwise.
class PublishAllBanner extends StatefulWidget {
  const PublishAllBanner({
    super.key,
    required this.orgId,
    required this.retail,
    this.onPublished,
  });

  final String orgId;
  final RetailRepository retail;

  /// After the publish: the list reloads its switches.
  final VoidCallback? onPublished;

  @override
  State<PublishAllBanner> createState() => PublishAllBannerState();
}

class PublishAllBannerState extends State<PublishAllBanner> {
  ({int published, int ready, int min})? _shelf;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Reads the shelf again — after an edit sheet changed a switch.
  Future<void> reload() async {
    final shelf = await widget.retail.vitrineShelf(widget.orgId);
    if (mounted) setState(() => _shelf = shelf);
  }

  Future<void> _publish() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final n = await widget.retail.publishAll(widget.orgId);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(context.tr('{n} article(s) publié(s) sur la vitrine.', {'n': n}))));
      widget.onPublished?.call();
      await reload();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _shelf;
    if (s == null || s.ready <= 0 || s.published >= s.min) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    // The count is goods and services together (070), so the words name
    // neither.
    final title = context.tr('Déjà {n} prêts pour la vitrine', {'n': s.ready});
    return Container(
      key: const Key('publish-all-banner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.storefront_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(context.tr('Ils ont un prix mais ne sont pas encore sur la vitrine. Mettez-les-y en un geste : vous pourrez en retirer un à tout moment.')),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('publish-all-go'),
            onPressed: _busy ? null : _publish,
            icon: const Icon(Icons.storefront),
            label: Text(context.tr('Tout mettre sur la vitrine ({n})', {'n': s.ready})),
          ),
        ],
      ),
    );
  }
}
