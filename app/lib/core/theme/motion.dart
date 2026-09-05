import 'dart:async';

import 'package:flutter/material.dart';

/// Motion, the way the shop the owner named does it (allbirds.com): calm,
/// quick, and always the same. Nothing bounces, nothing ripples, nothing
/// waits. A page walks in with a short fade and a small rise; a tile under
/// the pointer lifts a little; content that just arrived settles up into
/// place. Three gestures, one clock, everywhere — motion that repeats is a
/// texture, motion that varies is a show.
class KajMotion {
  const KajMotion._();

  /// A hover or press answering the hand. Short enough to feel attached.
  static const quick = Duration(milliseconds: 180);

  /// A page walking in.
  static const page = Duration(milliseconds: 260);

  /// Content settling in after a load.
  static const settle = Duration(milliseconds: 380);

  /// One curve for everything that appears; its mirror for what leaves.
  static const ease = Curves.easeOutCubic;
  static const leave = Curves.easeInCubic;

  /// The stagger between neighbours in a grid, capped so the tail of a long
  /// list never keeps a reader waiting — after the first rows the settling
  /// is a texture, not a queue.
  static Duration stagger(int index) =>
      Duration(milliseconds: 45 * (index % 8));

  /// Whether the person asked their device for less motion (Android's
  /// "remove animations", the browser's prefers-reduced-motion). When they
  /// did, every gesture in this file plays at once instead of over time:
  /// the same page, arriving still.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// The page transition: a quick fade with a small rise, the same on every
/// platform — the web build is the shop's front door and Android is the
/// same shop, so the door must open the same way. It replaces the zoom and
/// slide defaults, which read as "an app" where this reads as a page
/// arriving on paper.
class PaperPageTransitionsBuilder extends PageTransitionsBuilder {
  const PaperPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget? child,
  ) {
    if (KajMotion.reduced(context)) return child ?? const SizedBox.shrink();
    final eased = CurvedAnimation(
      parent: animation,
      curve: KajMotion.ease,
      reverseCurve: KajMotion.leave,
    );
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.012),
          end: Offset.zero,
        ).animate(eased),
        child: child,
      ),
    );
  }
}

/// A tile that lifts under the pointer and settles under the finger.
///
/// On the web this is the hover the goods sites taught everyone to expect;
/// on a phone there is no pointer, so only the gentle press-down shows.
/// Wraps without changing layout: the scale pivots on the centre and the
/// few extra pixels paint over the grid gap.
class Lift extends StatefulWidget {
  const Lift({
    super.key,
    this.enabled = true,
    this.scale = 1.02,
    required this.child,
  });

  final bool enabled;
  final double scale;
  final Widget child;

  @override
  State<Lift> createState() => _LiftState();
}

class _LiftState extends State<Lift> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = !widget.enabled || KajMotion.reduced(context)
        ? 1.0
        : _pressed
            ? 0.985
            : _hovered
                ? widget.scale
                : 1.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: KajMotion.quick,
          curve: KajMotion.ease,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Content settling into place: a fade with a small rise, once, when the
/// widget first appears — never again on a rebuild, because a page that
/// re-plays its entrance on every filter tap is a page that flickers.
class Reveal extends StatefulWidget {
  const Reveal({super.key, this.delay = Duration.zero, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  bool _in = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      // Next frame, so the first build paints the hidden pose to rise from.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _in = true);
      });
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _in = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Less motion asked for: already in place, no wait, no fade.
    if (KajMotion.reduced(context)) return widget.child;
    return AnimatedOpacity(
      opacity: _in ? 1 : 0,
      duration: KajMotion.settle,
      curve: KajMotion.ease,
      // A screen reader must find the content while it is still invisible:
      // the entrance is for the eye, and the eye is not the only reader.
      alwaysIncludeSemantics: true,
      child: AnimatedSlide(
        offset: _in ? Offset.zero : const Offset(0, 0.06),
        duration: KajMotion.settle,
        curve: KajMotion.ease,
        child: widget.child,
      ),
    );
  }
}
