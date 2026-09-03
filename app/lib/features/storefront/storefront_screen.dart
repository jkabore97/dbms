import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/format/money.dart';
import '../../core/nav/router.dart';
import '../../core/storefront/storefront_repository.dart';
import 'shop_style.dart';

/// A shop's window, for the street.
///
/// Opened from a link on WhatsApp by somebody with no account, so it asks for
/// nothing: no sign-in, no PIN, no business. It shows what the shop chose to
/// show — its name, a few words, the articles with a photo and a price — and
/// one way to act on it: contact the shop. Nothing is bought here. Phase one
/// of the vitrine is a window, not a till; the till comes when shoppers are
/// actually pulling on the door.
///
/// The look is the settled one for selling goods online (see [ShopStyle]):
/// white page, a quiet header, the shop's name large over a warm band, then
/// the photographs, each on its own off-white square with the name and the
/// price in small type underneath. The photograph is the product; nothing
/// else on the page is allowed to compete with it.
class StorefrontScreen extends StatefulWidget {
  const StorefrontScreen({
    super.key,
    required this.slug,
    required this.storefront,
    required this.capture,
  });

  final String slug;
  final StorefrontRepository storefront;

  /// For the photos, served publicly by the uploads Worker per key.
  final CaptureRepository capture;

  @override
  State<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends State<StorefrontScreen> {
  PublicShop? _shop;
  List<PublicItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!widget.storefront.isConfigured) {
      setState(() {
        _error = "La vitrine a besoin d'une connexion.";
        _loading = false;
      });
      return;
    }
    try {
      final shop = await widget.storefront.shop(widget.slug);
      final items = shop == null
          ? const <PublicItem>[]
          : await widget.storefront.items(widget.slug);
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = "La vitrine n'a pas pu être chargée. Vérifiez le réseau.";
        _loading = false;
      });
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _directory() => context.go(Routes.directory);

  @override
  Widget build(BuildContext context) {
    final shop = _shop;

    return ShopPage(
      title: shop?.name ?? 'Vitrine',
      leading: IconButton(
        tooltip: 'Toutes les vitrines',
        icon: const Icon(Icons.arrow_back),
        onPressed: _directory,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ShopNotice(
                  text: _error!,
                  action: OutlinedButton(
                      onPressed: _load, child: const Text('Réessayer')),
                )
              : shop == null
                  ? ShopNotice(
                      text: "Cette vitrine n'existe pas, ou n'est pas ouverte.",
                      action: OutlinedButton(
                          onPressed: _directory,
                          child: const Text('Voir les autres vitrines')),
                    )
                  : _Window(
                      shop: shop,
                      items: _items,
                      capture: widget.capture,
                      onOpen: _open,
                      onDirectory: _directory,
                    ),
    );
  }
}

class _Window extends StatelessWidget {
  const _Window({
    required this.shop,
    required this.items,
    required this.capture,
    required this.onOpen,
    required this.onDirectory,
  });

  final PublicShop shop;
  final List<PublicItem> items;
  final CaptureRepository capture;
  final Future<void> Function(String url) onOpen;
  final VoidCallback onDirectory;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(shop.currency);
    final whatsapp = whatsappUrl(shop.phone);
    final phone = (shop.phone ?? '').trim();
    final address = (shop.address ?? '').trim();
    final blurb = (shop.blurb ?? '').trim();
    final width = MediaQuery.sizeOf(context).width;
    final columns = ShopStyle.columnsFor(width);
    final wide = width >= 560;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // The band: who this is, in a word or two, and the one thing to do.
        ColoredBox(
          color: ShopStyle.stone,
          child: ShopWidth(
            padding: EdgeInsets.symmetric(
                horizontal: 20, vertical: wide ? 56 : 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shop.name,
                  style: TextStyle(
                    fontSize: wide ? 40 : 30,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: ShopStyle.ink,
                  ),
                ),
                if (blurb.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(blurb,
                        style: const TextStyle(
                            fontSize: 17,
                            height: 1.45,
                            color: ShopStyle.ink)),
                  ),
                ],
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(address,
                      style: const TextStyle(
                          fontSize: 14, color: ShopStyle.mist)),
                ],
                if (whatsapp != null || phone.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (whatsapp != null)
                        FilledButton(
                          onPressed: () => onOpen(whatsapp),
                          child: const Text('Écrire sur WhatsApp'),
                        ),
                      if (phone.isNotEmpty)
                        OutlinedButton(
                          onPressed: () => onOpen('tel:$phone'),
                          child: const Text('Appeler'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        // The goods.
        ShopWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              ShopSectionLabel(
                'Les articles',
                note: items.isEmpty
                    ? null
                    : '${items.length} article${items.length > 1 ? 's' : ''}',
              ),
              const SizedBox(height: 18),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Aucun article affiché pour le moment.',
                      style: TextStyle(fontSize: 15, color: ShopStyle.mist)),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: wide ? 24 : 14,
                    mainAxisSpacing: wide ? 36 : 26,
                    // Room under the square for a two-line name, the price
                    // and an "Épuisé" — measured, not guessed: 0.74 clipped
                    // the last line on a 390px phone.
                    childAspectRatio: wide ? 0.70 : 0.62,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) =>
                      _ItemTile(item: items[i], money: money, capture: capture),
                ),
              ShopFooter(onDirectory: onDirectory),
            ],
          ),
        ),
      ],
    );
  }
}

/// One article: the photograph on its square, then the name and the price
/// in small type. No frame, no shadow — the square is the frame. Out of
/// stock fades the picture and says so under the price, rather than
/// shouting over it in red.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.money,
    required this.capture,
  });

  final PublicItem item;
  final dynamic money;
  final CaptureRepository capture;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ColoredBox(
              color: ShopStyle.stone,
              child: Opacity(
                opacity: item.inStock ? 1 : 0.45,
                child: _Photo(photoKey: item.photoKey, capture: capture),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: ShopStyle.ink),
        ),
        const SizedBox(height: 3),
        Text(
          money.format(item.price),
          style: const TextStyle(fontSize: 14, color: ShopStyle.mist),
        ),
        if (!item.inStock)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('Épuisé',
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                    color: ShopStyle.mist)),
          ),
      ],
    );
  }
}

/// The article's photo, fetched once through the public read and held for
/// the life of the tile — a rebuild must not refetch a picture on a slow link.
class _Photo extends StatefulWidget {
  const _Photo({required this.photoKey, required this.capture});

  final String? photoKey;
  final CaptureRepository capture;

  @override
  State<_Photo> createState() => _PhotoState();
}

class _PhotoState extends State<_Photo> {
  late final Future<Uint8List>? _bytes = widget.photoKey == null
      ? null
      : widget.capture.publicObjectBytes(widget.photoKey!);

  @override
  Widget build(BuildContext context) {
    const placeholder = Center(
      child: Icon(Icons.image_outlined, size: 34, color: ShopStyle.line),
    );
    final future = _bytes;
    if (future == null) return placeholder;
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return placeholder;
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}
