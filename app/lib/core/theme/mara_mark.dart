import 'package:flutter/material.dart';

/// Mara's marks (the brand files in `assets/brand/`). Wherever the app
/// shows its own name — the sign-in, the splash, the code screen — it is
/// one of these, never a stand-in icon. Kaj, who makes Mara, signs the
/// street's footer (« POWERED BY KAJ » over `kaj_k.png`).
///
/// The palette they are drawn in: indigo [maraIndigo] for the grounds,
/// terracotta, gold and green for the seal's accents, warm paper behind.
const maraIndigo = Color(0xFF1E2560);
const maraTerracotta = Color(0xFFD9572B);
const maraGold = Color(0xFFF2B63D);
const maraGreen = Color(0xFF1C8A5B);
const maraCream = Color(0xFFF3EEE4);

/// The seal alone: the M under its gold point, the ring of rays, MMXXVI.
class MaraMark extends StatelessWidget {
  const MaraMark({super.key, this.size = 56});

  final double size;

  static const asset = 'assets/brand/mara_seal.png';

  @override
  Widget build(BuildContext context) => Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: 'Mara',
        filterQuality: FilterQuality.medium,
      );
}

/// The seal and « mara » side by side. [onDark] picks the cream wordmark
/// for an indigo or black ground.
class MaraWordmark extends StatelessWidget {
  const MaraWordmark({super.key, this.height = 64, this.onDark = false});

  final double height;
  final bool onDark;

  static const asset = 'assets/brand/mara_horizontal.png';
  static const assetDark = 'assets/brand/mara_horizontal_dark.png';

  @override
  Widget build(BuildContext context) => Image.asset(
        onDark ? assetDark : asset,
        height: height,
        // The file is 3:1; the height decides.
        fit: BoxFit.contain,
        semanticLabel: 'Mara',
        filterQuality: FilterQuality.medium,
      );
}

/// The seal above « mara », cream on indigo: the splash.
class MaraStacked extends StatelessWidget {
  const MaraStacked({super.key, this.height = 200});

  final double height;

  static const asset = 'assets/brand/mara_stacked_indigo.png';

  @override
  Widget build(BuildContext context) => Image.asset(
        asset,
        height: height,
        fit: BoxFit.contain,
        semanticLabel: 'Mara',
        filterQuality: FilterQuality.medium,
      );
}
