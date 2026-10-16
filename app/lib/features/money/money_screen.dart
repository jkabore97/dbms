import '../../core/money/money_types.dart' show canWriteTypes;
import '../../core/nav/app_scope.dart';
import 'package:flutter/material.dart';

import '../../core/access/org_access.dart';
import '../../core/accounting/accounting_repository.dart';
import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/credit/credit_repository.dart';
import '../../core/db/local_db.dart';
import '../../core/format/money.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/retail/retail_repository.dart';
import '../accounting/journal_screen.dart';
import '../cauris/path_card.dart';
import '../common/step_flow.dart';
import '../credit/credit_book_screen.dart';
import '../home/place_sections.dart';
import '../invoicing/invoices_screen.dart';
import 'expense_flow.dart';

/// « Argent » (134), the shop's fourth place: one question — « où en est
/// mon argent ? ».
///
/// Four numbers at the top for the month — what came in, what went out,
/// what customers owe, the invoices not paid — then three sections, each
/// the screen the shop already had: Factures, Dépenses (the books' money
/// out, with « Dépense » to note one more) and Crédit (the carnet). One
/// address, `argent?partie=factures|depenses|credit`; the old `factures`
/// and `credits` land here, on their section.
///
/// Factures' lock (089 — invoices open with articles and photos, or Pro)
/// stays exactly as it was: from the switch, a locked Factures shows the
/// lock with « lecture seule » beside it, as the bar's Factures did; inside
/// it, a new invoice is still refused while locked. The carnet's own lock
/// is asked the same way.
class MoneyScreen extends StatefulWidget {
  const MoneyScreen({
    super.key,
    required this.org,
    this.invoicing,
    this.credit,
    this.retail,
    this.accounting,
    this.db,
    this.capture,
    this.access = OrgAccess.allEdit,
    this.initialPart,
  });

  final OrgSummary org;
  final InvoicingRepository? invoicing;
  final CreditRepository? credit;
  final RetailRepository? retail;
  final AccountingRepository? accounting;

  /// The phone's outbox, where a « Dépense » is written first.
  final LocalDb? db;
  final CaptureRepository? capture;
  final OrgAccess access;

  /// `?partie=`: 'factures', 'depenses' or 'credit'.
  final String? initialPart;

  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  double? _in;
  double? _out;
  double? _owed;
  int? _unpaid;

  OrgSummary get _org => widget.org;

  bool get _invoicesShown =>
      widget.invoicing != null && widget.access.canSee('invoices');
  bool get _expensesShown =>
      widget.accounting != null && widget.access.canSee('reports');
  bool get _creditShown =>
      widget.credit != null && widget.retail != null && widget.access.canSee('credits');

  @override
  void initState() {
    super.initState();
    _read();
  }

  /// The month's four numbers, each on its own: one the server refuses (the
  /// books closed to this person) leaves a dash, never the others blank.
  Future<void> _read() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final accounting = widget.accounting;
    if (accounting != null && accounting.isConfigured && widget.access.canSee('reports')) {
      try {
        final lines = await accounting.incomeStatement(_org.id, from: from, to: now);
        double total(String code) => lines
            .where((l) => l.section == 'total' && l.code == code)
            .fold(0.0, (s, l) => s + l.amount);
        if (mounted) {
          setState(() {
            _in = total('1');
            _out = total('2');
          });
        }
      } catch (_) {}
    }
    final credit = widget.credit;
    if (credit != null && credit.isConfigured && widget.access.canSee('credits')) {
      try {
        final rows = await credit.debtors(_org.id);
        if (mounted) {
          setState(() => _owed = rows.fold<double>(0, (s, r) => s + r.totalOwed));
        }
      } catch (_) {}
    }
    final invoicing = widget.invoicing;
    if (invoicing != null && invoicing.isConfigured && _invoicesShown) {
      try {
        final list = await invoicing.list(_org.id);
        if (mounted) {
          setState(() => _unpaid =
              list.where((i) => !i.cancelled && i.outstanding > 0).length);
        }
      } catch (_) {}
    }
  }

  /// Where Argent opens with no `?partie=`: Factures, unless it is locked
  /// (then the first section that is not), as the bar used to open on it.
  String? get _fallback {
    if (_invoicesShown && !PathGate.locks(context, _org, 'invoices')) return 'factures';
    if (_expensesShown) return 'depenses';
    if (_creditShown && !PathGate.locks(context, _org, 'credits')) return 'credit';
    return null;
  }

  void _enter(BuildContext context, String id, VoidCallback open) {
    switch (id) {
      case 'factures':
        PathGate.open(context, _org, 'invoices', open);
      case 'credit':
        PathGate.open(context, _org, 'credits', open);
      default:
        open();
    }
  }

  Future<bool> _expense() async {
    final db = widget.db;
    if (db == null) return false;
    final saved = await StepFlow.push(
      context,
      ExpenseFlow(
        db: db,
        orgId: _org.id,
        profile: _org.profile,
        currency: _org.currency,
        capture: widget.capture,
        types: AppScope.read(context)?.reports,
        canEditTypes: canWriteTypes(_org),
      ),
    );
    if (saved == true) await _read();
    return saved == true;
  }

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(_org.currency);
    String amount(double? v) => v == null ? '—' : money.format(v);
    return PlaceSections(
      title: context.tr('Argent'),
      initial: widget.initialPart,
      fallback: _fallback,
      enter: _enter,
      above: MoneyNumbers(
        tiles: [
          MoneyTile(
              key: const Key('money-in'),
              label: context.tr('Entré'),
              value: amount(_in),
              tone: MoneyTone.good),
          MoneyTile(key: const Key('money-out'), label: context.tr('Sorti'), value: amount(_out)),
          MoneyTile(
              key: const Key('money-owed'),
              label: context.tr('On me doit'),
              value: amount(_owed),
              tone: (_owed ?? 0) > 0 ? MoneyTone.warn : MoneyTone.plain),
          MoneyTile(
              key: const Key('money-unpaid'),
              label: context.tr('Factures impayées'),
              value: _unpaid == null ? '—' : '$_unpaid'),
        ],
      ),
      sections: [
        if (_invoicesShown)
          PlaceSection(
            id: 'factures',
            label: context.tr('Factures'),
            build: (_) => InvoicesScreen(org: _org, invoicing: widget.invoicing!),
          ),
        if (_expensesShown)
          PlaceSection(
            id: 'depenses',
            label: context.tr('Dépenses'),
            build: (_) => JournalScreen(
              accounting: widget.accounting!,
              org: _org,
              direction: 'out',
              onAdd: _org.isObserverOnly || widget.db == null ? null : _expense,
            ),
          ),
        if (_creditShown)
          PlaceSection(
            id: 'credit',
            label: context.tr('Crédit'),
            build: (_) => CreditBookScreen(
              org: _org,
              credit: widget.credit!,
              retail: widget.retail!,
              access: widget.access,
            ),
          ),
      ],
    );
  }
}

enum MoneyTone { plain, good, warn }

/// One of Argent's four numbers: its word, and the figure under it.
class MoneyTile {
  const MoneyTile({
    this.key,
    required this.label,
    required this.value,
    this.tone = MoneyTone.plain,
  });

  final Key? key;
  final String label;
  final String value;
  final MoneyTone tone;
}

/// The four numbers, two by two (134's mockup: Entré, Sorti, On me doit,
/// Factures impayées), « Ce mois » above them.
class MoneyNumbers extends StatelessWidget {
  const MoneyNumbers({super.key, required this.tiles});

  final List<MoneyTile> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget tile(MoneyTile t) => Expanded(
          child: Container(
            key: t.key,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Whole, smaller when it must (« Factures imp… » at 320
                // px and a large text size).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(t.label,
                      maxLines: 1,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t.value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: switch (t.tone) {
                        MoneyTone.good => Colors.green.shade800,
                        MoneyTone.warn => scheme.error,
                        MoneyTone.plain => scheme.onSurface,
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(Row(children: [
        tile(tiles[i]),
        const SizedBox(width: 8),
        if (i + 1 < tiles.length) tile(tiles[i + 1]) else const Spacer(),
      ]));
    }
    return Column(
      key: const Key('money-numbers'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_month_outlined, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(context.tr('Ce mois'),
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        ...rows,
      ],
    );
  }
}
