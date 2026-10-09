import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/nav/app_scope.dart';
import '../../core/pay/wave_pay.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// Console › Paiements Wave (076): the switches, the platform's share, and
/// every payment with its payout — failed payouts first, since each is a
/// shop waiting for its money.
class WaveConsoleScreen extends StatefulWidget {
  const WaveConsoleScreen({super.key, this.pay});

  final WavePay? pay;

  @override
  State<WaveConsoleScreen> createState() => _WaveConsoleScreenState();
}

class _WaveConsoleScreenState extends State<WaveConsoleScreen> {
  late final WavePay? _pay = widget.pay ?? AppScope.read(context)?.wavePay;
  WaveTerms _terms = const WaveTerms();
  List<WavePaymentRow> _rows = const [];
  final _share = TextEditingController();
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _share.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final pay = _pay;
    if (pay == null) return;
    try {
      final terms = await pay.terms();
      final rows = await pay.platformPayments();
      if (!mounted) return;
      setState(() {
        _terms = terms;
        _rows = rows;
        _share.text = terms.commissionPct == terms.commissionPct.roundToDouble()
            ? terms.commissionPct.round().toString()
            : '${terms.commissionPct}';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(String key, Object value) async {
    setState(() => _busy = true);
    try {
      await _pay!.setSwitch(key, value);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat('XOF');
    final when = DateFormat('d MMM, HH:mm', 'fr_FR');
    final failed = _rows.where((r) => r.payoutStatus == 'failed').length;
    return Scaffold(
      appBar: AppBar(actions: const [bellRoom], title: Text(context.tr('Paiements Wave'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_pay!.compiledIn)
                  KajCard(
                    color: theme.colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(context.tr('Cette version de l\'app ne connaît pas le service de paiement (PAY_URL).')),
                    ),
                  ),
                SwitchListTile(
                  value: _terms.on,
                  onChanged: _busy ? null : (v) => _set('wave_checkout', v),
                  title: Text(context.tr('Paiement Wave dans Mara')),
                  subtitle: Text(
                      context.tr('Commandes, Mara Pro et mises en avant. À ouvrir une fois la clé Wave installée et un essai réussi.')),
                ),
                SwitchListTile(
                  value: _terms.card,
                  onChanged: _busy ? null : (v) => _set('wave_card', v),
                  title: Text(context.tr('Proposer « Payer par carte »')),
                  subtitle: Text(
                      context.tr('Seulement si la page de paiement Wave accepte les cartes pour votre compte.')),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _share,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: context.tr('Part de la plateforme sur une commande (%)'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () => _set('wave_commission_pct',
                            num.tryParse(_share.text.replaceAll(',', '.')) ?? 0),
                    child: Text(context.tr('Enregistrer')),
                  ),
                ]),
                const SizedBox(height: 24),
                Text(
                    failed == 0
                        ? context.tr('Paiements')
                        : 'Paiements · $failed versement${failed > 1 ? 's' : ''} en échec',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.tr('Aucun paiement Wave pour le moment.')),
                  ),
                for (final r in _rows)
                  KajCard(
                    color: r.payoutStatus == 'failed'
                        ? theme.colorScheme.errorContainer
                        : null,
                    child: ListTile(
                      title: Text('${r.orgName} · ${money.format(r.amount)}'),
                      subtitle: Text([
                        switch (r.kind) {
                          'order' => 'Commande',
                          'pro' => 'Mara Pro',
                          _ => 'Mise en avant',
                        },
                        r.method == 'card' ? 'carte' : context.tr('Wave'),
                        switch (r.status) {
                          'succeeded' => 'payé',
                          'failed' => 'échoué',
                          'expired' => 'expiré',
                          _ => 'en cours',
                        },
                        if (r.kind == 'order')
                          switch (r.payoutStatus) {
                            'sent' => 'versé à ${r.payoutTo ?? 'la boutique'}',
                            'pending' => 'versement en cours',
                            'failed' => 'versement échoué : ${r.payoutError ?? ''}',
                            _ => '',
                          },
                        if (r.commission > 0) 'part ${money.format(r.commission)}',
                        if (r.createdAt != null) when.format(r.createdAt!),
                      ].where((x) => x.isNotEmpty).join(' · ')),
                    ),
                  ),
              ],
            ),
    );
  }
}
