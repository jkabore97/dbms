import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/help/help_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/look_only.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';
import 'help_sheet.dart';
import 'help_words.dart';

/// « Besoin d'aide » (batch 136) on the top bar of every home — the shop's,
/// the farm's and the association's — where the mockup draws it, after the
/// business's name:
///
///   * a Pro business's member: the caramel « Besoin d'aide » — the sheet
///     (subject, a few words, a photo, how to be helped) or, with a request
///     on, its status;
///   * a free business (or a database without 133): « Aide » — the guides,
///     the FAQ, Mara's WhatsApp and e-mail (126), « Réponse sous 48 h »;
///   * a trainer in a business they help (an observer): « Demandes », the
///     inbox, with how many wait;
///   * a platform admin in someone's business, or an observer who is no
///     trainer: nothing (the button is the business's own people's).
///
/// The first frame guesses from the cached plan (Pro or not) and never
/// waits; help_state() corrects it — on a phone with no signal the guess
/// stays. Compte › Aide stays where it was.
class HelpButton extends StatefulWidget {
  const HelpButton({super.key, required this.org, this.help, this.screen});

  final OrgSummary org;

  /// The server; the app's own unless a test gives one.
  final HelpRepository? help;

  /// The home's place (« Vente », « Accueil »), sent with a request so the
  /// trainer knows where the person was.
  final String? screen;

  /// What each business said last, for the next home's first frame.
  static final _known = <String, HelpState>{};
  static final _inbox = <String, HelpInbox>{};

  /// A request made, closed or changed: every button asks again.
  static final changed = ValueNotifier<int>(0);

  @visibleForTesting
  static void reset() {
    _known.clear();
    _inbox.clear();
  }

  /// Below this width the Pro label goes on two lines (« Besoin / d'aide »).
  static const narrowWidth = 400.0;

  /// Below this width — measured in the text's own size, the width divided
  /// by the phone's text scale — the button is its icon alone, its words in
  /// the tooltip and for a screen reader (review of 136: at 320 px with
  /// large text the pill left the business's name a few letters, cut inside
  /// a word — « Group / eme… »). 320 px at normal size keeps its words.
  static const wordsWidth = 300.0;

  static bool iconOnly(BuildContext context) =>
      MediaQuery.sizeOf(context).width /
          MediaQuery.textScalerOf(context).scale(1) <
      wordsWidth;

  /// Whether the button takes room on a phone's bar here (136): a home
  /// then says its own extras briefly (the pending writes' number alone,
  /// its words in the tooltip), as it does beside Mara's « Admin » pill,
  /// so the bar never overflows and keeps the business's name.
  static bool crowds(BuildContext context) =>
      MediaQuery.sizeOf(context).width < narrowWidth &&
      !(AppScope.maybeOf(context)?.session.isPlatformAdmin ?? false);

  @override
  State<HelpButton> createState() => _HelpButtonState();
}

class _HelpButtonState extends State<HelpButton> {
  HelpRepository? _repo;
  HelpState? _state;
  HelpInbox? _inbox;

  bool get _observer => widget.org.isObserverOnly;

  /// A platform admin in a business: my_orgs() gives them the
  /// platform_admin role there, never a membership — the help is the
  /// business's own people's, and their bar is crowded already (the
  /// « Admin » pill, the pending chip).
  bool get _platformOnly =>
      (widget.org.roles.isNotEmpty &&
          widget.org.roles.every((r) => r == 'platform_admin')) ||
      (AppScope.maybeOf(context)?.session.isPlatformAdmin ?? false);

  @override
  void initState() {
    super.initState();
    _state = HelpButton._known[widget.org.id];
    _inbox = HelpButton._inbox[widget.org.id];
    HelpButton.changed.addListener(_reload);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo =
          widget.help ?? HelpRepository(AppScope.maybeOf(context)?.auth.client);
      unawaited(_reload());
    }
  }

  @override
  void didUpdateWidget(HelpButton old) {
    super.didUpdateWidget(old);
    if (old.org.id != widget.org.id) {
      _state = HelpButton._known[widget.org.id];
      _inbox = HelpButton._inbox[widget.org.id];
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    HelpButton.changed.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final repo = _repo;
    if (repo == null || !repo.isConfigured || _platformOnly) return;
    try {
      if (_observer) {
        final inbox = await repo.inbox();
        HelpButton._inbox[widget.org.id] = inbox;
        if (mounted) setState(() => _inbox = inbox);
      } else {
        final s = await repo.state(widget.org.id);
        HelpButton._known[widget.org.id] = s;
        if (mounted) setState(() => _state = s);
      }
    } catch (_) {
      // No signal: the guess stands.
    }
  }

  Future<void> _tap() async {
    final org = widget.org;
    if (_observer) {
      await context.push(Routes.trainerInbox);
      return _reload();
    }
    final s = _state;
    final pro = s == null ? org.isPro : s.trainers;
    if (pro && s != null && s.request == null) {
      final sent = await showHelpSheet(
        context,
        org: org,
        state: s,
        help: _repo!,
        screen: widget.screen,
      );
      if (!mounted) return;
      if (sent != null) {
        HelpButton.changed.value++;
        await context.push(Routes.inside(org.id, 'aide'));
      }
    } else {
      await context.push(Routes.inside(org.id, 'aide'));
    }
    if (mounted) unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    if (_platformOnly && !LookOnly.of(context)) return const SizedBox.shrink();
    if (_observer) {
      final inbox = _inbox;
      if (inbox == null || !inbox.trainer) return const SizedBox.shrink();
      return _TrainerPill(waiting: inbox.waiting, onTap: _tap);
    }
    final s = _state;
    if (s != null && !s.available) return const SizedBox.shrink();
    final pro = s == null ? widget.org.isPro : s.trainers;
    return pro
        ? _ProPill(onTap: _tap, active: s?.request != null)
        : _FreePill(onTap: _tap);
  }
}

/// The Pro button: caramel, the lifebuoy, « Besoin d'aide » — on two lines
/// on a phone, so the business's name keeps its room.
class _ProPill extends StatelessWidget {
  const _ProPill({required this.onTap, this.active = false});

  final VoidCallback onTap;

  /// A request is on: a dot says so.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < HelpButton.narrowWidth;
    final label = context.tr('Besoin d\'aide');
    final words = label.split(' ');
    // « Besoin d'aide » → « Besoin / d'aide »; « Need help » → « Need / help ».
    final twoLines = narrow && words.length >= 2
        ? '${words.first}\n${words.sublist(1).join(' ')}'
        : label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: Material(
            key: const Key('help-pro-button'),
            color: maraCaramel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: narrow ? 9 : 12,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(
                            Icons.support,
                            size: 18,
                            color: helpCaramelInk,
                          ),
                          if (active)
                            Positioned(
                              right: -3,
                              top: -3,
                              child: Container(
                                key: const Key('help-pro-active'),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: helpGreen,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: maraCaramel,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (!HelpButton.iconOnly(context)) ...[
                        const SizedBox(width: 6),
                        ExcludeSemantics(
                          child: MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.15,
                            child: Text(
                              twoLines,
                              maxLines: 2,
                              style: TextStyle(
                                color: helpCaramelInk,
                                fontWeight: FontWeight.w800,
                                fontSize: narrow ? 12.5 : 14,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The basic button: « Aide », outlined, never taken for a Pro one.
class _FreePill extends StatelessWidget {
  const _FreePill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: context.tr('Aide'),
        child: Material(
          key: const Key('help-free-button'),
          color: Colors.transparent,
          shape: StadiumBorder(
            side: BorderSide(color: ink.withValues(alpha: 0.45)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.help_outline, size: 18, color: ink),
                    if (!HelpButton.iconOnly(context)) ...[
                      const SizedBox(width: 5),
                      MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.15,
                        child: Text(
                          context.tr('Aide'),
                          style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A trainer in a business they help: their inbox, with what waits.
class _TrainerPill extends StatelessWidget {
  const _TrainerPill({required this.waiting, required this.onTap});

  final int waiting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = context.tr('Demandes d\'aide');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        key: const Key('help-trainer-button'),
        tooltip: label,
        onPressed: onTap,
        icon: Badge(
          isLabelVisible: waiting > 0,
          label: Text('$waiting'),
          child: const Icon(Icons.support_agent_outlined),
        ),
      ),
    );
  }
}
