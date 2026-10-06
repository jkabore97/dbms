import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/access/plan_terms.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/cauris/cauris_repository.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';
import 'cauris_console_card.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// Kaj Pro, from the platform's side (066, M10 block 2).
///
/// Two things and nothing more. The line: the Wave number the owners pay
/// to and the two prices, stored as platform settings so they move without
/// a deploy. The queue: every "J'ai payé" that has not been handled, oldest
/// first, each with the way to the business's Formule card (where Pro is
/// actually granted, 065) and a button to close it once that is done.
class ProConsoleScreen extends StatefulWidget {
  const ProConsoleScreen({super.key, required this.admin, this.cauris});

  final AdminRepository admin;

  /// The cauris rules and the week's top earners (084).
  final CaurisRepository? cauris;

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
  bool _stripeOn = false;
  bool _stripeSaving = false;

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
        _stripeOn = terms.stripeOn;
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
        _saved = 'Enregistré. Les prochains écrans Mara Pro le disent.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = describeError(error);
      });
    }
  }

  /// Kaj Pro by card (082): Stripe charges the two prices above, monthly
  /// or yearly. Saved at once — the comparison page reads it next time.
  Future<void> _setStripe(bool on) async {
    setState(() {
      _stripeSaving = true;
      _stripeOn = on;
    });
    try {
      await widget.admin.setPlatformSetting('stripe_on', on);
    } catch (error) {
      if (!mounted) return;
      setState(() => _stripeOn = !on);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _stripeSaving = false);
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
        title: Text(context.tr('Mara Pro')),
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
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  KajCard(
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(_error!),
                      trailing: TextButton(
                          onPressed: _load, child: Text(context.tr('Réessayer'))),
                    ),
                  ),
                Text(context.tr('Demandes en attente ({length})', {'length': _requests.length}),
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  context.tr('Un propriétaire a tapé « J\'ai payé ». Vérifiez le paiement dans Wave, passez l\'entreprise en Pro depuis sa formule, puis marquez la demande traitée.'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                if (_requests.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(context.tr('Aucune demande en attente.')),
                  ),
                for (final r in _requests)
                  KajCard(
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
                                  label: Text(context.tr('déjà Pro')),
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
                                onPressed: () => context.push(Routes.orgSettings(r.orgId)),
                                icon: const Icon(Icons.workspace_premium_outlined,
                                    size: 18),
                                label: Text(context.tr('Ouvrir la formule')),
                              ),
                              const SizedBox(width: 4),
                              FilledButton.tonalIcon(
                                onPressed: () => _handle(r),
                                icon: const Icon(Icons.done, size: 18),
                                label: Text(context.tr('Traitée')),
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
                Text(context.tr('Le numéro et le prix'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  context.tr('Ce que la fenêtre Mara Pro dit aux propriétaires : où payer et combien. Sans numéro, elle dit de contacter Mara.'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _wave,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: context.tr('Numéro Wave / Orange Money de Mara'),
                    hintText: '+226 70 00 00 00',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _waveName,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    labelText: context.tr('Nom affiché sur Wave'),
                    border: const OutlineInputBorder(),
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
                          labelText: context.tr('Prix par mois ({currency})', {'currency': _terms.currency}),
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
                          labelText: context.tr('Prix par an ({currency})', {'currency': _terms.currency}),
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
                    label: Text(context.tr('Enregistrer le numéro et les prix'),
                        style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  key: const Key('stripe-on'),
                  contentPadding: EdgeInsets.zero,
                  value: _stripeOn,
                  onChanged: _stripeSaving ? null : _setStripe,
                  title: Text(context.tr('Abonnement par carte (Stripe)')),
                  subtitle: Text(
                    context.tr('Les propriétaires s\'abonnent par carte, au prix ci-dessus, renouvelé chaque mois ou chaque année. À ouvrir une fois les clés Stripe installées (README, « Mara Pro by card »). Un nouveau prix vaut pour les nouveaux abonnements.'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (widget.cauris != null) ...[
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 12),
                  CaurisConsoleCard(cauris: widget.cauris!),
                ],
                const SizedBox(height: 16),
                Text(
                  context.tr('La liste des outils Pro et les plafonds gratuits ({freeMaxStaff} comptes, {freeMaxInvoicesMonth} factures par mois, {freeMaxPhotos} photos) se changent dans platform_settings.', {'freeMaxStaff': _terms.freeMaxStaff, 'freeMaxInvoicesMonth': _terms.freeMaxInvoicesMonth, 'freeMaxPhotos': _terms.freeMaxPhotos}),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
    );
  }
}
