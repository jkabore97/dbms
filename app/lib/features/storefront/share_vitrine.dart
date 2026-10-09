import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/format/money.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/mara_mark.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// « Partager » on a vitrine (the owner's or anybody's): three ways out,
/// each made for WhatsApp, where a vitrine travels here.
///
///  * « Mettre en statut » — a picture the size of a phone screen
///    (1080 × 1920): the shop's photo, its name and line, four articles with
///    their prices, and its address on marakaj.com with a QR code. Shared as
///    a file, so WhatsApp offers « Mon statut » straight away.
///  * « Envoyer à un contact » — a short message with the link; the chat
///    then shows the shop's own preview (the site writes its og tags).
///  * « Copier le lien ».
class ShareVitrine {
  const ShareVitrine._();

  static Future<void> open(
    BuildContext context, {
    required PublicShop shop,
    required List<PublicItem> items,
    CaptureRepository? capture,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _ShareSheet(shop: shop, items: items, capture: capture),
      );

  /// The message sent to a contact: name, line, and the link on its own
  /// line so WhatsApp builds the preview under it.
  static String message(BuildContext context, PublicShop shop) {
    final line = shop.style.tagline ?? shop.blurb;
    return [
      '*${shop.name}*',
      if (line != null && line.trim().isNotEmpty) line.trim(),
      '',
      context.tr('Voir les articles et commander :'),
      publicShopUrl(shop.slug),
    ].join('\n');
  }
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.shop, required this.items, this.capture});

  final PublicShop shop;
  final List<PublicItem> items;
  final CaptureRepository? capture;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _busy = false;

  Future<void> _status() async {
    setState(() => _busy = true);
    final shop = widget.shop;
    final chosen = StatusCard.pick(widget.items);
    final capture = widget.capture;
    Future<Uint8List?> bytes(String? key) async {
      if (key == null || capture == null) return null;
      try {
        return await capture.publicObjectBytes(key);
      } catch (_) {
        return null;
      }
    }

    final coverKey = shop.style.coverKey ??
        chosen.where((i) => i.photoKey != null).firstOrNull?.photoKey;
    final cover = await bytes(coverKey);
    final photos = <String, Uint8List>{};
    for (final i in chosen) {
      final b = await bytes(i.photoKey);
      if (b != null) photos[i.id] = b;
    }
    if (!mounted) return;
    // Decoded before the card is shown: the capture must not catch a photo
    // still loading.
    for (final b in [?cover, ...photos.values]) {
      try {
        await precacheImage(MemoryImage(b), context);
      } catch (_) {}
      if (!mounted) return;
    }
    setState(() => _busy = false);
    final navigator = Navigator.of(context);
    await navigator.push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StatusPreview(
        card: StatusCard(
            shop: shop, items: chosen, cover: cover, photos: photos),
        name: '${shop.slug}-mara.png',
        text: ShareVitrine.message(context, shop),
      ),
    ));
    if (mounted) navigator.pop();
  }

  Future<void> _contact() async {
    final url = whatsappShareUrl(ShareVitrine.message(context, widget.shop));
    Navigator.of(context).pop();
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.tr('Lien copié');
    await Clipboard.setData(
        ClipboardData(text: publicShopUrl(widget.shop.slug)));
    if (mounted) Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(copied)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          key: const Key('share-vitrine'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Partager {name}', {'name': widget.shop.name}),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(publicShopUrl(widget.shop.slug),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                key: const Key('share-status'),
                style: FilledButton.styleFrom(
                    backgroundColor: maraCaramel, foregroundColor: maraDeep),
                onPressed: _busy ? null : _status,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.amp_stories_outlined),
                label: Text(context.tr('Mettre en statut WhatsApp')),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                key: const Key('share-contact'),
                onPressed: _busy ? null : _contact,
                icon: const Icon(Icons.chat_outlined),
                label: Text(context.tr('Envoyer à un contact')),
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              key: const Key('share-copy'),
              onPressed: _busy ? null : _copy,
              icon: const Icon(Icons.link),
              label: Text(context.tr('Copier le lien')),
            ),
          ],
        ),
      ),
    );
  }
}

/// The status picture: 1080 × 1920, captured from [StatusPreview].
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.shop,
    required this.items,
    this.cover,
    this.photos = const {},
  });

  final PublicShop shop;

  /// Up to four articles, photographed first.
  final List<PublicItem> items;
  final Uint8List? cover;
  final Map<String, Uint8List> photos;

  static const size = Size(1080, 1920);

  /// The articles the card shows: photographed first, four at most.
  static List<PublicItem> pick(List<PublicItem> items) => [
        ...items.where((i) => i.photoKey != null),
        ...items.where((i) => i.photoKey == null),
      ].take(4).toList();

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(shop.currency);
    final line = shop.style.tagline ?? shop.blurb;
    final url = publicShopUrl(shop.slug);
    const paper = maraPaper;
    Widget tile(PublicItem i) => ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photos[i.id] != null)
                Image.memory(photos[i.id]!, fit: BoxFit.cover, gaplessPlayback: true)
              else
                ColoredBox(
                  color: paper.withValues(alpha: 0.08),
                  child: const Icon(Icons.shopping_bag_outlined,
                      size: 90, color: maraCaramel),
                ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 40, 22, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xCC0E0D0C)],
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
                              color: paper,
                              fontSize: 32,
                              fontWeight: FontWeight.w700)),
                      Text(money.format(i.price),
                          style: const TextStyle(
                              color: maraCaramel,
                              fontSize: 34,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
    Widget row(List<PublicItem> pair) => Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var k = 0; k < 2; k++) ...[
                if (k > 0) const SizedBox(width: 28),
                Expanded(
                    child: k < pair.length ? tile(pair[k]) : const SizedBox()),
              ],
            ],
          ),
        );
    // Its own text style: the card is drawn wherever it is captured, and
    // must not borrow (or miss) the screen's.
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
      style: TextStyle(fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
      child: SizedBox.fromSize(
      size: size,
      child: ColoredBox(
        color: maraDeep,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The shop's photo, a third of the screen, fading into the ground.
            SizedBox(
              height: 560,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover != null)
                    Image.memory(cover!, fit: BoxFit.cover, gaplessPlayback: true)
                  else
                    const ColoredBox(color: maraEspresso),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0x00000000), maraDeep],
                        stops: [0, 0.55, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 72, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shop.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: paper,
                          fontSize: 92,
                          height: 1.05,
                          fontWeight: FontWeight.w900)),
                  if (line != null && line.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(line.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: maraCaramel,
                            fontSize: 44,
                            height: 1.2,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 48),
            // Four articles, two by two, each with its price.
            if (items.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 72),
                  child: Column(
                    children: [
                      row(items.take(2).toList()),
                      if (items.length > 2) ...[
                        const SizedBox(height: 28),
                        row(items.skip(2).take(2).toList()),
                      ],
                    ],
                  ),
                ),
              )
            else
              const Spacer(),
            // Where to find it: the address and a QR code to scan.
            Container(
              margin: const EdgeInsets.fromLTRB(72, 24, 72, 96),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: paper,
                borderRadius: BorderRadius.circular(36),
              ),
              child: Row(
                children: [
                  QrImageView(
                    data: url,
                    size: 190,
                    padding: EdgeInsets.zero,
                    eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square, color: maraBlack),
                    dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: maraBlack),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('Commandez ici'),
                            style: const TextStyle(
                                color: maraBlack,
                                fontSize: 46,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Text(url.replaceFirst(RegExp(r'^https?://'), ''),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: maraBrown,
                                fontSize: 32,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 14),
                        const MaraWordmark(height: 44),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
      ),
    );
  }
}

/// The status picture as it will be posted, scaled to the screen, and the
/// button that shares it: what the shop sees is what goes on its status.
class StatusPreview extends StatefulWidget {
  const StatusPreview({
    super.key,
    required this.card,
    required this.name,
    required this.text,
  });

  final StatusCard card;
  final String name;
  final String text;

  @override
  State<StatusPreview> createState() => _StatusPreviewState();
}

class _StatusPreviewState extends State<StatusPreview> {
  final _key = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('Partage impossible sur cet appareil. {error}', {'error': ''});
    try {
      final boundary =
          _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('not ready');
      // Captured at the card's own 1080 px, whatever the phone's width.
      final image = await boundary.toImage(
          pixelRatio: StatusCard.size.width / boundary.size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('no image');
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(data.buffer.asUint8List(),
              mimeType: 'image/png', name: widget.name),
        ],
        text: widget.text,
      ));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$failed$error')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: maraBlack,
        appBar: AppBar(
          actions: const [bellRoom],
          backgroundColor: maraBlack,
          foregroundColor: maraPaper,
          title: Text(context.tr('Votre statut')),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: RepaintBoundary(
                        key: _key,
                        child: FittedBox(child: widget.card),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        key: const Key('status-share'),
                        style: FilledButton.styleFrom(
                            backgroundColor: maraCaramel,
                            foregroundColor: maraDeep),
                        onPressed: _sharing ? null : _share,
                        icon: const Icon(Icons.send),
                        label: Text(context.tr('Partager sur WhatsApp')),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('Choisissez WhatsApp, puis « Mon statut ».'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: maraGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
