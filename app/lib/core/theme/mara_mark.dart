import 'package:flutter/material.dart';

/// Mara's marks (the brand files in `assets/brand/`). Wherever the app
/// shows its own name — the sign-in, the splash, the code screen — it is
/// one of these, never a stand-in icon. Kaj, who makes Mara, signs the
/// street's footer (« POWERED BY KAJ »).
///
/// The palette they are drawn in — the neutral kit (docs/brand/mara-neutre):
/// no red, no blue, and not all brown. Graphite [maraDeep] for the grounds
/// (splash, setup, the street's announcement bar, the path), caramel
/// [maraCaramel] and brown [maraBrown] for what shines on them, off-white
/// [maraPaper] behind, near-black [maraBlack] for type. Dark brown
/// [maraEspresso] stays for a touch, never a whole ground.
const maraBlack = Color(0xFF0E0D0C);
const maraPaper = Color(0xFFF4F2EE);
const maraDeep = Color(0xFF3B3A38);
const maraEspresso = Color(0xFF4A3122);
const maraBrown = Color(0xFF8B5A3C);
const maraCaramel = Color(0xFFC49A6C);
const maraGrey = Color(0xFFA3A09B);
const maraGraphite = Color(0xFF3B3A38);

/// The one colour the kit has no word for: « done », « open ». A muted
/// green that sits with the browns.
const maraGreen = Color(0xFF3F7A52);

/// The seal alone: the M under its caramel point, the ring of rays, MMXXVI.
class MaraMark extends StatelessWidget {
  const MaraMark({super.key, this.size = 56});

  final double size;

  static const asset = 'assets/brand/mara_seal.webp';

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

/// The seal and « mara » side by side. [onDark] picks the off-white
/// wordmark for a brown or black ground.
class MaraWordmark extends StatelessWidget {
  const MaraWordmark({super.key, this.height = 64, this.onDark = false});

  final double height;
  final bool onDark;

  static const asset = 'assets/brand/mara_horizontal.webp';
  static const assetDark = 'assets/brand/mara_horizontal_dark.webp';

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

/// The seal above « mara », off-white on dark brown: the splash.
class MaraStacked extends StatelessWidget {
  const MaraStacked({super.key, this.height = 200});

  final double height;

  static const asset = 'assets/brand/mara_stacked.webp';

  @override
  Widget build(BuildContext context) => Image.asset(
        asset,
        height: height,
        fit: BoxFit.contain,
        semanticLabel: 'Mara',
        filterQuality: FilterQuality.medium,
      );
}
