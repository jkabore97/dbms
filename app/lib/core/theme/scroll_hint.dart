import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'motion.dart';

/// « There is more below » (122): a small arrow at the bottom centre of a
/// list that goes on under the edge of the screen — the owner: « an
/// animated arrow showing the list continues at the bottom … Make sure it
/// disappears when the bottom is reached. »
///
/// Wraps any part of a page or a sheet and watches the vertical scrollables
/// in it through their notifications, so one wrapper at a shared place (a
/// business's page, a street page, a sheet) serves every list drawn inside.
/// The largest of them on screen is the one the arrow speaks for — a list
/// nested in a page (a shrink-wrapped grid, a horizontal strip) never hides
/// it. The arrow sits on that list's own bottom edge, above whatever bar
/// the page keeps under it, and:
///
///  * shows while the list can scroll and its end is more than [margin]
///    below the bottom of the screen;
///  * fades out when the end is reached, and is never there when
///    everything fits;
///  * never takes a tap (IgnorePointer);
///  * speaks only for the lists of the page on top: a long page left under
///    a short one pushed above it (a business's pages share one wrapper)
///    no longer counts, and counts again once it is back on top;
///  * bounces a few times when it appears (a hint, not an alarm), and holds
///    still for someone who asked the phone for less motion.
class ScrollHint extends StatefulWidget {
  const ScrollHint({super.key, required this.child, this.margin = 24});

  final Widget child;

  /// How close to the end counts as the end.
  final double margin;

  @override
  State<ScrollHint> createState() => _ScrollHintState();
}

class _Seen {
  _Seen(this.after, this.rect, this.gap, this.route);

  /// How far the list's end is below the screen's edge.
  final double after;

  /// The list's box, in the wrapper's coordinates.
  final Rect rect;

  /// From the list's bottom edge to the wrapper's.
  final double gap;

  /// The page the list is on; null outside any route.
  final ModalRoute<Object?>? route;

  /// On the page on top of its navigator.
  bool get current => route == null || (route!.isActive && route!.isCurrent);
}

class _ScrollHintState extends State<ScrollHint> {
  final _seen = <Element, _Seen>{};
  _Seen? _shown;

  /// Where the arrow was last drawn: it fades out there, not elsewhere.
  _Seen? _last;
  bool _queued = false;

  bool _onNotification(Notification n) {
    final ScrollMetrics metrics;
    final BuildContext? from;
    if (n is ScrollNotification) {
      metrics = n.metrics;
      from = n.context;
    } else if (n is ScrollMetricsNotification) {
      metrics = n.metrics;
      from = n.context;
    } else {
      return false;
    }
    if (from is! Element || metrics.axis != Axis.vertical || !metrics.hasContentDimensions) {
      return false;
    }
    // A list under a nearer hint (a step flow's, a sheet's, inside a page
    // that has its own) is that one's: never two arrows.
    if (from.findAncestorStateOfType<_ScrollHintState>() != this) return false;
    // Sizes are not to be read while the frame is being laid out (a
    // ScrollMetricsNotification is sent from layout): measured once the
    // frame is done (UI audit B-6).
    final Element element = from;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && element.mounted) _measure(element, metrics);
      });
      return false;
    }
    _measure(from, metrics);
    return false;
  }

  void _measure(Element from, ScrollMetrics metrics) {
    final box = from.findRenderObject();
    final me = context.findRenderObject();
    if (box is! RenderBox || me is! RenderBox || !box.attached || !box.hasSize || !me.hasSize) {
      return;
    }
    final rect = box.localToGlobal(Offset.zero, ancestor: me) & box.size;
    _seen[from] = _Seen(
      metrics.maxScrollExtent <= 0 ? 0 : (metrics.maxScrollExtent - metrics.pixels).clamp(0, double.infinity).toDouble(),
      rect,
      me.size.height - rect.bottom,
      _seen[from]?.route ?? ModalRoute.of(from),
    );
    _refresh();
    _watch();
  }

  /// A page pushed over the list, or popped off it, sends no notification
  /// of its own when it has no list: while lists are known, every frame
  /// (a route's transition is frames) asks again which are on top. A
  /// post-frame callback never asks for a frame — an idle screen costs
  /// nothing.
  bool _watching = false;
  void _watch() {
    if (_watching) return;
    _watching = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _watching = false;
      if (!mounted) return;
      _apply();
      if (_seen.isNotEmpty) _watch();
    });
  }

  /// The list the arrow is for: the tallest one still on screen, on the
  /// page on top.
  _Seen? _pick() {
    _seen.removeWhere((e, _) => !e.mounted);
    _Seen? best;
    for (final s in _seen.values) {
      if (!s.current) continue;
      if (best == null || s.rect.height > best.rect.height) best = s;
    }
    if (best == null || best.after <= widget.margin) return null;
    return best;
  }

  void _refresh() {
    // A notification can arrive while the frame is being laid out: the
    // change waits for the frame's end.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      if (_queued) return;
      _queued = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _queued = false;
        if (mounted) _apply();
      });
      return;
    }
    _apply();
  }

  void _apply() {
    final next = _pick();
    final was = _shown;
    final moved = was != null && next != null && (was.rect != next.rect || was.gap != next.gap);
    if ((was == null) != (next == null) || moved) {
      setState(() {
        _shown = next;
        if (next != null) _last = next;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = KajMotion.reduced(context);
    final at = _last;
    return NotificationListener<Notification>(
      onNotification: _onNotification,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (at != null)
            Positioned(
              left: at.rect.left,
              width: at.rect.width,
              // Never inside the home indicator's band (UI audit B-5).
              bottom: (at.gap < MediaQuery.paddingOf(context).bottom
                      ? MediaQuery.paddingOf(context).bottom
                      : at.gap),
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: AnimatedSwitcher(
                    duration: reduced ? Duration.zero : const Duration(milliseconds: 220),
                    child: _shown == null
                        ? const SizedBox.shrink()
                        : _Arrow(key: const Key('scroll-hint'), still: reduced),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The hint itself, discreet (the owner: « make the arrow more discrete
/// … it seems to point to the tab »): the list fading into the page over
/// its last few pixels, and a small pale chevron in the fade — no chip, no
/// shadow, nothing that reads as a button over the bar. It drifts down a
/// little three times as it appears.
class _Arrow extends StatefulWidget {
  const _Arrow({super.key, required this.still});

  final bool still;

  @override
  State<_Arrow> createState() => _ArrowState();
}

class _ArrowState extends State<_Arrow> with SingleTickerProviderStateMixin {
  late final _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    if (!widget.still) _bounce.repeat(reverse: true, count: 6);
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ground = theme.scaffoldBackgroundColor;
    final chevron = Icon(Icons.expand_more,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55));
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ground.withValues(alpha: 0), ground.withValues(alpha: 0.85)],
        ),
      ),
      child: SizedBox(
        height: 30,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: widget.still
              ? chevron
              : AnimatedBuilder(
                  animation: _bounce,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, 3 * Curves.easeInOut.transform(_bounce.value)),
                    child: child,
                  ),
                  child: chevron,
                ),
        ),
      ),
    );
  }
}
