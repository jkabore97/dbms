import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/association/association_analytics.dart';
import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/reports/models.dart' show accountLabel;
import '../accounting/report_download.dart';
import '../accounting/report_exports.dart';
import '../accounting/report_shell.dart' show Period, PeriodSelector;
import 'members/member_words.dart' show isNarrow;

/// An association's « Analyses » (148) — a legacy church's too — drawn
/// for the treasurer: money in and out by month over the last 12 months
/// and what the association held at each month's end; where the money
/// came from and went over the chosen period, by category (Cotisations,
/// Dons, Ventes and every « Autre » it named, « Dîme » included), a
/// category opening its entries; the members — how many, how many gave,
/// up to date or late on the cotisation, new ones by month — and, for an
/// administrator only, who gave the most.
///
/// Marakaj Pro, as the farm's and the shop's (the 'analytics' tool): Compte
/// opens it through the same gate, and 148's association_analytics()
/// refuses it on a Free association. A caller on 'summary' visibility gets
/// the totals only, like every other report; the server decides.
class AssociationAnalyticsScreen extends StatefulWidget {
  const AssociationAnalyticsScreen({
    super.key,
    required this.org,
    required this.load,
    this.openCategory,
  });

  final OrgSummary org;

  /// The server's answer for a period (148); null when the database does
  /// not have it yet.
  final Future<AssociationAnalytics?> Function(DateTime? from, DateTime? to) load;

  /// A category's entries (account_ledger_screen), from the period chosen.
  /// Null: the rows do not open.
  final void Function(CategoryAmount category, String type, Period period)? openCategory;

  @override
  State<AssociationAnalyticsScreen> createState() => _AssociationAnalyticsScreenState();
}

/// In and out: two hues that pass the colour-blind checks in light and in
/// dark (validated), always with their words in the legend.
({Color income, Color expense}) inOutColours(Brightness b) => b == Brightness.dark
    ? (income: const Color(0xFF3987E5), expense: const Color(0xFFD95926))
    : (income: const Color(0xFF2A78D6), expense: const Color(0xFFEB6834));

class _AssociationAnalyticsScreenState extends State<AssociationAnalyticsScreen> {
  Period _period = Period.thisYear;
  AssociationAnalytics? _data;
  bool _missing = false;
  bool _loading = true;
  Object? _error;
  int? _month;

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
      final r = _period.range;
      final data = await widget.load(r.from, r.to);
      if (!mounted) return;
      setState(() {
        _data = data;
        _missing = data == null;
        _loading = false;
        _month = data == null || data.months.isEmpty ? null : data.months.length - 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Analyses')),
        actions: [
          ReportDownloadButton(
            build: _loading || _error != null || _data == null
                ? null
                : () async {
                    final r = _period.range;
                    return analyticsExport(widget.org, _data!, from: r.from, to: r.to);
                  },
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: context.tr('Actualiser'),
          ),
          bellRoom,
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _failed(context)
              : _missing
                  ? _message(context, Icons.update,
                      context.tr('Les analyses de l\'association arrivent avec la prochaine mise à jour du serveur.'))
                  : RefreshIndicator(onRefresh: _load, child: _body(context, _data!)),
    );
  }

  Widget _message(BuildContext context, IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(text, key: const Key('aa-message'), textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _failed(BuildContext context) {
    final e = _error!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44),
            const SizedBox(height: 12),
            Text(
              isProRefusal(e) || !isOffline(e)
                  ? describeError(e)
                  : context.tr('Les analyses ont besoin du réseau. Réessayez quand il revient.'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: Text(context.tr('Réessayer'))),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AssociationAnalytics d) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      children: [
        PeriodSelector(
          value: _period,
          onChanged: (p) {
            setState(() => _period = p);
            _load();
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(_period.describe(),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        if (!d.full)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              key: const Key('aa-summary-note'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                context.tr('Votre accès porte sur les totaux. Le détail des opérations ne vous est pas communiqué.'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
          ),
        _Section(
          key: const Key('aa-months'),
          title: context.tr('Entrées et sorties'),
          subtitle: context.tr('Par mois, sur les 12 derniers mois'),
          child: _months(context, d),
        ),
        _Section(
          key: const Key('aa-balance'),
          title: context.tr('Ce que l\'association détient'),
          subtitle: context.tr('Caisse, banque et mobile money à la fin de chaque mois'),
          child: _balance(context, d),
        ),
        if (d.income != null)
          _Section(
            key: const Key('aa-income'),
            title: context.tr('Recettes par catégorie'),
            subtitle: context.tr('Sur la période choisie'),
            child: _categories(context, d.income!, 'income'),
          ),
        if (d.expenses != null)
          _Section(
            key: const Key('aa-expenses'),
            title: context.tr('Dépenses par catégorie'),
            subtitle: context.tr('Sur la période choisie'),
            child: _categories(context, d.expenses!, 'expense'),
          ),
        _Section(
          key: const Key('aa-members'),
          title: context.tr('Les membres'),
          child: _members(context, d),
        ),
        if (d.topGivers != null)
          _Section(
            key: const Key('aa-top'),
            title: context.tr('Ceux qui donnent le plus'),
            subtitle: context.tr('Sur la période choisie · visible des responsables seulement'),
            child: _top(context, d.topGivers!),
          ),
      ],
    );
  }

  Widget _months(BuildContext context, AssociationAnalytics d) {
    final theme = Theme.of(context);
    final colours = inOutColours(theme.brightness);
    final months = d.months;
    if (months.isEmpty) return Text(context.tr('Rien à afficher pour cette période.'));
    final sel = _month == null ? null : months[_month!.clamp(0, months.length - 1)];
    final income = months.fold<double>(0, (s, m) => s + (m.income ?? 0));
    final out = months.fold<double>(0, (s, m) => s + (m.expenses ?? 0));
    final label = DateFormat('MMMM yyyy', context.trLocale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _Legend(colour: colours.income, label: context.tr('Entrées')),
            _Legend(colour: colours.expense, label: context.tr('Sorties')),
          ],
        ),
        const SizedBox(height: 10),
        InOutBars(
          key: const Key('aa-bars'),
          months: months,
          selected: _month,
          currency: widget.org.currency,
          onSelect: (i) => setState(() => _month = i),
        ),
        if (sel != null) ...[
          const SizedBox(height: 10),
          Text(label.format(sel.month), style: const TextStyle(fontWeight: FontWeight.w700)),
          _Figure(label: context.tr('Entrées'), value: _amount(sel.income), colour: colours.income),
          _Figure(label: context.tr('Sorties'), value: _amount(sel.expenses), colour: colours.expense),
          _Figure(
              label: context.tr('Résultat'),
              value: sel.income == null || sel.expenses == null
                  ? '—'
                  : _money.format(sel.income! - sel.expenses!)),
        ],
        const Divider(height: 24),
        _Figure(label: context.tr('Entrées sur 12 mois'), value: _money.format(income), bold: true),
        _Figure(label: context.tr('Sorties sur 12 mois'), value: _money.format(out), bold: true),
      ],
    );
  }

  String _amount(double? v) => v == null ? '—' : _money.format(v);

  Widget _balance(BuildContext context, AssociationAnalytics d) {
    final values = [for (final m in d.months) m.balance];
    if (values.every((v) => v == null)) return Text(context.tr('Rien à afficher pour cette période.'));
    final last = d.months.lastWhere((m) => m.balance != null);
    final sel = _month == null ? null : d.months[_month!.clamp(0, d.months.length - 1)];
    final label = DateFormat('MMMM yyyy', context.trLocale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BalanceLine(
          key: const Key('aa-line'),
          months: d.months,
          selected: _month,
          currency: widget.org.currency,
          onSelect: (i) => setState(() => _month = i),
        ),
        const SizedBox(height: 10),
        if (sel != null && sel.balance != null)
          _Figure(
              label: context.tr('Fin {month}', {'month': label.format(sel.month)}),
              value: _money.format(sel.balance)),
        _Figure(
            label: context.tr('Aujourd\'hui'),
            value: _money.format(last.balance),
            bold: true),
      ],
    );
  }

  Widget _categories(BuildContext context, List<CategoryAmount> rows, String type) {
    final theme = Theme.of(context);
    if (rows.isEmpty) return Text(context.tr('Rien à afficher pour cette période.'));
    final total = rows.fold<double>(0, (s, c) => s + c.amount);
    final colours = inOutColours(theme.brightness);
    final colour = type == 'income' ? colours.income : colours.expense;
    final open = widget.openCategory;
    final narrow = isNarrow(context);
    return Column(
      children: [
        for (final c in rows)
          InkWell(
            key: Key('aa-cat-${c.accountId}'),
            onTap: open == null ? null : () => open(c, type, _period),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(_categoryName(context, c.name),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      if (!narrow) ...[
                        const SizedBox(width: 8),
                        Text(_money.format(c.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                      if (open != null)
                        Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ),
                  if (narrow)
                    Text(_money.format(c.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: total <= 0 ? 0 : (c.amount / total).clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(colour),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        child: Text(
                          total <= 0 ? '' : '${(c.amount / total * 100).round()} %',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    c.entries == 1
                        ? context.tr('1 opération')
                        : context.tr('{n} opérations', {'n': c.entries}),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 20),
        _Figure(label: context.tr('Total'), value: _money.format(total), bold: true),
      ],
    );
  }

  /// The four kinds in Recette's words; the rest as the books hold them.
  String _categoryName(BuildContext context, String name) => switch (name.trim().toLowerCase()) {
        'cotisations' => context.tr('Cotisations'),
        'donations' => context.tr('Dons'),
        'ventes' => context.tr('Ventes'),
        _ => accountLabel(name),
      };

  Widget _members(BuildContext context, AssociationAnalytics d) {
    final theme = Theme.of(context);
    final short = DateFormat('MMM', context.trLocale);
    final newCount = d.newByMonth.fold<int>(0, (s, m) => s + m.count);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Tile(label: context.tr('Inscrits'), value: '${d.registered}'),
            if (d.gave != null)
              _Tile(label: context.tr('Ont donné sur la période'), value: '${d.gave}'),
            if (d.hasDues && d.upToDate != null) ...[
              _Tile(label: context.tr('À jour'), value: '${d.upToDate}'),
              _Tile(label: context.tr('À payer'), value: '${d.due}'),
              _Tile(label: context.tr('En retard'), value: '${d.late}'),
            ],
          ],
        ),
        if (!d.hasDues && d.full) ...[
          const SizedBox(height: 8),
          Text(context.tr('Sans cotisation habituelle, personne n\'est « en retard ».'),
              style: theme.textTheme.bodySmall),
        ],
        if (d.newByMonth.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            context.tr('Nouveaux membres par mois : {n} sur 12 mois', {'n': newCount}),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          CountBars(
            key: const Key('aa-new'),
            values: [for (final m in d.newByMonth) m.count],
            labels: [for (final m in d.newByMonth) short.format(m.month)],
          ),
        ],
      ],
    );
  }

  Widget _top(BuildContext context, List<Giver> givers) {
    if (givers.isEmpty) return Text(context.tr('Aucun don attribué à un membre sur la période.'));
    return Column(
      children: [
        for (final (i, g) in givers.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(width: 28, child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w700))),
                Expanded(child: Text(g.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Text(_money.format(g.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );
  }
}

/// A section: its own surface, readable in light and dark.
class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.colour, required this.label});
  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.colour, this.bold = false});
  final String label;
  final String value;
  final Color? colour;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            if (colour != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text(label)),
            const SizedBox(width: 8),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 96, maxWidth: 150),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// A round number at or above [v] for the top of an axis: 1, 2, 2.5 or 5
/// times a power of ten.
double niceCeiling(double v) {
  if (v <= 0) return 1;
  final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (m * p >= v) return m * p;
  }
  return 10 * p;
}

/// « 120 k », « 1,5 M »: an axis label, its money said once beside it.
String compactAmount(double v, String locale) => NumberFormat.compact(locale: locale).format(v);

/// In and out, side by side for each month, on one scale from zero: the
/// axis's top is a round number, labelled with the money; a tap picks a
/// month (its figures are said under the chart).
class InOutBars extends StatelessWidget {
  const InOutBars({
    super.key,
    required this.months,
    required this.currency,
    this.selected,
    this.onSelect,
    this.height = 180,
  });

  final List<MonthMoney> months;
  final String currency;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = inOutColours(theme.brightness);
    final top = niceCeiling(months.fold<double>(
        0, (s, m) => math.max(s, math.max(m.income ?? 0, m.expenses ?? 0))));
    final short = DateFormat('MMM', context.trLocale);
    final style = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return LayoutBuilder(builder: (context, box) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onSelect == null
            ? null
            : (d) {
                final w = box.maxWidth - _BarsPainter.axisW;
                final i = ((d.localPosition.dx - _BarsPainter.axisW) / (w / months.length))
                    .floor()
                    .clamp(0, months.length - 1);
                onSelect!(i);
              },
        child: Semantics(
          label: context.tr('Entrées et sorties par mois'),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _BarsPainter(
                months: months,
                top: top,
                topLabel: '${compactAmount(top, context.trLocale)} ${currencySymbol(currency)}',
                halfLabel: compactAmount(top / 2, context.trLocale),
                labels: [for (final m in months) short.format(m.month)],
                selected: selected,
                income: colours.income,
                expense: colours.expense,
                grid: theme.colorScheme.outlineVariant,
                highlight: theme.colorScheme.primary.withValues(alpha: 0.10),
                style: style ?? const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.months,
    required this.top,
    required this.topLabel,
    required this.halfLabel,
    required this.labels,
    required this.selected,
    required this.income,
    required this.expense,
    required this.grid,
    required this.highlight,
    required this.style,
  });

  static const axisW = 4.0;

  final List<MonthMoney> months;
  final double top;
  final String topLabel;
  final String halfLabel;
  final List<String> labels;
  final int? selected;
  final Color income;
  final Color expense;
  final Color grid;
  final Color highlight;
  final TextStyle style;

  TextPainter _text(String s, double max) => TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '',
      )..layout(maxWidth: max);

  @override
  void paint(Canvas canvas, Size size) {
    final head = _text(topLabel, size.width);
    final labelH = head.height + 4;
    final chartTop = labelH;
    final chartBottom = size.height - labelH;
    final chartH = chartBottom - chartTop;
    final w = size.width - axisW;
    final n = months.length;
    final slot = w / n;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    // The scale: zero, half and the top, the top labelled.
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = chartBottom - chartH * f;
      canvas.drawLine(Offset(axisW, y), Offset(size.width, y), gridPaint);
    }
    head.paint(canvas, const Offset(axisW, 0));
    final half = _text(halfLabel, size.width);
    half.paint(canvas, Offset(axisW, chartBottom - chartH / 2 - half.height - 1));
    if (selected != null && selected! >= 0 && selected! < n) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(axisW + slot * selected!, chartTop, slot, chartH),
              const Radius.circular(6)),
          Paint()..color = highlight);
    }
    final barW = math.max(2.0, math.min(14.0, (slot - 6) / 2));
    for (var i = 0; i < n; i++) {
      final m = months[i];
      final cx = axisW + slot * i + slot / 2;
      void bar(double? v, double left, Color c) {
        if (v == null || v <= 0) return;
        final h = chartH * (v / top);
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(left, chartBottom - h, barW, h),
                topLeft: const Radius.circular(3), topRight: const Radius.circular(3)),
            Paint()..color = c);
      }

      bar(m.income, cx - barW - 1, income);
      bar(m.expenses, cx + 1, expense);
      // Every third month named, and the last: twelve names do not fit 320 px.
      if (i % 3 == (n - 1) % 3) {
        final t = _text(labels[i], slot * 3);
        t.paint(canvas, Offset((cx - t.width / 2).clamp(0, size.width - t.width), chartBottom + 3));
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.months != months || old.selected != selected || old.income != income || old.top != top;
}

/// What the association held at each month's end, on one scale that
/// includes zero (a balance under zero shows below the line).
class BalanceLine extends StatelessWidget {
  const BalanceLine({
    super.key,
    required this.months,
    required this.currency,
    this.selected,
    this.onSelect,
    this.height = 150,
  });

  final List<MonthMoney> months;
  final String currency;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = [for (final m in months) m.balance];
    final known = values.whereType<double>();
    final hi = niceCeiling(math.max(0, known.fold<double>(0, math.max)));
    final lo = known.fold<double>(0, math.min);
    final bottom = lo < 0 ? -niceCeiling(-lo) : 0.0;
    final short = DateFormat('MMM', context.trLocale);
    return LayoutBuilder(builder: (context, box) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onSelect == null
            ? null
            : (d) => onSelect!(((d.localPosition.dx) / (box.maxWidth / months.length))
                .floor()
                .clamp(0, months.length - 1)),
        child: Semantics(
          label: context.tr('Solde à la fin de chaque mois'),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _LinePainter(
                values: values,
                hi: hi,
                lo: bottom,
                hiLabel: '${compactAmount(hi, context.trLocale)} ${currencySymbol(currency)}',
                loLabel: compactAmount(bottom, context.trLocale),
                labels: [for (final m in months) short.format(m.month)],
                selected: selected,
                line: inOutColours(theme.brightness).income,
                grid: theme.colorScheme.outlineVariant,
                surface: theme.colorScheme.surfaceContainerLow,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant) ??
                    const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.hi,
    required this.lo,
    required this.hiLabel,
    required this.loLabel,
    required this.labels,
    required this.selected,
    required this.line,
    required this.grid,
    required this.surface,
    required this.style,
  });

  final List<double?> values;
  final double hi;
  final double lo;
  final String hiLabel;
  final String loLabel;
  final List<String> labels;
  final int? selected;
  final Color line;
  final Color grid;
  final Color surface;
  final TextStyle style;

  TextPainter _text(String s, double max) => TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '',
      )..layout(maxWidth: max);

  @override
  void paint(Canvas canvas, Size size) {
    final head = _text(hiLabel, size.width);
    final top = head.height + 6;
    final bottom = size.height - head.height - 4;
    final h = bottom - top;
    final n = values.length;
    final slot = size.width / n;
    double y(double v) => bottom - h * ((v - lo) / (hi - lo == 0 ? 1 : hi - lo));
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y(hi)), Offset(size.width, y(hi)), gridPaint);
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), gridPaint..strokeWidth = 1.5);
    if (lo < 0) {
      canvas.drawLine(Offset(0, y(lo)), Offset(size.width, y(lo)), gridPaint..strokeWidth = 1);
      final l = _text(loLabel, size.width);
      l.paint(canvas, Offset(0, y(lo) - l.height - 1));
    }
    head.paint(canvas, Offset(0, y(hi) - head.height - 2));
    final path = Path();
    var started = false;
    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final p = Offset(slot * i + slot / 2, y(v));
      points.add(p);
      if (!started) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final p = Offset(slot * i + slot / 2, y(v));
      final r = i == selected ? 5.0 : 3.0;
      canvas.drawCircle(p, r + 2, Paint()..color = surface);
      canvas.drawCircle(p, r, Paint()..color = line);
      if (i % 3 == (n - 1) % 3) {
        final t = _text(labels[i], slot * 3);
        t.paint(canvas, Offset((p.dx - t.width / 2).clamp(0, size.width - t.width), bottom + 4));
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.selected != selected || old.line != line;
}

/// Small counts by month (new members), to scale from zero, each bar with
/// its number when it is not zero.
class CountBars extends StatelessWidget {
  const CountBars({super.key, required this.values, required this.labels, this.height = 90});

  final List<int> values;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = values.fold<int>(0, math.max);
    final style = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  children: [
                    SizedBox(
                      height: 14,
                      child: values[i] > 0 ? FittedBox(child: Text('${values[i]}', style: style)) : null,
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: max == 0 ? 0 : values[i] / max,
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(height: 1, color: theme.colorScheme.outlineVariant),
                    SizedBox(
                      height: 16,
                      child: i % 3 == (values.length - 1) % 3
                          ? FittedBox(child: Text(labels[i], style: style))
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
