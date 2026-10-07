import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/cauris/cauris_repository.dart';
import '../../core/cauris/feature_states.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';
import 'cauri_icon.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// A tool on Le Chemin (097): its picture and its name.
typedef PathTool = ({String key, IconData icon, String label});

const pathTools = <PathTool>[
  (key: 'invoices', icon: Icons.receipt_long, label: 'Factures'),
  (key: 'production', icon: Icons.precision_manufacturing, label: 'Production'),
  (key: 'credits', icon: Icons.handshake, label: 'Crédit'),
  (key: 'second_business', icon: Icons.add_business, label: '2e entreprise'),
];

/// The picture of each step on the path.
IconData pathStepIcon(String key) => switch (key) {
      'first_article' || 'articles' => Icons.inventory_2,
      'vitrine_open' => Icons.storefront,
      'contact' => Icons.call,
      'photos' => Icons.photo_camera,
      'blurb' => Icons.short_text,
      'pin' => Icons.place,
      'first_sale' => Icons.point_of_sale,
      'farm_log' => Icons.menu_book,
      'first_order' => Icons.shopping_bag,
      'three_orders' => Icons.task_alt,
      'returning' => Icons.replay,
      'till_week' || 'log_week' => Icons.calendar_month,
      'first_unlock' => Icons.lock_open,
      'referral' => Icons.group_add,
      'podium' => Icons.emoji_events,
      _ => Icons.flag,
    };

/// A step's name, in the person's language. The server writes it in
/// French (en.dart has each one, test/tr_coverage_test.dart checks); the
/// one with a number in it, `articles`, is said here from its goal.
String pathStepTitle(BuildContext context, PathStep s, {bool farm = false}) {
  if (s.key == 'articles') {
    return farm
        ? context.tr('{n} produits en vente', {'n': s.goal})
        : context.tr('{n} articles en vente', {'n': s.goal});
  }
  return translate(context.trLanguage, s.title);
}

/// Why a step matters, in the person's language — the numbers said here
/// for the two lines that carry one.
String pathStepLine(BuildContext context, PathStep s, {bool farm = false}) {
  switch (s.key) {
    case 'articles':
      return farm
          ? context.tr('Avec {n} produits, votre vitrine se montre à tout le monde.',
              {'n': s.goal})
          : context.tr('Avec {n} articles, votre vitrine se montre à tout le monde.',
              {'n': s.goal});
    case 'referral':
      // What a sponsored business pays once it takes off: the server's
      // number (cauris_rules), read back from its sentence.
      final m = RegExp(r'\+(\d+)').firstMatch(s.line);
      if (m != null) {
        return context.tr(
            'Une entreprise vous nomme parrain. Quand elle décolle, +{referral} cauris de plus.',
            {'referral': m.group(1)});
      }
  }
  return translate(context.trLanguage, s.line);
}

/// What the cauris history and rules say, from the server, in French: in
/// English wherever en.dart has the phrase.
String caurisText(BuildContext context, String fr) =>
    translate(context.trLanguage, fr);

/// « Étape 2 sur 4 · Remplir »
String pathStageLine(BuildContext context, PathState p) =>
    context.tr('Étape {n} sur 4 · {title}',
        {'n': p.stage, 'title': translate(context.trLanguage, p.titleOf(p.stage))});

/// What opens a tool, in a few words, from the steps that gate it — a
/// farm sells « produits ».
String pathToolGoal(BuildContext context, OrgSummary org, String feature,
    PathState? p) {
  switch (feature) {
    case 'invoices':
      final counts = {
        'n': p?.step('articles')?.goal ?? 1,
        'p': p?.step('photos')?.goal ?? 3,
      };
      return org.profile == 'farm'
          ? context.tr('{n} produits en vente et {p} en photo', counts)
          : context.tr('{n} articles en vente et {p} en photo', counts);
    case 'production':
      return context.tr('Terminez l\'étape {stage}', {
        'stage': translate(context.trLanguage,
            p == null || p.titleOf(2).isEmpty ? 'Remplir' : p.titleOf(2)),
      });
    case 'credits':
      return context.tr('{n} commandes terminées',
          {'n': p?.step('three_orders')?.goal ?? 3});
    case 'second_business':
      return 'Mara Pro';
  }
  return '';
}

/// The steps a tool waits for: invoices the articles and their photos,
/// production the whole of « Remplir », credits three finished orders.
List<PathStep> pathGateSteps(String feature, PathState p) => switch (feature) {
      'invoices' => [
          for (final k in const ['articles', 'photos']) ?p.step(k),
        ],
      'production' => p.stepsOf(2),
      'credits' => [?p.step('three_orders')],
      _ => const [],
    };

/// How far toward a step's goal, 0–1, as remembered (a step reached
/// stays full).
double pathStepShare(PathStep s) =>
    s.done || s.goal <= 0 ? 1 : (s.progress / s.goal).clamp(0, 1).toDouble();

/// How far toward a step's goal right now, 0–1 — what a tool's gate reads.
double pathStepLiveShare(PathStep s) =>
    s.goal <= 0 ? 1 : (s.live / s.goal).clamp(0, 1).toDouble();

/// What Mon chemin answers when a step is done at the till: the home
/// that opened it opens the sale sheet.
const pathSellResult = 'vendre';

/// Mon chemin's address, opened on one section: 'depenser' (what the
/// cauris buy) or 'parrainer'. [fromTill] says the home with the till
/// opened it, so a step done at the till can come back to it.
String pathCheminRest({String? part, bool fromTill = false}) {
  final q = [
    if (part != null) 'partie=$part',
    if (fromTill) 'caisse=1',
  ];
  return q.isEmpty ? 'chemin' : 'chemin?${q.join('&')}';
}

/// The section of Mon chemin where a step of the last stage is done.
String? pathCheminPart(PathStep s) => s.go != 'chemin'
    ? null
    : s.key == 'referral'
        ? 'parrainer'
        : 'depenser';

/// Goes where a step is done, then reads the gates again (a step may have
/// opened a tool). An empty address is the home itself: [onHere] there (the
/// sale sheet), or — with nothing to open — a word saying where.
Future<void> openPathStep(BuildContext context, OrgSummary org, PathStep s,
    {VoidCallback? onHere}) async {
  final session = AppScope.read(context)?.session;
  if (s.go.isEmpty) {
    if (onHere != null) {
      onHere();
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(context.tr('Faites vos ventes à la caisse, sur l\'accueil.'))));
    }
    return;
  }
  final part = pathCheminPart(s);
  await context.push(Routes.inside(
      org.id, part == null ? s.go : pathCheminRest(part: part)));
  await session?.reloadFeatures(org.id);
}

/// Le Chemin on the home (097): one graphite card with the one next thing
/// to do — its picture, a line on why, how far, what it pays and what it
/// opens — and « Faire maintenant », which goes where it is done. The rest
/// of the path is one touch away (the card itself opens Mon chemin). Gone
/// once the path is walked.
class PathCard extends StatelessWidget {
  const PathCard({
    super.key,
    required this.org,
    required this.state,
    this.onChanged,
    this.onHere,
  });

  final OrgSummary org;
  final PathState state;

  /// Back from a step or from Mon chemin: the home reads the path again.
  final VoidCallback? onChanged;

  /// A step done on the home itself (the till's first sale).
  final VoidCallback? onHere;

  /// For an admin of a shop or a farm with a step it can do now — never
  /// the podium while the league says « Bientôt ».
  static bool shows(OrgSummary org, PathState? p) =>
      org.isAdmin &&
      (org.profile == 'retail' || org.profile == 'farm') &&
      p != null &&
      !p.finished &&
      p.proposed != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduced = KajMotion.reduced(context);
    final step = state.proposed!;
    final farm = org.profile == 'farm';
    final stageSteps = state.stepsOf(state.stage);
    final stageShare = stageSteps.isEmpty
        ? 0.0
        : stageSteps.where((s) => s.done).length / stageSteps.length;
    final soft = maraPaper.withValues(alpha: 0.75);
    final opens = step.opens == null
        ? null
        : pathTools.where((t) => t.key == step.opens).firstOrNull;
    return InkWell(
      key: const Key('path-card'),
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        final session = AppScope.read(context)?.session;
        final r = await context.push<Object?>(
            Routes.inside(org.id, pathCheminRest(fromTill: onHere != null)));
        // A step done there may have opened a tool: the gates, then the path.
        await session?.reloadFeatures(org.id);
        if (r == pathSellResult) onHere?.call();
        onChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: maraDeep,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Where on the path: the stage's ring, its number and name.
            Row(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: stageShare),
                  duration: reduced ? Duration.zero : const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => SizedBox(
                    width: 30,
                    height: 30,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            value: v,
                            strokeWidth: 3.5,
                            color: maraCaramel,
                            backgroundColor: maraPaper.withValues(alpha: 0.18),
                          ),
                        ),
                        Text('${state.stage}',
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: maraPaper, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(pathStageLine(context, state),
                      key: const Key('path-stage'),
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: soft, fontWeight: FontWeight.w700)),
                ),
                Icon(Icons.chevron_right, color: soft),
              ],
            ),
            const SizedBox(height: 14),
            // The next step, picture first.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: maraCaramel,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(pathStepIcon(step.key), size: 30, color: maraDeep),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pathStepTitle(context, step, farm: farm),
                          key: const Key('path-next'),
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: maraPaper, fontWeight: FontWeight.w800)),
                      if (step.line.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(pathStepLine(context, step, farm: farm),
                            style: theme.textTheme.bodySmall?.copyWith(color: soft)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (step.goal > 1) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: pathStepShare(step)),
                      duration: reduced ? Duration.zero : const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: v,
                          minHeight: 8,
                          color: maraCaramel,
                          backgroundColor: maraPaper.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${step.progress} / ${step.goal}',
                      key: const Key('path-count'),
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: maraPaper, fontWeight: FontWeight.w800)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            // What it pays, and the door it opens.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(
                  key: const Key('path-reward'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CauriIcon(size: 15),
                      const SizedBox(width: 5),
                      Text(context.tr('+{n} cauris', {'n': step.reward}),
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: maraPaper, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                if (opens != null)
                  _Chip(
                    key: const Key('path-opens'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_open, size: 15, color: maraCaramel),
                        const SizedBox(width: 5),
                        Text(context.tr('ouvre : {tool}', {'tool': context.tr(opens.label)}),
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: maraPaper, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                key: const Key('path-do'),
                style: FilledButton.styleFrom(
                    backgroundColor: maraCaramel, foregroundColor: maraDeep),
                onPressed: () async {
                  await openPathStep(context, org, step, onHere: onHere);
                  if (step.go.isNotEmpty) onChanged?.call();
                },
                icon: const Icon(Icons.arrow_forward),
                label: Text(context.tr('Faire maintenant'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: maraPaper.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(99),
        ),
        child: child,
      );
}

/// The door to a tool on the path (089, step by step since 097).
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
  /// the goal, the steps it waits for, and the way there (Mon chemin).
  /// [view] is offered beside it so a business that already kept records
  /// reads them (« lecture seule »); leave it null where the act is to
  /// create. [load] reads the path; the app's own unless a test gives one.
  static Future<void> guard(BuildContext context, OrgSummary org,
      String feature, VoidCallback go,
      {VoidCallback? view, Future<PathState?> Function()? load}) async {
    final progress = _progress(context, org);
    if (progress == null || !progress.locks(feature)) {
      go();
      return;
    }
    final client = AppScope.read(context)?.auth.client;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => PathGateSheet(
        org: org,
        feature: feature,
        load: load ?? () => CaurisRepository(client).pathState(org.id),
        onPath: () {
          Navigator.of(sheet).pop();
          context.push(Routes.inside(org.id,
              feature == 'second_business' ? 'kaj-pro' : 'chemin'));
        },
        onView: view == null
            ? null
            : () {
                Navigator.of(sheet).pop();
                view();
              },
      ),
    );
  }
}

/// The lock on a tool on the path: its picture, its goal, the steps it
/// waits for — each ticked or counted — and the way to Mon chemin.
class PathGateSheet extends StatefulWidget {
  const PathGateSheet({
    super.key,
    required this.org,
    required this.feature,
    required this.load,
    required this.onPath,
    this.onView,
  });

  final OrgSummary org;
  final String feature;
  final Future<PathState?> Function() load;
  final VoidCallback onPath;

  /// « Voir (lecture seule) »; null hides it.
  final VoidCallback? onView;

  @override
  State<PathGateSheet> createState() => _PathGateSheetState();
}

class _PathGateSheetState extends State<PathGateSheet> {
  PathState? _path;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    PathState? p;
    try {
      p = await widget.load();
    } catch (_) {
      // The goal still reads without the counts.
    }
    if (mounted) setState(() => _path = p);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduced = KajMotion.reduced(context);
    final feature = widget.feature;
    final tool = pathTools.where((t) => t.key == feature).firstOrNull ??
        (key: feature, icon: Icons.lock, label: 'Verrouillé');
    final p = _path;
    final steps = p == null ? const <PathStep>[] : pathGateSteps(feature, p);
    // The gate is live: a photo taken off shows here, a step reached once
    // or not.
    final share = steps.isEmpty
        ? null
        : steps.map(pathStepLiveShare).reduce((a, b) => a + b) / steps.length;
    final farm = widget.org.profile == 'farm';
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
                    child: Icon(tool.icon, size: 44, color: maraPaper),
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
            Text(context.tr(tool.label),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
                context.tr('Se débloque : {goal}',
                    {'goal': pathToolGoal(context, widget.org, feature, p)}),
                key: const Key('path-goal'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall),
            if (share != null) ...[
              const SizedBox(height: 14),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: share),
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
              const SizedBox(height: 10),
              // The steps it waits for, each ticked or counted.
              Column(
                key: const Key('path-need'),
                children: [
                  for (final s in steps)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(s.live >= s.goal ? Icons.check_circle : pathStepIcon(s.key),
                              size: 20,
                              color: s.live >= s.goal
                                  ? maraGreen
                                  : theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(pathStepTitle(context, s, farm: farm),
                                style: theme.textTheme.bodyMedium),
                          ),
                          Text(
                            s.live >= s.goal ? context.tr('Fait') : '${s.live} / ${s.goal}',
                            style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: s.live >= s.goal ? maraGreen : null),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                key: const Key('path-go'),
                style: FilledButton.styleFrom(
                    backgroundColor: maraCaramel, foregroundColor: maraDeep),
                onPressed: widget.onPath,
                icon: Icon(feature == 'second_business'
                    ? Icons.workspace_premium
                    : Icons.route),
                label: Text(feature == 'second_business'
                    ? context.tr('Voir Mara Pro')
                    : context.tr('Mon chemin')),
              ),
            ),
            if (widget.onView != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('path-view'),
                onPressed: widget.onView,
                icon: const Icon(Icons.visibility_outlined),
                label: Text(context.tr('Voir (lecture seule)')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
