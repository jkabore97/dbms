import 'package:flutter/material.dart';

import '../../core/accounting/accounting_repository.dart';
import '../../core/accounting/models.dart';
import '../../core/auth/models.dart';
import 'report_shell.dart';

/// Did the business earn or lose, over a period.
///
/// The single most useful number in the app for anybody who is not the person
/// tapping the buttons, and until now it did not exist anywhere: the weekly
/// summary answered it for seven days and nothing answered it for a month, a
/// quarter or a year.
///
/// Per-account rows arrive only for a reader with full visibility. A summary
/// observer gets the three totals, and the screen renders what it was given
/// rather than deciding — the server already made that decision in
/// `income_statement()`, and a client that filtered as well would be a second
/// place for the rule to drift.
class IncomeStatementScreen extends StatefulWidget {
  const IncomeStatementScreen({
    super.key,
    required this.accounting,
    required this.org,
  });

  final AccountingRepository accounting;
  final OrgSummary org;

  @override
  State<IncomeStatementScreen> createState() => _IncomeStatementScreenState();
}

class _IncomeStatementScreenState extends State<IncomeStatementScreen> {
  Period _period = Period.thisMonth;
  List<StatementLine> _lines = const [];
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
      final lines = await widget.accounting.incomeStatement(
        widget.org.id,
        from: range.from,
        to: range.to,
      );
      if (!mounted) return;
      setState(() {
        _lines = lines;
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

  double _total(String name) => _lines
      .firstWhere(
        (l) => l.isTotal && l.name == name,
        orElse: () => const StatementLine(
          section: 'total',
          code: '',
          name: '',
          amount: 0,
        ),
      )
      .amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(widget.org.currency);

    final income = _lines.where((l) => l.section == 'income').toList();
    final expense = _lines.where((l) => l.section == 'expense').toList();

    final earned = _total('Produits');
    final spent = _total('Charges');
    final result = _total('Résultat');

    // Green when the business made money, red when it did not. The one number
    // on this screen that somebody scanning it in three seconds must read
    // correctly, and a minus sign in a column of digits is easy to miss.
    final resultTint =
        result < 0 ? theme.colorScheme.error : Colors.green.shade800;

    return Scaffold(
      appBar: AppBar(title: const Text('Compte de résultat')),
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
              isEmpty: _lines.isEmpty,
              emptyMessage: 'Rien enregistré sur cette période.',
              child: ListView(
                children: [
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _period.describe(),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: 'Reçu',
                                  amount: earned,
                                  money: money,
                                ),
                              ),
                              Expanded(
                                child: StatTile(
                                  label: 'Dépensé',
                                  amount: spent,
                                  money: money,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          StatTile(
                            label: result < 0 ? 'Perte' : 'Bénéfice',
                            amount: result,
                            money: money,
                            tint: resultTint,
                            emphasis: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (income.isEmpty && expense.isEmpty)
                    const SummaryOnlyNotice(),
                  if (income.isNotEmpty) ...[
                    const SectionHeader(title: 'Recettes'),
                    for (final line in income)
                      AmountRow(
                        label: line.label,
                        subtitle: line.code,
                        amount: line.amount,
                        money: money,
                      ),
                  ],
                  if (expense.isNotEmpty) ...[
                    const SectionHeader(title: 'Dépenses'),
                    for (final line in expense)
                      AmountRow(
                        label: line.label,
                        subtitle: line.code,
                        amount: line.amount,
                        money: money,
                      ),
                  ],
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
