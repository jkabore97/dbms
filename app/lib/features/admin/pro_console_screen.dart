import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/access/plan_terms.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';

/// Kaj Pro, from the platform's side (066, M10 block 2).
///
/// Two things and nothing more. The line: the Wave number the owners pay
/// to and the two prices, stored as platform settings so they move without
/// a deploy. The queue: every "J'ai payé" that has not been handled, oldest
/// first, each with the way to the business's Formule card (where Pro is
/// actually granted, 065) and a button to close it once that is done.
class ProConsoleScreen extends StatefulWidget {
  const ProConsoleScreen({super.key, required this.admin});

  final AdminRepository admin;

  @override
  State<ProConsoleScreen> createState() => _ProConsoleScreenState();
}

class _ProConsoleScreenState extends State<ProConsoleScreen> {
  List<PlanRequest> _requests = const [];
  PlanTerms _terms = PlanTerms.defaults;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _saved;

  final _wave = TextEditingController();
  final _waveName = TextEditingController();
  final _month = TextEditingController();
  final _year = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _wave.dispose();
    _waveName.dispose();
    _month.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final terms = await widget.admin.planTerms();
      final requests = await widget.admin.planRequestsOpen();
      if (!mounted) return;
      setState(() {
        _terms = terms;
        _requests = requests;
        _wave.text = terms.wave;
        _waveName.text = terms.waveName;
        _month.text = '${terms.priceMonth}';
        _year.text = '${terms.priceYear}';
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

  Future<void> _saveTerms() async {
    final month = int.tryParse(_month.text.trim());
    final year = int.tryParse(_year.text.trim());
    if (month == null || year == null || month <= 0 || year <= 0) {
      setState(() => _saved = 'Les deux prix doivent être des nombres entiers.');
      return;
    }
    setState(() {
      _saving = true;
      _saved = null;
    });
    try {
      await widget.admin.setPlatformSetting('platform_wave', _wave.text.trim());
      await widget.admin
          .setPlatformSetting('platform_wave_name', _waveName.text.trim());
      await widget.admin.setPlatformSetting('pro_price_month', month);
      await widget.admin.setPlatformSetting('pro_price_year', year);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = 'Enregistré. Les prochains écrans Kaj Pro le disent.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = describeError(error);
      });
    }
  }

  Future<void> _handle(PlanRequest r) async {
    try {
      await widget.admin.handlePlanRequest(r.id);
      if (!mounted) return;
      setState(() => _requests = _requests.where((x) => x.id != r.id).toList());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.decimalPattern('fr_FR');
    final when = DateFormat('d MMM, HH:mm', 'fr_FR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kaj Pro'),
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
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(_error!),
                      trailing: TextButton(
                          onPressed: _load, child: const Text('Réessayer')),
                    ),
                  ),
                Text('Demandes en attente (${_requests.length})',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Un propriétaire a tapé « J\'ai payé ». Vérifiez le '
                  'paiement dans Wave, passez l\'entreprise en Pro depuis sa '
                  'formule, puis marquez la demande traitée.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                if (_requests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Aucune demande en attente.'),
                  ),
                for (final r in _requests)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(r.orgName,
                                    style: theme.textTheme.titleMedium),
                              ),
                              if (r.orgPlan == 'pro')
                                Chip(
                                  label: const Text('déjà Pro'),
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              r.requestedBy,
                              if (r.amount != null)
                                '${money.format(r.amount)} F CFA',
                              if (r.note != null && r.note!.isNotEmpty) r.note!,
                              when.format(r.createdAt.toLocal()),
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => context.push(Routes.inside(
                                    r.orgId, 'administration/parametres')),
                                icon: const Icon(Icons.workspace_premium_outlined,
                                    size: 18),
                                label: const Text('Ouvrir la formule'),
                              ),
                              const SizedBox(width: 4),
                              FilledButton.tonalIcon(
                                onPressed: () => _handle(r),
                                icon: const Icon(Icons.done, size: 18),
                                label: const Text('Traitée'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 12),
                Text('Le numéro et le prix', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Ce que la fenêtre Kaj Pro dit aux propriétaires : où payer '
                  'et combien. Sans numéro, elle dit de contacter Kaj.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _wave,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Numéro Wave / Orange Money de Kaj',
                    hintText: '+226 70 00 00 00',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _waveName,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Nom affiché sur Wave',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _month,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Prix par mois (${_terms.currency})',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _year,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Prix par an (${_terms.currency})',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_saved != null) ...[
                  const SizedBox(height: 8),
                  Text(_saved!, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: FilledButton.tonalIcon(
                    onPressed: _saving ? null : _saveTerms,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Enregistrer le numéro et les prix',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'La liste des outils Pro et les plafonds gratuits '
                  '(${_terms.freeMaxStaff} comptes, '
                  '${_terms.freeMaxInvoicesMonth} factures par mois, '
                  '${_terms.freeMaxPhotos} photos) se changent dans '
                  'platform_settings.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
    );
  }
}
