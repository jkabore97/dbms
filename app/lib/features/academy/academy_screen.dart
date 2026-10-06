import 'package:flutter/material.dart';

import '../../core/academy/academy_repository.dart';
import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/theme/mara_mark.dart';
import '../cauris/cauri_icon.dart';
import 'lesson_player.dart';
import 'lessons.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// « Académie Mara » (087): the level this person climbed to, and the
/// lessons of the business's kind — guides to watch, missions to live —
/// each saying what it pays, the done ones ticked, the lived missions
/// glowing, ready to collect.
class AcademyScreen extends StatefulWidget {
  const AcademyScreen({super.key, required this.org, required this.academy});

  final OrgSummary org;
  final AcademyRepository academy;

  @override
  State<AcademyScreen> createState() => _AcademyScreenState();
}

class _AcademyScreenState extends State<AcademyScreen> {
  Academy? _a;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await widget.academy.mine(widget.org.id);
      if (!mounted) return;
      setState(() {
        _a = a;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _open(AcademyLesson l) async {
    await LessonPlayer.open(context,
        org: widget.org, lesson: l, academy: widget.academy);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = _a;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Académie Mara'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (a == null)
              Text(context.tr('L\'Académie n\'est pas encore ouverte.'))
            else ...[
              _LevelHeader(academy: a),
              const SizedBox(height: 18),
              GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.92,
                children: [
                  for (final l in a.lessons)
                    _LessonTile(
                      key: Key('lesson-${l.key}'),
                      lesson: l,
                      cauris: a.caurisEach,
                      onTap: () => _open(l),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The level as three medals, the reached ones gold, and a bar.
class _LevelHeader extends StatelessWidget {
  const _LevelHeader({required this.academy});

  final Academy academy;

  static const _levels = [
    ('Apprenti', Icons.school),
    ('Commerçant', Icons.storefront),
    ('Maître', Icons.workspace_premium),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = academy;
    final at = _levels.indexWhere((l) => l.$1 == a.level).clamp(0, 2);
    return Container(
      key: const Key('academy-level'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: maraIndigo,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < _levels.length; i++)
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: i == at ? 64 : 48,
                        height: i == at ? 64 : 48,
                        decoration: BoxDecoration(
                          color: i <= at ? maraGold : maraCream.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_levels[i].$2,
                            size: i == at ? 34 : 24,
                            color: i <= at ? maraIndigo : maraCream.withValues(alpha: 0.5)),
                      ),
                      const SizedBox(height: 6),
                      Text(context.tr(_levels[i].$1),
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: maraCream,
                              fontWeight: i == at ? FontWeight.w800 : FontWeight.w500)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: a.total == 0 ? 0 : a.done / a.total,
              minHeight: 8,
              color: maraGold,
              backgroundColor: maraCream.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 6),
          Text(context.tr('{done} / {total}', {'done': a.done, 'total': a.total}),
              style: theme.textTheme.labelLarge?.copyWith(color: maraCream)),
        ],
      ),
    );
  }
}

/// One lesson as a picture: its first step's image, its name, its state.
class _LessonTile extends StatelessWidget {
  const _LessonTile({super.key, required this.lesson, required this.cauris, required this.onTap});

  final AcademyLesson lesson;
  final int cauris;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = lesson;
    final icon = lessonScripts[l.key]?.steps.first.icon ?? Icons.school_outlined;
    return Material(
      color: l.ready
          ? const Color(0xFFFFF4D6)
          : l.done
              ? maraGreen.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: l.done ? maraGreen : maraIndigo,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(l.done ? Icons.check : icon,
                        color: l.done ? Colors.white : maraGold, size: 28),
                  ),
                  const Spacer(),
                  Icon(
                    l.mission ? Icons.flag : Icons.play_circle_fill,
                    size: 20,
                    color: l.ready ? maraTerracotta : maraIndigo.withValues(alpha: 0.4),
                  ),
                ],
              ),
              const Spacer(),
              Text(context.tr(l.title),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(l.ready ? context.tr('Réussie !') : context.tr('{minutes} min', {'minutes': l.minutes}),
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: l.ready ? maraTerracotta : kMist,
                          fontWeight: l.ready ? FontWeight.w800 : null)),
                  const Spacer(),
                  if (!l.done) CaurisAmount(cauris, style: theme.textTheme.labelLarge),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The « ? » on a screen: opens that screen's lesson (087). Drawn only
/// inside the app's scope (absent from bare test trees).
class LessonHelpButton extends StatelessWidget {
  const LessonHelpButton({
    super.key,
    required this.org,
    required this.lessonKey,
    required this.title,
    this.mission = true,
  });

  final OrgSummary org;
  final String lessonKey;
  final String title;
  final bool mission;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return IconButton(
      key: Key('help-$lessonKey'),
      tooltip: context.tr('Comment faire ?'),
      icon: const Icon(Icons.help_outline),
      onPressed: () => LessonPlayer.open(
        context,
        org: org,
        lesson: AcademyLesson(
            key: lessonKey,
            title: title,
            mission: mission,
            minutes: 1,
            done: false,
            ready: false),
        academy: AcademyRepository(scope.auth.client),
      ),
    );
  }
}
