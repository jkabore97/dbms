import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/nav/look_only.dart';

/// A screen drawn at a phone's [width], to look at and scroll, never to
/// use: taps, long presses, a drag on a switch and the keyboard never
/// reach it; a drag or the wheel scrolls its main list (the first that
/// takes the controller given here). Below it [LookOnly] holds: nothing
/// that opens by itself may run.
class LookOnlyView extends StatefulWidget {
  const LookOnlyView({super.key, required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  State<LookOnlyView> createState() => _LookOnlyViewState();
}

class _LookOnlyViewState extends State<LookOnlyView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _by(double dy) {
    if (!_scroll.hasClients) return;
    final p = _scroll.positions.first;
    p.jumpTo((p.pixels + dy).clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final size = Size(widget.width, box.maxHeight);
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) _by(e.scrollDelta.dy);
            },
            onPointerPanZoomUpdate: (e) => _by(-e.panDelta.dy),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => _by(-d.delta.dy),
              child: AbsorbPointer(
                child: ExcludeFocus(
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: size,
                      padding: EdgeInsets.zero,
                      viewPadding: EdgeInsets.zero,
                      viewInsets: EdgeInsets.zero,
                    ),
                    child: LookOnly(
                      child: HeroMode(
                        enabled: false,
                        child: PrimaryScrollController(
                          controller: _scroll,
                          automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      });
}
