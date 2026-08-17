import 'package:flutter/material.dart';

/// The charts, hand-drawn.
///
/// No charting package: the app's look is a bespoke glass wash and a library's
/// default axes would fight it, so a bar and a line are a few dozen lines of
/// CustomPainter each — self-contained, themeable, and with nothing to fetch at
/// build time. Both take already-computed values; neither knows what a sale is.

/// A row of bars with a label under each. Used for hours of the day and days of
/// the week — anything with a small fixed set of labelled buckets.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    required this.labels,
    this.height = 160,
    this.highlightMax = true,
  });

  /// One value per bar; all non-negative. Empty draws nothing.
  final List<double> values;

  /// One short label per bar, same length as [values].
  final List<String> labels;

  final double height;

  /// Paints the tallest bar in the accent colour so the peak reads at a glance.
  final bool highlightMax;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _BarPainter(
          values: values,
          labels: labels,
          bar: scheme.primary,
          peak: scheme.tertiary,
          ink: scheme.onSurfaceVariant,
          highlightMax: highlightMax,
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.labels,
    required this.bar,
    required this.peak,
    required this.ink,
    required this.highlightMax,
  });

  final List<double> values;
  final List<String> labels;
  final Color bar;
  final Color peak;
  final Color ink;
  final bool highlightMax;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const labelH = 18.0;
    final chartH = size.height - labelH;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final maxIndex = values.indexOf(maxV);
    final n = values.length;
    // Gaps scale with count so 24 hours stay legible and 7 days stay chunky.
    final gap = n > 12 ? 2.0 : 6.0;
    final barW = (size.width - gap * (n - 1)) / n;

    for (var i = 0; i < n; i++) {
      final v = values[i];
      final h = maxV == 0 ? 0.0 : (v / maxV) * (chartH - 6);
      final x = i * (barW + gap);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, chartH - h, barW, h),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      final paint = Paint()
        ..color = (highlightMax && i == maxIndex) ? peak : bar.withValues(alpha: 0.75);
      canvas.drawRRect(rect, paint);

      if (i < labels.length) {
        _label(canvas, labels[i], x + barW / 2, size.height - labelH + 2, barW);
      }
    }
  }

  void _label(Canvas canvas, String text, double cx, double top, double maxW) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: ink, fontSize: 10),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '',
    )..layout(maxWidth: maxW + 8);
    tp.paint(canvas, Offset(cx - tp.width / 2, top));
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values || old.labels != labels;
}

/// A single revenue line over time. Points are already ordered; the painter
/// scales them into the box and fills softly beneath.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.values,
    this.height = 160,
  });

  /// One value per point, in order. One or zero points draws nothing.
  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _LinePainter(
          values: values,
          line: scheme.primary,
          fill: scheme.primary.withValues(alpha: 0.14),
          dot: scheme.tertiary,
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.line,
    required this.fill,
    required this.dot,
  });

  final List<double> values;
  final Color line;
  final Color fill;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    const pad = 8.0;
    final w = size.width;
    final h = size.height - pad * 2;
    final n = values.length;

    Offset at(int i) {
      final x = n == 1 ? 0.0 : (i / (n - 1)) * w;
      final y = pad + (h - ((values[i] - minV) / span) * h);
      return Offset(x, y);
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }

    // Soft fill under the line.
    final area = Path.from(path)
      ..lineTo(w, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // The final point, dotted, so "where it stands now" is obvious.
    final last = at(n - 1);
    canvas.drawCircle(last, 4, Paint()..color = dot);
    canvas.drawCircle(last, 4, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values;
}
