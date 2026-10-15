import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/retail/fraud_guards.dart';
import '../../core/theme/mara_sheet.dart';
import '../common/keyboard_sheet.dart';

/// « Clôturer la caisse » (batch 151): the end of the day at the till, for
/// a shop and a farm (both sell through the same till). The association's
/// « Clôturer la journée » (close_day_sheet.dart) is its own, on the phone.
///
/// Counted blind: the person counts the cash in the drawer without being
/// shown what the server expects, then Mara says the expected — the change
/// the till started with, the day's cash sales, less its cash returns — and
/// the gap. Kept on the server (146), journaled in the business's Activité;
/// the owner reads every closing below, a cashier their own.
class TillCloseSheet extends StatefulWidget {
  const TillCloseSheet({super.key, required this.org, required this.guards, this.today});

  final OrgSummary org;
  final FraudGuardsRepository guards;

  /// The phone's « now » (tests give one).
  final DateTime? today;

  static Future<void> open(BuildContext context, OrgSummary org, FraudGuardsRepository guards) =>
      showMaraSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => TillCloseSheet(org: org, guards: guards),
      );

  @override
  State<TillCloseSheet> createState() => _TillCloseSheetState();
}

class _TillCloseSheetState extends State<TillCloseSheet> {
  final _counted = TextEditingController();
  final _float = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  bool _missing = false;
  String? _error;
  TillClosing? _done;
  List<TillClosing> _history = const [];

  DateTime get _now => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _counted.dispose();
    _float.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await widget.guards.tillClosings(widget.org.id, limit: 10);
      if (mounted) setState(() => _history = rows);
    } catch (error) {
      if (mounted && isGuardMissing(error)) setState(() => _missing = true);
    }
  }

  Future<void> _close() async {
    if (_busy) return;
    final counted = parseAmount(_counted.text, currency: widget.org.currency);
    final float = _float.text.trim().isEmpty
        ? 0.0
        : parseAmount(_float.text, currency: widget.org.currency);
    if (counted == null || counted < 0) {
      setState(() => _error = context.tr('Indiquez les espèces comptées dans la caisse.'));
      return;
    }
    if (float == null || float < 0) {
      setState(() => _error = context.tr('Le fonds de caisse est un montant, ou rien.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await widget.guards.closeTill(widget.org.id,
          day: _now, counted: counted, openingFloat: float, note: _note.text);
      if (!mounted) return;
      setState(() {
        _done = done;
        _busy = false;
      });
      await _loadHistory();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _missing = isGuardMissing(error);
        _error = _missing ? null : describeError(error);
      });
    }
  }

  /// « Juste », « Il manque 500 FCFA », « 200 FCFA en trop ».
  String _gapWords(TillClosing t) {
    if (t.gap.abs() < 0.005) return context.tr('Juste : la caisse tombe juste');
    final amount = moneyFormat(t.currency).format(t.gap.abs());
    return t.gap < 0
        ? context.tr('Il manque {amount}', {'amount': amount})
        : context.tr('{amount} en trop', {'amount': amount});
  }

  Color _gapColour(BuildContext context, TillClosing t) {
    if (t.gap.abs() < 0.005) return Colors.green.shade800;
    return t.gap < 0 ? Theme.of(context).colorScheme.error : Colors.orange.shade900;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = _done;
    final day = DateFormat('EEEE d MMMM', context.trLocale).format(_now);
    return KeyboardSheet(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      footer: _missing || done != null
          ? SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('till-done'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('Fermer')),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!,
                        key: const Key('till-error'),
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: FilledButton.icon(
                    key: const Key('till-close'),
                    onPressed: _busy ? null : _close,
                    icon: _busy
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.lock_clock_outlined),
                    label: Text(context.tr('Clôturer la caisse'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
      children: [
        Text(context.tr('Clôturer la caisse'),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        Text(day, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (_missing)
          Text(context.tr('La clôture de caisse arrive avec la prochaine mise à jour du serveur. Vos ventes, elles, sont bien enregistrées.'),
              key: const Key('till-missing'))
        else if (done != null)
          _Result(
            closing: done,
            money: moneyFormat(done.currency),
            gapWords: _gapWords(done),
            gapColour: _gapColour(context, done),
          )
        else ...[
          Text(context.tr(
              'Comptez les espèces dans la caisse, sans regarder les ventes. Marakaj compare ensuite avec ce qui est attendu : le fonds de caisse, plus les ventes en espèces du jour, moins les retours.')),
          const SizedBox(height: 14),
          TextField(
            key: const Key('till-counted'),
            controller: _counted,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: context.tr('Espèces comptées dans la caisse'),
              suffixText: currencySymbol(widget.org.currency),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('till-float'),
            controller: _float,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: context.tr('Fonds de caisse du matin (facultatif)'),
              helperText: context.tr('La monnaie mise dans la caisse à l\'ouverture'),
              suffixText: currencySymbol(widget.org.currency),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('till-note'),
            controller: _note,
            maxLines: 2,
            decoration: InputDecoration(labelText: context.tr('Un mot (facultatif)')),
          ),
        ],
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(context.tr('Clôtures récentes'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final t in _history)
            Padding(
              key: Key('till-history-${t.id}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      [
                        DateFormat('d MMM, HH:mm', context.trLocale).format(t.closedAt ?? t.day),
                        if ((t.closerName ?? '').isNotEmpty) t.closerName!,
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(_gapWords(t),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700, color: _gapColour(context, t))),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.closing,
    required this.money,
    required this.gapWords,
    required this.gapColour,
  });

  final TillClosing closing;
  final NumberFormat money;
  final String gapWords;
  final Color gapColour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, double value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              Text(money.format(value),
                  style: TextStyle(fontSize: strong ? 18 : 16, fontWeight: strong ? FontWeight.w700 : FontWeight.w600)),
            ],
          ),
        );
    return Column(
      key: const Key('till-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(context.tr('Fonds de caisse'), closing.openingFloat),
        row(context.tr('Ventes en espèces'), closing.cashSales),
        row(context.tr('Retours en espèces'), closing.cashReturns == 0 ? 0 : -closing.cashReturns),
        const Divider(height: 20),
        row(context.tr('Attendu'), closing.expected, strong: true),
        row(context.tr('Compté'), closing.counted, strong: true),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: gapColour.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(gapWords,
              key: const Key('till-gap'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: gapColour)),
        ),
        const SizedBox(height: 8),
        Text(context.tr('Enregistré. Le propriétaire voit chaque clôture et son écart.'),
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}
