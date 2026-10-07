import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/analytics/analytics_repository.dart';
import '../../core/analytics/models.dart';
import '../../core/format/money.dart';
import 'charts.dart';
import 'widgets.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// What the owner sees: what sells more or less, when the shop earns, and how
/// the takings trend — the "smart things" asked for, over a window they choose.
///
/// Every number comes from the server functions in 036, which refuse anyone
/// without full visibility of this business. The screen therefore never has to
/// hide anything itself: if it renders, the reader was entitled to it.
class OwnerAnalyticsScreen extends StatefulWidget {
  const OwnerAnalyticsScreen({
    super.key,
    required this.analytics,
    required this.orgId,
    required this.orgName,
    required this.currency,
  });

  final AnalyticsRepository analytics;
  final String orgId;
  final String orgName;
  final String currency;

  @override
  State<OwnerAnalyticsScreen> createState() => _OwnerAnalyticsScreenState();
}

class _OwnerAnalyticsScreenState extends State<OwnerAnalyticsScreen> {
  // Windows offered, in days; null is "all of time".
  static const _windows = <(String, int?)>[
    ('7 j', 7),
    ('30 j', 30),
    ('90 j', 90),
    ('Tout', null),
  ];

  int _windowIndex = 1; // 30 days
  bool _loading = true;
  String? _error;
  OwnerAnalytics? _data;

  int? get _days => _windows[_windowIndex].$2;
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
    try {
      final data = await widget.analytics.owner(widget.orgId, days: _days);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.tr('Les analyses n\'ont pas pu être chargées.');
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
        WindowPicker(
          windows: [for (final w in _windows) w.$1],
          selected: _windowIndex,
          onSelect: _pickWindow,
        ),
        const SizedBox(height: 16),
        if (data.isEmpty)
          const _EmptyState()
        else ...[
          _headline(context, data.headline),
          const SizedBox(height: 20),
          _sellsSection(context, data.products),
          const SizedBox(height: 20),
          _whenSection(context, data),
          const SizedBox(height: 20),
          _trendSection(context, data.daily),
        ],
      ],
    );
  }

  Widget _headline(BuildContext context, SalesHeadline h) {
    final marginPct = (h.marginRate * 100).round();
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        KpiCard(
          label: context.tr('Chiffre d\'affaires'),
          value: _money.format(h.revenue),
          icon: Icons.payments_outlined,
          emphasis: true,
        ),
        KpiCard(
          label: context.tr('Bénéfice'),
          value: _money.format(h.margin),
          hint: '$marginPct % du CA',
          icon: Icons.trending_up,
        ),
        KpiCard(
          label: context.tr('Ventes'),
          value: '${h.saleCount}',
          icon: Icons.receipt_long_outlined,
        ),
        KpiCard(
          label: context.tr('Panier moyen'),
          value: _money.format(h.avgBasket),
          icon: Icons.shopping_basket_outlined,
        ),
        KpiCard(
          label: context.tr('Articles vendus'),
          value: _units(h.units),
          icon: Icons.inventory_2_outlined,
        ),
        KpiCard(
          label: context.tr('Produits différents'),
          value: '${h.productsSold}',
          icon: Icons.category_outlined,
        ),
      ],
    );
  }

  Widget _sellsSection(BuildContext context, List<ProductPerformance> products) {
    if (products.isEmpty) return const SizedBox.shrink();
    final top = products.take(8).toList();
    final maxRevenue = top.first.revenue == 0 ? 1 : top.first.revenue;
    final best = top.first;
    final worst = products.last;

    return SectionCard(
      title: context.tr('Ce qui se vend'),
      subtitle: context.tr('Classé par chiffre d\'affaires sur la période'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in top) ...[
            _ProductRow(
              product: p,
              money: _money,
              fraction: (p.revenue / maxRevenue).clamp(0.0, 1.0),
            ),
            const SizedBox(height: 10),
          ],
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: _Superlative(
                  icon: Icons.local_fire_department_outlined,
                  label: context.tr('Le plus vendu'),
                  name: best.name,
                  detail: '${_units(best.units)} · ${_perDay(best.perDay)}',
                ),
              ),
              Expanded(
                child: _Superlative(
                  icon: Icons.hourglass_bottom_outlined,
                  label: context.tr('Le plus lent'),
                  name: worst.name,
                  detail: '${_units(worst.units)} · ${_perDay(worst.perDay)}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _whenSection(BuildContext context, OwnerAnalytics data) {
    // 24 hourly buckets, zero-filled so quiet hours read as gaps not absences.
    final hours = List<double>.filled(24, 0);
    for (final b in data.byHour) {
      if (b.index >= 0 && b.index < 24) hours[b.index] = b.revenue;
    }
    final hourLabels = [for (var h = 0; h < 24; h++) h % 6 == 0 ? '${h}h' : ''];

    // Postgres dow: 0=Sunday..6=Saturday. Shown Monday-first, the local week.
    const dowNames = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
    const order = [1, 2, 3, 4, 5, 6, 0];
    final byDow = {for (final b in data.byWeekday) b.index: b.revenue};
    final weekVals = [for (final d in order) byDow[d] ?? 0.0];
    final weekLabels = [for (final d in order) dowNames[d]];

    return SectionCard(
      title: context.tr('Quand ça se vend'),
      subtitle: context.tr('Chiffre d\'affaires par heure et par jour'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Par heure'), style: _muted(context)),
          const SizedBox(height: 8),
          BarChart(values: hours, labels: hourLabels),
          const SizedBox(height: 20),
          Text(context.tr('Par jour de la semaine'), style: _muted(context)),
          const SizedBox(height: 8),
          BarChart(values: weekVals, labels: weekLabels),
        ],
      ),
    );
  }

  Widget _trendSection(BuildContext context, List<DayPoint> daily) {
    if (daily.length < 2) return const SizedBox.shrink();
    final values = [for (final d in daily) d.revenue];
    final total = values.fold<double>(0, (a, b) => a + b);
    final peak = daily.reduce((a, b) => a.revenue >= b.revenue ? a : b);
    final df = DateFormat('d MMM', 'fr_FR');

    return SectionCard(
      title: context.tr('Tendance'),
      subtitle:
          'Meilleur jour : ${df.format(peak.day)} (${_money.format(peak.revenue)})',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LineChart(values: values),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(df.format(daily.first.day), style: _muted(context)),
              Text('Total : ${_money.format(total)}', style: _muted(context)),
              Text(df.format(daily.last.day), style: _muted(context)),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle? _muted(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall
      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

  // Whole units read cleaner than "10.000"; fractional stock keeps one place.
  String _units(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

  String _perDay(double v) {
    final s = v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
    return context.tr('{s} /jour', {'s': s});
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.money,
    required this.fraction,
  });

  final ProductPerformance product;
  final NumberFormat money;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(money.format(product.revenue),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(scheme.primary),
          ),
        ),
      ],
    );
  }
}

class _Superlative extends StatelessWidget {
  const _Superlative({
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 2),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(detail,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.insights_outlined, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(context.tr('Aucune vente sur cette période'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            context.tr('Enregistrez des ventes et les analyses apparaîtront ici.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
