import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/accounting/accounting_repository.dart';
import '../../core/auth/models.dart';
import '../../core/db/local_db.dart';
import '../../core/nav/router.dart';

/// The accounting section.
///
/// The ledger underneath this app has been proper double-entry since the first
/// schema and there has never been a way to look at it as one. That gap is
/// what this section closes: the same rows the home screen has been writing
/// all along, read four ways.
///
/// The order is by who needs it and how often, not by how an accountant would
/// list them:
///
///   * the journal, because "what did we record last month" is the question
///     people actually ask;
///   * the income statement, because it is the one number an owner, a pastor
///     or an investor wants;
///   * the balance sheet, because at some point somebody asks what the
///     business is worth;
///   * the chart of accounts, because it is maintenance rather than reading;
///   * the trial balance last, because it is not for a person deciding
///     anything — it is for proving the books have not been tampered with.
///
/// Nothing here is hidden from anyone by this screen. A summary observer can
/// open every one of these and will be shown the totals and no line items,
/// because that is what the server sends them. Hiding the tiles would only
/// mean that the one place the rule is written is a screen instead of a
/// policy.
class AccountingHubScreen extends StatelessWidget {
  const AccountingHubScreen({
    super.key,
    required this.accounting,
    required this.org,
    this.db,
  });

  final AccountingRepository accounting;
  final OrgSummary org;

  /// Passed through to the chart of accounts, which mirrors it to the device
  /// so the recording sheets can offer the real category names offline.
  final LocalDb? db;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Comptabilité')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Tile(
            icon: Icons.receipt_long_outlined,
            title: 'Journal',
            subtitle: 'Toutes les écritures, dans les mots employés',
            onTap: () => context.push(Routes.inside(org.id, 'journal')),
          ),
          _Tile(
            icon: Icons.trending_up,
            title: 'Compte de résultat',
            subtitle: "Ce qui est entré, ce qui est sorti, ce qu'il reste",
            onTap: () =>
                context.push(Routes.inside(org.id, 'comptabilite/resultat')),
          ),
          _Tile(
            icon: Icons.account_balance_outlined,
            title: 'Bilan',
            subtitle: "Ce que possède l'activité et ce qu'elle doit",
            onTap: () =>
                context.push(Routes.inside(org.id, 'comptabilite/bilan')),
          ),
          _Tile(
            icon: Icons.list_alt_outlined,
            title: 'Plan comptable',
            subtitle: 'Les catégories, et le détail de chacune',
            onTap: () =>
                context.push(Routes.inside(org.id, 'comptabilite/plan')),
          ),
          _Tile(
            icon: Icons.balance_outlined,
            title: 'Balance générale',
            subtitle: 'La preuve que les comptes sont équilibrés',
            onTap: () =>
                context.push(Routes.inside(org.id, 'comptabilite/balance')),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ces écrans ont besoin du réseau. Un rapport est un '
                    'chiffre à un instant : mieux vaut ne rien afficher que '
                    'de présenter celui de la semaine dernière.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
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
