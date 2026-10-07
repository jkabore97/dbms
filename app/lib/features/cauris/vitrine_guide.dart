import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// One of the six steps to a full vitrine: its picture, what to do, and
/// the rubrique of the settings where it is done.
typedef GuideStep = ({
  IconData icon,
  String title,
  String hint,
  String part,
  bool done,
});

/// The six steps in the order an owner should take them (070's order),
/// each with the words that say what is left.
List<GuideStep> guideSteps(VitrineChecklist c) {
  final min = c.minItems < 1 ? 1 : c.minItems;
  return [
    (
      icon: Icons.inventory_2,
      title: 'Des articles en vente',
      hint: '${c.published} / $min',
      part: 'articles',
      done: c.published >= min,
    ),
    (
      icon: Icons.photo_camera,
      title: 'Trois articles en photo',
      hint: '${c.withPhoto} / 3',
      part: 'articles',
      done: c.photosDone,
    ),
    (
      icon: Icons.short_text,
      title: 'Une phrase de présentation',
      hint: 'Ce que vous vendez, en une phrase',
      part: 'vitrine',
      done: c.blurb,
    ),
    (
      icon: Icons.call,
      title: 'Un numéro de téléphone',
      hint: 'Pour que vos clients vous appellent',
      part: 'vitrine',
      done: c.phone,
    ),
    (
      icon: Icons.home_work,
      title: "L'adresse",
      hint: 'Le quartier, un repère',
      part: 'vitrine',
      done: c.address,
    ),
    (
      icon: Icons.place,
      title: 'La position sur la carte',
      hint: 'Vos clients vous trouvent',
      part: 'position',
      done: c.pin,
    ),
  ];
}

/// « Votre vitrine ouvre vos outils », touched: the way to 100 %, one step
/// at a time. The next step is lit with « Faire maintenant », which opens
/// the very rubrique where it is done; back here the ring has moved and
/// the next one is lit. At 100 % the sheet says so and closes — and the
/// card on the home is gone.
class VitrineGuide extends StatefulWidget {
  const VitrineGuide({super.key, required this.org, this.load});

  final OrgSummary org;

  /// Reads the checklist; the app's admin repository unless a test gives
  /// its own.
  final Future<VitrineChecklist?> Function()? load;

  static Future<void> open(BuildContext context, OrgSummary org,
          {Future<VitrineChecklist?> Function()? load}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => VitrineGuide(org: org, load: load),
      );

  @override
  State<VitrineGuide> createState() => _VitrineGuideState();
}

class _VitrineGuideState extends State<VitrineGuide> {
  VitrineChecklist? _list;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    VitrineChecklist? list;
    try {
      list = await (widget.load ??
          () async =>
              AppScope.read(context)?.admin.vitrineChecklist(widget.org.id))();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  Future<void> _go(GuideStep step) async {
    await context.push(Routes.orgSettings(widget.org.id, part: step.part));
    if (!mounted) return;
    final before = _list?.score ?? 0;
    await _read();
    if (!mounted) return;
    // The path's own gates follow the new score.
    final scope = AppScope.maybeOf(context);
    if (scope != null) await scope.session.reloadFeatures(widget.org.id);
    if (!mounted) return;
    if ((_list?.score ?? 0) >= 100 && before < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduced = KajMotion.reduced(context);
    final list = _list;
    if (_loading) {
      return const SizedBox(
          height: 200, child: Center(child: CircularProgressIndicator()));
    }
    if (list == null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Text(
            context.tr('Impossible de lire votre vitrine pour le moment. Réessayez avec du réseau.'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final steps = guideSteps(list);
    final next = steps.indexWhere((s) => !s.done);
    final score = list.score;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: ListView(
          key: const Key('vitrine-guide'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: score / 100),
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 800),
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
                            strokeWidth: 7,
                            color: score >= 100 ? maraGreen : maraCaramel,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        Text('${(v * 100).round()} %',
                            key: const Key('guide-score'),
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        score >= 100
                            ? context.tr('Vitrine complète !')
                            : context.tr('Vers 100 %, pas à pas'),
                        key: const Key('guide-title'),
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        score >= 100
                            ? context.tr('Tous vos outils s\'ouvrent.')
                            : context.tr('{done} sur {total} — chaque étape ouvre un outil de plus.',
                                {'done': steps.where((s) => s.done).length, 'total': steps.length}),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < steps.length; i++)
              _StepRow(
                index: i,
                step: steps[i],
                current: i == next,
                onGo: () => _go(steps[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.step,
    required this.current,
    required this.onGo,
  });

  final int index;
  final GuideStep step;
  final bool current;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = step.done;
    return AnimatedContainer(
      key: Key('guide-step-$index'),
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: current
            ? maraDeep
            : theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: done ? 0.5 : 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: done
                  ? maraGreen
                  : current
                      ? maraCaramel
                      : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(done ? Icons.check : step.icon,
                color: done
                    ? maraPaper
                    : current
                        ? maraDeep
                        : theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(step.title),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: current ? maraPaper : null,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  done ? context.tr('Fait') : context.tr(step.hint),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: current
                        ? maraPaper.withValues(alpha: 0.75)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (current)
            FilledButton(
              key: const Key('guide-go'),
              style: FilledButton.styleFrom(
                  backgroundColor: maraCaramel, foregroundColor: maraDeep),
              onPressed: onGo,
              child: Text(context.tr('Faire maintenant')),
            )
          else if (!done)
            TextButton(onPressed: onGo, child: Text(context.tr('Faire'))),
        ],
      ),
    );
  }
}
