import 'package:flutter/material.dart';
import '../../../core/format/money.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/reports/models.dart';
import '../../../core/reports/reports_repository.dart';

/// Where the money is, right now — cash, bank, mobile money.
///
/// `church_balances` computes each from the ledger rather than reading a
/// stored number, so what is on this screen is the sum of every entry ever
/// posted and cannot drift from the entries behind it. That is the whole
/// argument for double-entry, made visible in one screen.
///
/// This is a totals-only report by nature, so an observer on 'summary'
/// visibility sees it in full: there are no line items here to withhold.
class BalancesScreen extends StatefulWidget {
  const BalancesScreen({
    super.key,
    required this.reports,
    required this.orgId,
    this.currency = 'XOF',
  });

  final ReportsRepository reports;
  final String orgId;
  final String currency;

  @override
  State<BalancesScreen> createState() => _BalancesScreenState();
}

class _BalancesScreenState extends State<BalancesScreen> {
  List<AccountBalance> _balances = const [];
  bool _loading = true;
  String? _error;

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
      final balances = await widget.reports.balances(widget.orgId);
      if (!mounted) return;
      setState(() {
        _balances = balances;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(widget.currency);
    final total = _balances.fold<double>(0, (sum, b) => sum + b.balance);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Soldes'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total disponible',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            money.format(total),
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Détail', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_balances.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Aucun compte pour le moment.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._balances.map(
                      (b) => Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: ListTile(
                          leading: Icon(_iconFor(b.name)),
                          title: Text(b.displayName),
                          trailing: Text(
                            money.format(b.balance),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  static IconData _iconFor(String accountName) => switch (accountName) {
        'Cash on Hand' => Icons.payments_outlined,
        'Bank Account' => Icons.account_balance_outlined,
        'Mobile Money' => Icons.phone_android_outlined,
        _ => Icons.savings_outlined,
      };
}
