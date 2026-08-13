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
    required this.hero,
    required this.tints,
  });

  /// What the whole `ColorScheme` is derived from.
  final Color seed;

  /// Two or three stops for the hero card behind the day's figures. Ordered
  /// light-to-dark along the diagonal it is painted on.
  final List<Color> hero;

  /// The rotation used for tiles and small cards, so neighbours differ.
  final List<Color> tints;

  /// A tile's colour by position, wrapping. Position rather than meaning: the
  /// point is that adjacent tiles are not the same, and a tile keeps its
  /// colour as long as the row does.
  Color tint(int index) => tints[index % tints.length];
}

/// Green, and not a muted one: this is the farm.
const farmPalette = KajPalette(
  seed: Color(0xFF0E9F6E),
  hero: [Color(0xFF10B981), Color(0xFF0E7490)],
  tints: [
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF0EA5E9),
    Color(0xFF8B5CF6),
    Color(0xFFEF4444),
    Color(0xFF14B8A6),
  ],
);

/// Indigo and violet for the church: the one profile whose screens are read
/// mostly in the evening, and the one where money is counted rather than
/// produced.
const churchPalette = KajPalette(
  seed: Color(0xFF5B4BE8),
  hero: [Color(0xFF6366F1), Color(0xFF9333EA)],
  tints: [
    Color(0xFF6366F1),
    Color(0xFF14B8A6),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF0EA5E9),
    Color(0xFF8B5CF6),
  ],
);

/// Amber and warm red for the shop, which is where the day is loudest.
const retailPalette = KajPalette(
  seed: Color(0xFFEA580C),
  hero: [Color(0xFFF97316), Color(0xFFDB2777)],
  tints: [
    Color(0xFFF97316),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
  ],
);

/// Sign-in, the business picker, the platform console: everything that belongs
/// to the app rather than to one business. Teal, so it is nobody's profile.
const kajPalette = KajPalette(
  seed: Color(0xFF0D9488),
  hero: [Color(0xFF14B8A6), Color(0xFF4F46E5)],
  tints: [
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFFEC4899),
    Color(0xFF0EA5E9),
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
    appBarTheme: AppBarTheme(
      backgroundColor: palette.hero.first,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
