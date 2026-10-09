import 'package:flutter/material.dart';

import '../cauris/path_card.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/format/money.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/credit/credit_repository.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../common/step_flow.dart';
import '../../core/retail/retail_repository.dart';
import '../../l10n/strings.dart';
import 'credit_flows.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// Qui me doit combien — the carnet de crédit.
///
/// Sorted oldest debt first, because that is the collection order: the
/// screen's job is to answer "who do I visit today", not to be a report.
/// Amounts are large and names are larger; this is read behind a counter,
/// not at a desk. A customer past the date they gave (117) says so in red.
///
/// Its two acts are flows (115), the same for a shop, a farm and an
/// association: « Nouveau crédit » and « Remboursement » (credit_flows.dart).
class CreditBookScreen extends StatefulWidget {
  const CreditBookScreen({
    super.key,
    required this.org,
    required this.credit,
    required this.retail,
    this.access = OrgAccess.allEdit,
  });

  /// The owner's dial: at 'view' the carnet is read-only here.
  final OrgAccess access;

  final OrgSummary org;
  final CreditRepository credit;

  /// The store side, so a credit sale in the carnet picks real products and
  /// moves stock through the same record_sale() path a cash sale uses —
  /// instead of a free-text line unrelated to the inventory.
  final RetailRepository retail;

  @override
  State<CreditBookScreen> createState() => _CreditBookScreenState();
}

/// The earliest date a customer gave for what is still open, by customer.
Map<String, DateTime> _earliest(List<DebtDate> dates) {
  final out = <String, DateTime>{};
  for (final d in dates) {
    final had = out[d.customerId];
    if (had == null || d.dueOn.isBefore(had)) out[d.customerId] = d.dueOn;
  }
  return out;
}

bool _late(DateTime due) {
  final now = DateTime.now();
  return due.isBefore(DateTime(now.year, now.month, now.day));
}

class _CreditBookScreenState extends State<CreditBookScreen> {
  List<DebtorRow> _rows = const [];
  Map<String, DateTime> _due = const {};
  bool _loading = true;
  String? _error;

  NumberFormat get _money => moneyFormat(widget.org.currency);
  late final _date = DateFormat('d MMM', 'fr_FR');

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
      final rows = await widget.credit.debtors(widget.org.id);
      // Before 117 is on the server: no dates, the carnet as it was.
      var due = const <String, DateTime>{};
      try {
        due = _earliest(await widget.credit.dueDates(widget.org.id));
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _due = due;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  /// Locked (089): what was kept is read, nothing new is written.
  bool _locked() {
    if (!PathGate.locks(context, widget.org, 'credits')) return false;
    PathGate.guard(context, widget.org, 'credits', () {});
    return true;
  }

  Future<void> _newCredit() async {
    if (_locked()) return;
    final done = await StepFlow.push(
      context,
      NewCreditFlow(
        org: widget.org,
        credit: widget.credit,
        retail: widget.retail,
        db: AppScope.maybeOf(context)?.db,
        debtors: _rows,
      ),
    );
    if (done == true && mounted) await _load();
  }

  Future<void> _repay() async {
    final done = await StepFlow.push(
      context,
      RepayFlow(org: widget.org, credit: widget.credit, debtors: _rows),
    );
    if (done == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final theme = Theme.of(context);
    final total = _rows.fold<double>(0, (s, r) => s + r.totalOwed);
    final canEdit = widget.access.canEdit('credits');

    return Scaffold(
      appBar: AppBar(title: Text(strings.creditBook)),
      floatingActionButton: !canEdit
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_rows.isNotEmpty) ...[
                  FloatingActionButton.extended(
                    key: const Key('credit-repay'),
                    heroTag: 'credit-repay',
                    onPressed: _repay,
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    foregroundColor: theme.colorScheme.onSecondaryContainer,
                    icon: const Icon(Icons.savings_outlined),
                    label: Text(context.tr('Remboursement')),
                  ),
                  const SizedBox(height: 12),
                ],
                FloatingActionButton.extended(
                  key: const Key('credit-new'),
                  heroTag: 'credit-new',
                  onPressed: _newCredit,
                  icon: const Icon(Icons.handshake_outlined),
                  label: Text(context.tr('Nouveau crédit')),
                ),
              ],
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: _load, child: Text(strings.retry)),
                      ],
                    ),
                  ),
                )
              : _rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          strings.noDebtors,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              strings.totalOutstanding(
                                  '${_money.format(total)} '
                                  '${widget.org.currency}'),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          for (final row in _rows)
                            KajCard(
                              child: ListTile(
                                title: Text(row.name,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600)),
                                subtitle: _subtitle(context, row),
                                trailing: Text(
                                  _money.format(row.totalOwed),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                onTap: () async {
                                  await context.push(Routes.inside(
                                      widget.org.id,
                                      'credits/${row.customerId}'));
                                  if (mounted) await _load();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }

  /// How old the debt is, and the date given — in red once it has passed.
  Widget? _subtitle(BuildContext context, DebtorRow row) {
    final strings = Strings.of(context);
    final due = _due[row.customerId];
    final age = row.daysOld == null ? null : strings.owedForDays(row.daysOld!);
    if (due == null) return age == null ? null : Text(age);
    final late = _late(due);
    final word = late
        ? context.tr('En retard depuis le {date}', {'date': _date.format(due)})
        : context.tr('À payer le {date}', {'date': _date.format(due)});
    return Text(
      [?age, word].join(' · '),
      style: late
          ? TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600)
          : null,
    );
  }
}

/// One customer's page of the carnet: each debt, what remains, the date
/// given, the reminder and the repayment. Lives at its own address so it
/// can be reopened from the list after a refresh.
class CustomerDebtsScreen extends StatefulWidget {
  const CustomerDebtsScreen({
    super.key,
    required this.org,
    required this.credit,
    required this.customerId,
    this.access = OrgAccess.allEdit,
  });

  /// The owner's dial: at 'view' debts are read, never settled here.
  final OrgAccess access;

  final OrgSummary org;
  final CreditRepository credit;
  final String customerId;

  @override
  State<CustomerDebtsScreen> createState() => _CustomerDebtsScreenState();
}

class _CustomerDebtsScreenState extends State<CustomerDebtsScreen> {
  List<DebtRow> _rows = const [];
  List<DebtorRow> _debtors = const [];
  Map<String, DateTime> _due = const {};
  bool _loading = true;
  String? _error;

  NumberFormat get _money => moneyFormat(widget.org.currency);
  late final _date = DateFormat('d MMM y', 'fr_FR');

  DebtorRow? get _me {
    for (final d in _debtors) {
      if (d.customerId == widget.customerId) return d;
    }
    return null;
  }

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
      final rows =
          await widget.credit.debtsOf(widget.org.id, widget.customerId);
      final debtors = await widget.credit.debtors(widget.org.id);
      var due = const <String, DateTime>{};
      try {
        due = {
          for (final d in await widget.credit.dueDates(widget.org.id))
            d.debtId: d.dueOn,
        };
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _debtors = debtors;
        _due = due;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _repay() async {
    final done = await StepFlow.push(
      context,
      RepayFlow(
        org: widget.org,
        credit: widget.credit,
        debtors: _debtors,
        customerId: widget.customerId,
      ),
    );
    if (done == true && mounted) await _load();
  }

  void _remind(DebtorRow me) {
    final open = [for (final r in _rows) if (r.remaining > 0) _due[r.debtId]]
        .whereType<DateTime>()
        .toList()
      ..sort();
    sendReminder(
      me.phone,
      creditReminder(context,
          customer: me.name,
          business: widget.org.name,
          amount: _money.format(me.totalOwed),
          due: open.isEmpty ? null : open.first),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final theme = Theme.of(context);
    final remaining = _rows.fold<double>(0, (s, r) => s + r.remaining);
    final me = _me;
    final canEdit = widget.access.canEdit('credits');

    return Scaffold(
      appBar: AppBar(title: Text(me?.name ?? strings.creditBook)),
      floatingActionButton: !canEdit || remaining <= 0
          ? null
          : FloatingActionButton.extended(
              key: const Key('customer-repay'),
              onPressed: _repay,
              icon: const Icon(Icons.savings_outlined),
              label: Text(context.tr('Remboursement')),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        strings.totalOutstanding(
                            '${_money.format(remaining)} '
                            '${widget.org.currency}'),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    if (me != null && remaining > 0) ...[
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          key: const Key('customer-remind'),
                          onPressed: () => _remind(me),
                          icon: const Icon(Icons.chat_outlined),
                          label: Text(context.tr('Envoyer un rappel sur WhatsApp')),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    for (final debt in _rows)
                      KajCard(
                        child: ListTile(
                          title: Text(debt.label),
                          subtitle: Text([
                            '${_date.format(debt.occurredAt)} · '
                                '${_money.format(debt.amount)}'
                                '${debt.paid > 0 ? ' − ${_money.format(debt.paid)}' : ''}',
                            if (_due[debt.debtId] != null)
                              _late(_due[debt.debtId]!)
                                  ? context.tr('En retard depuis le {date}',
                                      {'date': _date.format(_due[debt.debtId]!)})
                                  : context.tr('À payer le {date}',
                                      {'date': _date.format(_due[debt.debtId]!)}),
                          ].join('\n')),
                          trailing: debt.remaining <= 0
                              ? Icon(Icons.check_circle,
                                  color: theme.colorScheme.primary)
                              : Text(_money.format(debt.remaining),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                      color: _due[debt.debtId] != null &&
                                              _late(_due[debt.debtId]!)
                                          ? theme.colorScheme.error
                                          : null)),
                        ),
                      ),
                  ],
                ),
    );
  }
}
