import 'package:flutter/material.dart';

/// How the street side looks — the vitrine and the directory — and why it
/// does not look like the rest of the app.
///
/// Inside the app a shopkeeper is *working*: colour carries meaning, tiles
/// are tinted, the hero card is a gradient, because someone running two
/// businesses must know which one is open before reading a word. A shopper
/// on the street is doing something else: looking at goods. The pattern that
/// sells goods online has been settled for a decade (the reference the owner
/// named is allbirds.com): a white page, black type, one accent, big photos
/// on a warm off-white square, the name and the price in small quiet text
/// underneath, and a single black pill of a button. Nothing competes with the
/// photograph, because the photograph is the product.
///
/// So the public screens wrap themselves in [ShopStyle.theme] and draw with
/// the handful of pieces below. Nothing here reaches the business side.
class ShopStyle {
  ShopStyle._();

  /// Near-black for type and the one button. Pure black looks printed.
  static const ink = Color(0xFF1F1F1F);

  /// The page.
  static const paper = Color(0xFFFFFFFF);

  /// The warm off-white every photo sits on, and the hero band.
  static const stone = Color(0xFFF4F3EF);

  /// Secondary text: prices, addresses, distances, the footer.
  static const mist = Color(0xFF6E6E6B);

  /// Hairlines.
  static const line = Color(0xFFE7E5E0);

  /// The page never grows wider than this on a desktop screen: a grid of
  /// eight tiny photos across a monitor sells nothing.
  static const maxWidth = 1120.0;

  /// How many tiles across, for the width there is. Two on a phone is the
  /// widest a thumb can still read a name under; four is the most a photo
  /// stays a photo at.
  static int columnsFor(double width) =>
      width < 560 ? 2 : (width < 900 ? 3 : 4);

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    const scheme = ColorScheme.light(
      primary: ink,
      onPrimary: paper,
      secondary: ink,
      onSecondary: paper,
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: mist,
      surfaceContainerHighest: stone,
      outline: line,
      outlineVariant: line,
      error: Color(0xFFB3261E),
      onError: paper,
    );
    final text = base.textTheme.apply(bodyColor: ink, displayColor: ink);
    // Built from the app's label style rather than a bare TextStyle so the
    // buttons keep the app's font family instead of falling back.
    final button = (text.labelLarge ?? const TextStyle()).copyWith(
        fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2);
    final link = (text.labelLarge ?? const TextStyle()).copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      canvasColor: paper,
      dividerColor: line,
      textTheme: text,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: paper,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          textStyle: button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: ink, width: 1.2),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          textStyle: button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          textStyle: link,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: ink),
      snackBarTheme: base.snackBarTheme,
    );
  }
}

/// A street-side page: the quiet header, the theme, and the body centred to
/// [ShopStyle.maxWidth]. The header is a name and, at most, one way back.
class ShopPage extends StatelessWidget {
  const ShopPage({
    super.key,
    required this.title,
    required this.body,
    this.leading,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final Widget? leading;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ShopStyle.theme(context),
      child: Scaffold(
        appBar: AppBar(
          leading: leading,
          automaticallyImplyLeading: false,
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 1.1),
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(),
          ),
        ),
        floatingActionButton: floatingActionButton,
        body: body,
      ),
    );
  }
}

/// Keeps a block inside [ShopStyle.maxWidth] with the page margin.
class ShopWidth extends StatelessWidget {
  const ShopWidth({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ShopStyle.maxWidth),
        child: Padding(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 20),
          child: child,
        ),
      ),
    );
  }
}

/// The small letter-spaced caption above a block ("LES ARTICLES"), with an
/// optional quiet note on the right ("12 articles").
class ShopSectionLabel extends StatelessWidget {
  const ShopSectionLabel(this.text, {super.key, this.note});

  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6,
      color: ShopStyle.ink,
    );
    return Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: style)),
        if (note != null)
          Text(note!,
              style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
      ],
    );
  }
}

/// The bottom of every street page: who built it and the way to the rest.
class ShopFooter extends StatelessWidget {
  const ShopFooter({super.key, this.onDirectory});

  final VoidCallback? onDirectory;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 48),
        const Divider(),
        const SizedBox(height: 28),
        const Text('KAJ',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
                color: ShopStyle.ink)),
        const SizedBox(height: 8),
        const Text('Des vitrines de quartier, tenues par les boutiques.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: ShopStyle.mist)),
        if (onDirectory != null) ...[
          const SizedBox(height: 6),
          TextButton(
              onPressed: onDirectory,
              child: const Text('Toutes les vitrines')),
        ],
        const SizedBox(height: 36),
      ],
    );
  }
}

/// A page that has nothing to show yet, or could not: one line, one action.
class ShopNotice extends StatelessWidget {
  const ShopNotice({super.key, required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, color: ShopStyle.ink)),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
