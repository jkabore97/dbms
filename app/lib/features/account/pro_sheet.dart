import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/access/plan_terms.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/errors.dart';

/// The one door to Kaj Pro (066, M10 block 2).
///
/// Opened from every badged tool and from the Compte screen. It says what Pro
/// is, what it costs, where to pay, and carries the one button that closes
/// the loop by hand until money moves through the platform: "J'ai payé",
/// which writes a request the console lists. No money moves here.
class ProSheet {
  static Future<void> open(
    BuildContext context, {
    required OrgSummary org,
    required PlanTerms terms,
    required AdminRepository admin,
    required bool canRequest,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ProSheetBody(
        org: org,
        terms: terms,
        admin: admin,
        canRequest: canRequest,
      ),
    );
  }
}

class _ProSheetBody extends StatefulWidget {
  const _ProSheetBody({
    required this.org,
    required this.terms,
    required this.admin,
    required this.canRequest,
  });

  final OrgSummary org;
  final PlanTerms terms;
  final AdminRepository admin;

  /// True for an admin of the business — the only person the server lets
  /// say "J'ai payé". Others read the same sheet and are told whom to ask.
  final bool canRequest;

  @override
  State<_ProSheetBody> createState() => _ProSheetBodyState();
}

class _ProSheetBodyState extends State<_ProSheetBody> {
  late final _amount = TextEditingController(text: '${widget.terms.priceYear}');
  final _note = TextEditingController();
  bool _busy = false;
  bool _sent = false;
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

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            24, 8, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
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
              if (!widget.org.isPro) ...[
                const SizedBox(height: 16),
                Text(
                  '${_money(terms.priceMonth)} par mois, ou '
                  '${_money(terms.priceYear)} par an.',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (terms.hasWave)
                  Card(
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
                  Card(
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
        ),
      ),
    );
  }
}
