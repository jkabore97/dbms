import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/analytics/analytics_repository.dart';
import '../../core/analytics/models.dart';
import '../../core/format/money.dart';
import 'widgets.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// What the platform admin sees: the whole platform in a line of totals, then
/// every business ranked by what it takes. Backed by the two SECURITY DEFINER
/// functions in 036, which refuse anyone who is not a platform admin — so, like
/// the console it lives beside, this screen assumes its reader is entitled and
/// lets the server be the guard.
///
/// Money crosses currencies here, and is never added across them (144): the
/// totals are said once per money the businesses keep their books in —
/// « 1 250 000 FCFA · 340,50 EUR » — and each business's row in its own.
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
  List<PlatformHeadline> _headlines = const [PlatformHeadline.empty];
  List<BusinessPerformance> _businesses = const [];

  int? get _days => _windows[_windowIndex].$2;

  /// Each money's figure, one under the other: « 1 250 000 FCFA »,
  /// « 340,50 EUR ».
  String _each(double Function(PlatformHeadline) f) =>
      [for (final h in _headlines) moneyFormat(h.currency).format(f(h))].join('\n');

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
        widget.analytics.platformHeadlines(days: _days),
        widget.analytics.platformBusinesses(days: _days),
      ]);
      if (!mounted) return;
      setState(() {
        final heads = results[0] as List<PlatformHeadline>;
        _headlines = heads.isEmpty ? const [PlatformHeadline.empty] : heads;
        // Grouped by money, francs CFA first, each ranked as the server
        // ranked it: a ranking across moneys means nothing.
        final rows = results[1] as List<BusinessPerformance>;
        final order = {for (var i = 0; i < rows.length; i++) rows[i]: i};
        _businesses = [...rows]..sort((a, b) {
            final ka = a.currency == 'XOF' ? '' : a.currency;
            final kb = b.currency == 'XOF' ? '' : b.currency;
            final c = ka.compareTo(kb);
            return c != 0 ? c : order[a]!.compareTo(order[b]!);
          });
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
        title: Text(context.tr('Analyses de la plateforme')),
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
              ? Center(child: Text(_error!))
              : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The margin's share of the takings, per money (a ratio, so it may
    // be said for each).
    final marginPct = [
      for (final h in _headlines)
        '${h.revenue == 0 ? 0 : (h.margin / h.revenue * 100).round()}',
    ].join(' · ');
    final sales = _headlines.fold<int>(0, (s, h) => s + h.saleCount);
    final active = _headlines.fold<int>(0, (s, h) => s + h.activeBusinesses);
    final all = _headlines.fold<int>(0, (s, h) => s + h.businesses);

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
              label: context.tr('Chiffre d\'affaires'),
              value: _each((h) => h.revenue),
              icon: Icons.payments_outlined,
              emphasis: true,
            ),
            KpiCard(
              label: context.tr('Bénéfice'),
              value: _each((h) => h.margin),
              hint: context.tr('{pct} % du CA', {'pct': marginPct}),
              icon: Icons.trending_up,
            ),
            KpiCard(
              label: context.tr('Ventes'),
              value: '$sales',
              icon: Icons.receipt_long_outlined,
            ),
            KpiCard(
              label: context.tr('Entreprises actives'),
              value: '$active / $all',
              icon: Icons.storefront_outlined,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: context.tr('Les entreprises'),
          subtitle: context.tr('Classées par chiffre d\'affaires sur la période'),
          child: _businesses.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(context.tr('Aucune entreprise.'),
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                )
              : Column(
                  children: [
                    for (final b in _businesses)
                      _BusinessRow(b: b, money: moneyFormat(b.currency)),
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
        ? context.tr('Aucune vente')
        : context.tr('Dernière : {date}', {'date': DateFormat('d MMM', intlLocale()).format(b.lastSale!.toLocal())});

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
              Text(context.tr('{saleCount} ventes · {marginPct} %', {'saleCount': b.saleCount, 'marginPct': marginPct}),
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
