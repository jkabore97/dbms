import 'package:flutter/material.dart';

import '../../../core/theme/kaj_card.dart';
import '../../../l10n/strings.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/org_access.dart';
import '../../../core/auth/models.dart';
import '../../../core/reports/reports_repository.dart';
import '../../../core/nav/router.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../../core/notify/bell_room.dart';
import '../../../core/nav/app_scope.dart';
import '../../account/pro_sheet.dart';

/// The reports, and who is allowed to see which.
///
/// Two decisions live here rather than inside the screens:
///
///  * An observer granted 'summary' visibility gets totals, not the lines
///    behind them. That is what the investor in the schema comment was always
///    for: someone entitled to know whether the business is sound without
///    being entitled to read every transaction in it.
///  * A giving statement is not offered to observers at all, whatever their
///    visibility. It names one person and says what they gave; nobody outside
///    the church's own leadership has business with it, and "read the books"
///    was never meant to include that.
///
/// Both are courtesies, not protections — see the note in the class body.
class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({
    super.key,
    required this.reports,
    required this.org,
  });

  final ReportsRepository reports;
  final OrgSummary org;

  bool get _summaryOnly => org.visibility == 'summary';

  OrgAccess? _access(BuildContext context) =>
      AppScope.maybeOf(context)?.session.accessFor(org.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(actions: const [bellRoom], title: Text(Strings.of(context).reports)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ReportTile(
            icon: Icons.summarize_outlined,
            title: Strings.of(context).weeklySummary,
            subtitle: Strings.of(context).weeklySummarySubtitle,
            onTap: () =>
                context.push(Routes.inside(org.id, 'rapports/semaine')),
          ),
          _ReportTile(
            icon: Icons.account_balance_wallet_outlined,
            title: Strings.of(context).balances,
            subtitle: Strings.of(context).balancesSubtitle,
            onTap: () => context.push(Routes.inside(org.id, 'rapports/soldes')),
          ),

          // Named, per-person giving. Withheld from observers entirely.
          if (!org.isObserverOnly)
            _ReportTile(
              icon: Icons.volunteer_activism_outlined,
              title: Strings.of(context).givingStatement,
              subtitle: Strings.of(context).givingStatementSubtitle,
              onTap: () => context.push(Routes.inside(org.id, 'rapports/dons')),
            ),

          // « Membres » and « Analyses » (148), an association's.
          if (org.isAssociation)
            _ReportTile(
              key: const Key('hub-members'),
              icon: Icons.groups_2_outlined,
              title: context.tr('Membres'),
              subtitle: context.tr('La liste, ce que chacun a donné, les cotisations à jour'),
              onTap: () => context.push(Routes.inside(org.id, 'membres')),
            ),
          if (org.isAssociation && !(_access(context)?.isHidden('analytics') ?? false))
            _ReportTile(
              key: const Key('hub-analytics'),
              icon: Icons.insights_outlined,
              title: context.tr('Analyses'),
              subtitle: (_access(context)?.isProLocked('analytics') ?? false)
                  ? context.tr('Entrées et sorties par mois, catégories, membres · Marakaj Pro')
                  : context.tr('Entrées et sorties par mois, catégories, membres'),
              onTap: () {
                final scope = AppScope.maybeOf(context);
                if (scope != null && (_access(context)?.isProLocked('analytics') ?? false)) {
                  ProSheet.open(context,
                      org: org,
                      terms: scope.session.planTerms,
                      admin: scope.admin,
                      canRequest: org.isAdmin,
                      feature: 'analytics');
                  return;
                }
                context.push(Routes.inside(org.id, 'rapports/analyse'));
              },
            ),

          if (_summaryOnly) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('Votre accès porte sur les totaux. Le détail des opérations ne vous est pas communiqué.'),
                      style: theme.textTheme.bodySmall,
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

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KajCard(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Icon(icon, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
