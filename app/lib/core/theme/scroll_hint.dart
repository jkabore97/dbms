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
  _Seen(this.after, this.rect, this.gap);

  /// How far the list's end is below the screen's edge.
  final double after;

  /// The list's box, in the wrapper's coordinates.
  final Rect rect;

  /// From the list's bottom edge to the wrapper's.
  final double gap;
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
    final box = from.findRenderObject();
    final me = context.findRenderObject();
    if (box is! RenderBox || me is! RenderBox || !box.attached || !box.hasSize || !me.hasSize) {
      return false;
    }
    final rect = box.localToGlobal(Offset.zero, ancestor: me) & box.size;
    _seen[from] = _Seen(
      metrics.maxScrollExtent <= 0 ? 0 : (metrics.maxScrollExtent - metrics.pixels).clamp(0, double.infinity).toDouble(),
      rect,
      me.size.height - rect.bottom,
    );
    _refresh();
    return false;
  }

  /// The list the arrow is for: the tallest one still on screen.
  _Seen? _pick() {
    _seen.removeWhere((e, _) => !e.mounted);
    _Seen? best;
    for (final s in _seen.values) {
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
              bottom: at.gap + 10,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: AnimatedSwitcher(
                    duration: reduced ? Duration.zero : const Duration(milliseconds: 220),
                    child: _shown == null
                        ? const SizedBox.shrink()
                        : Center(child: _Arrow(key: const Key('scroll-hint'), still: reduced)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The arrow itself: a small round chip with a double chevron, bouncing
/// three times as it appears.
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
    final scheme = Theme.of(context).colorScheme;
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.94),
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.keyboard_double_arrow_down, size: 22, color: scheme.onSurface),
      ),
    );
    if (widget.still) return chip;
    return AnimatedBuilder(
      animation: _bounce,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 6 * Curves.easeInOut.transform(_bounce.value)),
        child: child,
      ),
      child: chip,
    );
  }
}
