import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import 'shop_style.dart';

/// The vitrine's item page (136, batch 141): what a customer reads and sees
/// before ordering — the photos to swipe, open full screen and pinch, the
/// shop's words with « Lire la suite », and the basket's button pinned at
/// the foot so it is always under the thumb. The sheet that holds them is
/// storefront_screen.dart's ArticleSheet; these are its parts, for a shop's
/// article, a farm's item and an association's article or service alike.

/// Draws one photo by its key, filling (cover) or whole (contain).
typedef ItemPhotoBuilder = Widget Function(BuildContext context, String key, BoxFit fit);

/// A mouse (and a trackpad) drags the photos too: on the website a PageView
/// otherwise moves only under a finger.
Widget _anyPointer(BuildContext context, Widget child) => ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      }),
      child: child,
    );

/// « ‹ » and « › » over the photos on the website, where there is no swipe
/// under a mouse's wheel: the previous and the next photo.
class _Arrows extends StatelessWidget {
  const _Arrows({required this.pages, required this.at, required this.count, this.prefix = 'item-carousel'});

  final PageController pages;
  final int at;
  final int count;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    Widget arrow(bool next) => IconButton.filled(
          key: Key('$prefix-${next ? 'next' : 'previous'}'),
          style: IconButton.styleFrom(
              backgroundColor: const Color(0x99000000), foregroundColor: Colors.white),
          tooltip: next ? context.tr('Photo suivante') : context.tr('Photo précédente'),
          icon: Icon(next ? Icons.chevron_right : Icons.chevron_left),
          onPressed: () => next
              ? pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
              : pages.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          if (at > 0) arrow(false),
          const Spacer(),
          if (at < count - 1) arrow(true),
        ],
      ),
    );
  }

  /// Shown on the website only (a phone swipes); [force] for a test.
  static bool shown({bool force = false}) => kIsWeb || force;
}

/// The photos at the top of the page. One photo is drawn exactly as the
/// page always drew it (a tap opens it full screen); several swipe, with
/// dots under them and « 2 / 3 ».
class ItemCarousel extends StatefulWidget {
  const ItemCarousel({
    super.key,
    required this.photos,
    required this.photo,
    required this.name,
  });

  final List<String> photos;
  final ItemPhotoBuilder photo;
  final String name;

  /// Draws the website's arrows in a test (they show on the web only).
  @visibleForTesting
  static bool debugArrows = false;

  @override
  State<ItemCarousel> createState() => _ItemCarouselState();
}

class _ItemCarouselState extends State<ItemCarousel> {
  final _pages = PageController();
  int _at = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _open(int i) => FullScreenPhotos.open(context,
      photos: widget.photos, initial: i, photo: widget.photo, name: widget.name);

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    if (photos.length <= 1) {
      return GestureDetector(
        key: const Key('item-carousel-single'),
        behavior: HitTestBehavior.opaque,
        onTap: photos.isEmpty ? null : () => _open(0),
        child: photos.isEmpty
            ? const SizedBox.shrink()
            : widget.photo(context, photos.first, BoxFit.cover),
      );
    }
    return Stack(
      key: const Key('item-carousel'),
      fit: StackFit.expand,
      children: [
        _anyPointer(context, PageView.builder(
          key: const Key('item-carousel-pages'),
          controller: _pages,
          itemCount: photos.length,
          onPageChanged: (i) => setState(() => _at = i),
          itemBuilder: (context, i) => Semantics(
            image: true,
            label: context.tr('Photo {n} sur {count}', {'n': i + 1, 'count': photos.length}),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _open(i),
              child: widget.photo(context, photos[i], BoxFit.cover),
            ),
          ),
        )),
        if (_Arrows.shown(force: ItemCarousel.debugArrows))
          Align(
            alignment: Alignment.center,
            child: _Arrows(pages: _pages, at: _at, count: photos.length),
          ),
        Positioned(
          right: 10,
          top: 10,
          child: Container(
            key: const Key('item-carousel-count'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ShopStyle.ink.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('${_at + 1} / ${photos.length}',
                style: const TextStyle(color: ShopStyle.paper, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: Dots(count: photos.length, at: _at, onLight: false),
        ),
      ],
    );
  }
}

/// « • • • »: where the photos are, the current one wide.
class Dots extends StatelessWidget {
  const Dots({super.key, required this.count, required this.at, this.onLight = true});

  final int count;
  final int at;

  /// On paper (ink dots) or on a photo (paper dots, a shadow).
  final bool onLight;

  @override
  Widget build(BuildContext context) {
    final on = onLight ? ShopStyle.ink : ShopStyle.paper;
    return ExcludeSemantics(
      child: Row(
        key: const Key('item-carousel-dots'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == at ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == at ? on : on.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
                boxShadow: onLight
                    ? null
                    : const [BoxShadow(color: Color(0x55000000), blurRadius: 4)],
              ),
            ),
        ],
      ),
    );
  }
}

/// The photos full screen, on black: swipe, pinch to zoom (up to 4×),
/// a double tap to zoom in and out, « Fermer ».
class FullScreenPhotos extends StatefulWidget {
  const FullScreenPhotos({
    super.key,
    required this.photos,
    required this.initial,
    required this.photo,
    required this.name,
  });

  final List<String> photos;
  final int initial;
  final ItemPhotoBuilder photo;
  final String name;

  static Future<void> open(
    BuildContext context, {
    required List<String> photos,
    required int initial,
    required ItemPhotoBuilder photo,
    required String name,
  }) =>
      Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
        opaque: true,
        barrierColor: const Color(0xFF000000),
        pageBuilder: (_, _, _) =>
            FullScreenPhotos(photos: photos, initial: initial, photo: photo, name: name),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ));

  @override
  State<FullScreenPhotos> createState() => _FullScreenPhotosState();
}

class _FullScreenPhotosState extends State<FullScreenPhotos> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _at = widget.initial;
  final _zoom = <int, TransformationController>{};
  bool _zoomed = false;

  TransformationController _of(int i) => _zoom.putIfAbsent(i, TransformationController.new);

  @override
  void dispose() {
    _pages.dispose();
    for (final z in _zoom.values) {
      z.dispose();
    }
    super.dispose();
  }

  void _doubleTap(int i, TapDownDetails? at) {
    final z = _of(i);
    if (z.value.getMaxScaleOnAxis() > 1.01) {
      z.value = Matrix4.identity();
      setState(() => _zoomed = false);
      return;
    }
    final p = at?.localPosition ?? Offset.zero;
    // Scaled 2.5× about the tapped spot: it stays under the finger.
    z.value = Matrix4.identity()
      ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
      ..scaleByDouble(2.5, 2.5, 1, 1);
    setState(() => _zoomed = true);
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    TapDownDetails? down;
    return Scaffold(
      key: const Key('item-fullscreen'),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _anyPointer(context, PageView.builder(
            controller: _pages,
            // Zoomed in, a drag moves the photo, not to the next one.
            physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
            itemCount: photos.length,
            onPageChanged: (i) => setState(() {
              _at = i;
              _zoomed = false;
            }),
            itemBuilder: (context, i) => GestureDetector(
              onDoubleTapDown: (d) => down = d,
              onDoubleTap: () => _doubleTap(i, down),
              child: InteractiveViewer(
                key: ValueKey('item-zoom-$i'),
                transformationController: _of(i),
                minScale: 1,
                maxScale: 4,
                onInteractionEnd: (_) =>
                    setState(() => _zoomed = _of(i).value.getMaxScaleOnAxis() > 1.01),
                child: SizedBox.expand(
                  child: Semantics(
                    image: true,
                    label: context.tr('Photo de {name}', {'name': widget.name}),
                    child: widget.photo(context, photos[i], BoxFit.contain),
                  ),
                ),
              ),
            ),
          )),
          if (photos.length > 1 && !_zoomed && _Arrows.shown(force: ItemCarousel.debugArrows))
            Align(
              alignment: Alignment.center,
              child: _Arrows(pages: _pages, at: _at, count: photos.length, prefix: 'item-fullscreen'),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton.filled(
                  key: const Key('item-fullscreen-close'),
                  style: IconButton.styleFrom(
                      backgroundColor: const Color(0x99000000), foregroundColor: Colors.white),
                  tooltip: context.tr('Fermer'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          if (photos.length > 1)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Dots(count: photos.length, at: _at, onLight: false),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The shop's words as written (line breaks kept), cut after [maxLines]
/// with « Lire la suite », and « Réduire » once read.
class ItemDescription extends StatefulWidget {
  const ItemDescription({super.key, required this.text, this.maxLines = 6});

  final String text;
  final int maxLines;

  @override
  State<ItemDescription> createState() => _ItemDescriptionState();
}

class _ItemDescriptionState extends State<ItemDescription> {
  bool _open = false;

  static const _style = TextStyle(fontSize: 15, height: 1.45, color: ShopStyle.ink);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final painter = TextPainter(
        // Measured in the font it is drawn in (the inherited one, merged).
        text: TextSpan(text: widget.text, style: DefaultTextStyle.of(context).style.merge(_style)),
        maxLines: widget.maxLines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: box.maxWidth);
      final long = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            key: const Key('item-description'),
            style: _style,
            maxLines: _open || !long ? null : widget.maxLines,
            overflow: _open || !long ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
          if (long)
            TextButton(
              key: const Key('item-read-more'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 40),
                foregroundColor: ShopStyle.ink,
                // The vitrine's own font, bolder and underlined.
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
              ),
              onPressed: () => setState(() => _open = !_open),
              child: Text(_open ? context.tr('Réduire') : context.tr('Lire la suite')),
            ),
        ],
      );
    });
  }
}
