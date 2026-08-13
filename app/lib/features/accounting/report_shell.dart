import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_repository.dart';

/// The parts every accounting screen needs and none of them should own.
///
/// All five reports have the same three states — loading, refused or
/// unreachable, and an answer — and the same period control at the top. Left to
/// themselves they grow five slightly different spinners and five slightly
/// different ways of saying "no signal", which is how an app starts feeling
/// assembled rather than built.

/// A window over the books, and what to call it.
///
/// A named period rather than two date pickers. "Ce mois" is what somebody
/// actually wants nine times out of ten, and two calendar dialogs to get there
/// is four taps and a chance to pick the wrong year.
enum Period {
  thisMonth('Ce mois'),
  lastMonth('Mois dernier'),
  thisYear('Cette année'),
  everything('Tout');

  const Period(this.label);
  final String label;

  /// Null means unbounded, which the SQL functions read as "no filter".
  ({DateTime? from, DateTime? to}) get range {
    final now = DateTime.now();
    return switch (this) {
      Period.thisMonth => (
          from: DateTime(now.year, now.month, 1),
          to: now,
        ),
      Period.lastMonth => (
          from: DateTime(now.year, now.month - 1, 1),
          // Day zero of this month is the last day of the previous one,
          // whatever its length and whether or not February has 29.
          to: DateTime(now.year, now.month, 0),
        ),
      Period.thisYear => (from: DateTime(now.year, 1, 1), to: now),
      Period.everything => (from: null, to: null),
    };
  }

  String describe() {
    final r = range;
    if (r.from == null) return 'Depuis le début';
    final f = DateFormat('d MMM', 'fr_FR');
    return '${f.format(r.from!)} — ${f.format(r.to!)}';
  }
}

class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Period value;
  final ValueChanged<Period> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final period in Period.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(period.label),
                selected: value == period,
                onSelected: (_) => onChanged(period),
              ),
            ),
        ],
      ),
    );
  }
}

/// Loading, failed, or loaded — drawn once.
///
/// [error] is deliberately given the whole body rather than a snackbar. These
/// screens need signal by design, most of the people using them will not have
/// it some of the time, and a report that quietly shows nothing is a report
/// that says the business earned nothing.
class ReportBody extends StatelessWidget {
  const ReportBody({
    super.key,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.child,
    this.isEmpty = false,
    this.emptyMessage = 'Rien à afficher pour cette période.',
  });

  final bool loading;
  final Object? error;
  final Future<void> Function() onRetry;
  final Widget child;
  final bool isEmpty;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                AuthRepository.describeError(error!),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Un rapport est un chiffre à un instant. '
                'Mieux vaut pas de chiffre du tout que le chiffre de la '
                'semaine dernière présenté comme celui d\'aujourd\'hui.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (isEmpty) {
      return RefreshIndicator(
        onRefresh: onRetry,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(onRefresh: onRetry, child: child);
  }
}

/// One figure with a word under it, for the header of a report.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.amount,
    required this.money,
    this.tint,
    this.emphasis = false,
  });

  final String label;
  final double amount;
  final NumberFormat money;
  final Color? tint;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          money.format(amount),
          style: (emphasis
                  ? theme.textTheme.headlineSmall
                  : theme.textTheme.titleMedium)
              ?.copyWith(fontWeight: FontWeight.bold, color: tint),
        ),
      ],
    );
  }
}

/// A line of a financial statement: a name on the left, an amount on the
/// right, aligned down the column so the eye can add them up.
class AmountRow extends StatelessWidget {
  const AmountRow({
    super.key,
    required this.label,
    required this.amount,
    required this.money,
    this.subtitle,
    this.bold = false,
    this.tint,
    this.onTap,
  });

  final String label;
  final String? subtitle;
  final double amount;
  final NumberFormat money;
  final bool bold;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weight = bold ? FontWeight.bold : FontWeight.normal;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: weight, color: tint),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              money.format(amount),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: tint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A heading inside a statement — "Recettes", "Ce que possède l'activité".
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown on a report a summary observer is reading. Without it the screen is
/// indistinguishable from a business with no transactions in it, which is a
/// much more alarming thing to read than "you are seeing the totals".
class SummaryOnlyNotice extends StatelessWidget {
  const SummaryOnlyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
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
              'Votre accès porte sur les totaux. Le détail par compte ne vous '
              'est pas communiqué.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Money, the way it is written here: no decimals, because a centime of CFA
/// franc does not exist and a column of ",00" is a column of noise.
NumberFormat moneyFormat(String currency) => NumberFormat.currency(
      locale: 'fr_FR',
      symbol: currency == 'XOF' ? 'FCFA' : currency,
      decimalDigits: 0,
    );
