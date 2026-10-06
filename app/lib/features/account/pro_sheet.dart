import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/access/plan_terms.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/nav/app_scope.dart';
import '../cauris/unlock_sheet.dart';
import 'package:go_router/go_router.dart';
import '../../core/nav/router.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The one door to Kaj Pro (066, M10 block 2).
///
/// Opened from every badged tool, the Compte screen and the « Pro » strip
/// on every page: it now opens the Free and Pro side by side
/// (`/o/<id>/kaj-pro`, ProPlansScreen), whose foot is [ProPayPanel].
class ProSheet {
  static Future<void> open(
    BuildContext context, {
    required OrgSummary org,
    required PlanTerms terms,
    required AdminRepository admin,
    required bool canRequest,
    String? feature,
  }) async {
    // A known tool opens its own door first (085): cauris, or Mara Pro.
    if (feature != null) {
      await UnlockSheet.open(context, org: org, feature: feature);
      return;
    }
    await GoRouter.of(context).push(Routes.inside(org.id, 'kaj-pro'));
  }
}

/// How to pay for Mara Pro: by card through Stripe (082), and only that way
/// — « Bientôt disponible » until the platform opens it. With [period] given, the page above chose month or year and this
/// panel draws no choice of its own; with [showFeatures] false, the page
/// above already listed what Pro adds.
class ProPayPanel extends StatefulWidget {
  const ProPayPanel({
    super.key,
    required this.org,
    required this.terms,
    required this.admin,
    required this.canRequest,
    this.period,
    this.showFeatures = true,
    this.top,
  });

  final String? period;
  final bool showFeatures;

  /// Drawn first, for an admin, above Wave: the card button (Stripe).
  final Widget? top;

  final OrgSummary org;
  final PlanTerms terms;
  final AdminRepository admin;

  /// True for an admin of the business — the only person the server lets
  /// say "J'ai payé". Others read the same sheet and are told whom to ask.
  final bool canRequest;

  @override
  State<ProPayPanel> createState() => _ProPayPanelState();
}

class _ProPayPanelState extends State<ProPayPanel> {
  /// The platform has opened the card (082), and this build carries the
  /// payment Worker (the scope's WavePay says; a tree without it — a test
  /// handing the button its own — takes the platform's word).
  bool _cardReady(BuildContext context) =>
      widget.terms.stripeOn &&
      (AppScope.read(context)?.wavePay?.compiledIn ?? true);

  String _money(int amount) =>
      '${NumberFormat.decimalPattern('fr_FR').format(amount)} F CFA';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terms = widget.terms;
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showFeatures) ...[
              Row(
                children: [
                  Icon(Icons.workspace_premium_outlined,
                      color: theme.colorScheme.primary, size: 28),
                  const SizedBox(width: 10),
                  Text(context.tr('Mara Pro'), style: theme.textTheme.headlineSmall),
                  const Spacer(),
                  if (widget.org.isPro)
                    Chip(
                      label: Text(context.tr('Active')),
                      backgroundColor: theme.colorScheme.primaryContainer,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.org.isPro
                    ? 'Cette entreprise est sur Mara Pro. Tous les outils '
                        'ci-dessous sont ouverts.'
                    : 'Mara reste gratuit pour le quotidien : le stock, les '
                        'ventes, le carnet de crédit, la vitrine et jusqu\'à '
                        '${terms.freeMaxStaff} comptes en plus du propriétaire. '
                        'Mara Pro ajoute ce dont une entreprise qui grandit a '
                        'besoin :',
                style: muted,
              ),
              const SizedBox(height: 12),
              for (final f in terms.proFeatures)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(PlanTerms.labelOf(f))),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(context.tr('Comptes, factures et photos sans limite (gratuit : {freeMaxInvoicesMonth} factures par mois, {freeMaxPhotos} photos)', {'freeMaxInvoicesMonth': terms.freeMaxInvoicesMonth, 'freeMaxPhotos': terms.freeMaxPhotos})),
                    ),
                  ],
                ),
              ),
              ],
              if (!widget.org.isPro) ...[
                if (widget.showFeatures) ...[
                const SizedBox(height: 16),
                Text(
                  '${_money(terms.priceMonth)} par mois, ou '
                  '${_money(terms.priceYear)} par an.',
                  style: theme.textTheme.titleMedium,
                ),
                ],
                const SizedBox(height: 12),
                // Mara Pro is paid by card through Stripe, and only that
                // way: no manual « J'ai payé », no Wave to Mara. Until the
                // card is open, the sheet says so.
                if (!widget.canRequest)
                  Text(
                    context.tr('Seul le propriétaire peut passer à Mara Pro.'),
                    style: muted,
                  )
                else if (_cardReady(context) && widget.top != null)
                  widget.top!
                else
                  Container(
                    key: const Key('pro-soon'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.credit_card,
                            size: 32, color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.tr('Bientôt disponible'),
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800)),
                              Text(context.tr('Paiement par carte bancaire.'), style: muted),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
    );
  }
}
