import 'package:flutter/material.dart';

/// The two glass panes analytics reuses: a small number on a card, and a titled
/// section that wraps a chart or a list. Kept here so the owner and platform
/// screens look like one feature rather than two.

/// One headline number. [emphasis] tints it for the figure that matters most on
/// the screen (revenue), so the eye lands there first.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? hint;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = _cardWidth(context);
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: emphasis
            ? scheme.primaryContainer.withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: emphasis ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
          if (hint != null)
            Text(
              hint!,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  // Two per row on a phone, more on a wide screen — sized so the Wrap breaks
  // cleanly rather than leaving a lonely third card half off the edge.
  double _cardWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width - 32; // page padding
    final perRow = w > 640 ? 3 : 2;
    return (w - 12 * (perRow - 1)) / perRow;
  }
}

/// A titled glass section. Everything below a heading — a chart, a ranked list
/// — sits in one of these.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
