import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:kaj_app/core/l10n/tr.dart';

/// [n] as the badge says it in [language] ('fr' or 'en'): grouped in the
/// reader's way (« 1 234 » / « 1,234 »), and short from 10 000 on
/// (« 12,3 k » / « 12.3k »; « 1,2 M » / « 1.2M » from a million).
String visitorCount(int n, String language) {
  final locale = intlLocale(language);
  if (n < 10000) return NumberFormat.decimalPattern(locale).format(n);
  final mega = n >= 999950;
  final short = NumberFormat('#,##0.#', locale).format(n / (mega ? 1e6 : 1e3));
  final unit = mega ? 'M' : 'k';
  return language == 'en' ? '$short$unit' : '$short $unit';
}

/// The vitrine's unique visitors (123): an eye and the number, under the
/// shop's name, in the vitrine's own colour — for everyone who opens it,
/// signed out or in, the owner's preview too. Its label says it whole
/// (« 1 234 visiteurs »), for a long press, a mouse and a screen reader.
class VisitorsBadge extends StatelessWidget {
  const VisitorsBadge({super.key, required this.count, required this.colour});

  /// From 1 up: the page draws no badge at 0.
  final int count;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final language = context.trLanguage;
    final label = count == 1
        ? context.tr('1 visiteur')
        : context.tr('{n} visiteurs', {
            'n': NumberFormat.decimalPattern(intlLocale(language)).format(count),
          });
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        label: label,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_outlined, size: 15, color: colour),
              const SizedBox(width: 5),
              Text(
                visitorCount(count, language),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colour,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
