import 'package:flutter/material.dart';
import '../../core/format/money.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/credit/credit_repository.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';
import '../retail/sale_sheet.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/retail/models.dart';
import '../../l10n/strings.dart';

/// Qui me doit combien — the carnet de crédit.
///
/// Sorted oldest debt first, because that is the collection order: the
/// screen's job is to answer "who do I visit today", not to be a report.
/// Amounts are large and names are larger; this is read behind a counter,
/// not at a desk.
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

class _CreditBookScreenState extends State<CreditBookScreen> {
  List<DebtorRow> _rows = const [];
  bool _loading = true;
  String? _error;

  NumberFormat get _money => moneyFormat(widget.org.currency);

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
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  /// A credit sale, product-backed: the same SaleSheet the store uses, opened
  /// on the Crédit method, so it picks real articles, moves stock and snapshots
  /// cost, and the debt it records is linked to that sale — not a free-text
  /// line unrelated to the inventory.
  Future<void> _newSale() async {
    List<Product> products = const [];
    try {
      products = await widget.retail.products(widget.org.id);
    } catch (_) {
      // Offline: the sheet still lets a name be typed; better than blocking.
    }
    if (!mounted) return;
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SaleSheet(
        orgId: widget.org.id,
        retail: widget.retail,
        currency: widget.org.currency,
        products: products,
        initialMethod: 'credit',
      ),
    );
    if (done == true && mounted) await _load();
  }

  /// A debt with no article behind it — money lent, a service owed. Kept as a
  /// deliberate secondary path: most carnet entries are goods taken on trust,
  /// which now go through _newSale; this is the exception, not the door.
  Future<void> _newLoan() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreditSaleSheet(org: widget.org, credit: widget.credit),
    );
    if (done == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final theme = Theme.of(context);
    final total = _rows.fold<double>(0, (s, r) => s + r.totalOwed);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.creditBook),
        actions: [
          if (widget.access.canEdit('credits'))
            IconButton(
              tooltip: 'Dette sans article (prêt)',
              icon: const Icon(Icons.request_quote_outlined),
              onPressed: _newLoan,
            ),
        ],
      ),
      floatingActionButton: !widget.access.canEdit('credits')
          ? null
          : FloatingActionButton.extended(
        onPressed: _newSale,
        icon: const Icon(Icons.handshake_outlined),
        label: Text(strings.creditSale),
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
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
                            Card(
                              child: ListTile(
                                title: Text(row.name,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  row.daysOld == null
                                      ? ''
                                      : strings.owedForDays(row.daysOld!),
                                ),
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
}

/// One customer's page of the carnet: each debt, what remains, and the
/// repayment button. Lives at its own address so it can be reopened from the
/// list after a refresh.
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
  bool _loading = true;
  String? _error;

  NumberFormat get _money => moneyFormat(widget.org.currency);
  late final _date = DateFormat('d MMM y', 'fr_FR');

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
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  Future<void> _repay(DebtRow debt) async {
    final strings = Strings.of(context);
    final controller =
        TextEditingController(text: debt.remaining.toStringAsFixed(0));
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.recordRepayment),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: strings.amount,
            helperText: strings.remainingOf(
                '${_money.format(debt.remaining)} ${widget.org.currency}'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: Text(strings.save),
          ),
        ],
      ),
    );
    if (amount == null || amount <= 0 || !mounted) return;
    try {
      await widget.credit.recordPayment(debtId: debt.debtId, amount: amount);
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final theme = Theme.of(context);
    final remaining = _rows.fold<double>(0, (s, r) => s + r.remaining);

    return Scaffold(
      appBar: AppBar(title: Text(strings.creditBook)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
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
                    for (final debt in _rows)
                      Card(
                        child: ListTile(
                          title: Text(debt.label),
                          subtitle: Text(
                            '${_date.format(debt.occurredAt)} · '
                            '${_money.format(debt.amount)}'
                            '${debt.paid > 0 ? ' − ${_money.format(debt.paid)}' : ''}',
                          ),
                          trailing: debt.remaining <= 0
                              ? Icon(Icons.check_circle,
                                  color: theme.colorScheme.primary)
                              : FilledButton.tonal(
                                  onPressed:
                                      widget.access.canEdit('credits')
                                          ? () => _repay(debt)
                                          : null,
                                  child: Text(_money.format(debt.remaining)),
                                ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// Recording a sale on credit: a name, an amount, a label. Three fields,
/// because the queue at the counter is real.
class _CreditSaleSheet extends StatefulWidget {
  const _CreditSaleSheet({required this.org, required this.credit});

  final OrgSummary org;
  final CreditRepository credit;

  @override
  State<_CreditSaleSheet> createState() => _CreditSaleSheetState();
}

class _CreditSaleSheetState extends State<_CreditSaleSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _label = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final strings = Strings.of(context);
    final amount = double.tryParse(_amount.text.trim());
    if (_name.text.trim().isEmpty) {
      setState(() => _error = strings.enterCustomerName);
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = strings.enterAmount);
      return;
    }
    if (_label.text.trim().isEmpty) {
      setState(() => _error = strings.enterLabel);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.credit.recordCreditSale(
        orgId: widget.org.id,
        customerName: _name.text.trim(),
        amount: amount,
        label: _label.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.creditSale,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            enabled: !_busy,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: strings.customerName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: strings.amount,
              suffixText: widget.org.currency,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _label,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: strings.whatWasSold,
              hintText: strings.whatWasSoldHint,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(strings.save),
            ),
          ),
        ],
      ),
    );
  }
}
