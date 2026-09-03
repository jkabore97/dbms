import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/format/money.dart';
import '../../core/nav/router.dart';
import '../../core/storefront/storefront_repository.dart';

/// A shop's window, for the street.
///
/// Opened from a link on WhatsApp by somebody with no account, so it asks for
/// nothing: no sign-in, no PIN, no business. It shows what the shop chose to
/// show — its name, a few words, the articles with a photo and a price — and
/// one way to act on it: contact the shop. Nothing is bought here. Phase one
/// of the vitrine is a window, not a till; the till comes when shoppers are
/// actually pulling on the door.
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
      final items =
          shop == null ? const <PublicItem>[] : await widget.storefront.items(widget.slug);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shop = _shop;

    return Scaffold(
      appBar: AppBar(
        title: Text(shop?.name ?? 'Vitrine'),
        actions: [
          IconButton(
            tooltip: 'Toutes les vitrines',
            icon: const Icon(Icons.storefront_outlined),
            onPressed: () => context.go(Routes.directory),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _Notice(
                  icon: Icons.cloud_off_outlined,
                  text: _error!,
                  action: TextButton(
                      onPressed: _load, child: const Text('Réessayer')),
                )
              : shop == null
                  ? const _Notice(
                      icon: Icons.storefront_outlined,
                      text: "Cette vitrine n'existe pas, ou n'est pas ouverte.",
                    )
                  : _Window(
                      shop: shop,
                      items: _items,
                      capture: widget.capture,
                      onOpen: _open,
                      theme: theme,
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
    required this.theme,
  });

  final PublicShop shop;
  final List<PublicItem> items;
  final CaptureRepository capture;
  final Future<void> Function(String url) onOpen;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(shop.currency);
    final whatsapp = whatsappUrl(shop.phone);
    final phone = (shop.phone ?? '').trim();
    final address = (shop.address ?? '').trim();
    final blurb = (shop.blurb ?? '').trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Who this is and how to reach them — the one action of the window.
        Text(shop.name, style: theme.textTheme.headlineSmall),
        if (blurb.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(blurb, style: theme.textTheme.bodyLarge),
        ],
        if (address.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place_outlined,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(address,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
        ],
        if (whatsapp != null || phone.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (whatsapp != null)
                FilledButton.icon(
                  onPressed: () => onOpen(whatsapp),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                ),
              if (phone.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => onOpen('tel:$phone'),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Appeler'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 22),

        // The articles.
        if (items.isEmpty)
          Text('Aucun article affiché pour le moment.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.76,
            children: [
              for (final item in items)
                _ItemCard(item: item, money: money, capture: capture),
            ],
          ),

        const SizedBox(height: 28),
        Center(
          child: Text(
            'Vitrine propulsée par Kaj',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.money,
    required this.capture,
  });

  final PublicItem item;
  final dynamic money;
  final CaptureRepository capture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Photo(photoKey: item.photoKey, capture: capture),
                if (!item.inStock)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Épuisé',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  money.format(item.price),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The article's photo, fetched once through the public read and held for
/// the life of the card — a rebuild must not refetch a picture on a slow link.
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
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.image_outlined,
            size: 34, color: theme.colorScheme.onSurfaceVariant),
      ),
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

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
