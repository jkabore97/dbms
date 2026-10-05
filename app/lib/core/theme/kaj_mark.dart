import 'package:flutter/material.dart';

/// The KAJ mark: KAJ Consulting's K (kaj-consulting.com), the owner's
/// official logo. Wherever the app shows who made it — the sign-in, the
/// splash, the code screen — this is the picture, never a stand-in icon.
///
/// The full logo with « KAJ CONSULTING LLC » under it is
/// `assets/brand/kaj_logo.png`, used by the street footer.
class KajMark extends StatelessWidget {
  const KajMark({super.key, this.size = 56});

  final double size;

  static const asset = 'assets/brand/kaj_mark.png';

  @override
  Widget build(BuildContext context) => Image.asset(
        asset,
        height: size,
        // The mark is a little taller than wide; the height decides.
        fit: BoxFit.contain,
        semanticLabel: 'KAJ',
        filterQuality: FilterQuality.medium,
      );
}
