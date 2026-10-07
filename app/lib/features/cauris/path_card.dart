import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/cauris/feature_states.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';
import 'vitrine_guide.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// One tool on the path (089): its picture, its name, what opens it.
typedef _Step = ({String key, IconData icon, String label});

const _steps = <_Step>[
  (key: 'invoices', icon: Icons.receipt_long, label: 'Factures'),
  (key: 'production', icon: Icons.precision_manufacturing, label: 'Production'),
  (key: 'credits', icon: Icons.handshake, label: 'Crédit'),
  (key: 'second_business', icon: Icons.add_business, label: '2e entreprise'),
];

/// The path on the home (089): the vitrine's ring, and the four tools it
/// opens drawn as tiles — locked grey with the goal under it, open gold.
/// Pictures first, a few words each. Touched, it opens the way to 100 %
/// ([VitrineGuide]); the home shows it only below 100 %.
class PathCard extends StatelessWidget {
  const PathCard({
    super.key,
    required this.org,
    required this.progress,
    this.onChanged,
  });

  final OrgSummary org;
  final BasicProgress progress;

  /// After the guide closes: the home reads its vitrine again.
  final VoidCallback? onChanged;

  /// Whether the home still shows the card: a business on the path whose
  /// vitrine is not yet full.
  static bool shows(BasicProgress p) => p.gated && p.score < 100;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    final reduced = KajMotion.reduced(context);
    return InkWell(
      key: const Key('path-card'),
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        await VitrineGuide.open(context, org);
        onChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: maraDeep,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: p.score / 100),
                  duration: reduced ? Duration.zero : const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            value: v,
                            strokeWidth: 6,
                            color: maraCaramel,
                            backgroundColor: maraPaper.withValues(alpha: 0.18),
                          ),
                        ),
                        Text('${(v * 100).round()} %',
                            key: const Key('path-score'),
                            style: theme.textTheme.labelLarge?.copyWith(
                                color: maraPaper, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(context.tr('Votre vitrine ouvre vos outils'),
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: maraPaper, fontWeight: FontWeight.w800)),
                ),
                const Icon(Icons.chevron_right, color: maraPaper),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final s in _steps)
                  Expanded(child: _Tile(step: s, progress: p)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.step, required this.progress});

  final _Step step;
  final BasicProgress progress;

  @override
  Widget build(BuildContext context) {
    final open = !progress.locks(step.key);
    final theme = Theme.of(context);
    return Column(
      key: Key('path-${step.key}'),
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: open ? maraCaramel : maraPaper.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(step.icon,
                  color: open ? maraDeep : maraPaper.withValues(alpha: 0.55)),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: CircleAvatar(
                radius: 10,
                backgroundColor: open ? maraGreen : maraDeep,
                child: Icon(open ? Icons.check : Icons.lock,
                    size: 12, color: maraPaper),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(context.tr(step.label),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: maraPaper, fontWeight: FontWeight.w700)),
        Text(open ? context.tr('Ouvert') : progress.goalFor(step.key, context.trLanguage),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: maraPaper.withValues(alpha: 0.7), fontSize: 10)),
      ],
    );
  }
}

/// The door to a tool on the path (089).
class PathGate {
  const PathGate._();

  static BasicProgress? _progress(BuildContext context, OrgSummary org) =>
      AppScope.read(context)?.session.featuresFor(org.id)?.progress;

  static bool locks(BuildContext context, OrgSummary org, String feature) =>
      _progress(context, org)?.locks(feature) ?? false;

  /// The way into a tool from a menu: open, or the lock with « lecture
  /// seule » beside it — what was kept is always readable.
  static Future<void> open(BuildContext context, OrgSummary org,
          String feature, VoidCallback go) =>
      guard(context, org, feature, go, view: go);

  /// Opens the tool, or — while it is still ahead — the lock: the picture,
  /// the goal, a bar, and the way there. [view] is offered beside it so a
  /// business that already kept records reads them (« lecture seule »);
  /// leave it null where the act is to create.
  static Future<void> guard(BuildContext context, OrgSummary org,
      String feature, VoidCallback go, {VoidCallback? view}) async {
    final progress = _progress(context, org);
    if (progress == null || !progress.locks(feature)) {
      go();
      return;
    }
    final step = _steps.firstWhere((s) => s.key == feature,
        orElse: () => (key: feature, icon: Icons.lock, label: ''));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) {
        final theme = Theme.of(sheet);
        final reduced = KajMotion.reduced(sheet);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              key: const Key('path-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: maraDeep,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(step.icon, size: 44, color: maraPaper),
                      ),
                      const Positioned(
                        right: -6,
                        bottom: -6,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: maraCaramel,
                          child: Icon(Icons.lock, color: maraDeep, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(context.tr(step.label.isEmpty ? context.tr('Verrouillé') : step.label),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Se débloque : ${progress.goalFor(feature, context.trLanguage)}',
                    key: const Key('path-goal'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 14),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress.progressFor(feature)),
                  duration: reduced ? Duration.zero : const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 10,
                      color: maraCaramel,
                      backgroundColor: maraDeep.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(progress.needFor(feature, context.trLanguage),
                    key: const Key('path-need'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 18),
                if (feature == 'second_business')
                  FilledButton.icon(
                    key: const Key('path-go'),
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      context.push(Routes.inside(org.id, 'kaj-pro'));
                    },
                    icon: const Icon(Icons.workspace_premium),
                    label: Text(context.tr('Voir Mara Pro')),
                  )
                else if (feature == 'credits')
                  FilledButton.icon(
                    key: const Key('path-go'),
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      context.push(Routes.inside(org.id, 'commandes'));
                    },
                    icon: const Icon(Icons.shopping_bag),
                    label: Text(context.tr('Mes commandes')),
                  )
                else
                  FilledButton.icon(
                    key: const Key('path-go'),
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      VitrineGuide.open(context, org);
                    },
                    icon: const Icon(Icons.storefront),
                    label: Text(context.tr('Compléter ma vitrine')),
                  ),
                if (view != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('path-view'),
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      view();
                    },
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(context.tr('Voir (lecture seule)')),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
