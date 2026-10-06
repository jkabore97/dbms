import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/access/plan_terms.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../pay/wave_buttons.dart';
import 'package:go_router/go_router.dart';
import '../../core/nav/router.dart';

/// The one door to Kaj Pro (066, M10 block 2).
///
/// Opened from every badged tool, the Compte screen and the « Pro » strip
/// on every page: it now opens the Free and Pro side by side
/// (`/o/<id>/kaj-pro`, ProPlansScreen), whose foot is [ProPayPanel].
class ProSheet {
  static Future<void> open(
    BuildContext context, {
    required OrgSummary org,
    required PlanTerms terms,
    required AdminRepository admin,
    required bool canRequest,
  }) async {
    await GoRouter.of(context).push(Routes.inside(org.id, 'kaj-pro'));
  }
}

/// How to pay for Kaj Pro, and the button that closes the loop by hand
/// until money moves through the platform: Wave (076) when it is open, the
/// platform's number, and « J'ai payé », which writes a request the console
/// lists. With [period] given, the page above chose month or year and this
/// panel draws no choice of its own; with [showFeatures] false, the page
/// above already listed what Pro adds.
class ProPayPanel extends StatefulWidget {
  const ProPayPanel({
    super.key,
    required this.org,
    required this.terms,
    required this.admin,
    required this.canRequest,
    this.period,
    this.showFeatures = true,
    this.top,
  });

  final String? period;
  final bool showFeatures;

  /// Drawn first, for an admin, above Wave: the card button (Stripe).
  final Widget? top;

  final OrgSummary org;
  final PlanTerms terms;
  final AdminRepository admin;

  /// True for an admin of the business — the only person the server lets
  /// say "J'ai payé". Others read the same sheet and are told whom to ask.
  final bool canRequest;

  @override
  State<ProPayPanel> createState() => _ProPayPanelState();
}

class _ProPayPanelState extends State<ProPayPanel> {
  late final _amount = TextEditingController(text: '${widget.terms.priceYear}');
  final _note = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  /// Which period Wave checkout pays for (076).
  String _period = 'year';
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String _money(int amount) =>
      '${NumberFormat.decimalPattern('fr_FR').format(amount)} F CFA';

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final amount =
          double.tryParse(_amount.text.trim().replaceAll(RegExp(r'[\s ]'), ''));
      await widget.admin.requestPro(widget.org.id,
          amount: amount, note: _note.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terms = widget.terms;
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final period = widget.period ?? _period;
    return Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showFeatures) ...[
              Row(
                children: [
                  Icon(Icons.workspace_premium_outlined,
                      color: theme.colorScheme.primary, size: 28),
                  const SizedBox(width: 10),
                  Text('Kaj Pro', style: theme.textTheme.headlineSmall),
                  const Spacer(),
                  if (widget.org.isPro)
                    Chip(
                      label: const Text('Active'),
                      backgroundColor: theme.colorScheme.primaryContainer,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.org.isPro
                    ? 'Cette entreprise est sur Kaj Pro. Tous les outils '
                        'ci-dessous sont ouverts.'
                    : 'Kaj reste gratuit pour le quotidien : le stock, les '
                        'ventes, le carnet de crédit, la vitrine et jusqu\'à '
                        '${terms.freeMaxStaff} comptes en plus du propriétaire. '
                        'Kaj Pro ajoute ce dont une entreprise qui grandit a '
                        'besoin :',
                style: muted,
              ),
              const SizedBox(height: 12),
              for (final f in terms.proFeatures)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(PlanTerms.labelOf(f))),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Comptes, factures et photos sans limite '
                          '(gratuit : ${terms.freeMaxInvoicesMonth} factures '
                          'par mois, ${terms.freeMaxPhotos} photos)'),
                    ),
                  ],
                ),
              ),
              ],
              if (!widget.org.isPro) ...[
                if (widget.showFeatures) ...[
                const SizedBox(height: 16),
                Text(
                  '${_money(terms.priceMonth)} par mois, ou '
                  '${_money(terms.priceYear)} par an.',
                  style: theme.textTheme.titleMedium,
                ),
                ],
                const SizedBox(height: 12),
                if (widget.canRequest && widget.top != null) ...[
                  widget.top!,
                  const SizedBox(height: 12),
                ],
                // Paid and switched on at once, by Wave or card (076) —
                // when the platform has opened it, and for an admin only.
                if (widget.canRequest)
                  WaveButtons(
                    kind: 'pro',
                    ref: widget.org.id,
                    period: period,
                    above: widget.period != null ? null : Center(
                      child: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                              value: 'month',
                              label: Text('1 mois · ${_money(terms.priceMonth)}')),
                          ButtonSegment(
                              value: 'year',
                              label: Text('1 an · ${_money(terms.priceYear)}')),
                        ],
                        selected: {_period},
                        onSelectionChanged: (v) =>
                            setState(() => _period = v.first),
                      ),
                    ),
                    below: Text('Ou à la main :', style: muted),
                  ),
                const SizedBox(height: 8),
                if (terms.hasWave)
                  KajCard(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: ListTile(
                      leading: const Icon(Icons.phone_android_outlined),
                      title: Text(terms.wave),
                      subtitle: Text(terms.waveName.isEmpty
                          ? 'Payez par Wave ou Orange Money à ce numéro'
                          : 'Wave · ${terms.waveName}'),
                      trailing: IconButton(
                        tooltip: 'Copier le numéro',
                        icon: const Icon(Icons.copy_outlined),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: terms.wave));
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              const SnackBar(content: Text('Numéro copié')));
                        },
                      ),
                    ),
                  )
                else
                  Text(
                    'Pour payer, contactez Kaj : le numéro de paiement vous '
                    'sera donné directement.',
                    style: muted,
                  ),
                const SizedBox(height: 16),
                if (_sent)
                  KajCard(
                    elevation: 0,
                    color: theme.colorScheme.primaryContainer,
                    child: const ListTile(
                      leading: Icon(Icons.check_circle_outline),
                      title: Text('Merci, c\'est noté.'),
                      subtitle: Text(
                          'Kaj vérifie le paiement et active Kaj Pro sur cette '
                          'entreprise. Vous le verrez dans Compte › Formule.'),
                    ),
                  )
                else if (widget.canRequest) ...[
                  Text(
                    'Une fois le paiement envoyé, dites-le ici : Kaj le vérifie '
                    'et active la formule.',
                    style: muted,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _amount,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Montant envoyé (F CFA)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _note,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Précision (facultatif)',
                      hintText: 'Nom Wave, référence, date…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _request,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.done_all),
                      label: const Text("J'ai payé",
                          style: TextStyle(fontSize: 17)),
                    ),
                  ),
                ] else
                  Text(
                    'Demandez au propriétaire de l\'entreprise de passer à '
                    'Kaj Pro : lui seul peut le faire.',
                    style: muted,
                  ),
              ],
            ],
          ),
    );
  }
}
