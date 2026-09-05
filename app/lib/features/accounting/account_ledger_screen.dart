import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/accounting/accounting_repository.dart';
import '../../core/accounting/models.dart';
import '../../core/auth/models.dart';
import 'report_shell.dart';

/// One account, every movement, with the balance after each.
///
/// The running balance is the reason this screen exists rather than a filtered
/// list. "The till says 43,500 and the app says 61,000" is answered by reading
/// down a column until the two stop agreeing, and by nothing else — not by a
/// total, not by a monthly summary, not by the journal.
///
/// Newest first, because the question is almost always about the recent end of
/// it. That means the balance column reads downwards as history running
/// backwards, which is the right way round for finding where a difference
/// started and would be the wrong way round for adding it up by hand.
///
/// Line items, so this needs `visibility = 'full'`. A summary observer calling
/// `account_ledger()` gets an empty result, and the screen says so plainly
/// rather than implying the account has never been used.
class AccountLedgerScreen extends StatefulWidget {
  const AccountLedgerScreen({
    super.key,
    required this.accounting,
    required this.org,
    required this.account,
  });

  final AccountingRepository accounting;
  final OrgSummary org;
  final LedgerAccount account;

  @override
  State<AccountLedgerScreen> createState() => _AccountLedgerScreenState();
}

class _AccountLedgerScreenState extends State<AccountLedgerScreen> {
  Period _period = Period.thisYear;
  List<LedgerMovement> _movements = const [];
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
      final movements = await widget.accounting.accountLedger(
        widget.org.id,
        widget.account.id,
        from: range.from,
        to: range.to,
      );
      if (!mounted) return;
      setState(() {
        _movements = movements;
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
    final summaryOnly = widget.org.visibility == 'summary';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.account.label),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${widget.account.code} · '
              '${accountTypeLabel(widget.account.type)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
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
              isEmpty: _movements.isEmpty,
              emptyMessage: summaryOnly
                  ? 'Votre accès porte sur les totaux. Le détail des '
                      'mouvements ne vous est pas communiqué.'
                  : 'Aucun mouvement sur ce compte pour cette période.',
              child: ListView.separated(
                itemCount: _movements.length + 1,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == 0) return _header(theme, money);
                  return _MovementTile(
                    movement: _movements[index - 1],
                    money: money,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, NumberFormat money) {
    // The top row is the newest movement, so its running balance is the
    // closing one for the period.
    final closing = _movements.isEmpty ? 0.0 : _movements.first.balance;

    var debit = 0.0;
    var credit = 0.0;
    for (final m in _movements) {
      debit += m.debit;
      credit += m.credit;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatTile(
            label: 'Solde à la fin de la période',
            amount: closing,
            money: money,
            emphasis: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(label: 'Entré', amount: debit, money: money),
              ),
              Expanded(
                child: StatTile(label: 'Sorti', amount: credit, money: money),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, required this.money});

  final LedgerMovement movement;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = movement.signed >= 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        movement.label,
        style: TextStyle(
          decoration: movement.reversed ? TextDecoration.lineThrough : null,
          color: movement.reversed ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Text(
        [
          DateFormat('d MMM y', 'fr_FR').format(movement.occurredAt),
          movement.recordedBy,
          if (movement.memo != null && movement.memo!.isNotEmpty)
            movement.memo!,
          if (movement.reversed) 'corrigé',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${positive ? '+' : '−'}${money.format(movement.signed.abs())}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: positive ? Colors.green.shade800 : Colors.orange.shade900,
            ),
          ),
          // Greyed and smaller than the movement itself: the balance is
          // context for the number above it, and a column of two equally loud
          // figures is a column nobody can scan.
          Text(
            money.format(movement.balance),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
