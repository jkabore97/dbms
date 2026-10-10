import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/nav/router.dart' show Routes;
import '../../core/site/site.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/scroll_hint.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

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

  /// Near-black for type and the one button (the neutral kit's noir).
  static const ink = Color(0xFF0E0D0C);

  /// The page.
  static const paper = Color(0xFFFFFFFF);

  /// The warm off-white every photo sits on, and the hero band: the kit's
  /// blanc cassé.
  static const stone = Color(0xFFF4F2EE);

  /// Secondary text: prices, addresses, distances, the footer — the kit's
  /// grey, deepened to read on white.
  static const mist = Color(0xFF6B6660);

  /// Hairlines.
  static const line = Color(0xFFE6E1D8);

  /// The page never grows wider than this on a desktop screen: a grid of
  /// eight tiny photos across a monitor sells nothing.
  static const maxWidth = 1120.0;

  /// Wide enough to be a desk: a pointer to hover with, room for a drawer.
  static const deskWidth = 900.0;

  /// How many tiles across, for the width there is. Two on a phone is the
  /// widest a thumb can still read a name under; four is the most a photo
  /// stays a photo at.
  static int columnsFor(double width) =>
      width < 560 ? 2 : (width < 900 ? 3 : 4);

  /// The one colour a Kaj Pro shop may choose (068): its buttons. Dark
  /// text on a light accent, light text on a dark one, decided by the
  /// colour itself rather than trusted to the shopkeeper's eye.
  static Color onAccent(Color accent) =>
      accent.computeLuminance() > 0.5 ? ink : paper;

  static ThemeData theme(BuildContext context, {Color? accent}) {
    final base = Theme.of(context);
    final primary = accent ?? ink;
    final onPrimary = accent == null ? paper : onAccent(accent);
    final scheme = ColorScheme.light(
      primary: primary,
      onPrimary: onPrimary,
      secondary: ink,
      onSecondary: paper,
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: mist,
      surfaceContainerHighest: stone,
      outline: line,
      outlineVariant: line,
      error: const Color(0xFFB3261E),
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
          backgroundColor: primary,
          foregroundColor: onPrimary,
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
class ShopPage extends StatefulWidget {
  const ShopPage({
    super.key,
    required this.title,
    required this.body,
    this.brand,
    this.leading,
    this.trailing,
    this.floatingActionButton,
    this.bottom,
    this.overlay,
    this.accent,
    this.announcements = const [],
  });

  final String title;

  /// Drawn in the header instead of [title], which still names the page
  /// for a screen reader: the street's own front page shows Mara's mark.
  final Widget? brand;
  final Widget body;
  final Widget? leading;

  /// A Pro shop's button colour (068); null is the street's ink.
  final Color? accent;

  /// The one thing allowed at the right of the header: the account corner.
  final Widget? trailing;
  final Widget? floatingActionButton;

  /// A bar pinned under the body.
  final Widget? bottom;

  /// Floats over the foot of the body without taking room from it — the
  /// basket, while the shopper is still among the goods.
  final Widget? overlay;

  /// The thin dark strip over the header, its lines taking turns. Empty:
  /// no strip (the courier's pages, which are work, not a shop).
  final List<String> announcements;

  /// What the street says about itself, true of every shop on it.
  static const street = [
    'Retrait en boutique, ou livraison dans le quartier',
    'Des boutiques de chez vous, tenues par leurs commerçants',
    'Commandez en ligne, payez au retrait ou à la livraison',
  ];

  /// The same strip over a farm's vitrine (083).
  static const farm = [
    'Retrait à la ferme, ou livraison dans le quartier',
    'Tout droit de la ferme, sans intermédiaire',
    'Commandez à l\'avance la prochaine bande ou la récolte',
  ];

  @override
  State<ShopPage> createState() => _ShopPageState();
}

/// The header the goods sites use: white, the name in the middle, a
/// hairline under it, and it steps out of the way — scrolling down into the
/// page slides it up and off, the first movement back up brings it back.
class _ShopPageState extends State<ShopPage> {
  bool _shown = true;

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final delta = n.scrollDelta ?? 0;
    // At the very end, the header sliding away makes the page taller and
    // the list settles back by the header's height — an upward move nobody
    // made. Bringing the header back for it pushed the end (the footer)
    // off the screen again, and the « more below » arrow back on (122).
    if (n.dragDetails == null &&
        delta < 0 &&
        n.metrics.pixels >= n.metrics.maxScrollExtent - 1) {
      return false;
    }
    // Near the top the header always shows: hiding it over the hero would
    // hide the only way back.
    final atTop = n.metrics.pixels < 80;
    final next = atTop
        ? true
        : delta > 2
            ? false
            : delta < -2
                ? true
                : _shown;
    if (next != _shown) setState(() => _shown = next);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final header = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.announcements.isNotEmpty)
          ShopAnnouncement(lines: widget.announcements),
        // An AppBar sizes itself only inside a Scaffold's slot; here, in a
        // column, it is given its height: the toolbar, the hairline, and the
        // status bar when no strip above has taken it.
        SizedBox(
          height: kToolbarHeight +
              1 +
              (widget.announcements.isEmpty
                  ? MediaQuery.paddingOf(context).top
                  : 0),
          child: AppBar(
          primary: widget.announcements.isEmpty,
          leading: widget.leading,
          actions: [?widget.trailing, bellRoom],
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: widget.brand != null
              ? Semantics(
                  header: true,
                  label: widget.title,
                  child: ExcludeSemantics(child: widget.brand!),
                )
              : Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1),
                ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(),
          ),
        ),
        ),
      ],
    );
    final reduced = KajMotion.reduced(context);
    return Theme(
      data: ShopStyle.theme(context, accent: widget.accent),
      child: Scaffold(
        floatingActionButton: widget.floatingActionButton,
        bottomNavigationBar: widget.bottom,
        body: Stack(
          children: [
            Column(
          children: [
            ClipRect(
              child: AnimatedAlign(
                alignment: Alignment.bottomCenter,
                heightFactor: _shown ? 1 : 0,
                duration: reduced ? Duration.zero : KajMotion.page,
                curve: KajMotion.ease,
                child: header,
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: _onScroll,
                // « The list continues » (122), on every street page.
                child: ScrollHint(child: widget.body),
              ),
            ),
          ],
            ),
            if (widget.overlay != null)
              Positioned(
                  left: 0, right: 0, bottom: 0, child: widget.overlay!),
          ],
        ),
      ),
    );
  }
}

/// The strip over the header: one short line at a time, in small white
/// type on ink, the next fading in every few seconds. Tapping it does
/// nothing; it is a sign over the door, not a door.
class ShopAnnouncement extends StatefulWidget {
  const ShopAnnouncement({super.key, required this.lines});

  final List<String> lines;

  static const every = Duration(seconds: 5);

  @override
  State<ShopAnnouncement> createState() => _ShopAnnouncementState();
}

class _ShopAnnouncementState extends State<ShopAnnouncement> {
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.lines.length > 1) {
      _timer = Timer.periodic(ShopAnnouncement.every, (_) {
        if (mounted) setState(() => _i = (_i + 1) % widget.lines.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.lines[_i % widget.lines.length];
    return Material(
      color: maraDeep, // Mara's own ground, over every street page
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 34,
          width: double.infinity,
          child: Center(
            child: AnimatedSwitcher(
              duration: KajMotion.reduced(context)
                  ? Duration.zero
                  : KajMotion.settle,
              switchInCurve: KajMotion.ease,
              switchOutCurve: KajMotion.leave,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(0, 0.4), end: Offset.zero)
                      .animate(animation),
                  child: child,
                ),
              ),
              child: Padding(
                key: ValueKey(line),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  context.tr(line),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w500,
                    color: ShopStyle.paper,
                  ),
                ),
              ),
            ),
          ),
        ),
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
    // Every section rises as the reader reaches it.
    return ScrollReveal(
        child: Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: style)),
        if (note != null)
          Text(note!,
              style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
      ],
    ));
  }
}

/// The bottom of every street page. First the way to the rest of the street
/// (« Toutes les vitrines »), on the page itself; then the footer proper: one
/// centred band of cream, with Mara, its slogan and « Aide » (126: the
/// help page, inside the app when there is a router, the site's /aide
/// otherwise), and under it « POWERED BY KAJ », KAJ in bold.
class ShopFooter extends StatelessWidget {
  const ShopFooter({super.key, this.onDirectory, this.onBecomeCourier});

  final VoidCallback? onDirectory;

  /// The street's foot only (112): « Devenir livreur ». A vitrine's foot
  /// is the shop's, and keeps to its own way back.
  final VoidCallback? onBecomeCourier;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onDirectory != null) ...[
          const SizedBox(height: 32),
          Center(
            child: UnderlineLink(
                key: const Key('footer-directory'),
                label: context.tr('Toutes les vitrines'),
                onTap: onDirectory,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ShopStyle.ink)),
          ),
        ],
        if (onBecomeCourier != null) ...[
          const SizedBox(height: 28),
          Center(
            child: UnderlineLink(
                key: const Key('footer-become-courier'),
                label: context.tr('Devenir livreur'),
                onTap: onBecomeCourier,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ShopStyle.ink)),
          ),
        ],
        const SizedBox(height: 28),
        // Small on purpose (the owner: « Make footer smaller »): the mark
        // and the slogan on one line, the credit and the year on another.
        Container(
          key: const Key('shop-footer'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: ShopStyle.stone,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 2,
                children: [
                  const MaraWordmark(key: Key('mara-footer'), height: 22),
                  Text(context.tr('Au Service du Peuple'),
                      key: const Key('footer-slogan'),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontSize: 12, color: ShopStyle.mist)),
                  // A plain link on the slogan's line: the band stays small,
                  // at least 48 × 24 for a finger (the most the < 90 px band allows).
                  Semantics(
                    link: true,
                    child: InkWell(
                      key: const Key('footer-help'),
                      onTap: () => openHelp(context),
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 24),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Center(
                            widthFactor: 1,
                            heightFactor: 1,
                            child: Text(context.tr('Aide'),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: ShopStyle.ink,
                                    decoration: TextDecoration.underline)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // « POWERED BY KAJ », KAJ in bold, and the year.
              Semantics(
                label: context.tr('Powered by KAJ'),
                child: ExcludeSemantics(
                  child: Text.rich(
                    key: const Key('powered-by'),
                    TextSpan(
                      text: 'POWERED BY ',
                      children: [
                        const TextSpan(
                          text: 'KAJ',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: ShopStyle.ink),
                        ),
                        TextSpan(
                            text: '  ·  © ${DateTime.now().year} Mara',
                            style: const TextStyle(letterSpacing: 0.4)),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 2,
                        color: ShopStyle.mist),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// « Aide Mara »: the app's own page (/aide, the FAQ with the support
/// card), or the site's when no router is drawn.
void openHelp(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    router.push(Routes.faq);
    return;
  }
  launchUrl(Uri.parse('$siteOrigin/aide'), mode: LaunchMode.externalApplication);
}

/// A street page's scroll with the footer at the foot (122). The owner:
/// « The footer is really a footer at the bottom everywhere » — on « Mes
/// commandes » and the street, a short page left the footer floating in
/// the middle with the white under it. [children] scroll as before; the
/// [footer] comes after them when they are long, and sits on the bottom
/// edge of the page when they are short.
class ShopScroll extends StatelessWidget {
  const ShopScroll({super.key, required this.children, required this.footer});

  final List<Widget> children;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverList(delegate: SliverChildListDelegate(children)),
        SliverFillRemaining(
          hasScrollBody: false,
          fillOverscroll: false,
          // A column, not an Align: the footer is drawn at its own height
          // (its ShopWidth would otherwise centre it in the room left) and
          // pushed to the bottom edge.
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [footer],
          ),
        ),
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

/// Opens a street sheet — the basket, an article — the way the goods sites
/// do on each screen: from the bottom on a phone, where the thumb is; from
/// the right on a desk, a drawer over a dimmed page, as their cart slides in.
Future<T?> showShopSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = false,
}) {
  final desk = MediaQuery.sizeOf(context).width >= ShopStyle.deskWidth;
  if (!desk) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: showDragHandle,
      builder: builder,
    );
  }
  final reduced = KajMotion.reduced(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.tr('Fermer'),
    barrierColor: const Color(0x66000000),
    transitionDuration: reduced ? Duration.zero : KajMotion.settle,
    pageBuilder: (dialog, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: ShopStyle.paper,
        elevation: 0,
        child: SizedBox(
          width: 440,
          height: double.infinity,
          child: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: context.tr('Fermer'),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(dialog).pop(),
                  ),
                ),
                Expanded(child: Builder(builder: builder)),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, animation, _, child) {
      final eased = CurvedAnimation(
          parent: animation, curve: KajMotion.ease, reverseCurve: KajMotion.leave);
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(eased),
        child: child,
      );
    },
  );
}
