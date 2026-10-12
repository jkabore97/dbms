import 'package:flutter/material.dart';

/// An amount on one line, whole: « 1 293 500 FCFA » shrinks to fit rather
/// than breaking inside the number or the currency (UI audit R-1). The
/// number and its symbol are joined by non-breaking spaces (moneyFormat),
/// so a too-narrow column used to cut the « word » anywhere — « FCF / A ».
///
/// Give it a bounded width: inside a Row, wrap it in Flexible (or set
/// [maxWidth]); in a Column or a ListTile's title it already has one.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.text, {
    super.key,
    this.style,
    this.alignment = Alignment.centerLeft,
    this.maxWidth,
  });

  final String text;
  final TextStyle? style;
  final AlignmentGeometry alignment;

  /// A cap on the width, for a place with loose room (a ListTile's
  /// trailing) where the amount must leave the rest its share.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    Widget child = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(text, maxLines: 1, softWrap: false, style: style),
    );
    if (maxWidth != null) {
      child = ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth!), child: child);
    }
    return child;
  }
}
