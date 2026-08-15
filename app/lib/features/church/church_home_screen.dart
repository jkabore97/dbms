import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/retail/staff.dart';
import '../../core/db/local_db.dart';
import '../../core/reports/models.dart' show accountLabel;
import '../../core/reports/reports_repository.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/invoicing/invoicing_repository.dart';
import 'close_day_sheet.dart';
import 'record_entry_sheet.dart';
import 'record_transfer_sheet.dart';
import '../../core/nav/router.dart';

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
    this.invoicing,
    required this.db,
    required this.orgId,
    required this.orgName,
    this.reports,
    this.org,
    this.capture,
    this.staff,
    this.accountAction,
    this.onHistory,
  });

  final LocalDb db;
  final String orgId;
  final String orgName;

  /// Null in a build with no server: the reports are computed by SQL functions
  /// and there is nothing offline to compute them from.
  final ReportsRepository? reports;

  /// The membership this screen was opened under — carries the currency and
  /// the observer's visibility.
  final OrgSummary? org;

  /// The account menu, supplied by whatever resolved the org — sign out and
  /// switch business live there.
  /// Photographs. A church has receipts too — the mason's invoice for the
  /// roof is the same object as a shop's delivery note. Null in a build with
  /// no server or no upload Worker, and the button is then not shown.
  final CaptureRepository? capture;

  /// Staff. Every business has people; 012 built the payroll behind a shop's
  /// home screen and 018 made the records general enough for a church's
  /// volunteers and a farm's seasonal hands. Null in a build with no server,
  /// and every screen behind it is refused by RLS for anyone who is not an
  /// org admin.
  final StaffRepository? staff;

  /// Invoicing. Every business bills somebody — a shop bills a
  /// wholesaler, a church bills a hall hire — and until 020 this was
  /// reachable from the farm alone. Null in a build with no server:
  /// invoicing is the one thing here that cannot work offline.
  final InvoicingRepository? invoicing;

  final Widget? accountAction;

  /// Opens the history of every entry ever recorded. Null in a build with no
  /// server, and null once the token has expired: the list is paginated by the
  /// database and there is nothing offline to page through.
  final VoidCallback? onHistory;

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
  bool _dayClosed = false;

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
    final closed = await widget.db.isDayClosed(widget.orgId, today);

    if (!mounted) return;
    setState(() {
      _dayClosed = closed;
      _moneyIn = totals.moneyIn;
      _moneyOut = totals.moneyOut;
      _entries = entries;
      _pending = pending;
      _loading = false;
    });
  }

  /// Money in and money out are the same sheet with the direction flipped, so
  /// the only thing that varies between the two buttons is what they mean.
  Future<void> _openRecordSheet(String direction) async {
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordEntrySheet(
        db: widget.db,
        orgId: widget.orgId,
        direction: direction,
      ),
    );

    if (recorded == true) await _refresh();
  }

  Future<void> _openTransferSheet() async {
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordTransferSheet(
        db: widget.db,
        orgId: widget.orgId,
      ),
    );

    if (recorded == true) await _refresh();
  }

  Future<void> _openCloseDay() async {
    final closed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CloseDaySheet(
        db: widget.db,
        orgId: widget.orgId,
        currency: widget.org?.currency ?? 'XOF',
      ),
    );

    if (closed == true) {
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Journée clôturée')),
      );
    }
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
          if (widget.invoicing != null && widget.org != null)
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Factures',
              onPressed: () =>
                  context.push(Routes.inside(widget.org!.id, 'factures')),
            ),
          if (widget.reports != null && widget.org != null)
            IconButton(
              icon: const Icon(Icons.assessment_outlined),
              tooltip: 'Rapports',
              onPressed: () =>
                  context.push(Routes.inside(widget.org!.id, 'rapports')),
            ),
          // A peer of Rapports rather than something to be found three taps
          // down inside Comptabilité: "when did we record that" is a question
          // any member asks, not an accounting exercise. Absent for an
          // observer on 'summary' visibility, whose grant is the totals and
          // for whom this screen would only ever be an empty list with an
          // explanation — see journal_page, which returns them no rows.
          if (widget.onHistory != null && widget.org?.visibility != 'summary')
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Historique',
              onPressed: widget.onHistory,
            ),
          if (widget.capture != null &&
              widget.capture!.isConfigured &&
              widget.org != null)
            IconButton(
              icon: const Icon(Icons.photo_camera_outlined),
              tooltip: 'Photos',
              onPressed: () =>
                  context.push(Routes.inside(widget.org!.id, 'photos')),
            ),
          if (widget.staff != null && widget.org != null && widget.org!.isAdmin)
            IconButton(
              icon: const Icon(Icons.groups_outlined),
              tooltip: 'Personnel',
              onPressed: () =>
                  context.push(Routes.inside(widget.org!.id, 'personnel')),
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
                  const SizedBox(height: 24),
                  // At the foot of the day it closes, rather than in a menu:
                  // the gesture belongs at the end of the list it is agreeing
                  // with.
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _openCloseDay,
                      icon: Icon(
                        _dayClosed
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                      ),
                      label: Text(
                        _dayClosed ? 'Journée clôturée' : 'Clôturer la journée',
                        style: const TextStyle(fontSize: 16),
                      ),
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
          // Smaller and unlabelled, unlike the other two. A transfer is a
          // bookkeeping correctness feature — it stops banking the offering
          // being recorded as earning it twice — and it happens once a week
          // where a contribution happens forty times on a Sunday.
          FloatingActionButton.small(
            heroTag: 'record-transfer',
            onPressed: _openTransferSheet,
            tooltip: 'Transfert entre caisses',
            backgroundColor: theme.colorScheme.tertiaryContainer,
            foregroundColor: theme.colorScheme.onTertiaryContainer,
            child: const Icon(Icons.swap_horiz),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'record-expense',
            onPressed: () => _openRecordSheet('out'),
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
            onPressed: () => _openRecordSheet('in'),
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

    // The gradient is what makes this read as a screen rather than a printed
    // form. The palette's ink on it, not white: the wash is pale by design
    // and white measured well under the readable threshold on it.
    final on = KajTheme.of(context).ink;
    return Card(
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(gradient: kajGradient(KajTheme.of(context))),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now()),
              style: theme.textTheme.labelLarge?.copyWith(
                color: on.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              currency.format(moneyIn),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: on,
              ),
            ),
            Text(
              'reçu aujourd\'hui',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: on,
              ),
            ),
            if (moneyOut > 0) ...[
              const SizedBox(height: 12),
              Text(
                '${currency.format(moneyOut)} dépensé',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: on.withValues(alpha: 0.82),
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
    final direction = entry['direction'] as String;
    final amount = (entry['amount'] as num).toDouble();
    final memberName = entry['member_name'] as String?;
    final time = DateTime.parse(entry['occurred_at'] as String).toLocal();

    final label = entry['label'] as String;
    final category = entry['category'] as String?;
    final memo = entry['memo'] as String?;
    final hasDetails = (entry['details'] as String?)?.isNotEmpty ?? false;

    final (icon, tint, wash) = switch (direction) {
      'in' => (
          Icons.arrow_downward,
          Colors.green.shade800,
          Colors.green.shade100
        ),
      'out' => (
          Icons.arrow_upward,
          Colors.orange.shade800,
          Colors.orange.shade100
        ),
      _ => (
          Icons.swap_horiz,
          Colors.blueGrey.shade700,
          Colors.blueGrey.shade100
        ),
    };

    // The category, but only when it says something the name did not. Most
    // entries are named after the category they are filed under, and repeating
    // the word underneath itself is noise on a screen read in poor light.
    final categoryNote = (category == null ||
            category.toLowerCase() == label.toLowerCase() ||
            accountLabel(category).toLowerCase() == label.toLowerCase())
        ? null
        : accountLabel(category);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: reversed ? Colors.grey.shade300 : wash,
        child: Icon(reversed ? Icons.undo : icon,
            color: reversed ? Colors.grey : tint),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                decoration: reversed ? TextDecoration.lineThrough : null,
                color: reversed ? Colors.grey : null,
              ),
            ),
          ),
          // A note or a characteristic was typed with this entry. Marked
          // rather than shown: the row is a list item, not a record card, and
          // whoever typed it needs to know it was kept.
          if (hasDetails || (memo != null && memo.isNotEmpty)) ...[
            const SizedBox(width: 6),
            Icon(Icons.notes, size: 14, color: Colors.grey.shade500),
          ],
        ],
      ),
      subtitle: Text(
        [
          DateFormat.Hm().format(time),
          if (categoryNote != null) categoryNote,
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
