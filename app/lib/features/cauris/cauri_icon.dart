import 'package:flutter/material.dart';

import '../../core/theme/mara_mark.dart';

/// A cowrie shell — the cauri, West Africa's old money and Mara's points —
/// drawn rather than borrowed from an icon font, which has none: an oval
/// shell, its slit, and the small teeth either side.
class CauriIcon extends StatelessWidget {
  const CauriIcon({super.key, this.size = 20, this.color = maraCaramel});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'cauris',
        child: CustomPaint(
          size: Size(size * 0.78, size),
          painter: _CauriPainter(color),
        ),
      );
}

class _CauriPainter extends CustomPainter {
  _CauriPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final shell = Paint()..color = color;
    canvas.drawOval(Rect.fromLTWH(0, 0, w, h), shell);
    // A soft light on the back of the shell.
    canvas.drawOval(
      Rect.fromLTWH(w * 0.14, h * 0.08, w * 0.34, h * 0.42),
      Paint()..color = Colors.white.withValues(alpha: 0.28),
    );
    final dark = Paint()
      ..color = const Color(0xFF5A3A08)
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // The slit, slightly curved, top to bottom.
    final slit = Path()
      ..moveTo(w * 0.5, h * 0.16)
      ..quadraticBezierTo(w * 0.42, h * 0.5, w * 0.5, h * 0.84);
    canvas.drawPath(slit, dark);
    // The teeth either side of it.
    final tooth = Paint()
      ..color = const Color(0xFF5A3A08)
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final y = h * (0.28 + i * 0.11);
      canvas.drawLine(Offset(w * 0.33, y), Offset(w * 0.42, y), tooth);
      canvas.drawLine(Offset(w * 0.55, y), Offset(w * 0.64, y), tooth);
    }
  }

  @override
  bool shouldRepaint(_CauriPainter old) => old.color != color;
}

/// « 260 » next to a cauri: how a price or a balance in cauris reads.
class CaurisAmount extends StatelessWidget {
  const CaurisAmount(this.amount, {super.key, this.style, this.iconSize});

  final int amount;
  final TextStyle? style;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final s = style ?? DefaultTextStyle.of(context).style;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CauriIcon(size: iconSize ?? (s.fontSize ?? 14) * 1.05),
        const SizedBox(width: 4),
        Text('$amount', style: s),
      ],
    );
  }
}
