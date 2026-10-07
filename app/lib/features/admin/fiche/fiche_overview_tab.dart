import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/plan_terms.dart';
import '../../../core/console/fiche_repository.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/router.dart';
import '../../../core/storefront/storefront_repository.dart' show publicShopUrl;
import '../../../core/theme/kaj_card.dart';
import '../../../core/theme/mara_mark.dart';
import '../../auth/org_picker_screen.dart' show kindSingular;
import 'fiche_widgets.dart';

/// Aperçu: the business at a glance — how it is doing, whose it is, its
/// plan and cauris, its people, its vitrine, and what wants attention,
/// each alert one tap from where it is dealt with.
class FicheOverviewTab extends StatelessWidget {
  const FicheOverviewTab({
    super.key,
    required this.overview,
    required this.onTab,
    required this.onPreview,
  });

  final OrgOverview overview;
  final void Function(FicheTab tab) onTab;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final theme = Theme.of(context);
    final health = healthOf(context, o.health);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final figures = LayoutBuilder(builder: (context, box) {
      // Numbers first: two abreast on a phone, three on a tablet, all six
      // in one row on a computer.
      final columns = box.maxWidth >= 900 ? 6 : (box.maxWidth >= 560 ? 3 : 2);
      final w = (box.maxWidth - 10 * (columns - 1)) / columns;
      return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FicheFigure(
          width: w,
          key: const Key('fiche-health'),
          value: health.label,
          label: context.tr('Dernière activité : {when}', {'when': sinceLine(context, o.lastActivityAt)}),
          colour: health.colour,
        ),
        FicheFigure(
          width: w,
          key: const Key('fiche-plan'),
          value: o.isPro ? context.tr('Pro') : context.tr('Gratuit'),
          label: context.tr('Formule Mara'),
          hint: o.isPro && o.planUntil != null
              ? context.tr('jusqu\'au {date}', {'date': dayLine(context, o.planUntil!)})
              : null,
          colour: o.isPro ? maraGreen : maraDeep,
          onTap: () => onTab(FicheTab.pro),
        ),
        FicheFigure(
          width: w,
          key: const Key('fiche-cauris'),
          value: '${o.cauris}',
          label: context.tr('cauris'),
          hint: o.promo.isEmpty
              ? null
              : context.tr('dont {n} à utiliser avant le {date}', {
                  'n': o.promo.first.points,
                  'date': dayLine(context, o.promo.first.until),
                }),
          colour: maraBrown,
          onTap: () => onTab(FicheTab.pro),
        ),
        FicheFigure(
          width: w,
          key: const Key('fiche-members'),
          value: '${o.members}',
          label: o.members > 1 ? context.tr('membres') : context.tr('membre'),
          onTap: () => onTab(FicheTab.team),
        ),
        FicheFigure(
          width: w,
          key: const Key('fiche-vitrine'),
          value: '${o.published}',
          label: o.isAssociation ? context.tr('en ligne') : context.tr('en vente'),
          hint: o.vitrineOpen ? context.tr('Vitrine ouverte') : context.tr('Vitrine fermée'),
          colour: o.vitrineOpen ? maraGreen : maraGrey,
          onTap: () => onTab(FicheTab.vitrine),
        ),
        FicheFigure(
          width: w,
          key: const Key('fiche-rules'),
          value: '${o.rules}',
          label: context.tr('réglages Mara'),
          hint: o.actions > 0
              ? context.tr('{n} au journal', {'n': o.actions})
              : null,
          onTap: () => onTab(FicheTab.features),
        ),
      ],
    );
    });

    final alerts = _Alerts(overview: o, onTab: onTab);
    final owner = _OwnerCard(overview: o);
    final facts = _Facts(overview: o);

    return ListView(
      key: const Key('fiche-overview'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        FicheWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              figures,
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('fiche-overview-preview'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: onPreview,
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(context.tr('Voir comme le commerçant')),
                ),
              ),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: [owner, facts])),
                    const SizedBox(width: 16),
                    Expanded(child: alerts),
                  ],
                )
              else ...[
                alerts,
                owner,
                facts,
              ],
              const SizedBox(height: 8),
              Text(
                context.tr('{kind} · créée le {date}', {
                  'kind': kindSingular(context, o.profile),
                  'date': o.createdAt == null ? '—' : dayLine(context, o.createdAt!),
                }),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Alerts extends StatelessWidget {
  const _Alerts({required this.overview, required this.onTab});

  final OrgOverview overview;
  final void Function(FicheTab tab) onTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [
      for (final a in overview.alerts) _line(context, a),
    ].whereType<_Alert>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FicheHeading(context.tr('À surveiller')),
        if (rows.isEmpty)
          KajCard(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline, color: maraGreen),
              title: Text(context.tr('Rien à signaler')),
            ),
          )
        else
          KajCard(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, r) in rows.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  ListTile(
                    key: Key('fiche-alert-${r.kind}'),
                    minVerticalPadding: 12,
                    leading: Icon(r.icon, color: r.colour),
                    title: Text(r.title, style: theme.textTheme.bodyLarge),
                    trailing: r.go == null ? null : const Icon(Icons.chevron_right),
                    onTap: r.go,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  _Alert? _line(BuildContext context, Map<String, dynamic> a) {
    final kind = '${a['kind']}';
    final n = a['n'] is num ? (a['n'] as num).toInt() : 0;
    DateTime? when(String key) => DateTime.tryParse('${a[key] ?? ''}');
    const urgent = Color(0xFFB03B3B);
    const soon = Color(0xFFA96A0B);
    return switch (kind) {
      'suspended' => _Alert(kind, Icons.lock_outline, urgent,
          context.tr('Suspendue depuis le {date}', {
            'date': when('at') == null ? '—' : dayLine(context, when('at')!),
          })),
      'paid_claim' => _Alert(kind, Icons.payments_outlined, urgent,
          context.tr('« J\'ai payé » à confirmer ({n})', {'n': n}),
          () => context.push(Routes.consolePro)),
      'promotion' => _Alert(kind, Icons.campaign_outlined, soon,
          context.tr('Mise en avant à décider ({n})', {'n': n}),
          () => context.push(Routes.consoleFeatured)),
      'pro_ending' => _Alert(kind, Icons.workspace_premium_outlined, soon,
          context.tr('Mara Pro se termine le {date}', {
            'date': when('until') == null ? '—' : dayLine(context, when('until')!),
          }),
          () => onTab(FicheTab.pro)),
      'unlock_ending' => _Alert(kind, Icons.lock_clock_outlined, soon,
          context.tr('Outil ouvert qui se ferme dans 7 jours ({n})', {'n': n}),
          () => onTab(FicheTab.pro)),
      'rule_ending' => _Alert(kind, Icons.toggle_off_outlined, soon,
          context.tr('Réglage Mara qui se termine dans 7 jours ({n})', {'n': n}),
          () => onTab(FicheTab.features)),
      'silent' => _Alert(kind, Icons.notifications_paused_outlined, const Color(0xFFB1541A),
          context.tr('Silencieuse depuis {n} jours', {'n': a['days'] ?? '—'})),
      'never' => _Alert(kind, Icons.hourglass_empty, urgent, context.tr('Jamais utilisée')),
      'setup' => _Alert(kind, Icons.flag_outlined, soon, context.tr('Mise en route pas terminée')),
      _ => null,
    };
  }
}

class _Alert {
  const _Alert(this.kind, this.icon, this.colour, this.title, [this.go]);
  final String kind;
  final IconData icon;
  final Color colour;
  final String title;
  final VoidCallback? go;
}

class _OwnerCard extends StatelessWidget {
  const _OwnerCard({required this.overview});

  final OrgOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owner = overview.owner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FicheHeading(context.tr('Propriétaire')),
        KajCard(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: owner == null
                ? Text(context.tr('Aucun propriétaire nommé.'),
                    style: theme.textTheme.bodyLarge)
                : Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: maraPaper,
                        child: Text(
                          (owner.name ?? '?').trim().isEmpty
                              ? '?'
                              : owner.name!.trim()[0].toUpperCase(),
                          style: const TextStyle(
                              color: maraBrown, fontWeight: FontWeight.w800, fontSize: 20),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(owner.name ?? '—',
                                key: const Key('fiche-owner-name'),
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            if (owner.phone != null)
                              SelectableText(owner.phone!,
                                  key: const Key('fiche-owner-phone'),
                                  style: theme.textTheme.bodyLarge),
                            if (owner.email != null)
                              SelectableText(owner.email!, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      if (owner.phone != null)
                        IconButton(
                          tooltip: context.tr('Copier le numéro'),
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: owner.phone!));
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(context.tr('Numéro copié.'))));
                          },
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.overview});

  final OrgOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      (context.tr('Type'), kindSingular(context, o.profile)),
      (context.tr('Adresse web'), publicShopUrl(o.slug)),
      (context.tr('Monnaie'), o.currency),
      (context.tr('Téléphone'), o.phone ?? '—'),
      (context.tr('Adresse'), o.address ?? '—'),
      if (o.city != null) (context.tr('Ville'), o.city!),
      if (o.isAssociation)
        (context.tr('Vérifiée par Mara'),
            o.verifiedAt == null ? context.tr('Non') : dayLine(context, o.verifiedAt!)),
      (context.tr('Paiements Wave'), o.waveAllowed ? context.tr('Autorisés') : context.tr('Espèces seulement')),
      for (final u in o.unlocks.take(3))
        (context.tr('Outil ouvert'),
            '${u.feature == 'pro_all' ? context.tr('Mara Pro complet') : PlanTerms.labelOf(u.feature)} · '
            '${context.tr('jusqu\'au {date}', {'date': dayLine(context, u.until)})}'),
      if (o.showcase) (context.tr('Vitrine d\'exemple'), context.tr('Oui')),
      if (o.isArchived) (context.tr('Archivée'), dayLine(context, o.archivedAt!)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FicheHeading(context.tr('Fiche')),
        KajCard(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ),
                        Expanded(
                          child: SelectableText(value, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
