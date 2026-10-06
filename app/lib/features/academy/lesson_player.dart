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
  bool _busy = false;
  String? _result;

  LessonScript get _script =>
      lessonScripts[widget.lessonKey] ??
      LessonScript(steps: [
        LessonStep(Icons.school_outlined, widget.title, 'Bientôt dans l\'Académie.'),
      ]);

  @override
  void dispose() {
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
          ? 'Pas encore : faites-le d\'abord dans l\'application, puis revenez.'
          : r.earned > 0
              ? 'Bravo ! +${r.earned} cauris pour votre entreprise.'
              : 'Bravo, leçon terminée !');
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
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                key: const Key('lesson-pages'),
                controller: _pages,
                itemCount: steps.length,
                onPageChanged: (i) => setState(() => _at = i),
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
                      child: const Text('Suivant'),
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
                        child: Text(_script.tryLabel ?? 'Essayer maintenant'),
                      ),
                    if (!widget.mission && _script.tryIt != null)
                      TextButton(
                        onPressed: () =>
                            context.push(Routes.inside(widget.org.id, _script.tryIt!)),
                        child: Text(_script.tryLabel ?? 'Y aller'),
                      ),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      key: const Key('lesson-finish'),
                      onPressed: _busy ? null : _finish,
                      icon: const CauriIcon(size: 16, color: maraGold),
                      label: Text(widget.mission ? 'C\'est fait !' : 'J\'ai compris'),
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
          Text(step.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(step.text,
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
                    child: Column(
                      children: [
                        SizedBox(height: h * 0.06),
                        // A screen sketched in a few bars.
                        for (final f in const [0.7, 0.5, 0.6])
                          Container(
                            margin: EdgeInsets.symmetric(
                                horizontal: w * 0.1, vertical: h * 0.012),
                            height: h * 0.022,
                            width: w * f,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8E3D8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        const Spacer(),
                        Icon(widget.step.icon, size: w * 0.36, color: maraIndigo),
                        const Spacer(),
                        Container(
                          margin: EdgeInsets.all(w * 0.06),
                          height: h * 0.07,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F2EA),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ],
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
                    child: Text(widget.step.target!,
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
