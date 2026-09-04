import 'package:flutter/material.dart';

import 'motion.dart';

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
      'church' || 'association' => churchPalette,
      'retail' => retailPalette,
      _ => kajPalette,
    };

/// The page. The look the owner asked for, by name, is the one that sells
/// goods online (allbirds.com): white paper, near-black type, a warm
/// off-white for anything that has to sit apart from the page, hairlines
/// instead of shadows, one black pill of a button. It replaced the glass
/// edition — translucent panes over a colour wash — because that read as
/// "an app" where this reads as "a shop", and the owner runs shops.
///
/// The business's colour is not gone: it is now the one accent. The
/// palette's ink paints what carries state — the floating button, a switch,
/// a focused field, the icon on a tile, the day's figure — and the pale
/// hero wash is the flat band behind the home screen's figure. Everything
/// else is paper, ink and stone, the same for every business, so a shop and
/// a farm are told apart by their accent rather than by a different page.
const kPaper = Color(0xFFFFFFFF);
const kInk = Color(0xFF1F1F1F);
const kStone = Color(0xFFF4F3EF);
const kMist = Color(0xFF6E6E6B);
const kLine = Color(0xFFE7E5E0);

/// Builds the app's `ThemeData` from a palette — the paper edition.
///
/// One thing deliberately unchanged through every restyle: the enlarged body
/// text. No amount of style is worth a smaller font on a cheap screen in
/// daylight.
ThemeData kajTheme(KajPalette palette) {
  final scheme = ColorScheme.fromSeed(seedColor: palette.seed).copyWith(
    // The accent: the business's ink, everywhere Material asks for primary.
    primary: palette.ink,
    onPrimary: kPaper,
    primaryContainer: palette.hero.first,
    onPrimaryContainer: palette.ink,
    secondary: palette.ink,
    onSecondary: kPaper,
    secondaryContainer: kStone,
    onSecondaryContainer: kInk,
    tertiary: palette.ink,
    // Paper, and stone for every container slot: twenty-eight screens tint
    // their cards with surfaceContainerHighest by hand, and re-pointing the
    // slot turns them all into quiet off-white blocks at once.
    surface: kPaper,
    onSurface: kInk,
    onSurfaceVariant: kMist,
    surfaceContainerLowest: kPaper,
    surfaceContainerLow: kStone,
    surfaceContainer: kStone,
    surfaceContainerHigh: kStone,
    surfaceContainerHighest: kStone,
    surfaceTint: Colors.transparent,
    outline: kLine,
    outlineVariant: kLine,
  );
  const pill = StadiumBorder();
  // Every hand-set text style below is derived from the base theme's own so
  // it keeps the app's font family: a bare TextStyle on a button falls back
  // to the platform's default face on the web, and a page with two typefaces
  // reads as two products.
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final label = base.textTheme.labelLarge ?? const TextStyle();
  final title = base.textTheme.titleLarge ?? const TextStyle();
  final buttonText = label.copyWith(
      fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.2);

  return base.copyWith(
    scaffoldBackgroundColor: kPaper,
    canvasColor: kPaper,
    dividerColor: kLine,

    // The motion the owner asked for by name: the goods sites answer a
    // touch with a quiet change of tone, never a spreading ripple — a
    // ripple reads as "an app", and this reads as a page. And every page,
    // on every platform, walks in the same way: a quick fade with a small
    // rise, instead of Android's slide here and the web's zoom there.
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: kInk.withValues(alpha: 0.06),
    hoverColor: kInk.withValues(alpha: 0.04),
    focusColor: kInk.withValues(alpha: 0.08),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PaperPageTransitionsBuilder(),
      TargetPlatform.iOS: PaperPageTransitionsBuilder(),
      TargetPlatform.linux: PaperPageTransitionsBuilder(),
      TargetPlatform.macOS: PaperPageTransitionsBuilder(),
      TargetPlatform.windows: PaperPageTransitionsBuilder(),
      TargetPlatform.fuchsia: PaperPageTransitionsBuilder(),
    }),

    textTheme: base.textTheme.copyWith(
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 16, color: kInk),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 18, color: kInk),
      titleLarge: title.copyWith(
          fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.4),
      displaySmall: base.textTheme.displaySmall?.copyWith(
          fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -0.8),
    ),

    // Paper, with a hairline under it. The colour that used to be here is
    // now the accent on the page instead.
    appBarTheme: AppBarTheme(
      backgroundColor: kPaper,
      foregroundColor: kInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      shape: const Border(bottom: BorderSide(color: kLine)),
      titleTextStyle: title.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: kInk,
      ),
      iconTheme: const IconThemeData(color: kInk),
    ),

    // A card is a hairline on paper: no fill to speak of, no shadow, a small
    // radius. Screens that tint their cards keep their tint.
    cardTheme: CardThemeData(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: kPaper,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: kLine),
      ),
    ),

    // The one black pill, and its outlined twin.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kInk,
        foregroundColor: kPaper,
        disabledBackgroundColor: kLine,
        disabledForegroundColor: kMist,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        side: const BorderSide(color: kInk, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.ink,
        shape: pill,
        textStyle: label.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: kInk,
        foregroundColor: kPaper,
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        textStyle: buttonText,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: kInk,
        selectedForegroundColor: kPaper,
        foregroundColor: kInk,
        side: const BorderSide(color: kLine),
      ),
    ),

    // The accent, floating: the business's ink with white on it.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      highlightElevation: 0,
      backgroundColor: palette.ink,
      foregroundColor: kPaper,
      shape: pill,
      extendedTextStyle: buttonText,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: kStone,
      selectedColor: palette.hero.first,
      shape: pill,
      side: BorderSide.none,
      labelStyle: label.copyWith(color: kInk, fontWeight: FontWeight.w500),
    ),

    // Fields are white with a hairline that turns to ink when it has focus.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kPaper,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kInk, width: 1.5),
      ),
      labelStyle: label.copyWith(color: kMist, fontWeight: FontWeight.w400),
      hintStyle: label.copyWith(color: kMist, fontWeight: FontWeight.w400),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kPaper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kPaper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: kPaper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: kLine),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kInk,
      contentTextStyle: label.copyWith(color: kPaper, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      iconColor: kInk,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kPaper,
      surfaceTintColor: Colors.transparent,
      indicatorColor: kStone,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? palette.ink : kMist)),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => label.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected) ? kInk : kMist)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: kInk,
      unselectedLabelColor: kMist,
      indicatorColor: kInk,
      dividerColor: kLine,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.ink),

    dividerTheme: const DividerThemeData(color: kLine, space: 24, thickness: 1),
  );
}

/// The ground every page stands on: paper. It stays a widget with the same
/// signature so the app shell and the profile theme need not change; what
/// it paints is a white page, because that is what the goods sit on.
class KajBackground extends StatelessWidget {
  const KajBackground({super.key, required this.palette, required this.child});

  final KajPalette palette;
  final Widget child;

  /// A page never grows wider than this on a monitor. A shop page spread
  /// across 1920 pixels is a form nobody can read in one glance; a centred
  /// column with paper either side is what every goods site does.
  static const maxWidth = 1120.0;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: kPaper,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        ),
      );
}

/// The band behind a home screen's figure: the palette's pale wash, flat.
/// Still a `LinearGradient` so the panels that paint it need not change; the
/// two stops are the same colour, which is the point — a band, not a sunset.
LinearGradient kajGradient(KajPalette palette) => LinearGradient(
      colors: [palette.hero.first, palette.hero.first],
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
