import 'package:flutter/material.dart';

import '../../core/academy/academy_repository.dart';
import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/theme/mara_mark.dart';
import '../cauris/cauri_icon.dart';
import 'lesson_player.dart';

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
      appBar: AppBar(title: const Text('Académie Mara')),
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
              const Text('L\'Académie n\'est pas encore ouverte.')
            else ...[
              Container(
                key: const Key('academy-level'),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: maraIndigo,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.school, color: maraGold, size: 30),
                        const SizedBox(width: 10),
                        Text(a.level,
                            style: theme.textTheme.headlineSmall?.copyWith(
                                color: maraCream, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: a.total == 0 ? 0 : a.done / a.total,
                        minHeight: 8,
                        color: maraGold,
                        backgroundColor: maraCream.withValues(alpha: 0.2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${a.done} leçon${a.done > 1 ? 's' : ''} sur ${a.total} · '
                      'Apprenti › Commerçant › Maître',
                      style: theme.textTheme.bodySmall?.copyWith(color: maraCream),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              for (final l in a.lessons)
                KajCard(
                  key: Key('lesson-${l.key}'),
                  margin: const EdgeInsets.only(bottom: 10),
                  color: l.ready ? const Color(0xFFFFF4D6) : null,
                  child: ListTile(
                    onTap: () => _open(l),
                    leading: CircleAvatar(
                      backgroundColor: l.done ? maraGreen : maraIndigo,
                      child: Icon(
                        l.done
                            ? Icons.check
                            : l.mission
                                ? Icons.flag_outlined
                                : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(l.title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(l.ready
                        ? 'Mission réussie : touchez pour la valider'
                        : '${l.mission ? 'Mission' : 'Guide'} · ${l.minutes} min',
                        style: TextStyle(color: l.ready ? maraIndigo : kMist)),
                    trailing: l.done
                        ? null
                        : CaurisAmount(a.caurisEach,
                            style: theme.textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ],
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
      tooltip: 'Comment faire ?',
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
