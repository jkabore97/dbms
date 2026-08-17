import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/analytics/analytics_repository.dart';
import '../../core/analytics/models.dart';
import '../../core/format/money.dart';
import 'widgets.dart';

/// What the platform admin sees: the whole platform in a line of totals, then
/// every business ranked by what it takes. Backed by the two SECURITY DEFINER
/// functions in 036, which refuse anyone who is not a platform admin — so, like
/// the console it lives beside, this screen assumes its reader is entitled and
/// lets the server be the guard.
///
/// Money crosses currencies here. The platform's own home currency (XOF) is
/// used for the totals, because a single comparable number across businesses is
/// the point; per-business rows show each business's figure in that same unit.
class PlatformAnalyticsScreen extends StatefulWidget {
  const PlatformAnalyticsScreen({super.key, required this.analytics});

  final AnalyticsRepository analytics;

  @override
  State<PlatformAnalyticsScreen> createState() =>
      _PlatformAnalyticsScreenState();
}

class _PlatformAnalyticsScreenState extends State<PlatformAnalyticsScreen> {
  static const _windows = <(String, int?)>[
    ('7 j', 7),
    ('30 j', 30),
    ('90 j', 90),
    ('Tout', null),
  ];

  int _windowIndex = 1;
  bool _loading = true;
  String? _error;
  PlatformHeadline _headline = PlatformHeadline.empty;
  List<BusinessPerformance> _businesses = const [];

  int? get _days => _windows[_windowIndex].$2;
  // The platform reports in the franc, the shared unit across businesses.
  final NumberFormat _money = moneyFormat('XOF');

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
      final results = await Future.wait([
        widget.analytics.platformHeadline(days: _days),
        widget.analytics.platformBusinesses(days: _days),
      ]);
      if (!mounted) return;
      setState(() {
        _headline = results[0] as PlatformHeadline;
        _businesses = results[1] as List<BusinessPerformance>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Les analyses n'ont pas pu être chargées.";
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
        title: const Text('Analyses de la plateforme'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final marginPct = _headline.revenue == 0
        ? 0
        : (_headline.margin / _headline.revenue * 100).round();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < _windows.length; i++)
              ChoiceChip(
                label: Text(_windows[i].$1),
                selected: i == _windowIndex,
                onSelected: (_) => _pickWindow(i),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            KpiCard(
              label: 'Chiffre d\'affaires',
              value: _money.format(_headline.revenue),
              icon: Icons.payments_outlined,
              emphasis: true,
            ),
            KpiCard(
              label: 'Bénéfice',
              value: _money.format(_headline.margin),
              hint: '$marginPct % du CA',
              icon: Icons.trending_up,
            ),
            KpiCard(
              label: 'Ventes',
              value: '${_headline.saleCount}',
              icon: Icons.receipt_long_outlined,
            ),
            KpiCard(
              label: 'Entreprises actives',
              value: '${_headline.activeBusinesses} / ${_headline.businesses}',
              icon: Icons.storefront_outlined,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Les entreprises',
          subtitle: 'Classées par chiffre d\'affaires sur la période',
          child: _businesses.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('Aucune entreprise.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                )
              : Column(
                  children: [
                    for (final b in _businesses) _BusinessRow(b: b, money: _money),
                  ],
                ),
        ),
      ],
    );
  }
}

class _BusinessRow extends StatelessWidget {
  const _BusinessRow({required this.b, required this.money});

  final BusinessPerformance b;
  final NumberFormat money;

  static const _profileLabels = {
    'association': 'Association',
    'church': 'Association',
    'farm': 'Ferme',
    'retail': 'Commerce',
    'generic': 'Autre',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final marginPct =
        b.revenue == 0 ? 0 : (b.margin / b.revenue * 100).round();
    final last = b.lastSale == null
        ? 'Aucune vente'
        : 'Dernière : ${DateFormat('d MMM', 'fr_FR').format(b.lastSale!.toLocal())}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.orgName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${_profileLabels[b.profile] ?? b.profile} · $last',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(money.format(b.revenue),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${b.saleCount} ventes · $marginPct %',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
