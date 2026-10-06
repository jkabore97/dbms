import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/cauris/feature_states.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';

/// The Basic path (085) on a new business's home: a ring that fills with
/// the vitrine, and what each step opens — the street at 60 %; invoices
/// and receipts, production and the credit book at 90 %; a second
/// business after 10 orders. During the first days' trial everything is
/// open, and the card says until when.
class PathCard extends StatelessWidget {
  const PathCard({super.key, required this.org, required this.progress});

  final OrgSummary org;
  final BasicProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    final reduced = KajMotion.reduced(context);
    final steps = [
      (done: p.onStreet, text: '${p.streetPct} % : votre vitrine sur le marché'),
      (done: p.score >= p.toolsPct,
          text: '${p.toolsPct} % : reçus et factures, production, carnet de crédit'),
      (done: p.orders >= p.ordersNeeded,
          text: '${p.ordersNeeded} commandes : une deuxième entreprise'),
    ];
    return InkWell(
      key: const Key('path-card'),
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push(Routes.orgSettings(org.id)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: maraIndigo,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: p.score / 100),
              duration:
                  reduced ? Duration.zero : const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: v,
                        strokeWidth: 6,
                        color: maraGold,
                        backgroundColor: maraCream.withValues(alpha: 0.18),
                      ),
                    ),
                    Text('${(v * 100).round()} %',
                        key: const Key('path-score'),
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: maraCream, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Votre vitrine ouvre vos outils',
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: maraCream, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final s in steps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            s.done ? Icons.check_circle : Icons.lock_outline,
                            size: 16,
                            color: s.done ? maraGold : maraCream.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(s.text,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: maraCream.withValues(
                                        alpha: s.done ? 1 : 0.8))),
                          ),
                        ],
                      ),
                    ),
                  if (p.inTrial && p.trialUntil != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Essai : tout est ouvert jusqu\'au '
                      '${DateFormat('d MMMM', 'fr_FR').format(p.trialUntil!.toLocal())}.',
                      key: const Key('path-trial'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: maraGold, fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a Basic tool, or — while the path still holds it — says what
/// opens it, with the way to get there (085).
class PathGate {
  const PathGate._();

  static bool locks(BuildContext context, OrgSummary org, String feature) =>
      AppScope.read(context)
          ?.session
          .featuresFor(org.id)
          ?.progress
          .locks(feature) ??
      false;

  static Future<void> guard(BuildContext context, OrgSummary org,
      String feature, VoidCallback go) async {
    final progress =
        AppScope.read(context)?.session.featuresFor(org.id)?.progress;
    if (progress == null || !progress.locks(feature)) {
      go();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            key: const Key('path-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Encore une étape',
                        style: Theme.of(sheet).textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(progress.needFor(feature),
                  style: Theme.of(sheet).textTheme.bodyLarge),
              const SizedBox(height: 6),
              Text(
                feature == 'second_business'
                    ? 'Une deuxième entreprise s\'ouvre quand la première vend : '
                        'chaque commande terminée vous en rapproche.'
                    : 'Une vitrine complète — photos, présentation, téléphone, '
                        'adresse, position — attire les clients et ouvre cet outil.',
                style: Theme.of(sheet).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (feature != 'second_business')
                FilledButton(
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    context.push(Routes.orgSettings(org.id));
                  },
                  child: const Text('Compléter ma vitrine'),
                ),
              TextButton(
                onPressed: () => Navigator.of(sheet).pop(),
                child: const Text('Plus tard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
