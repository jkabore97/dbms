import 'package:flutter/material.dart';

/// What the app looks like, and why it looks like more than one thing.
///
/// Until now there was a single `ColorScheme.fromSeed` on one muted green, and
/// every screen in every business was the same quiet grey-green: the church,
/// the farm and the shop were indistinguishable at a glance, and the only
/// colour on a home screen was whatever an icon happened to bring with it.
/// That reads as unfinished, and it wastes the one signal that costs nothing —
/// somebody who runs two businesses should know which one is open before they
/// have read a word.
///
/// So colour carries meaning here rather than decorating:
///
///   * **Each profile has its own palette.** Green grows, indigo is the
///     church, amber is the shop. The org's `profile` column picks it — the
///     same rule that picks the home screen, so the two can never disagree.
///   * **The hero card is a gradient in that palette**, which is what makes a
///     screen look alive rather than printed.
///   * **The tiles under it are individually tinted** instead of six identical
///     grey rectangles, so they are told apart by shape *and* colour. On a
///     cheap screen in daylight that is the difference between finding the
///     right one and reading all six.
///
/// One thing deliberately unchanged: the enlarged body text. Many people here
/// are reading on small, cheap screens in poor light, sometimes without
/// reading glasses, and no amount of colour is worth a smaller font.
class KajPalette {
  const KajPalette({
    required this.name,
    required this.label,
    required this.seed,
    required this.ink,
    required this.hero,
    required this.tints,
  });

  /// The stable identifier stored in `orgs.theme`. Never translated and never
  /// renamed: a business that chose `ocean` two years ago must still get ocean
  /// after this file has been rewritten twice.
  final String name;

  /// What the person choosing it reads. French, like the rest of the app.
  final String label;

  /// What the whole `ColorScheme` is derived from.
  final Color seed;

  /// The deep tone of this palette: what is *written* in it. Text on the hero
  /// card, icons on their tinted chips, the business name on an invoice.
  ///
  /// It exists because the first version of this theme painted saturated
  /// gradients and put white text on them, and measurement said white failed
  /// on the light end of every single one — 2.49:1 on the farm, 2.80 on the
  /// shop, against a 4.5 minimum. Four of the six tile colours were equally
  /// unreadable under a white icon.
  ///
  /// The fix is not a darker gradient, which would be the opposite of what
  /// was asked for. It is to turn the relationship around: the surfaces go
  /// pale and the *ink* carries the colour. Every pairing below is measured
  /// at 4.6:1 or better.
  final Color ink;

  /// Two pale stops for the hero card behind the day's figures, ordered along
  /// the diagonal they are painted on. Tints, not fills — [ink] is what has to
  /// be legible on them.
  final List<Color> hero;

  /// The rotation used for tiles and small cards, so neighbours differ. These
  /// are deep tones: a tile paints its chip as this colour at low opacity and
  /// draws the icon in the colour itself.
  final List<Color> tints;

  /// A tile's colour by position, wrapping. Position rather than meaning: the
  /// point is that adjacent tiles are not the same, and a tile keeps its
  /// colour as long as the row does.
  Color tint(int index) => tints[index % tints.length];
}

/// Green for the farm: a pale mint and sky wash, with deep emerald ink.
const farmPalette = KajPalette(
  name: 'verdure',
  label: 'Verdure',
  seed: Color(0xFF0E7A63),
  ink: Color(0xFF0B6B57),
  hero: [Color(0xFFDCF2E9), Color(0xFFCCE7F0)],
  tints: [
    Color(0xFF0E7A63),
    Color(0xFFA96A0B),
    Color(0xFF0A6E9E),
    Color(0xFF6D45C4),
    Color(0xFFB03B3B),
    Color(0xFF0D7A72),
  ],
);

/// Indigo and violet for the church: the one profile read mostly in the
/// evening, and the one where money is counted rather than produced.
const churchPalette = KajPalette(
  name: 'indigo',
  label: 'Indigo',
  seed: Color(0xFF4338CA),
  ink: Color(0xFF4338CA),
  hero: [Color(0xFFE6E3FB), Color(0xFFF0DEFA)],
  tints: [
    Color(0xFF4F46B8),
    Color(0xFF0D7A72),
    Color(0xFFA96A0B),
    Color(0xFFB63A73),
    Color(0xFF0A6E9E),
    Color(0xFF6D45C4),
  ],
);

/// Warm apricot and rose for the shop, which is where the day is busiest.
const retailPalette = KajPalette(
  name: 'terre',
  label: 'Terre cuite',
  seed: Color(0xFF9A3412),
  ink: Color(0xFF9A3412),
  hero: [Color(0xFFFCEBDB), Color(0xFFFBDFE8)],
  tints: [
    Color(0xFFB1541A),
    Color(0xFF0A6E9E),
    Color(0xFF0E7A63),
    Color(0xFF6D45C4),
    Color(0xFFB63A73),
    Color(0xFFA96A0B),
  ],
);

/// Sign-in, the business picker, the platform console: everything that belongs
/// to the app rather than to one business. Teal, so it is nobody's profile.
const kajPalette = KajPalette(
  name: 'lagune',
  label: 'Lagune',
  seed: Color(0xFF0B5F58),
  ink: Color(0xFF0B5F58),
  hero: [Color(0xFFDCF0EE), Color(0xFFE4E1FB)],
  tints: [
    Color(0xFF0D7A72),
    Color(0xFF4F46B8),
    Color(0xFFA96A0B),
    Color(0xFF0E7A63),
    Color(0xFFB63A73),
    Color(0xFF0A6E9E),
  ],
);

// ---------------------------------------------------------------------------
// The palettes that exist only because somebody chose them
// ---------------------------------------------------------------------------
// The four above are the profile defaults: a farm is green because it is a
// farm. These four are not tied to any profile — they exist so a business can
// look like itself rather than like its category. A tailor's shop and a
// hardware shop are both `retail` and have no reason to be the same colour.
//
// Every one of them is measured against the same bar as the defaults, by the
// same tests, over `allPalettes` below. That list is the point: a palette
// added here is contrast-checked automatically, so nobody can add a pretty
// one that cannot be read.

/// Deep sea blue. The most neutral of the choices, and the one that reads
/// best in the sun — blue ink on a pale blue wash keeps its edge outdoors.
const oceanPalette = KajPalette(
  name: 'ocean',
  label: 'Océan',
  seed: Color(0xFF0B5A8A),
  ink: Color(0xFF0B5A8A),
  hero: [Color(0xFFDCEBF7), Color(0xFFDDE6F7)],
  tints: [
    Color(0xFF0A6E9E),
    Color(0xFF0D7A72),
    Color(0xFF6D45C4),
    Color(0xFFA96A0B),
    Color(0xFFB63A73),
    Color(0xFF0E7A63),
  ],
);

/// Plum and lilac. The deepest ink of the set, at 8.8:1 on white.
const prunePalette = KajPalette(
  name: 'prune',
  label: 'Prune',
  seed: Color(0xFF7B2D5E),
  ink: Color(0xFF7B2D5E),
  hero: [Color(0xFFF7E3EE), Color(0xFFEDE1F7)],
  tints: [
    Color(0xFFB63A73),
    Color(0xFF6D45C4),
    Color(0xFF0A6E9E),
    Color(0xFF0D7A72),
    Color(0xFFA96A0B),
    Color(0xFFB03B3B),
  ],
);

/// Sand and ochre — the warmest, and the closest to the light here.
const savanePalette = KajPalette(
  name: 'savane',
  label: 'Savane',
  seed: Color(0xFF8A5A0B),
  ink: Color(0xFF8A5A0B),
  hero: [Color(0xFFFAEEDA), Color(0xFFF6E7D2)],
  tints: [
    Color(0xFFA96A0B),
    Color(0xFF0E7A63),
    Color(0xFF0A6E9E),
    Color(0xFFB03B3B),
    Color(0xFF6D45C4),
    Color(0xFF0D7A72),
  ],
);

/// Slate. For the business that wants the app to be quiet — the only choice
/// here with no hue to speak of, and deliberately so.
const ardoisePalette = KajPalette(
  name: 'ardoise',
  label: 'Ardoise',
  seed: Color(0xFF44506B),
  ink: Color(0xFF44506B),
  hero: [Color(0xFFE7EAF0), Color(0xFFE2E7EE)],
  tints: [
    Color(0xFF44506B),
    Color(0xFF0A6E9E),
    Color(0xFF0D7A72),
    Color(0xFFA96A0B),
    Color(0xFF6D45C4),
    Color(0xFFB03B3B),
  ],
);

/// Every palette this build knows, in the order they are offered.
///
/// The profile defaults come first because they are what the business already
/// looks like; the rest follow. Tests iterate this rather than a hand-kept
/// list, so adding a palette here is what subjects it to the contrast bar.
const allPalettes = <KajPalette>[
  farmPalette,
  churchPalette,
  retailPalette,
  kajPalette,
  oceanPalette,
  prunePalette,
  savanePalette,
  ardoisePalette,
];

/// The palette a business chose, by its stored name.
///
/// Returns null rather than a default for a name this build has never heard
/// of, so the caller can fall back to the profile's own colour. That case is
/// not hypothetical: a palette added server-side, or an APK three versions
/// old, must not leave somebody staring at a screen with no colour at all.
KajPalette? paletteNamed(String? name) {
  if (name == null || name.isEmpty) return null;
  for (final palette in allPalettes) {
    if (palette.name == name) return palette;
  }
  return null;
}

/// The palette for a business: what it chose, or what its profile implies.
///
/// [theme] wins when it names a palette this build knows. Otherwise the
/// profile decides, exactly as it did before anyone could choose — and an
/// unknown profile still falls through to the app's own, the same tolerance
/// `homeScreenFor` shows, for the same reason: neither a profile nor a palette
/// added server-side may break an APK already in somebody's hand.
KajPalette paletteFor(String? profile, {String? theme}) =>
    paletteNamed(theme) ??
    switch (profile) {
      'farm' => farmPalette,
      'church' => churchPalette,
      'retail' => retailPalette,
      _ => kajPalette,
    };

/// The frost. One number rather than many: the app bar, the cards and the
/// inputs all take their translucency from here, and the render tests assert
/// against the same constants — so "the glass got cloudier" is a deliberate
/// edit in one place, never a drift.
///
/// Everything glassy here is translucency over the soft [KajBackground]
/// wash, deliberately without `BackdropFilter` blur: real blur is the most
/// expensive pixel on a cheap phone, and the frosted read comes from the
/// layering, not the blur.
const double kGlassAppBarAlpha = 0.62;
const double kGlassCardAlpha = 0.66;
const double kGlassFieldAlpha = 0.55;

/// Builds the app's `ThemeData` from a palette — the glass edition.
///
/// The geometry is soft (large radii, hairline light borders, no hard
/// elevation), the surfaces are translucent, and the page behind them is the
/// palette's own wash painted by [KajBackground]. Every business keeps its
/// colour; the glass is how the colour is worn.
///
/// One thing deliberately unchanged through every restyle: the enlarged body
/// text. No amount of style is worth a smaller font on a cheap screen in
/// daylight.
ThemeData kajTheme(KajPalette palette) {
  final scheme = ColorScheme.fromSeed(seedColor: palette.seed);
  final hairline = Colors.white.withValues(alpha: 0.65);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,

    // Transparent on purpose: the page's ground is the palette wash painted
    // by KajBackground behind the Navigator, which is what lets every
    // translucent surface above it read as glass instead of as grey.
    scaffoldBackgroundColor: Colors.transparent,

    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 16),
      bodyLarge: TextStyle(fontSize: 18),
    ),

    // The app bar still carries the business's colour — frosted now: the
    // hero tint at kGlassAppBarAlpha over the wash, with the palette's ink
    // on it. The ink was measured against the solid tint; over the lighter
    // blend the contrast only improves.
    appBarTheme: AppBarTheme(
      backgroundColor: palette.hero.first.withValues(alpha: kGlassAppBarAlpha),
      foregroundColor: palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: palette.ink,
      ),
      iconTheme: IconThemeData(color: palette.ink),
    ),

    // A pane of glass: translucent white, a hairline of light along its
    // edge, and a large radius. Screens that tint their cards keep their
    // tint and inherit the shape.
    cardTheme: CardThemeData(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: Colors.white.withValues(alpha: kGlassCardAlpha),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: hairline),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide.none,
    ),

    // Fields are shallow pools: translucent white with a soft edge that
    // sharpens to the palette's primary when focused.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: kGlassFieldAlpha),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide:
            BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),

    // Sheets and dialogs float above content someone was just reading, so
    // they stay near-opaque — frosted at the edge of legibility is a trick
    // played on the reader, not a style.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.white.withValues(alpha: 0.97),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white.withValues(alpha: 0.97),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),

    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 24,
    ),
  );
}

/// The ground every page stands on: the palette's wash, lit by two soft
/// colour glows drifting in from the corners — the "aurora" that makes the
/// glass above it read as glass.
///
/// Painted once behind the Navigator (and again, in the business's own
/// palette, by [ProfileTheme]), it is entirely static: gradients, no blur,
/// no animation — the futurism has to run on a cheap phone in a market.
class KajBackground extends StatelessWidget {
  const KajBackground({super.key, required this.palette, required this.child});

  final KajPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // StackFit.expand, not loose: a Stack whose children are all Positioned
    // otherwise sizes itself to nothing, and a zero-sized Navigator is a
    // blank page — caught by screenshot, kept here as a warning.
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(palette.hero.first, Colors.white, 0.45)!,
                  Colors.white,
                  Color.lerp(palette.hero.last, Colors.white, 0.35)!,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -140,
          right: -100,
          child: _glow(palette.tint(0).withValues(alpha: 0.13), 340),
        ),
        Positioned(
          bottom: -160,
          left: -120,
          child: _glow(palette.tint(2).withValues(alpha: 0.11), 380),
        ),
        Positioned.fill(child: child),
      ],
    );
  }

  Widget _glow(Color colour, double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [colour, colour.withValues(alpha: 0)],
            ),
          ),
        ),
      );
}

/// The gradient behind a hero card or an app bar, painted along the diagonal
/// so the two stops are both visible on a wide, short box.
LinearGradient kajGradient(KajPalette palette) => LinearGradient(
      colors: palette.hero,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

/// Makes the palette reachable from any widget under the profile's theme,
/// without threading it through every constructor.
///
/// The theme itself cannot carry it: `ColorScheme` has no room for a gradient
/// or a tint rotation, and deriving them back out of the scheme would mean
/// each screen guessing at what the palette had been.
class KajTheme extends InheritedWidget {
  const KajTheme({
    super.key,
    required this.palette,
    required super.child,
  });

  final KajPalette palette;

  /// The palette in scope, or the app's own outside a business. Never null, so
  /// no caller has to hold an opinion about what to do without one.
  static KajPalette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KajTheme>()?.palette ??
      kajPalette;

  @override
  bool updateShouldNotify(KajTheme oldWidget) => oldWidget.palette != palette;
}

/// Wraps [child] in a business's colours: both the `ThemeData` every Material
/// widget reads, and the palette the hand-painted parts read.
class ProfileTheme extends StatelessWidget {
  const ProfileTheme({
    super.key,
    required this.profile,
    this.theme,
    required this.child,
  });

  final String? profile;

  /// The palette the business chose, if it chose one. Null means "whatever
  /// the profile implies", which is what every business had before this
  /// setting existed and what a business that never touches it keeps.
  final String? theme;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = paletteFor(profile, theme: theme);
    return KajTheme(
      palette: palette,
      child: Theme(
        data: kajTheme(palette),
        // The business's own wash behind its transparent Scaffold — this is
        // what repaints the whole page, not just the widgets, in its colours.
        child: KajBackground(palette: palette, child: child),
      ),
    );
  }
}
