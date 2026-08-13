import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/accounting/accounting_repository.dart';
import '../../core/accounting/models.dart';
import '../../core/auth/models.dart';
import 'report_shell.dart';

/// What the business owns and what it owes, at a date.
///
/// The two totals are shown side by side and they are equal or the books are
/// broken. That equality is the point of the report and the screen says so out
/// loud rather than leaving it to be noticed — a balance sheet whose sides
/// disagree means something wrote to the ledger without going through the
/// recording functions, and nobody would spot it by reading down a list.
///
/// "Résultat accumulé" is not an account and is labelled so nobody goes
/// hunting for it in the chart. The ledger has no closing entries and no
/// retained-earnings account, so income minus expense to date is computed by
/// `balance_sheet()` and shown under equity, which is what makes the two sides
/// meet.
class BalanceSheetScreen extends StatefulWidget {
  const BalanceSheetScreen({
    super.key,
    required this.accounting,
    required this.org,
  });

  final AccountingRepository accounting;
  final OrgSummary org;

  @override
  State<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends State<BalanceSheetScreen> {
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
      final lines = await widget.accounting.balanceSheet(widget.org.id);
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

    final assets = _lines.where((l) => l.section == 'asset').toList();
    final liabilities = _lines.where((l) => l.section == 'liability').toList();
    final equity = _lines.where((l) => l.section == 'equity').toList();

    final totalAssets = _total('Total actif');
    final totalClaims = _total('Total passif');

    // Floating point, not accounting: both sides come back as Postgres
    // numerics rendered through doubles, and a franc of tolerance is the
    // difference between an honest check and one that fails on a rounding
    // artefact nobody can act on.
    final balanced = (totalAssets - totalClaims).abs() < 1;

    return Scaffold(
      appBar: AppBar(title: const Text('Bilan')),
      body: ReportBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        isEmpty: _lines.isEmpty,
        emptyMessage: 'Rien enregistré pour le moment.',
        child: ListView(
          children: [
            Card(
              elevation: 0,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              color: balanced
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Au ${DateFormat('d MMMM y', 'fr_FR').format(DateTime.now())}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: 'Actif',
                            amount: totalAssets,
                            money: money,
                            emphasis: true,
                          ),
                        ),
                        Expanded(
                          child: StatTile(
                            label: 'Passif',
                            amount: totalClaims,
                            money: money,
                            emphasis: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          balanced ? Icons.check_circle_outline : Icons.warning_amber,
                          size: 18,
                          color: balanced
                              ? Colors.green.shade800
                              : theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            balanced
                                ? 'Les deux colonnes sont égales : les comptes '
                                    'sont équilibrés.'
                                : 'Les deux colonnes ne sont pas égales. '
                                    'Signalez-le : une écriture a contourné '
                                    "l'application.",
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (assets.isEmpty && liabilities.isEmpty && equity.isEmpty)
              const SummaryOnlyNotice(),

            if (assets.isNotEmpty) ...[
              SectionHeader(title: accountTypes['asset']!),
              for (final line in assets)
                AmountRow(
                  label: line.label,
                  subtitle: line.code,
                  amount: line.amount,
                  money: money,
                ),
            ],

            if (liabilities.isNotEmpty) ...[
              SectionHeader(title: accountTypes['liability']!),
              for (final line in liabilities)
                AmountRow(
                  label: line.label,
                  subtitle: line.code,
                  amount: line.amount,
                  money: money,
                ),
            ],

            if (equity.isNotEmpty) ...[
              SectionHeader(title: accountTypes['equity']!),
              for (final line in equity)
                AmountRow(
                  label: line.label,
                  // 'zzz' is the sort key balance_sheet() gives the computed
                  // result row so it lands last. It is not a code and must
                  // not be shown as one.
                  subtitle: line.code == 'zzz'
                      ? 'Recettes moins dépenses, depuis le début'
                      : line.code,
                  amount: line.amount,
                  money: money,
                ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
