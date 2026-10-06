import 'package:flutter/material.dart';

import 'package:kaj_app/core/l10n/tr.dart';

/// « Ouvert maintenant » in green or « Fermé » in grey (093).
class OpenBadge extends StatelessWidget {
  const OpenBadge({super.key, required this.open, this.large = false});

  final bool open;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colour = open ? const Color(0xFF2E7D32) : const Color(0xFF6E6E6B);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 8,
        vertical: large ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: large ? 8 : 6,
            height: large ? 8 : 6,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          SizedBox(width: large ? 7 : 5),
          Text(
            open ? context.tr('Ouvert maintenant') : context.tr('Fermé'),
            style: TextStyle(
              fontSize: large ? 13 : 10.5,
              fontWeight: FontWeight.w700,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

/// « Pas à proximité » (094): a vitrine d'exemple, browsed but never
/// ordered from — no pin, no map, no delivery to anyone.
class FarBadge extends StatelessWidget {
  const FarBadge({super.key, this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    const colour = Color(0xFF8A5A00);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 8,
        vertical: large ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1D6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_off_outlined,
            size: large ? 15 : 12,
            color: colour,
          ),
          SizedBox(width: large ? 6 : 4),
          Text(
            context.tr('Pas à proximité'),
            style: TextStyle(
              fontSize: large ? 13 : 10.5,
              fontWeight: FontWeight.w700,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}
