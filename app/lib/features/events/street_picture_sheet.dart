import 'package:flutter/material.dart';

import '../../core/events/street_event.dart';
import '../../core/l10n/tr.dart';
import 'events_screens.dart' show streetGalleryUrl;

/// The event's picture on the street (175), as its row says it: null for the
/// automatic one, `'fete:<name>'` for a gallery picture, a key for one of the
/// card's own pictures.
String streetPictureLabel(BuildContext context, String? choice) {
  if (choice == null) return context.tr('Automatique : l’aperçu de votre carte, sinon sa photo ou celle de son type d’événement.');
  if (choice.startsWith('fete:')) return context.tr('Une photo de la galerie Marakaj.');
  return context.tr('Une photo de votre carte.');
}

/// « Photo sur la rue » (175): the organiser chooses the picture shown on the
/// street's « Événements » — automatic, one of the card's own pictures, or a
/// picture of Marakaj's gallery (the event's kind's first). Answers the
/// choice ((choice: null) for automatic), or null when closed untouched.
Future<({String? choice})?> showStreetPictureSheet(
  BuildContext context, {
  required String? current,
  required String kind,
  required List<String> ownKeys,
  required String? Function(String key) ownUrl,
}) {
  return showModalBottomSheet<({String? choice})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StreetPictureSheet(current: current, kind: kind, ownKeys: ownKeys, ownUrl: ownUrl),
  );
}

class StreetPictureSheet extends StatelessWidget {
  const StreetPictureSheet({
    super.key,
    required this.current,
    required this.kind,
    required this.ownKeys,
    required this.ownUrl,
  });

  final String? current;
  final String kind;

  /// The card's own stored pictures (the organiser's).
  final List<String> ownKeys;
  final String? Function(String key) ownUrl;

  /// The gallery, the event's kind's picture first.
  List<String> get gallery {
    final mine = streetPictureOfKind(kind);
    return [mine, for (final g in streetGallery) if (g != mine) g];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void pick(String? choice) => Navigator.of(context).pop((choice: choice));
    Widget grid(List<Widget> tiles) => GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: tiles,
        );
    final own = [
      for (final k in ownKeys)
        if (ownUrl(k) case final url?) (key: k, url: url),
    ];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      maxChildSize: .95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Text(context.tr('Photo sur la rue'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(context.tr('La photo de votre événement dans « Événements », sur la rue de Marakaj.'),
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          ListTile(
            key: const Key('street-picture-auto'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(current == null ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: current == null ? theme.colorScheme.primary : null),
            onTap: () => pick(null),
            title: Text(context.tr('Automatique')),
            subtitle: Text(context.tr('L’aperçu de votre carte, telle que vos invités la voient.')),
          ),
          const SizedBox(height: 8),
          Text(context.tr('Mes photos'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (own.isEmpty)
            Text(context.tr('Ajoutez une photo sur votre carte (« Modifier la carte ») : elle apparaîtra ici.'),
                key: const Key('street-picture-own-none'), style: theme.textTheme.bodySmall)
          else
            grid([
              for (final o in own)
                _Choice(
                  key: Key('street-picture-own-${o.key}'),
                  url: o.url,
                  chosen: current == o.key,
                  onTap: () => pick(o.key),
                ),
            ]),
          const SizedBox(height: 18),
          Text(context.tr('Galerie Marakaj'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          grid([
            for (final g in gallery)
              _Choice(
                key: Key('street-picture-fete-$g'),
                url: streetGalleryUrl(g),
                chosen: current == 'fete:$g',
                onTap: () => pick('fete:$g'),
              ),
          ]),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.url, required this.chosen, required this.onTap});

  final String url;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(color: Colors.black.withValues(alpha: .06)),
          Image.network(url, fit: BoxFit.cover, cacheWidth: 360, errorBuilder: (_, _, _) => const SizedBox()),
          if (chosen) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 4),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: CircleAvatar(radius: 12, backgroundColor: color, child: const Icon(Icons.check, size: 16, color: Colors.white)),
            ),
          ],
        ]),
      ),
    );
  }
}
