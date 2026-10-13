import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/nav/app_scope.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/mara_mark.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import 'package:kaj_app/core/theme/mara_sheet.dart';
import 'status_card.dart';
import 'status_designs.dart';

export 'status_card.dart';
export 'status_designs.dart';

/// « Partager » on a vitrine (the owner's or anybody's): three ways out,
/// each made for WhatsApp, where a vitrine travels here.
///
///  * « Mettre en statut » — a picture the size of a phone screen
///    (1080 × 1920): the business's name and line, its articles with their
///    prices, and its address on marakaj.com with a QR code, in one of five
///    designs and a choice of colours (137). Shared as a file, so WhatsApp
///    offers « Mon statut » straight away.
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
      showMaraSheet<void>(
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
    // Mara's marks too, both: a design on a light ground draws the dark one.
    for (final image in <ImageProvider>[
      for (final b in [?cover, ...photos.values]) MemoryImage(b),
      const AssetImage(MaraWordmark.asset),
      const AssetImage(MaraWordmark.assetDark),
    ]) {
      // Bounded: a decode that never answers must not hold the share.
      try {
        await precacheImage(image, context).timeout(const Duration(seconds: 3));
      } catch (_) {}
      if (!mounted) return;
    }
    // The design and colour this business chose last time on this phone,
    // read before the preview opens so it never flashes another one.
    final db = AppScope.read(context)?.db;
    final memory = db == null ? null : DbStatusMemory(db);
    final remembered = await StatusMemory.recall(memory, shop.orgId);
    if (!mounted) return;
    setState(() => _busy = false);
    final navigator = Navigator.of(context);
    // Built now, while this sheet is alive: the preview's route rebuilds
    // during its exit, after the sheet is gone (UI audit V-2).
    final text = ShareVitrine.message(context, shop);
    await navigator.push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StatusPreview(
        card: StatusCard(
            shop: shop, items: chosen, cover: cover, photos: photos),
        name: '${shop.slug}-mara.png',
        text: text,
        initial: remembered,
        memory: memory,
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
    // Scrolls when taller than the screen (iPhone SE at large text, UI
    // audit V-1): every button stays reachable.
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('share-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          key: const Key('share-vitrine'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Partager {name}', {'name': widget.shop.name}),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(publicShopUrl(widget.shop.slug),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
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
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
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

/// The status picture as it will be posted, scaled to the screen, the one
/// compact panel that dresses it (137) — five designs as live thumbnails,
/// the colours as dots, « Surprise » — and the button that shares it: what
/// the business sees is what goes on its status.
class StatusPreview extends StatefulWidget {
  const StatusPreview({
    super.key,
    required this.card,
    required this.name,
    required this.text,
    this.initial,
    this.memory,
    this.random,
  });

  /// The picture's content; its design and colour are the panel's.
  final StatusCard card;
  final String name;
  final String text;

  /// The choice to open on (the one remembered); null reads it from
  /// [memory], and the business's default shows meanwhile.
  final StatusChoice? initial;

  /// Where the choice is kept; null: this device's, when the app has one.
  final StatusMemory? memory;

  /// For « Surprise » (a test's own seed).
  final math.Random? random;

  @override
  State<StatusPreview> createState() => _StatusPreviewState();
}

class _StatusPreviewState extends State<StatusPreview> {
  final _key = GlobalKey();
  bool _sharing = false;
  late StatusChoice _choice;
  late final List<StatusPalette> _palettes = widget.card.palettes;
  bool _touched = false;

  StatusMemory? get _memory {
    if (widget.memory != null) return widget.memory;
    final db = AppScope.read(context)?.db;
    return db == null ? null : DbStatusMemory(db);
  }

  @override
  void initState() {
    super.initState();
    _choice = widget.initial ?? widget.card.choice;
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final remembered = await StatusMemory.recall(_memory, widget.card.shop.orgId);
        if (mounted && remembered != null && !_touched) {
          setState(() => _choice = remembered);
        }
      });
    }
  }

  void _choose(StatusChoice c) {
    if (c == _choice) return;
    setState(() {
      _choice = c;
      _touched = true;
    });
    StatusMemory.remember(_memory, widget.card.shop.orgId, c);
  }

  StatusCard get _card => widget.card
      .copyWith(design: _choice.design, palette: _choice.paletteIn(_palettes));

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
          title: Text(context.tr('Votre statut')),
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
                card: widget.card,
                palettes: _palettes,
                choice: _choice,
                onChoose: _choose,
                onSurprise: () => _choose(_choice.surprise(_palettes, widget.random)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 52,
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
                    const SizedBox(height: 6),
                    Text(
                      context.tr('Choisissez WhatsApp, puis « Mon statut ».'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: maraGrey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
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
  });

  final StatusCard card;
  final List<StatusPalette> palettes;
  final StatusChoice choice;
  final ValueChanged<StatusChoice> onChoose;
  final VoidCallback onSurprise;

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
