import 'package:flutter/material.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/theme/mara_sheet.dart';
import '../common/step_flow.dart';
import '../farm/for_sale_screen.dart';
import '../home/place_sections.dart';
import '../services/service_flow.dart';
import '../services/services_screen.dart';
import 'article_flow.dart';
import 'products_screen.dart';

/// « Catalogue » (134): everything the business offers, in one place on the
/// bar — the shop's and, since 134, the association's.
///
/// Two sections at the top, Articles | Services: the screens the business
/// already had (the shop's articles, an association's simple list — a
/// book, a t-shirt, a ticket: a name, a price, a photo, a count if it is
/// counted — and « Mes services »), behind one address,
/// `catalogue?partie=articles|services`. Its single ＋ asks « un article
/// ou un service ? ». The old `produits` and `services` addresses land
/// here, on their section.
///
/// The association keeps it simpler than the shop: no till, no barcode, no
/// buying price — its articles are ordered from the vitrine as a shop's
/// are, and its services booked as before (098).
class CatalogueScreen extends StatefulWidget {
  const CatalogueScreen({
    super.key,
    required this.org,
    required this.retail,
    this.capture,
    this.access = OrgAccess.allEdit,
    this.initialPart,
    this.initialQuery,
  });

  final OrgSummary org;
  final RetailRepository retail;
  final CaptureRepository? capture;
  final OrgAccess access;

  /// `?partie=`: 'articles' or 'services'.
  final String? initialPart;

  /// `?q=`: the article a « Stock bas » ring is about (shop).
  final String? initialQuery;

  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  int? _articles;
  int? _services;

  bool get _servicesShown => !widget.access.isHidden('services');

  /// Who may add: somebody who records, with the articles open to edit.
  bool get _canAdd =>
      !widget.org.isObserverOnly && widget.access.canEdit('products');

  @override
  void initState() {
    super.initState();
    _count();
  }

  /// How many of each, beside their words (« Articles · 42 »). Best-effort.
  Future<void> _count() async {
    if (!widget.retail.isConfigured) return;
    try {
      final all = await widget.retail.products(widget.org.id);
      if (!mounted) return;
      setState(() {
        _articles = all.where((p) => !p.isService && !p.isIngredient).length;
        _services = all.where((p) => p.isService).length;
      });
    } catch (_) {}
  }

  /// The single ＋: « un article ou un service ? » — or straight to the
  /// one there is.
  Future<void> _add(BuildContext context, VoidCallback reload) async {
    // A database before 098 has no services: the ＋ is an article's
    // (« Mes services » says why), as its own button was disabled.
    final kind = _servicesShown && !widget.retail.servicesMissing
        ? await _ask(context)
        : 'article';
    if (kind == null || !context.mounted) return;
    final bool? saved;
    if (kind == 'service') {
      saved = await StepFlow.push(
          context,
          ServiceFlow(
              org: widget.org, retail: widget.retail, capture: widget.capture));
    } else {
      saved = await ArticleFlow.open(context,
          org: widget.org,
          retail: widget.retail,
          capture: widget.capture,
          forSale: widget.org.isAssociation);
    }
    if (saved == true && mounted) {
      reload();
      await _count();
    }
  }

  Future<String?> _ask(BuildContext context) => showMaraSheet<String>(
        context: context,
        showDragHandle: true,
        // Scrolls when it cannot all show (320 px at a large text size).
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              key: const Key('catalogue-ask'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(sheet.tr('Un article ou un service ?'),
                    style: Theme.of(sheet).textTheme.titleLarge),
                const SizedBox(height: 12),
                _Choice(
                  key: const Key('catalogue-add-article'),
                  icon: Icons.sell_outlined,
                  title: sheet.tr('Un article'),
                  detail: widget.org.isAssociation
                      ? sheet.tr('Un livre, un t-shirt, un billet : il se commande sur la vitrine.')
                      : sheet.tr('Ce que vous vendez : il a un prix et un stock.'),
                  onTap: () => Navigator.of(sheet).pop('article'),
                ),
                const SizedBox(height: 10),
                _Choice(
                  key: const Key('catalogue-add-service'),
                  icon: Icons.event_available_outlined,
                  title: sheet.tr('Un service'),
                  detail: widget.org.isAssociation
                      ? sheet.tr('Une adhésion, un cours, la salle : il se réserve.')
                      : sheet.tr('Ce que vous faites : une coupe, une réparation — il se réserve.'),
                  onTap: () => Navigator.of(sheet).pop('service'),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final org = widget.org;
    return PlaceSections(
      title: context.tr('Catalogue'),
      initial: widget.initialPart,
      ownsAdd: _canAdd,
      actions: _canAdd
          ? (context, reload) => [
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton.filled(
                    key: const Key('catalogue-add'),
                    tooltip: context.tr('Ajouter'),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () => _add(context, reload),
                    // Its own colour: the bar's icon colour is the bar's ink.
                    icon: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimary),
                  ),
                ),
              ]
          : null,
      sections: [
        PlaceSection(
          id: 'articles',
          label: context.tr('Articles'),
          count: _articles,
          build: (_) => org.isAssociation
              ? ForSaleScreen(
                  org: org, retail: widget.retail, capture: widget.capture)
              : ProductsScreen(
                  // A bell's new ?q= while Catalogue is on screen: its article.
                  key: ValueKey('products:${widget.initialQuery}'),
                  org: org,
                  retail: widget.retail,
                  capture: widget.capture,
                  access: widget.access,
                  initialQuery: widget.initialQuery,
                ),
        ),
        if (_servicesShown)
          PlaceSection(
            id: 'services',
            label: context.tr('Services'),
            count: _services,
            build: (_) => ServicesScreen(
                org: org, retail: widget.retail, capture: widget.capture),
          ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(detail, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
