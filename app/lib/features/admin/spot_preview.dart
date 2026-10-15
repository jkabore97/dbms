import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import '../../core/theme/mara_mark.dart';
import '../storefront/directory_screen.dart' show SponsoredTag;
import '../storefront/shop_style.dart';

/// « Voir à quoi ça ressemble » (142): the home street, small, drawn with
/// the street's own pieces — its ink, its stone squares, its « Sponsorisé »
/// tag — with this business's spot where it would be: its article first in
/// « À la une », or its card first in the list of vitrines. Not a picture:
/// the business's own name, photo and price, in the reader's language and
/// at the reader's text size.
///
/// The other places are drawn as quiet blanks, never as another business:
/// the preview shows where the spot goes, not who it pushes down.
class SpotPreview extends StatelessWidget {
  const SpotPreview({
    super.key,
    required this.shop,
    required this.businessName,
    required this.profile,
    this.articleName,
    this.articlePrice,
    this.photoKey,
    this.photo,
  });

  /// The whole vitrine's spot, or one article's.
  final bool shop;
  final String businessName;

  /// 'retail' · 'farm' · 'association' (or the older 'church').
  final String profile;
  final String? articleName;

  /// The article's price as the street writes it (« 25 000 FCFA »).
  final String? articlePrice;

  /// The article's (or, for the vitrine, its first article's) photo.
  final String? photoKey;
  final Future<Uint8List> Function(String key)? photo;

  bool get _association => profile == 'association' || profile == 'church';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      key: const Key('spot-preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: shop
              ? context.tr('Aperçu : {name} en tête de la liste des vitrines, marqué Sponsorisé', {'name': businessName})
              : context.tr('Aperçu : {name} en tête de « À la une », marqué Sponsorisé', {'name': articleName ?? businessName}),
          child: ExcludeSemantics(
            child: Container(
              decoration: BoxDecoration(
                color: ShopStyle.paper,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: ShopStyle.line, width: 1.2),
                boxShadow: const [
                  BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 6)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _bar(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                    child: shop ? _street(context) : _featured(context),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          shop
              ? switch (profile) {
                  'farm' => context.tr('Votre ferme apparaît en premier dans la liste des vitrines de la page d\'accueil de Marakaj, avec le badge « Sponsorisé ».'),
                  'association' || 'church' => context.tr('Votre association apparaît en premier dans la liste des vitrines de la page d\'accueil de Marakaj, avec le badge « Sponsorisé ».'),
                  _ => context.tr('Votre boutique apparaît en premier dans la liste des vitrines de la page d\'accueil de Marakaj, avec le badge « Sponsorisé ».'),
                }
              : context.tr('Votre article apparaît en premier dans « À la une », en haut de la page d\'accueil de Marakaj, avec le badge « Sponsorisé ».'),
          key: const Key('spot-preview-what'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('Pendant 7 jours, pour tous ceux qui ouvrent Marakaj, sur le site et dans l\'application. Vous voyez ses vues et ses commandes dans « Mettre en avant ».'),
          style: muted,
        ),
      ],
    );
  }

  /// The street's top: « marakaj » and its search, as the shopper sees them.
  Widget _bar(BuildContext context) => Container(
        color: maraDeep,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            const Text('marakaj',
                style: TextStyle(
                    color: maraCaramel, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0x26FFFFFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(Icons.search, size: 15, color: Color(0xCCFFFFFF)),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _label(BuildContext context, String text, {String? note}) => Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: ShopStyle.ink)),
          ),
          if (note != null) ...[
            const SizedBox(width: 8),
            Text(note, maxLines: 1, style: const TextStyle(fontSize: 12, color: ShopStyle.mist)),
          ],
        ],
      );

  /// « À la une »: the business's article first, then a blank.
  Widget _featured(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, context.tr('À la une'), note: context.tr('Sponsorisé')),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - 12) / 2;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                key: const Key('spot-preview-first'),
                width: w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _Picture(photoKey: photoKey, photo: photo, icon: Icons.image_outlined),
                            const Positioned(left: 6, top: 6, child: SponsoredTag()),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(articleName ?? context.tr('Votre article'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, height: 1.25, color: ShopStyle.ink)),
                    if (articlePrice != null)
                      Text(articlePrice!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: ShopStyle.mist)),
                    Text(businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ShopStyle.mist)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(width: w, child: const _Blank(square: 1)),
            ],
          );
        }),
        const SizedBox(height: 14),
        _label(context, context.tr('Toutes les vitrines')),
        const SizedBox(height: 8),
        const _BlankRow(),
      ],
    );
  }

  /// The list of vitrines: the business's card first, then a blank.
  Widget _street(BuildContext context) {
    final kind = switch (profile) {
      'farm' => context.tr('Ferme'),
      'association' || 'church' => context.tr('Association'),
      _ => context.tr('Boutique'),
    };
    final icon = switch (profile) {
      'farm' => Icons.agriculture_outlined,
      'association' || 'church' => Icons.groups_outlined,
      _ => Icons.storefront_outlined,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, context.tr('Toutes les vitrines')),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - 12) / 2;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                key: const Key('spot-preview-first'),
                width: w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1.15,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _Picture(photoKey: photoKey, photo: photo, icon: icon),
                            const Positioned(left: 6, top: 6, child: SponsoredTag()),
                            if (_association)
                              Positioned(
                                left: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: maraDeep, borderRadius: BorderRadius.circular(999)),
                                  child: Text(context.tr('Association'),
                                      style: const TextStyle(
                                          fontSize: 10, fontWeight: FontWeight.w700, color: maraCaramel)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, height: 1.25, color: ShopStyle.ink)),
                    Text(kind,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: ShopStyle.mist)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(width: w, child: const _Blank(square: 1.15)),
            ],
          );
        }),
        const SizedBox(height: 12),
        const _BlankRow(),
      ],
    );
  }
}

/// The business's photo when it has one; its kind's icon on stone else.
/// Asked once per photo, not at every rebuild of the sheet.
class _Picture extends StatefulWidget {
  const _Picture({required this.photoKey, required this.photo, required this.icon});

  final String? photoKey;
  final Future<Uint8List> Function(String key)? photo;
  final IconData icon;

  @override
  State<_Picture> createState() => _PictureState();
}

class _PictureState extends State<_Picture> {
  Future<Uint8List>? _bytes;
  String? _for;

  Future<Uint8List>? _load() {
    final key = widget.photoKey;
    final load = widget.photo;
    if (key == null || load == null) return null;
    if (key != _for) {
      _for = key;
      _bytes = load(key);
    }
    return _bytes;
  }

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: ShopStyle.stone,
      child: Center(child: Icon(widget.icon, size: 30, color: ShopStyle.mist)),
    );
    final bytes = _load();
    if (bytes == null) return fallback;
    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snap) => snap.hasData
          ? ColoredBox(
              color: ShopStyle.stone,
              child: Image.memory(snap.data!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  key: const Key('spot-preview-photo'),
                  errorBuilder: (_, _, _) => fallback),
            )
          : fallback,
    );
  }
}

/// Another place on the street, as a quiet blank.
class _Blank extends StatelessWidget {
  const _Blank({required this.square});

  final double square;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: square,
            child: Container(
              decoration: BoxDecoration(color: ShopStyle.stone, borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(height: 8),
          FractionallySizedBox(
            widthFactor: 0.8,
            child: Container(height: 9, decoration: BoxDecoration(color: ShopStyle.line, borderRadius: BorderRadius.circular(4))),
          ),
          const SizedBox(height: 6),
          FractionallySizedBox(
            widthFactor: 0.5,
            child: Container(height: 8, decoration: BoxDecoration(color: ShopStyle.line, borderRadius: BorderRadius.circular(4))),
          ),
        ],
      );
}

class _BlankRow extends StatelessWidget {
  const _BlankRow();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 34,
                decoration: BoxDecoration(color: ShopStyle.stone, borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ],
        ],
      );
}
