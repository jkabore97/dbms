import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/models.dart';
import '../../../core/reports/reports_repository.dart';
import '../../../core/nav/router.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Rapports')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ReportTile(
            icon: Icons.summarize_outlined,
            title: 'Résumé de la semaine',
            subtitle: 'À envoyer au pasteur, par WhatsApp',
            onTap: () =>
                context.push(Routes.inside(org.id, 'rapports/semaine')),
          ),
          _ReportTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Soldes',
            subtitle: 'Espèces, banque, Mobile Money',
            onTap: () => context.push(Routes.inside(org.id, 'rapports/soldes')),
          ),

          // Named, per-person giving. Withheld from observers entirely.
          if (!org.isObserverOnly)
            _ReportTile(
              icon: Icons.volunteer_activism_outlined,
              title: 'Relevé de dons',
              subtitle: "Pour un membre, sur l'année",
              onTap: () => context.push(Routes.inside(org.id, 'rapports/dons')),
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
                      'Votre accès porte sur les totaux. Le détail des '
                      'opérations ne vous est pas communiqué.',
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
    return Card(
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
