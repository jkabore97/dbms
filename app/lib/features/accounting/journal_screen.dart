import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/accounting/accounting_repository.dart';
import '../../core/accounting/models.dart';
import '../../core/auth/models.dart';
import 'report_shell.dart';

/// Every entry, newest first, in the words it was written in.
///
/// The home screen shows today. This is the same list for any period, and it
/// is the screen where the free-text names stop being a data-entry convenience
/// and start being the point: an entry called "Réparation du toit — côté est"
/// is findable eight months later, and an entry called "Fournitures" is not.
///
/// Both sides of each entry are named, because a journal that says only
/// "-45,000" cannot answer the question anybody actually brings to it, which
/// is "out of which pocket".
class JournalScreen extends StatefulWidget {
  const JournalScreen({
    super.key,
    required this.accounting,
    required this.org,
  });

  final AccountingRepository accounting;
  final OrgSummary org;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  static const _pageSize = 50;

  // Everything, not this month: the question this screen answers is "when did
  // we record that", and the entry being looked for is usually older than the
  // period a month-bounded default would have hidden it inside. The page size
  // makes that affordable — 50 rows arrive whatever the range.
  Period _period = Period.everything;
  List<JournalRow> _rows = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
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
      _exhausted = false;
    });
    try {
      final range = _period.range;
      final rows = await widget.accounting.journal(
        widget.org.id,
        from: range.from,
        to: range.to,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _exhausted = rows.length < _pageSize;
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

  /// Offset paging rather than keyset, unlike the audit log. The ledger is
  /// append-only and entries carry the date they happened rather than the date
  /// they arrived, so a page boundary here does not slide while somebody reads
  /// past it the way a live log's would.
  Future<void> _loadMore() async {
    if (_loadingMore || _exhausted || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final range = _period.range;
      final more = await widget.accounting.journal(
        widget.org.id,
        from: range.from,
        to: range.to,
        limit: _pageSize,
        offset: _rows.length,
      );
      if (!mounted) return;
      setState(() {
        _rows = [..._rows, ...more];
        _exhausted = more.length < _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(widget.org.currency);
    final summaryOnly = widget.org.visibility == 'summary';

    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
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
              emptyMessage: summaryOnly
                  ? 'Votre accès porte sur les totaux. Le détail des écritures '
                      'ne vous est pas communiqué.'
                  : 'Aucune écriture sur cette période.',
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.extentAfter < 400) _loadMore();
                  return false;
                },
                child: ListView.separated(
                  itemCount: _rows.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index == _rows.length) return _footer();
                    return _JournalTile(row: _rows[index], money: money);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: 48);
  }
}

class _JournalTile extends StatelessWidget {
  const _JournalTile({required this.row, required this.money});

  final JournalRow row;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, tint) = switch (row.direction) {
      'in' => (Icons.arrow_downward, Colors.green.shade800),
      'out' => (Icons.arrow_upward, Colors.orange.shade800),
      _ => (Icons.swap_horiz, Colors.blueGrey.shade700),
    };

    // Reversed, or itself a reversal. Both stay visible — nothing is ever
    // deleted from the ledger — and both are struck through so a reader
    // totalling a column by eye does not count them.
    final cancelled = row.reversed || row.isReversal;

    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: cancelled
            ? theme.colorScheme.surfaceContainerHighest
            : tint.withValues(alpha: 0.12),
        child: Icon(
          cancelled ? Icons.undo : icon,
          size: 20,
          color: cancelled ? theme.colorScheme.onSurfaceVariant : tint,
        ),
      ),
      title: Text(
        row.label,
        style: TextStyle(
          decoration: cancelled ? TextDecoration.lineThrough : null,
          color: cancelled ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Text(
        [
          DateFormat('d MMM', 'fr_FR').format(row.occurredAt),
          row.recordedBy,
          if (row.isReversal) 'correction',
          if (row.reversed) 'corrigé',
        ].join(' · '),
      ),
      trailing: Text(
        money.format(row.amount),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          decoration: cancelled ? TextDecoration.lineThrough : null,
          color: cancelled ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Debit and credit, named rather than numbered. Israel never
              // sees the words "débit" and "crédit" anywhere else in the app
              // and does not need to see them here either — "Vers" and "De"
              // say the same thing about where the money went.
              _Fact(label: 'Vers', value: row.debitLabel),
              _Fact(label: 'De', value: row.creditLabel),
              if (row.memo != null && row.memo!.isNotEmpty)
                _Fact(label: 'Note', value: row.memo!),
              for (final entry in row.details.entries)
                _Fact(label: entry.key, value: '${entry.value}'),
              _Fact(
                label: 'Enregistré',
                value: DateFormat('d MMMM y à HH:mm', 'fr_FR')
                    .format(row.occurredAt),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
