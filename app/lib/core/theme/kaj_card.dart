import 'package:flutter/material.dart';

import 'motion.dart';

/// A [Card] that rises into place as it scrolls into view — the goods
/// sites' way with every block on a page (ScrollReveal), carried into the
/// business side so that a list of sales, a dashboard or a settings page
/// arrives the same way the street does.
///
/// Every parameter is [Card]'s own, passed straight through: swapping one
/// for the other changes the entrance and nothing else. Under « less
/// motion », or with no scrolling ancestor beyond the first frame, it is
/// simply a Card.
class KajCard extends StatelessWidget {
  const KajCard({
    super.key,
    this.color,
    this.shadowColor,
    this.surfaceTintColor,
    this.elevation,
    this.shape,
    this.borderOnForeground = true,
    this.margin,
    this.clipBehavior,
    this.child,
    this.semanticContainer = true,
  });

  final Color? color;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final double? elevation;
  final ShapeBorder? shape;
  final bool borderOnForeground;
  final EdgeInsetsGeometry? margin;
  final Clip? clipBehavior;
  final Widget? child;
  final bool semanticContainer;

  @override
  Widget build(BuildContext context) => ScrollReveal(
        child: Card(
          color: color,
          shadowColor: shadowColor,
          surfaceTintColor: surfaceTintColor,
          elevation: elevation,
          shape: shape,
          borderOnForeground: borderOnForeground,
          margin: margin,
          clipBehavior: clipBehavior,
          semanticContainer: semanticContainer,
          child: child,
        ),
      );
}
