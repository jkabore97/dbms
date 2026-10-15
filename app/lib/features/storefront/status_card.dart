import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/mara_mark.dart';
import 'status_designs.dart';
import 'storefront_screen.dart' show priceOf;

/// The status picture: 1080 × 1920, captured from StatusPreview, in one of
/// five designs ([StatusDesign]) and one of the colour themes
/// ([StatusPalette]). With neither given it is drawn in the business's own
/// default ([StatusChoice.defaultFor]).
///
/// Every design is drawn for what a vitrine really holds: no photo at all,
/// one, four; a name of forty letters; a farm's « / plateau »; services
/// « à partir de »; an association; nothing on the shelf yet.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.shop,
    required this.items,
    this.cover,
    this.photos = const {},
    this.design,
    this.palette,
  });

  final PublicShop shop;

  /// Up to four articles, photographed first ([pick]), or the ones the
  /// business chose (140); one is an ad for it, in every design.
  final List<PublicItem> items;
  final Uint8List? cover;
  final Map<String, Uint8List> photos;

  /// Null: the business's default.
  final StatusDesign? design;
  final StatusPalette? palette;

  static const size = Size(1080, 1920);

  /// The articles the card shows: four at most, those in stock first, and
  /// among them the photographed ones first.
  static List<PublicItem> pick(List<PublicItem> items) => [
        ...items.where((i) => i.inStock && i.photoKey != null),
        ...items.where((i) => i.inStock && i.photoKey == null),
        ...items.where((i) => !i.inStock && i.photoKey != null),
        ...items.where((i) => !i.inStock && i.photoKey == null),
      ].take(4).toList();

  /// The colour themes this business can choose from.
  List<StatusPalette> get palettes => StatusPalette.forShop(shop.accent);

  /// What it looks like before anything is chosen.
  StatusChoice get defaultChoice =>
      StatusChoice.defaultFor(shop.orgId, hasOwn: shop.accent != null);

  StatusChoice get choice => StatusChoice(
        design ?? defaultChoice.design,
        palette?.id ?? defaultChoice.paletteId,
      );

  StatusCard copyWith({
    StatusDesign? design,
    StatusPalette? palette,
    List<PublicItem>? items,
    Map<String, Uint8List>? photos,
  }) =>
      StatusCard(
        shop: shop,
        items: items ?? this.items,
        cover: cover,
        photos: photos ?? this.photos,
        design: design ?? this.design,
        palette: palette ?? this.palette,
      );

  @override
  Widget build(BuildContext context) {
    final p = palette ?? defaultChoice.paletteIn(palettes);
    final c = _Content.of(context, this);
    final body = switch (design ?? defaultChoice.design) {
      StatusDesign.vitrine => _Vitrine(c, p),
      StatusDesign.grille => _Grille(c, p),
      StatusDesign.vedette => _Vedette(c, p),
      StatusDesign.affiche => _Affiche(c, p),
      StatusDesign.bandeau => _Bandeau(c, p),
    };
    // A picture of a fixed size, drawn at its own text size, never the
    // reader's (UI audit V-3: it overflowed at 2.0), in its own text style:
    // it must not borrow (or miss) the screen's.
    return MediaQuery.withNoTextScaling(
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
            color: p.ink,
          ),
          child: SizedBox.fromSize(
            size: size,
            child: ColoredBox(color: p.ground, child: body),
          ),
        ),
      ),
    );
  }
}

/// One article as the picture says it.
class _Item {
  const _Item(this.name, this.price, this.photo, {this.note, this.soldOut = false, this.description});
  final String name;
  final String price;
  final Uint8List? photo;

  /// « Épuisé », or the day a pre-order will be there; null otherwise.
  final String? note;

  /// Chosen though out of stock (140): the picture says « Épuisé ».
  final bool soldOut;

  /// What the business wrote about it, for an ad of one article (140).
  final String? description;

  /// The price as a list or a grid writes it: « Épuisé » after it when so.
  String get shown => soldOut && note != null ? '$price · $note' : price;
}

/// Everything a design writes, in the reader's language and the kind's own
/// words: a shop's « Nos articles », a farm's « À vendre », an
/// association's « À découvrir », « Nos services » for a window of services.
class _Content {
  const _Content({
    required this.name,
    required this.line,
    required this.kind,
    required this.section,
    required this.cta,
    required this.pill,
    required this.ribbon,
    required this.empty,
    required this.url,
    required this.items,
    required this.cover,
    this.adRibbon = '',
  });

  /// The ribbon over an ad of one article: what it is now.
  final String adRibbon;

  final String name;
  final String? line;
  final String kind;
  final String section;
  final String cta;
  final String pill;
  final String ribbon;
  final String empty;
  final String url;
  final List<_Item> items;
  final Uint8List? cover;

  String get shortUrl => url.replaceFirst(RegExp(r'^https?://'), '');

  /// One article only (140): an ad for it, in every design.
  bool get ad => items.length == 1;

  /// The kind and what the shelf holds, for a kicker: « FERME · À VENDRE ».
  String get kicker =>
      (items.isEmpty ? kind : '$kind · $section').toUpperCase();

  /// The cover, or the first article's photo.
  Uint8List? get hero => cover ?? items.where((i) => i.photo != null).firstOrNull?.photo;

  factory _Content.of(BuildContext context, StatusCard card) {
    final shop = card.shop;
    final money = moneyFormat(shop.currency);
    final lang = context.trLanguage;
    final raw = (shop.style.tagline ?? shop.blurb)?.trim();
    final services = card.items.isNotEmpty && card.items.every((i) => i.isService);
    final farm = shop.profile == 'farm';
    final association = shop.profile == 'association' || shop.profile == 'church';
    return _Content(
      name: shop.name.trim(),
      line: raw == null || raw.isEmpty ? null : raw,
      kind: context.tr(farm ? 'Ferme' : association ? 'Association' : 'Boutique'),
      section: context.tr(services
          ? 'Nos services'
          : farm
              ? 'À vendre'
              : association
                  ? 'À découvrir'
                  : 'Nos articles'),
      cta: context.tr(services
          ? 'Réservez ici'
          : association
              ? 'Retrouvez-nous ici'
              : 'Commandez ici'),
      pill: context.tr(services
          ? 'Réservez sur Marakaj'
          : association
              ? 'Retrouvez-nous sur Marakaj'
              : 'Commandez sur Marakaj'),
      ribbon: context.tr(services
          ? 'Sur rendez-vous'
          : farm
              ? (card.items.any((i) => i.isPreorder) ? 'En précommande' : 'Disponible')
              : association
                  ? 'À découvrir'
                  : 'Nouveautés'),
      empty: context.tr('Découvrez notre vitrine'),
      url: publicShopUrl(shop.slug),
      cover: card.cover,
      adRibbon: _adRibbon(context, card, services: services, farm: farm, association: association),
      items: [
        for (final i in card.items)
          _Item(
            i.name.trim(),
            priceOf(money, i, lang),
            card.photos[i.id],
            soldOut: !i.inStock,
            note: !i.inStock
                ? context.tr('Épuisé')
                : i.isPreorder
                    ? context.tr('Disponible à partir du {date}',
                        {'date': DateFormat('dd/MM').format(i.availableFrom!)})
                    : null,
            description: i.hasDescription ? i.description!.trim() : null,
          ),
      ],
    );
  }
}

/// The ribbon of an ad (140): « Épuisé », « En précommande », « Sur
/// rendez-vous », a farm's « Disponible », « À découvrir », « À la une ».
String _adRibbon(BuildContext context, StatusCard card,
    {required bool services, required bool farm, required bool association}) {
  final one = card.items.length == 1 ? card.items.first : null;
  if (one == null) return '';
  if (!one.inStock) return context.tr('Épuisé');
  if (one.isPreorder) return context.tr('En précommande');
  if (services) return context.tr('Sur rendez-vous');
  if (farm) return context.tr('Disponible');
  if (association) return context.tr('À découvrir');
  return context.tr('À la une');
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

/// Text set as large as it fits its box — its width, its lines and, when
/// the box is bounded, its height: a name of four letters or of forty.
class _FitText extends StatelessWidget {
  const _FitText(
    this.text, {
    required this.style,
    required this.max,
    this.min = 28,
    this.maxLines = 2,
    this.align = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final double max;
  final double min;
  final int maxLines;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(builder: (context, box) {
      var size = max;
      while (size > min) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: base.copyWith(fontSize: size)),
          maxLines: maxLines,
          textAlign: align,
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: box.maxWidth);
        final fits = !tp.didExceedMaxLines &&
            tp.width <= box.maxWidth + 0.5 &&
            (!box.hasBoundedHeight || tp.height <= box.maxHeight);
        tp.dispose();
        if (fits) break;
        size -= 4;
      }
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: style.copyWith(fontSize: math.max(size, min)),
      );
    });
  }
}

Widget _photo(Uint8List bytes) =>
    Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);

/// The business's initials in a round of its accent.
class _Monogram extends StatelessWidget {
  const _Monogram(this.name, this.p, {this.size = 300});

  final String name;
  final StatusPalette p;
  final double size;

  static String initials(String name) {
    const small = {'à', 'a', 'au', 'aux', 'de', 'des', 'du', 'd', 'et', 'en', 'la', 'le', 'les', 'l', 'pour', 'sur', 'un', 'une', 'the', 'of', 'and'};
    final words = name
        .split(RegExp(r"[\s'’-]+"))
        .where((w) =>
            w.isNotEmpty &&
            RegExp(r'[A-Za-zÀ-ÿ0-9]').hasMatch(w[0]) &&
            !small.contains(w.toLowerCase()))
        .toList();
    if (words.isEmpty) return name.isEmpty ? 'M' : name[0].toUpperCase();
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
        child: Text(initials(name),
            style: TextStyle(
                color: p.onAccent,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w900,
                letterSpacing: -2)),
      );
}

/// Rings drawn round a point: a ground with something on it when there is
/// no photograph.
class _Rings extends CustomPainter {
  const _Rings(this.color, this.center);
  final Color color;
  final Alignment center;

  @override
  void paint(Canvas canvas, Size size) {
    final o = center.alongSize(size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color;
    for (var r = 200.0; r < size.longestSide * 1.2; r += 90) {
      canvas.drawCircle(o, r, paint);
    }
  }

  @override
  bool shouldRepaint(_Rings old) => old.color != color || old.center != center;
}

/// An article with no photograph: its name set large on the card, as the
/// vitrine does it.
class _NamePlate extends StatelessWidget {
  const _NamePlate(this.name, this.p, {this.max = 56, this.price});

  final String name;
  final StatusPalette p;
  final double max;

  /// Under the rule, when the plate says it.
  final String? price;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: p.surface,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Center(
                  child: _FitText(name,
                      max: max,
                      min: 26,
                      maxLines: 3,
                      align: TextAlign.center,
                      style: TextStyle(
                          color: p.onSurface, fontWeight: FontWeight.w800, height: 1.1)),
                ),
              ),
              const SizedBox(height: 14),
              Container(width: 70, height: 6, color: p.priceOnSurface),
              if (price != null) ...[
                const SizedBox(height: 14),
                _FitText(price!,
                    max: 34,
                    min: 22,
                    maxLines: 1,
                    align: TextAlign.center,
                    style: TextStyle(color: p.priceOnSurface, fontWeight: FontWeight.w900)),
              ],
            ],
          ),
        ),
      );
}

/// The QR code on its white plate: always black on white, the way every
/// phone's camera reads it.
class _Qr extends StatelessWidget {
  const _Qr(this.url, {this.size = 170, this.plate = true});

  final String url;
  final double size;
  final bool plate;

  @override
  Widget build(BuildContext context) {
    final qr = QrImageView(
      data: url,
      size: size,
      padding: EdgeInsets.zero,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: maraBlack),
      dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square, color: maraBlack),
    );
    if (!plate) return qr;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: qr,
    );
  }
}

/// Mara's mark, small: the light one on a dark ground.
Widget _mark(StatusPalette p, {double height = 44, bool? onDark}) =>
    MaraWordmark(height: height, onDark: onDark ?? p.dark);

/// Where to find it: the QR code, « Commandez ici » and the address — on a
/// paper plate ([plate]) or straight on the ground.
class _Footer extends StatelessWidget {
  const _Footer(this.c, this.p, {this.plate = false, this.qr = 170, this.mark = true});

  final _Content c;
  final StatusPalette p;
  final bool plate;
  final double qr;

  /// Mara's mark under the address; false where the design has it already.
  final bool mark;

  @override
  Widget build(BuildContext context) {
    final ink = plate ? maraBlack : p.ink;
    final soft = plate ? maraBrown : p.soft;
    final row = Row(
      children: [
        _Qr(c.url, size: qr, plate: !plate),
        const SizedBox(width: 32),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.cta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ink, fontSize: 46, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(c.shortUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: soft, fontSize: 31, fontWeight: FontWeight.w700)),
              if (mark) ...[
                const SizedBox(height: 14),
                _mark(p, onDark: plate ? false : null),
              ],
            ],
          ),
        ),
      ],
    );
    if (!plate) return row;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: p.dark ? maraPaper : Colors.white,
        borderRadius: BorderRadius.circular(36),
        border: p.dark ? null : Border.all(color: p.soft.withValues(alpha: 0.25), width: 2),
      ),
      child: row,
    );
  }
}

/// Nothing on the shelf yet: the initials and an invitation, on a card.
class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf(this.c, this.p);

  final _Content c;
  final StatusPalette p;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(32)),
        padding: const EdgeInsets.all(48),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: _Monogram(c.name, p, size: 220)),
            const SizedBox(height: 36),
            Text(c.empty,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.onSurface, fontSize: 52, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

/// A short label in capitals, spaced: « BOUTIQUE · NOS ARTICLES ».
Widget _kicker(String text, Color color, {double size = 30}) => Text(text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
        color: color, fontSize: size, fontWeight: FontWeight.w800, letterSpacing: size * 0.18));

/// An article with no photograph, in an ad (140): its initials on rings.
class _AdPlate extends StatelessWidget {
  const _AdPlate(this.name, this.p, {this.size = 340});

  final String name;
  final StatusPalette p;
  final double size;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: p.surface),
          CustomPaint(painter: _Rings(p.ink.withValues(alpha: 0.08), Alignment.center)),
          Center(child: _Monogram(name, p, size: size)),
        ],
      );
}

/// The ribbon of an ad, as a pill: « ÉPUISÉ », « À LA UNE »…
Widget _pill(String text, Color ground, Color ink, {double size = 30}) => Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.9, vertical: size * 0.42),
      decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(size * 2)),
      child: Text(text.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: ink, fontSize: size, fontWeight: FontWeight.w900, letterSpacing: size * 0.12)),
    );

/// The words of an ad (140), in the order a passer-by reads them: whose it
/// is, what it is, what the business says of it, its price, whether it is
/// there — each as large as it fits.
class _AdWords extends StatelessWidget {
  const _AdWords(this.c, this.i, this.p,
      {this.ribbon});

  final _Content c;
  final _Item i;
  final StatusPalette p;

  /// What the design's own ribbon already says: not said twice.
  final String? ribbon;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kicker(c.name.toUpperCase(), p.accentOnGround),
          const SizedBox(height: 14),
          _FitText(i.name,
              max: 92,
              min: 50,
              style: TextStyle(color: p.ink, height: 1.04, fontWeight: FontWeight.w900, letterSpacing: -1)),
          if (i.description != null) ...[
            const SizedBox(height: 12),
            Text(i.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.soft, fontSize: 36, height: 1.25, fontWeight: FontWeight.w500)),
          ],
          const SizedBox(height: 14),
          _FitText(i.price,
              max: 116,
              min: 52,
              maxLines: 1,
              style: TextStyle(color: p.accentOnGround, fontWeight: FontWeight.w900, letterSpacing: -2)),
          if (i.note != null && i.note != ribbon) ...[
            const SizedBox(height: 18),
            _pill(i.note!, i.soldOut ? p.ink : p.accent, i.soldOut ? p.ground : p.onAccent),
          ],
        ],
      );
}

// ---------------------------------------------------------------------------
// 1. Vitrine — the shop's photo, its name, four articles two by two
// ---------------------------------------------------------------------------

class _Vitrine extends StatelessWidget {
  const _Vitrine(this.c, this.p);
  final _Content c;
  final StatusPalette p;

  Widget _tile(_Item i) => ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: i.photo == null
            ? _NamePlate(i.name, p, max: 50, price: i.shown)
            : Stack(
                fit: StackFit.expand,
                children: [
                  _photo(i.photo!),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 56, 24, 20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x000E0D0C), Color(0xDD0E0D0C)],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: maraPaper, fontSize: 32, fontWeight: FontWeight.w700)),
                          _FitText(i.shown,
                              max: 34,
                              min: 22,
                              maxLines: 1,
                              style: const TextStyle(
                                  color: Color(0xFFE6C9A2), fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      );

  /// One article (140): its photograph over most of the screen, fading
  /// into the ground, then its name, its price, and the plate.
  Widget _ad(_Item i) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (i.photo != null) _photo(i.photo!) else _AdPlate(i.name, p),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [p.ground.withValues(alpha: 0), p.ground.withValues(alpha: 0), p.ground],
                      stops: const [0, 0.7, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 72,
                  right: 72,
                  top: 140,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _pill(c.adRibbon, p.ground.withValues(alpha: 0.92), p.accentOnGround, size: 28),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 16, 72, 0),
            child: _AdWords(c, i, p, ribbon: c.adRibbon),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 40, 72, 110),
            child: _Footer(c, p, plate: true, qr: 170),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (c.ad) return _ad(c.items.first);
    final items = c.items;
    final hero = c.hero;
    Widget row(List<_Item> pair) => Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var k = 0; k < pair.length; k++) ...[
                if (k > 0) const SizedBox(width: 28),
                Expanded(child: _tile(pair[k])),
              ],
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The shop's photo, a third of the screen, fading into the ground;
        // its initials on rings when it has none.
        SizedBox(
          height: items.isEmpty ? 820 : 620,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hero != null)
                _photo(hero)
              else ...[
                ColoredBox(color: p.surface),
                CustomPaint(
                    painter: _Rings(p.ink.withValues(alpha: 0.09), const Alignment(0.55, -0.1))),
                Align(
                  alignment: const Alignment(0.55, -0.1),
                  child: _Monogram(c.name, p, size: 300),
                ),
              ],
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [p.ground.withValues(alpha: 0), p.ground.withValues(alpha: 0), p.ground],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
              Positioned(
                left: 72,
                top: 140,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                  decoration: BoxDecoration(
                      color: p.ground.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(40)),
                  child: _kicker(c.kind.toUpperCase(), p.accentOnGround, size: 28),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 72),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FitText(c.name,
                  max: 96,
                  min: 56,
                  style: TextStyle(color: p.ink, height: 1.05, fontWeight: FontWeight.w900)),
              if (c.line != null) ...[
                const SizedBox(height: 16),
                Text(c.line!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.accentOnGround,
                        fontSize: 42,
                        height: 1.2,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 44),
        if (items.isNotEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 72),
              child: items.length <= 2
                  // One row: no taller than its tiles are wide, centred.
                  ? LayoutBuilder(
                      builder: (context, box) => Center(
                        child: SizedBox(
                          height: math.min(box.maxHeight, items.length == 1 ? 560 : 470),
                          child: Column(children: [row(items)]),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        row(items.take(2).toList()),
                        const SizedBox(height: 28),
                        row(items.skip(2).take(2).toList()),
                      ],
                    ),
            ),
          )
        else
          const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 36, 72, 110),
          child: _Footer(c, p, plate: true, qr: 180),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Grille — a magazine page: masthead, a grid of cards with prices
// ---------------------------------------------------------------------------

class _Grille extends StatelessWidget {
  const _Grille(this.c, this.p);
  final _Content c;
  final StatusPalette p;

  Widget _card(_Item i, {bool wide = false}) {
    final text = Padding(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(i.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.onSurface, fontSize: wide ? 40 : 32, height: 1.15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _FitText(i.shown,
              max: wide ? 44 : 34,
              min: 22,
              maxLines: 1,
              style: TextStyle(color: p.priceOnSurface, fontWeight: FontWeight.w900)),
        ],
      ),
    );
    final picture = i.photo != null
        ? _photo(i.photo!)
        : ColoredBox(
            color: Color.lerp(p.surface, p.accent, 0.16)!,
            child: Center(
              child: Text(_Monogram.initials(i.name),
                  style: TextStyle(
                      color: p.onSurface.withValues(alpha: 0.85),
                      fontSize: wide ? 150 : 110,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -3)),
            ),
          );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(26)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Expanded(child: picture), text],
      ),
    );
  }

  /// One article (140): the whole page's card, its photograph large, its
  /// name, its words and its price under it, its state on the photograph.
  Widget _adCard(_Item i) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(30)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (i.photo != null)
                    _photo(i.photo!)
                  else
                    ColoredBox(
                      color: Color.lerp(p.surface, p.accent, 0.16)!,
                      child: Center(
                        child: Text(_Monogram.initials(i.name),
                            style: TextStyle(
                                color: p.onSurface.withValues(alpha: 0.85),
                                fontSize: 220,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -4)),
                      ),
                    ),
                  if (i.note != null)
                    Positioned(
                      left: 28,
                      top: 28,
                      right: 28,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _pill(i.note!, i.soldOut ? maraBlack : p.accent,
                            i.soldOut ? maraPaper : p.onAccent),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(34, 26, 34, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FitText(i.name,
                      max: 60,
                      min: 36,
                      style: TextStyle(color: p.onSurface, height: 1.1, fontWeight: FontWeight.w800)),
                  if (i.description != null) ...[
                    const SizedBox(height: 8),
                    Text(i.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.onSurface.withValues(alpha: 0.8), fontSize: 32, height: 1.25)),
                  ],
                  const SizedBox(height: 10),
                  _FitText(i.price,
                      max: 84,
                      min: 40,
                      maxLines: 1,
                      style: TextStyle(color: p.priceOnSurface, fontWeight: FontWeight.w900, letterSpacing: -1)),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final items = c.items.take(4).toList();
    const gap = 26.0;
    Widget grid;
    if (items.isEmpty) {
      grid = _EmptyShelf(c, p);
    } else if (items.length == 1) {
      grid = _adCard(items[0]);
    } else if (items.length == 2) {
      grid = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _card(items[0], wide: true)),
        const SizedBox(height: gap),
        Expanded(child: _card(items[1], wide: true)),
      ]);
    } else {
      grid = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _card(items[0])),
            const SizedBox(width: gap),
            Expanded(child: _card(items[1])),
          ]),
        ),
        const SizedBox(height: gap),
        Expanded(
          child: items.length == 3
              ? _card(items[2], wide: true)
              : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: _card(items[2])),
                  const SizedBox(width: gap),
                  Expanded(child: _card(items[3])),
                ]),
        ),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 120, 64, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: _kicker(c.kicker, p.accentOnGround)),
            const SizedBox(width: 24),
            _mark(p, height: 42),
          ]),
          const SizedBox(height: 14),
          Container(height: 3, color: p.ink.withValues(alpha: 0.85)),
          const SizedBox(height: 30),
          _FitText(c.name,
              max: 112,
              min: 60,
              style: TextStyle(
                  color: p.ink, height: 1.0, fontWeight: FontWeight.w900, letterSpacing: -2)),
          if (c.line != null) ...[
            const SizedBox(height: 16),
            Text(c.line!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.soft, fontSize: 38, height: 1.25, fontWeight: FontWeight.w500)),
          ],
          const SizedBox(height: 40),
          Expanded(child: grid),
          const SizedBox(height: 40),
          _Footer(c, p, qr: 160, mark: false),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Vedette — one article: its big photo, its big price
// ---------------------------------------------------------------------------

class _Vedette extends StatelessWidget {
  const _Vedette(this.c, this.p);
  final _Content c;
  final StatusPalette p;

  @override
  Widget build(BuildContext context) {
    final star = c.items.firstOrNull;
    // An ad (140) shows the article's own photograph, never the shop's
    // cover under its name: none, and its initials stand there.
    final picture = star?.photo ?? (c.ad ? null : c.hero);
    final title = star?.name ?? c.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (picture != null)
                _photo(picture)
              else if (c.ad)
                _AdPlate(star!.name, p, size: 360)
              else ...[
                ColoredBox(color: p.surface),
                CustomPaint(painter: _Rings(p.ink.withValues(alpha: 0.08), Alignment.center)),
                Center(child: _Monogram(c.name, p, size: 360)),
              ],
              // The shop's name over the photograph, where it is read
              // first, under WhatsApp's own bar.
              Positioned(
                left: 64,
                right: 64,
                top: 140,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                    decoration: BoxDecoration(
                        color: p.ground.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(44)),
                    child: Text(star == null ? c.kind : c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.ink, fontSize: 36, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(height: 14, color: p.accent),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 52, 72, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kicker(
                  (star == null
                          ? c.kind
                          : c.ad
                              ? star.note ?? c.adRibbon
                              : c.section)
                      .toUpperCase(),
                  p.accentOnGround),
              const SizedBox(height: 14),
              _FitText(title,
                  max: 88,
                  min: 52,
                  style: TextStyle(color: p.ink, height: 1.05, fontWeight: FontWeight.w900)),
              if (c.ad && star!.description != null) ...[
                const SizedBox(height: 10),
                Text(star.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.soft, fontSize: 36, height: 1.25, fontWeight: FontWeight.w500)),
              ],
              if (star != null) ...[
                const SizedBox(height: 6),
                _FitText(star.price,
                    max: 120,
                    min: 56,
                    maxLines: 1,
                    style: TextStyle(
                        color: p.accentOnGround, fontWeight: FontWeight.w900, letterSpacing: -2)),
              ] else if (c.line != null) ...[
                const SizedBox(height: 14),
                Text(c.line!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.soft, fontSize: 42, height: 1.2)),
              ],
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 26),
                decoration:
                    BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(60)),
                child: Text(c.pill,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.onAccent, fontSize: 42, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 44),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.ink, fontSize: 40, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(c.shortUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.soft, fontSize: 30, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 18),
                        _mark(p, height: 42),
                      ],
                    ),
                  ),
                  const SizedBox(width: 28),
                  _Qr(c.url, size: 150),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Affiche — the name huge, the line, the articles as a price list
// ---------------------------------------------------------------------------

class _Affiche extends StatelessWidget {
  const _Affiche(this.c, this.p);
  final _Content c;
  final StatusPalette p;

  /// One article (140): a poster for it — whose it is, its photograph in
  /// a band, its name huge, its price as large, the address.
  Widget _ad(_Item i) => Padding(
        padding: const EdgeInsets.fromLTRB(80, 150, 80, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(width: 56, height: 8, color: p.accentOnGround),
              const SizedBox(width: 22),
              // « Ferme · Ferme Horizon Vert » says « ferme » twice: once.
              Expanded(
                  child: _kicker(
                      (c.name.toLowerCase().contains(c.kind.toLowerCase()) ? c.name : '${c.kind} · ${c.name}')
                          .toUpperCase(),
                      p.accentOnGround,
                      size: 32)),
            ]),
            const SizedBox(height: 40),
            // With a photograph it takes the room the name leaves; without,
            // the name is the poster.
            if (i.photo != null) ...[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: SizedBox.expand(child: _photo(i.photo!)),
                ),
              ),
              const SizedBox(height: 36),
              _FitText(i.name,
                  max: 120,
                  min: 64,
                  maxLines: 2,
                  style: TextStyle(color: p.ink, height: 0.98, fontWeight: FontWeight.w900, letterSpacing: -3)),
            ] else
              Expanded(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: _FitText(i.name,
                      max: 190,
                      min: 64,
                      maxLines: 4,
                      style: TextStyle(
                          color: p.ink, height: 0.98, fontWeight: FontWeight.w900, letterSpacing: -3)),
                ),
              ),
            if (i.description != null) ...[
              const SizedBox(height: 24),
              Text(i.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.soft, fontSize: 42, height: 1.22, fontWeight: FontWeight.w500)),
            ],
            const SizedBox(height: 36),
            Container(height: 6, color: p.accentOnGround),
            const SizedBox(height: 24),
            _FitText(i.price,
                max: 130,
                min: 56,
                maxLines: 1,
                style: TextStyle(color: p.accentOnGround, fontWeight: FontWeight.w900, letterSpacing: -2)),
            if (i.note != null) ...[
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: _pill(i.note!, i.soldOut ? p.ink : p.accent, i.soldOut ? p.ground : p.onAccent),
              ),
            ],
            const SizedBox(height: 44),
            _Footer(c, p, qr: 170),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final items = c.items.take(4).toList();
    return Stack(
      children: [
        Positioned(
          right: -300,
          top: -260,
          child: Container(
            width: 900,
            height: 900,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent.withValues(alpha: 0.16)),
          ),
        ),
        Positioned(
          right: -150,
          top: -110,
          child: Container(
            width: 600,
            height: 600,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: p.accent.withValues(alpha: 0.5), width: 4)),
          ),
        ),
        if (c.ad) _ad(c.items.first) else
        Padding(
          padding: const EdgeInsets.fromLTRB(80, 150, 80, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(width: 56, height: 8, color: p.accentOnGround),
                const SizedBox(width: 22),
                Expanded(child: _kicker(c.kind.toUpperCase(), p.accentOnGround, size: 32)),
              ]),
              const SizedBox(height: 36),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: _FitText(c.name,
                      max: 210,
                      min: 80,
                      maxLines: 4,
                      style: TextStyle(
                          color: p.ink, height: 0.98, fontWeight: FontWeight.w900, letterSpacing: -4)),
                ),
              ),
              if (c.line != null) ...[
                const SizedBox(height: 30),
                Text(c.line!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.soft, fontSize: 46, height: 1.22, fontWeight: FontWeight.w500)),
              ],
              const SizedBox(height: 52),
              Container(height: 6, color: p.accentOnGround),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 18),
                for (var k = 0; k < items.length; k++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      border: k == items.length - 1
                          ? null
                          : Border(bottom: BorderSide(color: p.ink.withValues(alpha: 0.18), width: 2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(items[k].name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink, fontSize: 42, height: 1.15, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 28),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: _FitText(items[k].shown,
                              max: 42,
                              min: 30,
                              maxLines: 2,
                              align: TextAlign.end,
                              style: TextStyle(
                                  color: p.accentOnGround, height: 1.15, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 52),
              _Footer(c, p, qr: 170),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Bandeau — a banner and its ribbon, three articles in rows
// ---------------------------------------------------------------------------

class _Slant extends CustomClipper<Path> {
  const _Slant();
  @override
  Path getClip(Size s) => Path()
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height - 110)
    ..lineTo(0, s.height)
    ..close();
  @override
  bool shouldReclip(_Slant old) => false;
}

class _Bandeau extends StatelessWidget {
  const _Bandeau(this.c, this.p);
  final _Content c;
  final StatusPalette p;

  Widget _row(_Item i, double height) {
    final thumb = i.photo != null
        ? _photo(i.photo!)
        : ColoredBox(
            color: p.accent,
            child: Center(
              child: Text(_Monogram.initials(i.name),
                  style: TextStyle(
                      color: p.onAccent, fontSize: height * 0.36, fontWeight: FontWeight.w900)),
            ),
          );
    return Container(
      height: height,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(30)),
      child: Row(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(borderRadius: BorderRadius.circular(22), child: thumb),
          ),
          const SizedBox(width: 30),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.onSurface, fontSize: 40, height: 1.15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _FitText(i.shown,
                    max: 46,
                    min: 30,
                    maxLines: 1,
                    style: TextStyle(color: p.priceOnSurface, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One article (140): a single card under the banner — its photograph
  /// large, its name and price beside the ribbon's word for it.
  Widget _adCard(_Item i) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(34)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: i.photo != null
                    ? _photo(i.photo!)
                    : ColoredBox(
                        color: p.accent,
                        child: Center(
                          child: Text(_Monogram.initials(i.name),
                              style: TextStyle(
                                  color: p.onAccent, fontSize: 200, fontWeight: FontWeight.w900)),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FitText(i.name,
                      max: 60,
                      min: 36,
                      style: TextStyle(color: p.onSurface, height: 1.1, fontWeight: FontWeight.w800)),
                  if (i.description != null) ...[
                    const SizedBox(height: 8),
                    Text(i.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.onSurface.withValues(alpha: 0.8), fontSize: 32, height: 1.25)),
                  ],
                  const SizedBox(height: 8),
                  _FitText(
                      i.note != null && i.note != c.adRibbon ? '${i.price} · ${i.note}' : i.price,
                      max: 76,
                      min: 36,
                      maxLines: 1,
                      style: TextStyle(color: p.priceOnSurface, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final items = c.items.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipPath(
          clipper: const _Slant(),
          child: Container(
            color: p.accent,
            padding: const EdgeInsets.fromLTRB(72, 140, 72, 170),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                  decoration: BoxDecoration(color: p.ground, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Transform.rotate(
                      angle: math.pi / 4,
                      child: Container(width: 20, height: 20, color: p.accentOnGround),
                    ),
                    const SizedBox(width: 22),
                    Flexible(
                      child: Text((c.ad ? c.adRibbon : c.ribbon).toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 5)),
                    ),
                  ]),
                ),
                const SizedBox(height: 34),
                _FitText(c.name,
                    max: 112,
                    min: 60,
                    style: TextStyle(
                        color: p.onAccent, height: 1.0, fontWeight: FontWeight.w900, letterSpacing: -2)),
                if (c.line != null) ...[
                  const SizedBox(height: 18),
                  Text(c.line!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.onAccent, fontSize: 40, height: 1.2, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: items.isEmpty
                ? _EmptyShelf(c, p)
                : c.ad
                ? _adCard(items.first)
                : LayoutBuilder(builder: (context, box) {
                    const gap = 24.0;
                    final h = math.min(270.0, (box.maxHeight - gap * (items.length - 1)) / items.length);
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var k = 0; k < items.length; k++) ...[
                          if (k > 0) const SizedBox(height: gap),
                          _row(items[k], h),
                        ],
                      ],
                    );
                  }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(64, 40, 64, 110),
          child: _Footer(c, p, qr: 160),
        ),
      ],
    );
  }
}
