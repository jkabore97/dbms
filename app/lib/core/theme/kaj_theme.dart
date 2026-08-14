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
    required this.seed,
    required this.ink,
    required this.hero,
    required this.tints,
  });

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

/// The palette for an org profile. Falls through to the app's own for a
/// profile this build has never heard of — the same tolerance `homeScreenFor`
/// shows, and for the same reason: a profile added server-side must not be
/// able to break an APK already in somebody's hand.
KajPalette paletteFor(String? profile) => switch (profile) {
      'farm' => farmPalette,
      'church' => churchPalette,
      'retail' => retailPalette,
      _ => kajPalette,
    };

/// Builds the app's `ThemeData` from a palette.
ThemeData kajTheme(KajPalette palette) {
  final scheme = ColorScheme.fromSeed(seedColor: palette.seed);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,

    // Larger default text: many users are reading on cheap phones in poor
    // light, sometimes without reading glasses. This predates the colour and
    // survives it.
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 16),
      bodyLarge: TextStyle(fontSize: 18),
    ),

    // The app bar carries the business's colour, which is the cheapest way to
    // say which business is open without spending a line of the screen on it.
    // A pale wash with the palette's ink on it rather than a saturated block
    // with white — the same reversal as the hero card, and for the same
    // measured reason.
    appBarTheme: AppBarTheme(
      backgroundColor: palette.hero.first,
      foregroundColor: palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: palette.ink,
      ),
      iconTheme: IconThemeData(color: palette.ink),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),

    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide.none,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),

    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 24),
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

/// Wraps [child] in a profile's colours: both the `ThemeData` every Material
/// widget reads, and the palette the hand-painted parts read.
class ProfileTheme extends StatelessWidget {
  const ProfileTheme({super.key, required this.profile, required this.child});

  final String? profile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = paletteFor(profile);
    return KajTheme(
      palette: palette,
      child: Theme(data: kajTheme(palette), child: child),
    );
  }
}
