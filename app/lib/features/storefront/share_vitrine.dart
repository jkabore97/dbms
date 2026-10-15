import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/format/money.dart';
import '../../core/retail/models.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/mara_mark.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import 'package:kaj_app/core/theme/mara_sheet.dart';
import 'status_articles.dart';
import 'status_card.dart';
import 'status_designs.dart';
import 'status_out.dart';
import 'storefront_screen.dart' show priceOf;

export 'status_articles.dart';
export 'status_card.dart';
export 'status_designs.dart';
export 'status_out.dart';

/// « Partager » (140): on a vitrine (the owner's or anybody's), on one of
/// its articles or services, on an article in the business's Catalogue.
/// Two clear choices, the same words on every app:
///
///  * « Une image » — for a status or a story: a picture the size of a
///    phone screen (1080 × 1920), the business's name and line, its
///    articles — the four it picks, the ones the business ticks, or one
///    alone as an ad (140) — with their prices, and its address on
///    marakaj.com with a QR code, in one of five designs and a choice of
///    colours (137). It leaves by WhatsApp, Facebook, any other app, or
///    into the photos ([StatusSharer]).
///  * « Le lien » — to send to someone: a short message with the link; the
///    chat then shows the shop's own preview (the site writes its og tags).
///
/// The app has no address for one article (its sheet opens over the
/// vitrine), so one article's link is the vitrine's, its name and price in
/// the message.
class ShareVitrine {
  const ShareVitrine._();

  static Future<void> open(
    BuildContext context, {
    required PublicShop shop,
    required List<PublicItem> items,
    CaptureRepository? capture,
    PublicItem? article,
    bool mine = false,
    StatusPhotoLoader? photos,
    StatusPlatform? platform,
    AdminRepository? admin,
  }) =>
      showMaraSheet<void>(
        context: context,
        showDragHandle: true,
        // As tall as its two ways need (320 px at large text).
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ShareSheet(
          shop: shop,
          items: items,
          capture: capture,
          article: article,
          mine: mine,
          photos: photos,
          platform: platform,
          admin: admin,
        ),
      );

  /// « Partager ma boutique », « Partager cette ferme », « Partager ce
  /// produit », « Partager ce service »: the kind and what is shared. « ma »
  /// for the business's own people, « cette » for a passer-by.
  static String title(BuildContext context, PublicShop shop, {PublicItem? article, bool mine = false}) {
    if (article != null) {
      return article.isService ? context.tr('Partager ce service') : context.tr('Partager ce produit');
    }
    final farm = shop.profile == 'farm';
    final association = shop.profile == 'association' || shop.profile == 'church';
    if (mine) {
      return farm
          ? context.tr('Partager ma ferme')
          : association
              ? context.tr('Partager mon association')
              : context.tr('Partager ma boutique');
    }
    return farm
        ? context.tr('Partager cette ferme')
        : association
            ? context.tr('Partager cette association')
            : context.tr('Partager cette boutique');
  }

  /// The message sent to a contact: name, line, and the link on its own
  /// line so WhatsApp builds the preview under it. For one article: its
  /// name and price first, then whose it is.
  static String message(BuildContext context, PublicShop shop, {PublicItem? article}) {
    final line = shop.style.tagline ?? shop.blurb;
    if (article != null) {
      final price = priceOf(moneyFormat(shop.currency), article, context.trLanguage);
      return [
        '*${article.name.trim()}* — $price',
        context.tr('chez {name}', {'name': shop.name}),
        '',
        article.isService
            ? context.tr('Voir et réserver :')
            : context.tr('Voir et commander :'),
        publicShopUrl(shop.slug),
      ].join('\n');
    }
    return [
      '*${shop.name}*',
      if (line != null && line.trim().isNotEmpty) line.trim(),
      '',
      context.tr('Voir les articles et commander :'),
      publicShopUrl(shop.slug),
    ].join('\n');
  }

  /// A photograph's bytes by its key: the public copy the vitrine shows,
  /// else (an article not yet on the vitrine) the business's own, through
  /// its token.
  static StatusPhotoLoader? loaderFor(CaptureRepository? capture) {
    if (capture == null) return null;
    final kept = <String, Uint8List?>{};
    return (key, {width}) async {
      if (kept.containsKey(key)) return kept[key];
      Uint8List? bytes;
      try {
        bytes = await capture.publicObjectBytes(key);
      } catch (_) {
        try {
          bytes = await capture.objectBytes(key);
        } catch (_) {}
      }
      return kept[key] = bytes;
    };
  }

  /// StatusPreview, its photographs decoded first: from the share sheet's
  /// « Une image ». [article] opens it as an ad of that one.
  static Future<void> openStatus(
    BuildContext context, {
    required PublicShop shop,
    required List<PublicItem> items,
    StatusPhotoLoader? photos,
    PublicItem? article,
    StatusPlatform? platform,
    StatusMemory? memory,
  }) async {
    final catalogue = [
      ...items,
      if (article != null && !items.any((i) => i.id == article.id)) article,
    ];
    final selection = article == null ? const StatusSelection() : StatusSelection.only(article.id);
    final chosen = selection.itemsIn(catalogue);
    Future<Uint8List?> bytes(String? key) async {
      if (key == null || photos == null) return null;
      try {
        return await photos(key);
      } catch (_) {
        return null;
      }
    }

    // The cover is the shop's own photograph only: a ticked article's is
    // its own, and must not head a picture of others.
    final cover = await bytes(shop.style.coverKey);
    final pictures = <String, Uint8List>{};
    for (final i in chosen) {
      final b = await bytes(i.photoKey);
      if (b != null) pictures[i.id] = b;
    }
    if (!context.mounted) return;
    // Decoded before the card is shown: the capture must not catch a photo
    // still loading.
    // Mara's marks too, both: a design on a light ground draws the dark one.
    for (final image in <ImageProvider>[
      for (final b in [?cover, ...pictures.values]) MemoryImage(b),
      const AssetImage(MaraWordmark.asset),
      const AssetImage(MaraWordmark.assetDark),
    ]) {
      // Bounded: a decode that never answers must not hold the share.
      try {
        await precacheImage(image, context).timeout(const Duration(seconds: 3));
      } catch (_) {}
      if (!context.mounted) return;
    }
    // The design and colour this business chose last time on this phone,
    // read before the preview opens so it never flashes another one. An
    // ad opens on « Vedette », in the colour remembered.
    final db = AppScope.read(context)?.db;
    final kept = memory ?? (db == null ? null : DbStatusMemory(db));
    final remembered = await StatusMemory.recall(kept, shop.orgId);
    if (!context.mounted) return;
    final card = StatusCard(shop: shop, items: chosen, cover: cover, photos: pictures);
    final initial = article == null
        ? remembered
        : StatusChoice(StatusDesign.vedette, (remembered ?? card.choice).paletteId);
    final navigator = Navigator.of(context);
    // Built now, while the sheet is alive: the preview's route rebuilds
    // during its exit, after the sheet is gone (UI audit V-2).
    final text = message(context, shop, article: article);
    await navigator.push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StatusPreview(
        card: card,
        catalogue: catalogue,
        selection: selection,
        photos: photos,
        name: article == null ? '${shop.slug}-marakaj.png' : '${shop.slug}-annonce-marakaj.png',
        text: text,
        initial: initial,
        memory: kept,
        platform: platform,
      ),
    ));
  }

  /// « Partager » on an article or a service in the business's Catalogue
  /// (140): the vitrine as the street sees it when it can be read, else
  /// the business's own words for it; the article from the Catalogue, as
  /// the vitrine would show it ([publicItemOf]).
  static Future<void> openForProduct(
    BuildContext context, {
    required OrgSummary org,
    required Product product,
    String? photoKey,
    CaptureRepository? capture,
    StorefrontRepository? storefront,
    StatusPlatform? platform,
    AdminRepository? admin,
  }) async {
    final slug = org.slug ?? '';
    final street = storefront ??
        (AppScope.maybeOf(context) == null
            ? null
            : StorefrontRepository(AppScope.of(context).auth.client));
    PublicShop? shop;
    var items = <PublicItem>[];
    if (street != null && street.isConfigured && slug.isNotEmpty) {
      try {
        shop = await street.shop(slug).timeout(const Duration(seconds: 8));
        if (shop != null) items = await street.items(slug).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    shop ??= PublicShop(
      orgId: org.id,
      name: org.name,
      slug: slug,
      profile: org.profile,
      theme: org.theme,
      currency: org.currency,
    );
    final mapped = publicItemOf(product, photoKey: photoKey);
    final article = items.where((i) => i.id == product.id).firstOrNull ?? mapped;
    if (!context.mounted) return;
    await open(context,
        shop: shop,
        items: items.isEmpty ? [article] : items,
        capture: capture,
        article: article,
        mine: true,
        platform: platform,
        admin: admin);
  }
}

/// A business's article or service as the vitrine shows it — the same rule
/// as storefront_products (131): a service, a count above zero, a count
/// not followed, or a pre-order is « there »; a pre-order's day only while
/// it is still to come.
PublicItem publicItemOf(Product p, {String? photoKey, DateTime? today}) {
  final day = DateUtils.dateOnly(today ?? DateTime.now());
  final from = p.availableFrom;
  final later = from != null && DateUtils.dateOnly(from).isAfter(day);
  final description = p.description?.trim();
  final unit = p.unit?.trim();
  return PublicItem(
    id: p.id,
    name: p.name,
    price: p.salePrice,
    inStock: p.isService || p.quantity > 0 || !p.stockTracked || later,
    isService: p.isService,
    priceFrom: p.priceFrom,
    photoKey: photoKey,
    description: description == null || description.isEmpty ? null : description,
    unit: unit == null || unit.isEmpty ? null : unit,
    availableFrom: later ? from : null,
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.shop,
    required this.items,
    this.capture,
    this.article,
    this.mine = false,
    this.photos,
    this.platform,
    this.admin,
  });

  final PublicShop shop;
  final List<PublicItem> items;
  final CaptureRepository? capture;
  final PublicItem? article;
  final bool mine;
  final StatusPhotoLoader? photos;
  final StatusPlatform? platform;

  /// For whether the street sees the vitrine; null: the app's own.
  final AdminRepository? admin;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _busy = false;

  /// Its own people's vitrine the street cannot see yet (140): what they
  /// share leads to a closed door, so the sheet says so. Null: not known.
  bool? _visible;

  @override
  void initState() {
    super.initState();
    if (widget.mine) unawaited(_checkVisible());
  }

  Future<void> _checkVisible() async {
    final admin = widget.admin ?? AppScope.read(context)?.session.admin;
    if (admin == null) return;
    try {
      final c = await admin.vitrineChecklist(widget.shop.orgId);
      if (mounted && c != null) setState(() => _visible = c.visible);
    } catch (_) {
      // Not known: no line rather than a wrong one.
    }
  }

  void _settings() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(Routes.orgSettings(widget.shop.orgId));
  }

  Future<void> _image() async {
    // One picture per tap: a second tap while it is made opens nothing.
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    await ShareVitrine.openStatus(
      context,
      shop: widget.shop,
      items: widget.items,
      photos: widget.photos ?? ShareVitrine.loaderFor(widget.capture),
      article: widget.article,
      platform: widget.platform,
    );
    if (mounted) navigator.pop();
  }

  Future<void> _link() async {
    final text = ShareVitrine.message(context, widget.shop, article: widget.article);
    final platform = widget.platform ?? StatusPlatform.device();
    Navigator.of(context).pop();
    try {
      await platform.text(text);
    } catch (_) {}
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.tr('Lien copié');
    await Clipboard.setData(ClipboardData(text: publicShopUrl(widget.shop.slug)));
    if (mounted) Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(copied)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final article = widget.article;
    // Scrolls when taller than the screen (iPhone SE at large text, UI
    // audit V-1): every button stays reachable.
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('share-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          key: const Key('share-vitrine'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(ShareVitrine.title(context, widget.shop, article: article, mine: widget.mine),
                key: const Key('share-title'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(article == null ? widget.shop.name : '${article.name} · ${widget.shop.name}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (_visible == false) ...[
              const SizedBox(height: 12),
              Material(
                key: const Key('share-hidden'),
                color: const Color(0xFFF6E7C8),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility_off_outlined, color: maraDeep, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.tr('Votre vitrine n\'est pas encore visible : vos clients ne la verront pas.'),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: maraDeep, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        key: const Key('share-hidden-open'),
                        onPressed: _settings,
                        child: Text(context.tr('Régler')),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _Way(
              key: const Key('share-image'),
              icon: Icons.image_outlined,
              title: context.tr('Une image'),
              detail: context.tr('pour un statut ou une story'),
              busy: _busy,
              onTap: _busy ? null : _image,
            ),
            const SizedBox(height: 10),
            _Way(
              key: const Key('share-link'),
              icon: Icons.link,
              title: context.tr('Le lien'),
              detail: context.tr('à envoyer à quelqu\'un'),
              onTap: _busy ? null : _link,
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('share-copy'),
              onPressed: _busy ? null : _copy,
              child: Text(context.tr('Copier le lien')),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the sheet's two ways: an icon, a word, what it is for.
class _Way extends StatelessWidget {
  const _Way({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: maraCaramel, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: maraDeep))
                      : Icon(icon, color: maraDeep),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text(detail,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The status picture as it will be posted, scaled to the screen, the one
/// compact panel that dresses it (137) — its articles (140), five designs
/// as live thumbnails, the colours as dots, « Surprise » — and the four
/// ways out (140): WhatsApp, Facebook, any other app, the photos. What the
/// business sees is what goes on its status.
class StatusPreview extends StatefulWidget {
  const StatusPreview({
    super.key,
    required this.card,
    required this.name,
    required this.text,
    this.catalogue = const [],
    this.selection = const StatusSelection(),
    this.photos,
    this.initial,
    this.memory,
    this.random,
    this.platform,
  });

  /// The picture's content; its design and colour are the panel's.
  final StatusCard card;
  final String name;
  final String text;

  /// Every article and service the business could show (140); empty, no
  /// choice is offered and [card]'s own articles show.
  final List<PublicItem> catalogue;

  /// The articles it opens on: « Automatique », or one as an ad when
  /// opened from it. Never remembered.
  final StatusSelection selection;

  /// For the photographs of articles ticked after it opened.
  final StatusPhotoLoader? photos;

  /// The choice to open on (the one remembered); null reads it from
  /// [memory], and the business's default shows meanwhile.
  final StatusChoice? initial;

  /// Where the choice is kept; null: this device's, when the app has one.
  final StatusMemory? memory;

  /// For « Surprise » (a test's own seed).
  final math.Random? random;

  /// Where the picture leaves by; null: this device's.
  final StatusPlatform? platform;

  @override
  State<StatusPreview> createState() => _StatusPreviewState();
}

class _StatusPreviewState extends State<StatusPreview> {
  final _key = GlobalKey();
  bool _sharing = false;
  late StatusChoice _choice;
  late final List<StatusPalette> _palettes = widget.card.palettes;
  bool _touched = false;
  late StatusSelection _selection = widget.selection;
  late final Map<String, Uint8List> _photos = {...widget.card.photos};
  late final StatusSharer _sharer = StatusSharer(widget.platform ?? StatusPlatform.device());
  List<StatusTarget> _targets = const [];

  /// The owner picked a design on a thumbnail. Until then an ad's « Vedette »
  /// is the app's, not theirs: a colour changed is remembered with the
  /// design remembered before (140).
  bool _designPicked = false;

  /// The web (140): the picture made ahead, while the preview shows, so the
  /// browser's share runs straight from the tap — Safari refuses one that
  /// comes after the picture is made, the tap's moment gone. Dropped at
  /// every change; [_shape] counts them.
  Uint8List? _ready;
  int _shape = 0;
  Timer? _prebuild;

  void _changed() {
    _shape++;
    _ready = null;
    if (_sharer.platform.os != StatusOs.web) return;
    _prebuild?.cancel();
    _prebuild = Timer(const Duration(milliseconds: 500), _prepare);
  }

  Future<void> _prepare() async {
    if (!mounted || _sharing) return;
    final at = _shape;
    try {
      final png = await _png();
      if (mounted && at == _shape) _ready = png;
    } catch (_) {}
  }

  @override
  void dispose() {
    _prebuild?.cancel();
    super.dispose();
  }

  StatusMemory? get _memory {
    if (widget.memory != null) return widget.memory;
    final db = AppScope.read(context)?.db;
    return db == null ? null : DbStatusMemory(db);
  }

  @override
  void initState() {
    super.initState();
    _choice = widget.initial ??
        (widget.selection.single
            ? StatusChoice(StatusDesign.vedette, widget.card.choice.paletteId)
            : widget.card.choice);
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final remembered = await StatusMemory.recall(_memory, widget.card.shop.orgId);
        if (mounted && remembered != null && !_touched) {
          // An ad keeps its « Vedette »; the colour is the one remembered.
          setState(() => _choice = _selection.single
              ? StatusChoice(StatusDesign.vedette, remembered.paletteId)
              : remembered);
          _changed();
        }
      });
    }
    _sharer.targets().then((t) {
      if (mounted) setState(() => _targets = t);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _changed();
    });
  }

  /// [picked]: a design's thumbnail tapped — the owner's own choice.
  void _choose(StatusChoice c, {bool picked = false}) {
    if (c == _choice) return;
    setState(() {
      _choice = c;
      _touched = true;
      if (picked) _designPicked = true;
    });
    _changed();
    unawaited(_remember(c));
  }

  Future<void> _remember(StatusChoice c) async {
    final memory = _memory;
    final org = widget.card.shop.orgId;
    if (!_selection.single || _designPicked) return StatusMemory.remember(memory, org, c);
    // An ad: its colour is the owner's, its « Vedette » (or Surprise's
    // design) is not — the design remembered before stays.
    final before = await StatusMemory.recall(memory, org);
    await StatusMemory.remember(
        memory, org, StatusChoice(before?.design ?? widget.card.choice.design, c.paletteId));
  }

  /// The articles changed (140): at once in the picture, their photographs
  /// as they come. « Un seul produit » turned on brings « Vedette » — not
  /// remembered: the owner did not choose it.
  void _select(StatusSelection s) {
    if (!mounted || s == _selection) return;
    setState(() {
      if (s.single && !_selection.single) {
        _choice = StatusChoice(StatusDesign.vedette, _choice.paletteId);
        _designPicked = false;
      }
      _selection = s;
    });
    _changed();
    _fetchPhotos();
  }

  Future<void> _fetchPhotos() async {
    final load = widget.photos;
    if (load == null) return;
    for (final i in _items) {
      final key = i.photoKey;
      if (key == null || _photos.containsKey(i.id)) continue;
      Uint8List? bytes;
      try {
        bytes = await load(key);
      } catch (_) {}
      if (bytes == null || !mounted) continue;
      try {
        await precacheImage(MemoryImage(bytes), context).timeout(const Duration(seconds: 3));
      } catch (_) {}
      if (!mounted) return;
      setState(() => _photos[i.id] = bytes!);
      _changed();
    }
  }

  List<PublicItem> get _items =>
      widget.catalogue.isEmpty ? widget.card.items : _selection.itemsIn(widget.catalogue);

  StatusCard get _card => widget.card.copyWith(
        design: _choice.design,
        palette: _choice.paletteIn(_palettes),
        items: _items,
        photos: _photos,
      );

  Future<void> _articles() => StatusArticlesSheet.open(
        context,
        catalogue: widget.catalogue,
        currency: widget.card.shop.currency,
        selection: _selection,
        onChanged: _select,
        photos: widget.photos,
      );

  Future<Uint8List> _png() async {
    final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('not ready');
    // Captured at the card's own 1080 px, whatever the phone's width.
    final image = await boundary.toImage(pixelRatio: StatusCard.size.width / boundary.size.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('no image');
    return data.buffer.asUint8List();
  }

  Future<void> _send(StatusTarget target) async {
    // One way out per tap: a double tap sends once.
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('Partage impossible sur cet appareil. {error}', {'error': ''});
    final saved = _sharer.platform.os == StatusOs.web
        ? context.tr('Image téléchargée.')
        : context.tr('Image enregistrée dans vos photos.');
    try {
      final png = _ready ?? await _png();
      final outcome = await _sharer.send(target, png, widget.name, widget.text);
      if (outcome == StatusOutcome.saved) {
        messenger.showSnackBar(SnackBar(content: Text(saved)));
      } else if (outcome == StatusOutcome.failed) {
        messenger.showSnackBar(SnackBar(content: Text(failed.trim())));
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$failed$error')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// « Automatique », « 2/4 », « Annonce : Œufs frais ».
  String _articlesLabel(BuildContext context) {
    if (_selection.automatic) return context.tr('Automatique');
    final items = _items;
    if (_selection.single) {
      return context.tr('Annonce : {name}', {'name': items.firstOrNull?.name ?? ''});
    }
    return '${items.length}/${StatusSelection.max}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: maraBlack,
        appBar: AppBar(
          actions: const [bellRoom],
          backgroundColor: maraBlack,
          foregroundColor: maraPaper,
          // The app's AppBarTheme sets its icons and title in ink, which wins
          // over foregroundColor: on this dark bar they were drawn ink on
          // black — the way back was there but invisible (132).
          iconTheme: const IconThemeData(color: maraPaper),
          actionsIconTheme: const IconThemeData(color: maraPaper),
          titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(color: maraPaper),
          // Always its own way back (132): an iPhone has no system back,
          // and this page is also opened where nothing implies one.
          leading: IconButton(
            key: const Key('status-close'),
            tooltip: context.tr('Fermer'),
            color: maraPaper,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(context.tr('Votre image')),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: RepaintBoundary(
                        key: _key,
                        child: FittedBox(
                            child: KeyedSubtree(key: const Key('status-card'), child: _card)),
                      ),
                    ),
                  ),
                ),
              ),
              _Panel(
                card: _card,
                palettes: _palettes,
                choice: _choice,
                onChoose: (c) => _choose(c, picked: c.design != _choice.design),
                onSurprise: () => _choose(_choice.surprise(_palettes, widget.random)),
                articles: widget.catalogue.isEmpty ? null : _articlesLabel(context),
                onArticles: widget.catalogue.isEmpty ? null : _articles,
                servicesOnly: StatusArticlesSheet.speaksServices(widget.catalogue, _selection.chosen),
              ),
              _Foot(
                targets: _targets,
                busy: _sharing,
                hint: _sharer.whatsAppHint,
                web: _sharer.platform.os == StatusOs.web,
                onSend: _send,
              ),
            ],
          ),
        ),
      );
}

/// The foot: one button for each way out, the same size, under the panel.
class _Foot extends StatelessWidget {
  const _Foot({
    required this.targets,
    required this.busy,
    required this.hint,
    required this.web,
    required this.onSend,
  });

  final List<StatusTarget> targets;
  final bool busy;
  final bool hint;
  final bool web;
  final ValueChanged<StatusTarget> onSend;

  @override
  Widget build(BuildContext context) {
    (IconData, String, Color) look(StatusTarget t) => switch (t) {
          StatusTarget.whatsapp => (Icons.chat, context.tr('WhatsApp'), const Color(0xFF1FA855)),
          StatusTarget.facebook => (Icons.facebook, context.tr('Facebook'), const Color(0xFF1877F2)),
          StatusTarget.others => (
              web ? Icons.ios_share : Icons.more_horiz,
              web ? context.tr('Partager…') : context.tr('Autres…'),
              maraDeep
            ),
          StatusTarget.save => (
              web ? Icons.download_outlined : Icons.save_alt,
              context.tr('Enregistrer'),
              maraDeep
            ),
        };
    return Padding(
      key: const Key('status-foot'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (final t in targets)
                Expanded(
                  child: _OutButton(
                    key: Key('status-out-${t.name}'),
                    icon: look(t).$1,
                    label: look(t).$2,
                    colour: look(t).$3,
                    onTap: busy ? null : () => onSend(t),
                  ),
                ),
            ],
          ),
          if (hint && targets.contains(StatusTarget.whatsapp))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                context.tr('Choisissez WhatsApp'),
                key: const Key('status-ios-hint'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: maraGrey, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// One way out: a round of its colour, its word under it.
class _OutButton extends StatelessWidget {
  const _OutButton({
    super.key,
    required this.icon,
    required this.label,
    required this.colour,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color colour;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        enabled: onTap != null,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: onTap == null ? 0.5 : 1,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colour,
                      shape: BoxShape.circle,
                      border: colour == maraDeep ? Border.all(color: const Color(0x55F4F2EE)) : null,
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(height: 4),
                // Its word whole, a size smaller when it must (« Enregistrer »
                // at 320 px and large text), never cut.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: const TextStyle(color: maraPaper, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      );
}

/// The one compact panel under the preview: the choice said in words with
/// « Surprise » beside it, the five designs as thumbnails, the colours as
/// dots. Nothing else: the owner hates crowded screens.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.card,
    required this.palettes,
    required this.choice,
    required this.onChoose,
    required this.onSurprise,
    this.articles,
    this.onArticles,
    this.servicesOnly = false,
  });

  final StatusCard card;
  final List<StatusPalette> palettes;
  final StatusChoice choice;
  final ValueChanged<StatusChoice> onChoose;
  final VoidCallback onSurprise;

  /// « ARTICLES  Automatique ▾ » (140): the one line the choice of articles
  /// adds; null where there is nothing to choose from.
  final String? articles;
  final VoidCallback? onArticles;

  /// A business that only does services: « SERVICES », not « ARTICLES ».
  final bool servicesOnly;

  @override
  Widget build(BuildContext context) {
    final palette = choice.paletteIn(palettes);
    return Container(
      key: const Key('status-panel'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1C1A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (articles != null)
            InkWell(
              key: const Key('status-articles-row'),
              onTap: onArticles,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2, right: 10),
                child: Row(
                  children: [
                    Text((servicesOnly ? context.tr('Services') : context.tr('Articles')).toUpperCase(),
                        style: const TextStyle(
                            color: maraGrey, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(articles!,
                          key: const Key('status-articles-value'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: maraPaper, fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    const Icon(Icons.expand_more, color: maraCaramel, size: 22),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${context.tr(choice.design.label)} · ${context.tr(palette.label)}',
                  key: const Key('status-choice'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: maraPaper, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                key: const Key('status-surprise'),
                style: TextButton.styleFrom(foregroundColor: maraCaramel),
                onPressed: onSurprise,
                icon: const Icon(Icons.shuffle, size: 18),
                label: Text(context.tr('Surprise')),
              ),
            ],
          ),
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final d in StatusDesign.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _Thumb(
                      key: Key('status-design-${d.name}'),
                      label: context.tr(d.label),
                      selected: d == choice.design,
                      onTap: () => onChoose(StatusChoice(d, choice.paletteId)),
                      child: card.copyWith(design: d, palette: palette),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in palettes)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _Dot(
                      key: Key('status-colour-${p.id}'),
                      palette: p,
                      label: context.tr(p.label),
                      selected: p.id == palette.id,
                      onTap: () => onChoose(StatusChoice(choice.design, p.id)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A design, drawn small in the colour chosen: what a tap will give.
class _Thumb extends StatelessWidget {
  const _Thumb({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 45 + 6,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                  color: selected ? maraCaramel : const Color(0x33F4F2EE), width: selected ? 3 : 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              // Drawn once per change, apart from the preview's own layer.
              child: RepaintBoundary(
                child: IgnorePointer(
                  child: ExcludeSemantics(child: FittedBox(child: child)),
                ),
              ),
            ),
          ),
        ),
      );
}

/// A colour: its ground, its accent at the centre.
class _Dot extends StatelessWidget {
  const _Dot({
    super.key,
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final StatusPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Tooltip(
          message: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? maraCaramel : Colors.transparent, width: 2.5),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.ground,
                  border: Border.all(color: const Color(0x55F4F2EE)),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: palette.accent),
                ),
              ),
            ),
          ),
        ),
      );
}

/// « Partager » on an article or a service of the business (140): in its
/// Catalogue sheet, or — [compact] — as an icon on its row. Offered once
/// it is on the vitrine, where the picture's QR code leads.
class ShareArticleButton extends StatefulWidget {
  const ShareArticleButton({
    super.key,
    required this.org,
    required this.product,
    this.photoKey,
    this.capture,
    this.compact = false,
    this.storefront,
    this.platform,
    this.admin,
  });

  final OrgSummary org;
  final Product product;
  final String? photoKey;
  final CaptureRepository? capture;
  final bool compact;

  /// For a test; null: the app's own.
  final StorefrontRepository? storefront;
  final StatusPlatform? platform;
  final AdminRepository? admin;

  /// Whether it is offered: the article is on a vitrine that has an address.
  static bool offered(OrgSummary org, Product product) =>
      product.isPublished && (org.slug ?? '').isNotEmpty;

  @override
  State<ShareArticleButton> createState() => _ShareArticleButtonState();
}

class _ShareArticleButtonState extends State<ShareArticleButton> {
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ShareVitrine.openForProduct(context,
          org: widget.org,
          product: widget.product,
          photoKey: widget.photoKey,
          capture: widget.capture,
          storefront: widget.storefront,
          platform: widget.platform,
          admin: widget.admin);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = context.tr('Partager');
    final icon = _busy
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.share_outlined, size: 20);
    if (widget.compact) {
      return IconButton(
        key: Key('share-article-${widget.product.id}'),
        tooltip: label,
        onPressed: _busy ? null : _share,
        icon: icon,
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: Key('share-article-${widget.product.id}'),
        onPressed: _busy ? null : _share,
        icon: icon,
        label: Text(label),
      ),
    );
  }
}
