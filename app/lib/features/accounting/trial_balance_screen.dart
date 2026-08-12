import 'package:flutter/material.dart';

import '../../core/accounting/accounting_repository.dart';
import '../../core/accounting/models.dart';
import '../../core/auth/models.dart';
import 'report_shell.dart';

/// Debits and credits, uninterpreted.
///
/// The only report in the app that is not for a person deciding something. It
/// is for proving that the two columns are equal, and it is deliberately the
/// least friendly screen here — the numbers are raw, the accounts are in code
/// order, and nothing is translated into "reçu" and "dépensé", because the
/// moment a trial balance is made comfortable to read it stops being able to
/// show you what is wrong.
///
/// Any member may open it. A trial balance is entirely totals, and 006 decided
/// that totals are what a summary observer is entitled to.
class TrialBalanceScreen extends StatefulWidget {
  const TrialBalanceScreen({
    super.key,
    required this.accounting,
    required this.org,
  });

  final AccountingRepository accounting;
  final OrgSummary org;

  @override
  State<TrialBalanceScreen> createState() => _TrialBalanceScreenState();
}

class _TrialBalanceScreenState extends State<TrialBalanceScreen> {
  Period _period = Period.thisYear;
  List<TrialBalanceRow> _rows = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final range = _period.range;
      final rows = await widget.accounting.trialBalance(
        widget.org.id,
        from: range.from,
        to: range.to,
      );
      if (!mounted) return;
      setState(() {
        // An account nothing has landed on tells you nothing and pushes the
        // ones that did off the screen.
        _rows = rows.where((r) => !r.isEmpty).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(widget.org.currency);

    var debit = 0.0;
    var credit = 0.0;
    for (final row in _rows) {
      debit += row.debit;
      credit += row.credit;
    }
    final balanced = (debit - credit).abs() < 1;

    return Scaffold(
      appBar: AppBar(title: const Text('Balance générale')),
      body: Column(
        children: [
          const SizedBox(height: 12),
          PeriodSelector(
            value: _period,
            onChanged: (p) {
              setState(() => _period = p);
              _load();
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ReportBody(
              loading: _loading,
              error: _error,
              onRetry: _load,
              isEmpty: _rows.isEmpty,
              emptyMessage: 'Aucun mouvement sur cette période.',
              child: ListView(
                children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: balanced
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: StatTile(
                                label: 'Débit',
                                amount: debit,
                                money: money,
                              ),
                            ),
                            Expanded(
                              child: StatTile(
                                label: 'Crédit',
                                amount: credit,
                                money: money,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              balanced
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber,
                              size: 18,
                              color: balanced
                                  ? Colors.green.shade800
                                  : theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                balanced
                                    ? 'Débit = crédit. Chaque écriture a bien '
                                        'ses deux côtés.'
                                    : "Débit et crédit ne s'égalisent pas. "
                                        'Une écriture a contourné '
                                        "l'application.",
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // A header row, because two numeric columns with no labels
                  // above them is a table nobody can read.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        const Expanded(flex: 5, child: Text('Compte')),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Débit',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Crédit',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  for (final row in _rows)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(row.label,
                                    style: theme.textTheme.bodyMedium),
                                Text(
                                  '${row.code} · ${accountTypeLabel(row.type)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              row.debit == 0 ? '—' : money.format(row.debit),
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              row.credit == 0 ? '—' : money.format(row.credit),
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
