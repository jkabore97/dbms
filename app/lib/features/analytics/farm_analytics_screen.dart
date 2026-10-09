import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/analytics/analytics_repository.dart';
import '../../core/analytics/models.dart';
import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/retail/stock_rule.dart';
import '../../core/theme/mara_mark.dart';
import 'charts.dart';
import 'widgets.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// A farm's analyses (101), drawn like the shop's: what came in and went
/// out, this month against the last; what sold best and worst; where the
/// money went; how each flock is doing; what the animals ate.
///
/// Every number comes from 101's farm_analytics(), which refuses anyone
/// without full visibility and a farm without the 'analytics' tool (Pro,
/// or unlocked with cauris) — Compte opens this screen only through the
/// same gate.
class FarmAnalyticsScreen extends StatefulWidget {
  const FarmAnalyticsScreen({
    super.key,
    required this.analytics,
    required this.orgId,
    required this.orgName,
    required this.currency,
    this.load,
  });

  final AnalyticsRepository analytics;
  final String orgId;
  final String orgName;
  final String currency;

  /// Replaces the server call in tests.
  final Future<FarmAnalytics> Function(int? days)? load;

  @override
  State<FarmAnalyticsScreen> createState() => _FarmAnalyticsScreenState();
}

class _FarmAnalyticsScreenState extends State<FarmAnalyticsScreen> {
  static const _windows = <(String, int?)>[
    ('7 j', 7),
    ('30 j', 30),
    ('90 j', 90),
    ('Tout', null),
  ];

  int _windowIndex = 1;
  bool _loading = true;
  String? _error;
  FarmAnalytics? _data;

  NumberFormat get _money => moneyFormat(widget.currency);

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
    final days = _windows[_windowIndex].$2;
    try {
      final data = widget.load != null
          ? await widget.load!(days)
          : await widget.analytics.farm(widget.orgId, days: days);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final why = describeError(e);
      setState(() {
        // The Pro words when the tool is closed; the plain sentence otherwise.
        _error = isProRefusal(e)
            ? why
            : context.tr('Les analyses n\'ont pas pu être chargées.');
        _loading = false;
      });
    }
  }

  void _pickWindow(int i) {
    if (i == _windowIndex) return;
    setState(() => _windowIndex = i);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Analyses')),
        actions: [
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
              ? AnalyticsErrorState(message: _error!, onRetry: _load)
              : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final data = _data!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MonthCard(data: data, money: _money),
        const SizedBox(height: 16),
        WindowPicker(
          windows: [for (final w in _windows) context.tr(w.$1)],
          selected: _windowIndex,
          onSelect: _pickWindow,
        ),
        const SizedBox(height: 16),
        if (data.isEmpty)
          const _EmptyFarm()
        else ...[
          _headline(context, data.window),
          if (data.products.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sells(context, data.products),
          ],
          if (data.expenses.isNotEmpty) ...[
            const SizedBox(height: 20),
            _bars(context,
                title: context.tr('Où va l\'argent'),
                subtitle: context.tr('Dépenses par poste sur la période'),
                rows: data.expenses,
                colour: maraBrown),
          ],
          if (data.flocks.isNotEmpty) ...[
            const SizedBox(height: 20),
            _flocks(context, data.flocks),
          ],
          if (data.feed.isNotEmpty) ...[
            const SizedBox(height: 20),
            _feed(context, data.feed),
          ],
          if (data.daily.length >= 2) ...[
            const SizedBox(height: 20),
            _trend(context, data.daily),
          ],
        ],
      ],
    );
  }

  Widget _headline(BuildContext context, FarmPeriod w) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        KpiCard(
          label: context.tr('Entrées'),
          value: _money.format(w.income),
          icon: Icons.south_west,
          emphasis: true,
        ),
        KpiCard(
          label: context.tr('Dépenses'),
          value: _money.format(w.expenses),
          icon: Icons.north_east,
        ),
        KpiCard(
          label: context.tr('Résultat'),
          value: _money.format(w.result),
          icon: Icons.trending_up,
        ),
        KpiCard(
          label: context.tr('Commandes livrées'),
          value: '${w.orders}',
          hint: w.orders == 0 ? null : _money.format(w.ordersTotal),
          icon: Icons.shopping_bag_outlined,
        ),
        if (w.eggs > 0)
          KpiCard(
            label: context.tr('Œufs ramassés'),
            value: stockQty(w.eggs),
            icon: Icons.egg_outlined,
          ),
        if (w.productionCost > 0)
          KpiCard(
            label: context.tr('Coût de production'),
            value: _money.format(w.productionCost),
            icon: Icons.precision_manufacturing_outlined,
          ),
      ],
    );
  }

  Widget _sells(BuildContext context, List<NamedAmount> products) {
    final top = products.take(8).toList();
    final best = products.first;
    final worst = products.last;
    return SectionCard(
      title: context.tr('Ce qui se vend'),
      subtitle: context.tr('Classé par chiffre d\'affaires sur la période'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BarList(rows: top, money: _money, colour: maraGreen),
          if (products.length > 1) ...[
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _Best(
                    icon: Icons.local_fire_department_outlined,
                    label: context.tr('Le plus vendu'),
                    name: best.name,
                    detail: _money.format(best.amount),
                  ),
                ),
                Expanded(
                  child: _Best(
                    icon: Icons.hourglass_bottom_outlined,
                    label: context.tr('Le plus lent'),
                    name: worst.name,
                    detail: _money.format(worst.amount),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bars(BuildContext context,
      {required String title,
      required String subtitle,
      required List<NamedAmount> rows,
      required Color colour}) {
    return SectionCard(
      title: title,
      subtitle: subtitle,
      child: _BarList(rows: rows.take(8).toList(), money: _money, colour: colour),
    );
  }

  Widget _flocks(BuildContext context, List<FlockFigure> flocks) {
    return SectionCard(
      title: context.tr('Mes bandes'),
      subtitle: context.tr('Vivants, pertes et ponte de chaque bande ouverte'),
      child: Column(
        children: [
          for (final f in flocks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 22,
                    backgroundColor: maraPaper,
                    child: Icon(Icons.pets_outlined, color: maraBrown),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.batchCode,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          context.tr('{alive} vivants sur {started}',
                              {'alive': f.alive, 'started': f.started}),
                          style: const TextStyle(color: maraDeep),
                        ),
                      ],
                    ),
                  ),
                  _Figure(
                    icon: Icons.heart_broken_outlined,
                    value: '${(f.mortality * 100).toStringAsFixed(1)} %',
                    label: context.tr('pertes'),
                    colour: maraBrown,
                  ),
                  const SizedBox(width: 12),
                  _Figure(
                    icon: Icons.egg_outlined,
                    value: '${(f.layRate * 100).round()} %',
                    label: context.tr('ponte'),
                    colour: maraGreen,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _feed(BuildContext context, List<FeedUse> feed) {
    return SectionCard(
      title: context.tr('Ce que les bêtes mangent'),
      subtitle: context.tr('Consommé ce mois-ci, et le mois dernier'),
      child: Column(
        children: [
          for (final f in feed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.grass_outlined, color: maraBrown),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(f.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Text('${stockQty(f.month)} ${f.unit}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  _Trend(now: f.month, before: f.lastMonth, upIsGood: false),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _trend(BuildContext context, List<FarmDay> daily) {
    final df = DateFormat('d MMM', intlLocale());
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return SectionCard(
      title: context.tr('Tendance'),
      subtitle: context.tr('Entrées par jour'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LineChart(values: [for (final d in daily) d.income]),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(df.format(daily.first.day), style: muted),
              Text(df.format(daily.last.day), style: muted),
            ],
          ),
        ],
      ),
    );
  }
}

/// This month against the last, always — whatever window is picked below.
class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.data, required this.money});

  final FarmAnalytics data;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final m = data.month;
    final l = data.lastMonth;
    Widget row(IconData icon, String label, String value, double now,
            double before, bool upIsGood) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, color: maraCaramel, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: Colors.white70, fontSize: 15)),
              ),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(width: 8),
              _Trend(now: now, before: before, upIsGood: upIsGood, onDark: true),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: maraDeep,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Ce mois-ci'),
              style: const TextStyle(
                  color: maraCaramel, fontWeight: FontWeight.w700, fontSize: 16)),
          Text(context.tr('comparé au mois dernier'),
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 6),
          row(Icons.south_west, context.tr('Entrées'), money.format(m.income),
              m.income, l.income, true),
          row(Icons.north_east, context.tr('Dépenses'), money.format(m.expenses),
              m.expenses, l.expenses, false),
          row(Icons.trending_up, context.tr('Résultat'), money.format(m.result),
              m.result, l.result, true),
          if (m.eggs > 0 || l.eggs > 0)
            row(Icons.egg_outlined, context.tr('Œufs'), stockQty(m.eggs), m.eggs,
                l.eggs, true),
          if (m.deaths > 0 || l.deaths > 0)
            row(Icons.heart_broken_outlined, context.tr('Bêtes perdues'),
                stockQty(m.deaths), m.deaths, l.deaths, false),
        ],
      ),
    );
  }
}

/// ▲ or ▼ against last month, green when it is good news, brown when not.
class _Trend extends StatelessWidget {
  const _Trend({
    required this.now,
    required this.before,
    required this.upIsGood,
    this.onDark = false,
  });

  final double now;
  final double before;
  final bool upIsGood;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    if (now == before) {
      return Icon(Icons.remove,
          size: 18, color: onDark ? Colors.white38 : Colors.black26);
    }
    final up = now > before;
    final good = up == upIsGood;
    return Icon(
      up ? Icons.arrow_upward : Icons.arrow_downward,
      size: 18,
      color: good ? (onDark ? const Color(0xFF8FD3A4) : maraGreen) : maraCaramel,
      semanticLabel: up ? context.tr('en hausse') : context.tr('en baisse'),
    );
  }
}

class _BarList extends StatelessWidget {
  const _BarList({required this.rows, required this.money, required this.colour});

  final List<NamedAmount> rows;
  final NumberFormat money;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final max = rows.map((r) => r.amount).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text(money.format(r.amount),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: max == 0 ? 0 : (r.amount / max).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: maraPaper,
                    valueColor: AlwaysStoppedAnimation(colour),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Best extends StatelessWidget {
  const _Best({
    required this.icon,
    required this.label,
    required this.name,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: maraBrown),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: maraDeep)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(detail, style: const TextStyle(fontSize: 12, color: maraDeep)),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.icon,
    required this.value,
    required this.label,
    required this.colour,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: colour, size: 20),
        Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: colour)),
        Text(label, style: const TextStyle(fontSize: 11, color: maraDeep)),
      ],
    );
  }
}

class _EmptyFarm extends StatelessWidget {
  const _EmptyFarm();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.agriculture_outlined, size: 56, color: maraCaramel),
          const SizedBox(height: 12),
          Text(context.tr('Rien sur cette période'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            context.tr('Vos ventes, dépenses, récoltes et bandes apparaîtront ici.'),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
