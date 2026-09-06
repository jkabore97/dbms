import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/access/plan_terms.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart';

/// What each courier owes for a month (067, M10 block 4).
///
/// The customer pays the courier at the door; the platform's part of every
/// delivery fee is a debt the courier settles by Wave once a month, from
/// this page. One row per courier: courses, fees collected, the share owed,
/// what they kept. The month steps back and forward; the share percentage
/// for the *next* orders is set at the bottom — an order already placed
/// keeps the percentage it was placed at.
class SettlementScreen extends StatefulWidget {
  const SettlementScreen({super.key, required this.admin});

  final AdminRepository admin;

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<CourierSettlement> _rows = const [];
  PlanTerms _terms = PlanTerms.defaults;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _saved;
  final _pct = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pct.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final terms = await widget.admin.planTerms();
      final rows = await widget.admin.deliverySettlement(_month);
      if (!mounted) return;
      setState(() {
        _terms = terms;
        _rows = rows;
        if (_pct.text.isEmpty) _pct.text = '${terms.deliverySharePct}';
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

  void _step(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
    _load();
  }

  Future<void> _savePct() async {
    final pct = int.tryParse(_pct.text.trim());
    if (pct == null || pct < 0 || pct > 100) {
      setState(() => _saved = 'Le pourcentage va de 0 à 100.');
      return;
    }
    setState(() {
      _saving = true;
      _saved = null;
    });
    try {
      await widget.admin.setPlatformSetting('delivery_share_pct', pct);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = 'Enregistré : $pct % sur les prochaines livraisons. '
            'Les commandes déjà passées gardent leur part.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.decimalPattern('fr_FR');
    final monthLabel = DateFormat('MMMM yyyy', 'fr_FR').format(_month);
    final owed = _rows.fold<double>(0, (sum, r) => sum + r.share);
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Règlement des livreurs'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Mois précédent',
                onPressed: _loading ? null : () => _step(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  monthLabel[0].toUpperCase() + monthLabel.substring(1),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Mois suivant',
                onPressed: _loading || isCurrent ? null : () => _step(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Le client paie le livreur à la porte ; la part de Kaj sur '
            'chaque livraison est due par le livreur à la fin du mois, '
            'par Wave. Ce que chaque livreur doit, ce mois-ci :',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
                trailing:
                    TextButton(onPressed: _load, child: const Text('Réessayer')),
              ),
            ),
          if (!_loading && _error == null) ...[
            Card(
              elevation: 0,
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text('${money.format(owed)} F CFA dus à Kaj',
                    style: theme.textTheme.titleMedium),
                subtitle: Text(
                    '${_rows.length} livreur${_rows.length > 1 ? 's' : ''} · '
                    '${_rows.fold<int>(0, (s, r) => s + r.courses)} courses'),
              ),
            ),
            const SizedBox(height: 8),
            if (_rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Aucune livraison ce mois-ci.'),
              ),
            for (final r in _rows)
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                color: theme.colorScheme.surfaceContainerHighest,
                child: ListTile(
                  title: Text(r.name),
                  subtitle: Text([
                    if (r.phone != null) r.phone!,
                    '${r.courses} course${r.courses > 1 ? 's' : ''}',
                    'encaissé ${money.format(r.fees)} F',
                    'gardé ${money.format(r.net)} F',
                  ].join(' · ')),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${money.format(r.share)} F',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('à régler',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          Text('La part de Kaj', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'En pourcentage des frais de livraison. Fixée sur chaque '
            'commande au moment où elle est passée : changer le taux ne '
            'change que les prochaines. Aujourd\'hui : ${_terms.deliverySharePct} %.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _pct,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Part (%)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: FilledButton.tonalIcon(
                    onPressed: _saving ? null : _savePct,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Enregistrer le taux'),
                  ),
                ),
              ),
            ],
          ),
          if (_saved != null) ...[
            const SizedBox(height: 8),
            Text(_saved!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
