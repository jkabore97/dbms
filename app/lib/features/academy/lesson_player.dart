import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/academy/academy_repository.dart';
import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';
import '../cauris/cauri_icon.dart';
import 'lessons.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// One lesson of Académie Mara, played step by step (087): a drawn phone
/// showing the screen in question and a hand that travels to the button
/// and taps it, under a caption in a few words. At the end, a guide is
/// done; a mission sends the person to live it, and is collected — and
/// paid — once the business's own data says it happened.
class LessonPlayer extends StatefulWidget {
  const LessonPlayer({
    super.key,
    required this.org,
    required this.lessonKey,
    required this.title,
    required this.mission,
    required this.academy,
  });

  final OrgSummary org;
  final String lessonKey;
  final String title;
  final bool mission;
  final AcademyRepository academy;

  static Future<void> open(
    BuildContext context, {
    required OrgSummary org,
    required AcademyLesson lesson,
    required AcademyRepository academy,
  }) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => LessonPlayer(
          org: org,
          lessonKey: lesson.key,
          title: lesson.title,
          mission: lesson.mission,
          academy: academy,
        ),
      ));

  @override
  State<LessonPlayer> createState() => _LessonPlayerState();
}

class _LessonPlayerState extends State<LessonPlayer> {
  final _pages = PageController();
  int _at = 0;

  /// The steps follow one another by themselves (one every few seconds,
  /// once the hand has tapped); a tap on pause holds the current one.
  bool _auto = true;
  Timer? _next;

  void _schedule() {
    _next?.cancel();
    if (!_auto || !mounted || KajMotion.reduced(context)) return;
    if (_at >= _script.steps.length - 1) return;
    _next = Timer(const Duration(milliseconds: 4200), () {
      if (mounted && _pages.hasClients) {
        _pages.nextPage(duration: KajMotion.page, curve: KajMotion.ease);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }
  bool _busy = false;
  String? _result;

  LessonScript get _script =>
      lessonScripts[widget.lessonKey] ??
      LessonScript(steps: [
        LessonStep(Icons.school_outlined, widget.title, 'Bientôt dans l\'Académie.'),
      ]);

  @override
  void dispose() {
    _next?.cancel();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final r = await widget.academy.complete(widget.org.id, widget.lessonKey);
      if (!mounted) return;
      setState(() => _result = !r.done
          ? context.tr('Pas encore : faites-le d\'abord dans l\'application, puis revenez.')
          : r.earned > 0
              ? context.tr('Bravo ! +{earned} cauris pour votre entreprise.', {'earned': r.earned})
              : context.tr('Bravo, leçon terminée !'));
    } catch (e) {
      if (mounted) setState(() => _result = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = _script.steps;
    final last = _at == steps.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(widget.title)),
        actions: [
          IconButton(
            key: const Key('lesson-auto'),
            tooltip: _auto ? context.tr('Pause') : context.tr('Lecture'),
            icon: Icon(_auto ? Icons.pause_circle_outline : Icons.play_circle_outline),
            onPressed: () {
              setState(() => _auto = !_auto);
              _schedule();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                key: const Key('lesson-pages'),
                controller: _pages,
                itemCount: steps.length,
                onPageChanged: (i) {
                  setState(() => _at = i);
                  _schedule();
                },
                itemBuilder: (context, i) => _StepView(step: steps[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < steps.length; i++)
                  AnimatedContainer(
                    duration: KajMotion.quick,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _at ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _at ? maraIndigo : maraIndigo.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_result != null) ...[
                    Text(_result!,
                        key: const Key('lesson-result'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 10),
                  ],
                  if (!last)
                    FilledButton(
                      key: const Key('lesson-next'),
                      onPressed: () => _pages.nextPage(
                          duration: KajMotion.page, curve: KajMotion.ease),
                      child: Text(context.tr('Suivant')),
                    )
                  else ...[
                    if (widget.mission && _script.tryIt != null)
                      OutlinedButton(
                        key: const Key('lesson-try'),
                        onPressed: () {
                          final rest = _script.tryIt!;
                          context.push(rest.isEmpty
                              ? Routes.inside(widget.org.id, '').replaceAll(RegExp(r'/$'), '')
                              : Routes.inside(widget.org.id, rest));
                        },
                        child: Text(context.tr(_script.tryLabel ?? context.tr('Essayer maintenant'))),
                      ),
                    if (!widget.mission && _script.tryIt != null)
                      TextButton(
                        onPressed: () =>
                            context.push(Routes.inside(widget.org.id, _script.tryIt!)),
                        child: Text(context.tr(_script.tryLabel ?? context.tr('Y aller'))),
                      ),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      key: const Key('lesson-finish'),
                      onPressed: _busy ? null : _finish,
                      icon: const CauriIcon(size: 16, color: maraGold),
                      label: Text(widget.mission ? context.tr('C\'est fait !') : context.tr('J\'ai compris')),
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

/// The phone's screen, drawn like Mara's own: status bar, app bar, a card
/// with the step's picture, three rows, the bottom bar.
class _MockScreen extends StatelessWidget {
  const _MockScreen({required this.step, required this.w, required this.h});

  final LessonStep step;
  final double w;
  final double h;

  @override
  Widget build(BuildContext context) {
    final small = TextStyle(fontSize: w * 0.04, color: maraIndigo);
    Widget bar(double f, {Color c = const Color(0xFFE8E3D8), double t = 0.018}) => Container(
          height: h * t,
          width: w * f,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
        );
    return ColoredBox(
      color: const Color(0xFFFBF8F2),
      child: Column(
        children: [
          // Status bar.
          Padding(
            padding: EdgeInsets.fromLTRB(w * 0.06, h * 0.012, w * 0.06, h * 0.006),
            child: Row(
              children: [
                Text('9:41', style: small.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Icon(Icons.signal_cellular_alt, size: w * 0.045, color: maraIndigo),
                Icon(Icons.battery_full, size: w * 0.045, color: maraIndigo),
              ],
            ),
          ),
          // The app's bar.
          Container(
            color: maraIndigo,
            padding: EdgeInsets.symmetric(horizontal: w * 0.05, vertical: h * 0.018),
            child: Row(
              children: [
                Icon(Icons.storefront, size: w * 0.06, color: maraGold),
                SizedBox(width: w * 0.03),
                Expanded(
                  child: Text(context.tr(step.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: maraCream, fontSize: w * 0.045, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          // The card: the step's picture.
          Container(
            margin: EdgeInsets.all(w * 0.05),
            padding: EdgeInsets.all(w * 0.04),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(w * 0.04),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
            ),
            child: Row(
              children: [
                Container(
                  width: w * 0.16,
                  height: w * 0.16,
                  decoration: BoxDecoration(
                    color: maraIndigo,
                    borderRadius: BorderRadius.circular(w * 0.04),
                  ),
                  child: Icon(step.icon, size: w * 0.09, color: maraGold),
                ),
                SizedBox(width: w * 0.04),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(0.4, c: maraIndigo.withValues(alpha: 0.7)),
                      SizedBox(height: h * 0.01),
                      bar(0.28),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Three rows of a list.
          for (final f in const [0.42, 0.34, 0.38])
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.06, vertical: h * 0.011),
              child: Row(
                children: [
                  CircleAvatar(radius: w * 0.04, backgroundColor: const Color(0xFFE8E3D8)),
                  SizedBox(width: w * 0.04),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [bar(f), SizedBox(height: h * 0.006), bar(f * 0.6, t: 0.012)],
                    ),
                  ),
                  bar(0.12, c: maraGold.withValues(alpha: 0.6)),
                ],
              ),
            ),
          const Spacer(),
          // The bar at the foot.
          Container(
            padding: EdgeInsets.symmetric(vertical: h * 0.014),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE8E3D8))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final i in const [Icons.home, Icons.inventory_2_outlined, Icons.shopping_bag_outlined, Icons.menu])
                  Icon(i, size: w * 0.07, color: maraIndigo.withValues(alpha: i == Icons.home ? 1 : 0.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One step: the drawn phone, the travelling hand, the caption.
class _StepView extends StatelessWidget {
  const _StepView({required this.step});

  final LessonStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          Expanded(child: Center(child: _Phone(step: step))),
          const SizedBox(height: 18),
          Text(context.tr(step.title),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(context.tr(step.text),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _Phone extends StatefulWidget {
  const _Phone({required this.step});

  final LessonStep step;

  @override
  State<_Phone> createState() => _PhoneState();
}

class _PhoneState extends State<_Phone> with SingleTickerProviderStateMixin {
  late final _loop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (KajMotion.reduced(context)) {
      _loop.value = 0.75;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.step.point;
    return AspectRatio(
      aspectRatio: 0.52,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // The phone.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: maraIndigo,
                  borderRadius: BorderRadius.circular(w * 0.12),
                ),
                child: Padding(
                  padding: EdgeInsets.all(w * 0.05),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(w * 0.08),
                    ),
                    // A real screen, drawn: the status bar, the app's bar
                    // with the page's name, a card, three rows, the bar at
                    // the foot — the hand then taps where it would.
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(w * 0.08),
                      child: _MockScreen(step: widget.step, w: w, h: h),
                    ),
                  ),
                ),
              ),
            ),
            // The button the hand is going to, drawn in the app's words.
            if (point != null && widget.step.target != null)
              Positioned(
                left: w * point.dx,
                top: h * point.dy,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: Container(
                    key: const Key('lesson-target'),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: maraGold,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [
                        BoxShadow(
                            color: maraGold.withValues(alpha: 0.45),
                            blurRadius: 14,
                            spreadRadius: 2),
                      ],
                    ),
                    child: Text(context.tr(widget.step.target!),
                        style: const TextStyle(
                            color: maraIndigo, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            // The hand, travelling in from below and tapping.
            if (point != null)
              AnimatedBuilder(
                animation: _loop,
                builder: (context, _) {
                  final t = _loop.value;
                  final travel = Curves.easeOutCubic.transform((t / 0.55).clamp(0, 1));
                  final tap = t > 0.6 && t < 0.8 ? 1 - ((t - 0.7).abs() / 0.1) : 0.0;
                  final x = w * point.dx;
                  final y = h * (1.15 + (point.dy - 1.15) * travel);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: x - 22 * (1 + tap),
                        top: h * point.dy - 22 * (1 + tap),
                        child: Opacity(
                          opacity: tap.clamp(0, 1) * 0.6,
                          child: Container(
                            width: 44 * (1 + tap),
                            height: 44 * (1 + tap),
                            decoration: const BoxDecoration(
                                color: maraGold, shape: BoxShape.circle),
                          ),
                        ),
                      ),
                      Positioned(
                        left: x + 6,
                        top: y + 8,
                        child: Transform.scale(
                          scale: 1 - 0.12 * tap,
                          child: const Icon(Icons.touch_app,
                              key: Key('lesson-hand'),
                              size: 46,
                              color: maraTerracotta),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        );
      }),
    );
  }
}
