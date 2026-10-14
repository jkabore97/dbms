import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/store_rules.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/mara_sheet.dart';
import '../admin/spots_card.dart';
import '../storefront/share_vitrine.dart';

/// What « Ma vitrine » was asked to do (146).
enum VitrineAction { view, customise, share, promote, open, articles }

/// « Ma vitrine » (146): the top bar's button opens this sheet, the
/// vitrine's one entry point — for a shop, a farm and an association alike.
///
///  * « Voir ma vitrine » — the public page, as the button opened it (140);
///  * « Personnaliser ma vitrine » — straight to the cover, the colour, the
///    phrase, the hours and the Pro options ([Routes.vitrineSettings]), for
///    who may change the settings (an admin) only;
///  * « Partager ma vitrine » — batch 140's share sheet;
///  * « Mettre en avant » — the spots' sheet (071), where spots are sold
///    (not in the iPhone app, not hidden by Mara) and for an admin.
///
/// A vitrine the street cannot see yet (140's vitrine_checklist: closed, or
/// short of articles) is said first, with the step that opens it.
class VitrineSheet extends StatefulWidget {
  const VitrineSheet({
    super.key,
    required this.org,
    this.checklist,
    this.canPromote = false,
  });

  final OrgSummary org;

  /// What the vitrine has and lacks; null: not asked (no banner).
  final Future<VitrineChecklist?>? checklist;

  /// « Mettre en avant » offered: an admin, where spots are sold.
  final bool canPromote;

  static bool _promotable(BuildContext context, OrgSummary org) =>
      org.isAdmin &&
      sellsDigitalInApp &&
      !(AppScope.maybeOf(context)?.session.accessFor(org.id).isHidden('spots') ?? false);

  /// Opens the sheet over [context] and does what was picked.
  static Future<void> open(BuildContext context, OrgSummary org) async {
    final scope = AppScope.maybeOf(context);
    Future<VitrineChecklist?>? checklist;
    if (scope != null) {
      checklist = scope.admin.vitrineChecklist(org.id).catchError((Object _) => null);
    }
    final action = await showMaraSheet<VitrineAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VitrineSheet(
        org: org,
        checklist: checklist,
        canPromote: _promotable(context, org),
      ),
    );
    if (action == null || !context.mounted) return;
    await act(context, org, action);
  }

  /// What each line does, from the context that opened the sheet.
  static Future<void> act(BuildContext context, OrgSummary org, VitrineAction action) async {
    final slug = org.slug ?? '';
    switch (action) {
      case VitrineAction.view:
        if (slug.isNotEmpty) context.go(Routes.storefront(slug));
      case VitrineAction.customise || VitrineAction.open:
        await context.push(Routes.vitrineSettings(org.id));
      case VitrineAction.articles:
        await context.push(Routes.orgSettings(org.id, part: 'articles'));
      case VitrineAction.share:
        await _share(context, org);
      case VitrineAction.promote:
        final scope = AppScope.maybeOf(context);
        if (scope == null) return;
        await SpotSheet.open(context,
            orgId: org.id,
            admin: scope.admin,
            retail: scope.retail,
            isPro: org.isPro,
            vitrineOnly: org.profile == 'association' || org.profile == 'church');
    }
  }

  /// Batch 140's share sheet: the vitrine as the street sees it when it
  /// can be read, else the business's own words for it.
  static Future<void> _share(BuildContext context, OrgSummary org) async {
    final scope = AppScope.maybeOf(context);
    final slug = org.slug ?? '';
    PublicShop? shop;
    var items = <PublicItem>[];
    final street = scope == null ? null : StorefrontRepository(scope.auth.client);
    if (street != null && street.isConfigured && slug.isNotEmpty) {
      try {
        shop = await street.shop(slug).timeout(const Duration(seconds: 8));
        if (shop != null) items = await street.items(slug).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    // Not on the street yet: the business's own published articles, as
    // the vitrine would show them (140's mapper).
    if (items.isEmpty && scope != null) {
      try {
        final goods = await scope.retail.products(org.id).timeout(const Duration(seconds: 8));
        items = [for (final p in goods) if (p.isPublished) publicItemOf(p)];
      } catch (_) {}
    }
    shop ??= PublicShop(
      orgId: org.id,
      name: org.name,
      slug: slug,
      profile: org.profile,
      theme: org.theme,
      currency: org.currency,
    );
    if (!context.mounted) return;
    await ShareVitrine.open(context,
        shop: shop, items: items, capture: scope?.capture, mine: true, admin: scope?.admin);
  }

  @override
  State<VitrineSheet> createState() => _VitrineSheetState();
}

class _VitrineSheetState extends State<VitrineSheet> {
  VitrineChecklist? _checklist;

  @override
  void initState() {
    super.initState();
    unawaited(widget.checklist?.then((c) {
      if (mounted) setState(() => _checklist = c);
    }));
  }

  void _pick(VitrineAction a) => Navigator.of(context).pop(a);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = widget.org;
    final edit = org.isAdmin;
    final c = _checklist;
    final hidden = c != null && !c.visible;
    return SingleChildScrollView(
      key: const Key('vitrine-sheet'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('Ma vitrine'),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            org.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (hidden) ...[
            _NotVisible(
              checklist: c,
              canFix: edit,
              onFix: () => _pick(c.open ? VitrineAction.articles : VitrineAction.open),
            ),
            const SizedBox(height: 8),
          ],
          _Line(
            key: const Key('vitrine-sheet-view'),
            icon: Icons.visibility_outlined,
            title: context.tr('Voir ma vitrine'),
            line: context.tr('La page que voient vos clients'),
            onTap: () => _pick(VitrineAction.view),
          ),
          if (edit)
            _Line(
              key: const Key('vitrine-sheet-customise'),
              icon: Icons.palette_outlined,
              title: context.tr('Personnaliser ma vitrine'),
              line: context.tr('Couverture, couleur, phrase, horaires, présentation'),
              onTap: () => _pick(VitrineAction.customise),
            ),
          _Line(
            key: const Key('vitrine-sheet-share'),
            icon: Icons.share_outlined,
            title: context.tr('Partager ma vitrine'),
            line: context.tr('Une image pour un statut, ou le lien'),
            onTap: () => _pick(VitrineAction.share),
          ),
          if (widget.canPromote)
            _Line(
              key: const Key('vitrine-sheet-promote'),
              icon: Icons.campaign_outlined,
              title: context.tr('Mettre en avant'),
              line: context.tr('Une place en tête de la rue'),
              onTap: () => _pick(VitrineAction.promote),
            ),
        ],
      ),
    );
  }
}

/// « Votre vitrine n'est pas encore visible des clients » (140's words),
/// first in the sheet, with the step that opens it.
class _NotVisible extends StatelessWidget {
  const _NotVisible({required this.checklist, required this.canFix, required this.onFix});

  final VitrineChecklist checklist;
  final bool canFix;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = (checklist.minItems - checklist.published).clamp(0, 9999);
    return Container(
      key: const Key('vitrine-sheet-hidden'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6E7C8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.visibility_off_outlined, color: maraDeep),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr('Votre vitrine n\'est pas encore visible des clients'),
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800, color: maraDeep),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Text(
              !checklist.open
                  ? context.tr('Elle est fermée : ouvrez-la, et vos clients la voient.')
                  : context.tr(
                      'Encore {n} article(s) en vente, et elle se montre à tout le monde.',
                      {'n': missing}),
              style: theme.textTheme.bodyMedium?.copyWith(color: maraDeep),
            ),
          ),
          if (canFix)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('vitrine-sheet-fix'),
                onPressed: onFix,
                child: Text(!checklist.open
                    ? context.tr('Ouvrir ma vitrine')
                    : context.tr('Mettre des articles en vente')),
              ),
            ),
        ],
      ),
    );
  }
}

/// One line of the sheet: its icon, its name, one short line under it.
class _Line extends StatelessWidget {
  const _Line({
    super.key,
    required this.icon,
    required this.title,
    required this.line,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(line,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
