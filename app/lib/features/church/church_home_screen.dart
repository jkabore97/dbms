import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/local_db.dart';
import 'record_contribution_sheet.dart';
import 'record_expense_sheet.dart';

/// Israel's home screen.
///
/// Three design decisions, all deliberate:
///
/// 1. The primary action is enormous and always visible. Recording an offering
///    is the reason the app exists; it is never more than one tap away.
/// 2. Today's total is shown at the top, updating instantly from local data.
///    Progress you can see is progress you keep making.
/// 3. Pending sync count is always honest. A user who is unsure whether their
///    work was saved will re-enter it, and double-counted offerings destroy
///    trust faster than any bug.
class ChurchHomeScreen extends StatefulWidget {
  const ChurchHomeScreen({
    super.key,
    required this.db,
    required this.orgId,
    required this.orgName,
    this.accountAction,
  });

  final LocalDb db;
  final String orgId;
  final String orgName;

  /// The account menu, supplied by whatever resolved the org — sign out and
  /// switch business live there.
  final Widget? accountAction;

  @override
  State<ChurchHomeScreen> createState() => _ChurchHomeScreenState();
}

class _ChurchHomeScreenState extends State<ChurchHomeScreen> {
  final _currency = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: 'FCFA',
    decimalDigits: 0,
  );

  double _moneyIn = 0;
  double _moneyOut = 0;
  int _pending = 0;
  List<Map<String, Object?>> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final today = DateTime.now();
    final totals = await widget.db.dayTotals(widget.orgId, today);
    final entries = await widget.db.entriesForDay(widget.orgId, today);
    final pending = await widget.db.pendingCount();

    if (!mounted) return;
    setState(() {
      _moneyIn = totals.moneyIn;
      _moneyOut = totals.moneyOut;
      _entries = entries;
      _pending = pending;
      _loading = false;
    });
  }

  Future<void> _openRecordSheet() async {
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordContributionSheet(
        db: widget.db,
        orgId: widget.orgId,
      ),
    );

    if (recorded == true) await _refresh();
  }

  Future<void> _openExpenseSheet() async {
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordExpenseSheet(
        db: widget.db,
        orgId: widget.orgId,
      ),
    );

    if (recorded == true) await _refresh();
  }

  Future<void> _undo(Map<String, Object?> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler cette entrée ?'),
        content: const Text(
          "L'entrée reste visible dans l'historique, marquée comme corrigée. "
          "Rien n'est supprimé.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Annuler l\'entrée'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.db.reverse(
      entry['client_uuid'] as String,
      reason: 'Correction',
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.orgName),
        actions: [
          if (_pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.cloud_upload_outlined, size: 16),
                  label: Text('$_pending en attente'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          if (widget.accountAction != null) widget.accountAction!,
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _TodayCard(
                    moneyIn: _moneyIn,
                    moneyOut: _moneyOut,
                    currency: _currency,
                  ),
                  const SizedBox(height: 24),
                  Text("Aujourd'hui", style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'Rien enregistré aujourd\'hui.\nAppuyez sur le bouton pour commencer.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._entries.map(
                      (e) => _EntryTile(
                        entry: e,
                        currency: _currency,
                        onUndo: () => _undo(e),
                      ),
                    ),
                  const SizedBox(height: 96),
                ],
              ),
            ),
      // Two buttons, not one with a mode. Money in and money out are different
      // acts with different consequences, and a toggle at the top of a sheet is
      // exactly the control someone taps past while concentrating on the
      // number. They differ in colour, in icon, in wording and in size — the
      // arrows match the ones on the rows each button produces.
      //
      // Recording money in stays the larger and louder of the two: it is the
      // reason the app exists and it happens many times for every expense.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'record-expense',
            onPressed: _openExpenseSheet,
            backgroundColor: Colors.orange.shade100,
            foregroundColor: Colors.orange.shade900,
            icon: const Icon(Icons.arrow_upward, size: 20),
            label: const Text(
              'Dépense',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'record-income',
            onPressed: _openRecordSheet,
            icon: const Icon(Icons.arrow_downward, size: 28),
            label: const Text(
              'Recette',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            extendedPadding: const EdgeInsets.symmetric(horizontal: 32),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.moneyIn,
    required this.moneyOut,
    required this.currency,
  });

  final double moneyIn;
  final double moneyOut;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now()),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              currency.format(moneyIn),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            Text(
              'reçu aujourd\'hui',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            if (moneyOut > 0) ...[
              const SizedBox(height: 12),
              Text(
                '${currency.format(moneyOut)} dépensé',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.currency,
    required this.onUndo,
  });

  final Map<String, Object?> entry;
  final NumberFormat currency;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final reversed = (entry['reversed'] as int? ?? 0) == 1;
    final isIncome = entry['direction'] == 'in';
    final amount = (entry['amount'] as num).toDouble();
    final memberName = entry['member_name'] as String?;
    final time = DateTime.parse(entry['occurred_at'] as String).toLocal();

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: reversed
            ? Colors.grey.shade300
            : isIncome
                ? Colors.green.shade100
                : Colors.orange.shade100,
        child: Icon(
          reversed
              ? Icons.undo
              : isIncome
                  ? Icons.arrow_downward
                  : Icons.arrow_upward,
          color: reversed
              ? Colors.grey
              : isIncome
                  ? Colors.green.shade800
                  : Colors.orange.shade800,
        ),
      ),
      title: Text(
        entry['label'] as String,
        style: TextStyle(
          decoration: reversed ? TextDecoration.lineThrough : null,
          color: reversed ? Colors.grey : null,
        ),
      ),
      subtitle: Text(
        [
          DateFormat.Hm().format(time),
          if (memberName != null) memberName,
          if (reversed) 'corrigé',
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            currency.format(amount),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              decoration: reversed ? TextDecoration.lineThrough : null,
              color: reversed ? Colors.grey : null,
            ),
          ),
          if (!reversed)
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: onUndo,
              tooltip: 'Annuler',
            ),
        ],
      ),
    );
  }
}
