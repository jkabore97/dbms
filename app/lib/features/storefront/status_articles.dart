import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/mara_mark.dart';
import 'package:kaj_app/core/theme/mara_sheet.dart';
import 'status_card.dart';
import 'storefront_screen.dart' show priceOf;

/// Fetches an article's photograph by its key, at about [width] pixels;
/// null when there is none to have.
typedef StatusPhotoLoader = Future<Uint8List?> Function(String key, {int? width});

/// Which articles the status picture shows (140). The owner: « if you want
/// to make an ad for one product only, the user should have the choice. »
///
/// [ids] empty is « Automatique »: today's rule ([StatusCard.pick]). Up to
/// [max] chosen, in the order they were ticked; with [single] one only —
/// an ad for it. Never remembered: the next share starts on « Automatique »
/// unless it is opened from an article.
@immutable
class StatusSelection {
  const StatusSelection([this.ids = const [], this.single = false]);

  /// The ad of one article, as opened from it.
  StatusSelection.only(String id) : this([id], true);

  final List<String> ids;
  final bool single;

  static const max = 4;

  List<String> get chosen => ids;

  bool get automatic => chosen.isEmpty && !single;

  int get limit => single ? 1 : max;

  /// A tap on [id]: ticked, unticked, or — a fifth — refused (null). One
  /// only: the tap moves the choice.
  StatusSelection? toggle(String id) {
    final now = chosen;
    if (single) return StatusSelection([id], true);
    if (now.contains(id)) return StatusSelection([for (final k in now) if (k != id) k]);
    if (now.length >= max) return null;
    return StatusSelection([...now, id]);
  }

  /// « Un seul produit (annonce) »: on, the first chosen (or the first the
  /// automatic rule would take) stays; off, back to up to four.
  StatusSelection toggleSingle(List<PublicItem> catalogue) {
    if (single) return StatusSelection(chosen);
    final first = chosen.isNotEmpty
        ? chosen.first
        : StatusCard.pick(catalogue).firstOrNull?.id;
    return StatusSelection([?first], true);
  }

  /// The articles the picture shows, in the order chosen; the automatic
  /// rule when none is.
  List<PublicItem> itemsIn(List<PublicItem> catalogue) {
    final byId = {for (final i in catalogue) i.id: i};
    final picked = [for (final id in chosen) ?byId[id]];
    if (picked.isEmpty) return StatusCard.pick(catalogue).take(single ? 1 : max).toList();
    return picked.take(limit).toList();
  }

  @override
  bool operator ==(Object other) =>
      other is StatusSelection &&
      other.single == single &&
      other.chosen.length == chosen.length &&
      [for (var k = 0; k < chosen.length; k++) other.chosen[k] == chosen[k]].every((b) => b);

  @override
  int get hashCode => Object.hash(single, Object.hashAll(chosen));
}

/// The sheet that chooses them: every article and service with its photo,
/// name and price; « Choix automatique », « Un seul produit (annonce) »;
/// a search past twelve; « Articles | Services » when there are both. Each
/// tap changes the picture behind it at once.
class StatusArticlesSheet extends StatefulWidget {
  const StatusArticlesSheet({
    super.key,
    required this.catalogue,
    required this.currency,
    required this.selection,
    required this.onChanged,
    this.photos,
  });

  final List<PublicItem> catalogue;
  final String currency;
  final StatusSelection selection;
  final ValueChanged<StatusSelection> onChanged;
  final StatusPhotoLoader? photos;

  static Future<void> open(
    BuildContext context, {
    required List<PublicItem> catalogue,
    required String currency,
    required StatusSelection selection,
    required ValueChanged<StatusSelection> onChanged,
    StatusPhotoLoader? photos,
  }) =>
      showMaraSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => StatusArticlesSheet(
          catalogue: catalogue,
          currency: currency,
          selection: selection,
          onChanged: onChanged,
          photos: photos,
        ),
      );

  /// Every one a service (140): the sheet says « services », not
  /// « articles ».
  static bool servicesOnly(List<PublicItem> catalogue) =>
      catalogue.isNotEmpty && catalogue.every((i) => i.isService);

  /// The word for what is shared: « services » when every chosen one is a
  /// service (a haircut shared from a shop that also sells goods), else as
  /// the catalogue is — so a service is never called « article ».
  static bool speaksServices(List<PublicItem> catalogue, Iterable<String> chosen) {
    final picked = [for (final i in catalogue) if (chosen.contains(i.id)) i];
    if (picked.isNotEmpty) return picked.every((i) => i.isService);
    return servicesOnly(catalogue);
  }

  @override
  State<StatusArticlesSheet> createState() => _StatusArticlesSheetState();
}

class _StatusArticlesSheetState extends State<StatusArticlesSheet> {
  late StatusSelection _selection = widget.selection;
  final _search = TextEditingController();
  bool _refused = false;

  /// « Articles | Services »: null shows both.
  bool? _services;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _set(StatusSelection s) {
    setState(() {
      _selection = s;
      _refused = false;
    });
    widget.onChanged(s);
  }

  void _tap(PublicItem i) {
    final next = _selection.toggle(i.id);
    if (next == null) {
      setState(() => _refused = true);
      return;
    }
    _set(next);
  }

  bool get _both =>
      widget.catalogue.any((i) => i.isService) && widget.catalogue.any((i) => !i.isService);

  List<PublicItem> get _shown {
    final q = foldSearchText(_search.text.trim());
    return [
      for (final i in widget.catalogue)
        if ((_services == null || i.isService == _services) &&
            (q.isEmpty || foldSearchText(i.name).contains(q)))
          i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(widget.currency);
    final chosen = _selection.chosen;
    final services = StatusArticlesSheet.speaksServices(widget.catalogue, chosen);
    // What the picture shows: a chosen one gone from the catalogue since
    // is not counted.
    final counted = chosen.where((id) => widget.catalogue.any((i) => i.id == id)).length;
    final soldOut = widget.catalogue.any((i) => chosen.contains(i.id) && !i.inStock);
    final shown = _shown;
    final label = theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w800, letterSpacing: 1.1, color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      key: const Key('status-articles'),
      // Clear of the phone's home bar: a bottom sheet's safe area pads
      // the top only, and « Terminé » sat under the iPhone's line.
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 12 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(services ? context.tr('Services du statut') : context.tr('Articles du statut'),
                    maxLines: 2,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Text(
                _selection.automatic ? context.tr('Automatique') : '$counted/${_selection.limit}',
                key: const Key('status-articles-count'),
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _refused ? theme.colorScheme.error : null),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _refused
                ? (services
                    ? context.tr('4 services au plus : retirez-en un d\'abord.')
                    : context.tr('4 articles au plus : retirez-en un d\'abord.'))
                : _selection.single
                    ? (services
                        ? context.tr('Une annonce pour un seul service : touchez celui à montrer.')
                        : context.tr('Une annonce pour un seul article : touchez celui à montrer.'))
                    : (services
                        ? context.tr('Touchez jusqu\'à 4 services, dans l\'ordre où ils paraîtront.')
                        : context.tr('Touchez jusqu\'à 4 articles, dans l\'ordre où ils paraîtront.')),
            key: const Key('status-articles-hint'),
            style: theme.textTheme.bodySmall?.copyWith(
                color: _refused ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                key: const Key('status-articles-auto'),
                // Chosen reads at a glance: ink with white words, no tick
                // drawn over the icon.
                showCheckmark: false,
                selectedColor: theme.colorScheme.primary,
                labelStyle: _selection.automatic
                    ? TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w700)
                    : null,
                avatar: Icon(Icons.auto_awesome_outlined,
                    size: 18,
                    color: _selection.automatic ? theme.colorScheme.onPrimary : null),
                label: Text(context.tr('Choix automatique')),
                selected: _selection.automatic,
                onSelected: (_) => _set(const StatusSelection()),
              ),
              ChoiceChip(
                key: const Key('status-articles-single'),
                // Chosen reads at a glance: ink with white words, no tick
                // drawn over the icon.
                showCheckmark: false,
                selectedColor: theme.colorScheme.primary,
                labelStyle: _selection.single
                    ? TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w700)
                    : null,
                avatar: Icon(Icons.campaign_outlined,
                    size: 18,
                    color: _selection.single ? theme.colorScheme.onPrimary : null),
                label: Text(services
                    ? context.tr('Un seul service (annonce)')
                    : context.tr('Un seul produit (annonce)')),
                selected: _selection.single,
                onSelected: (_) => _set(_selection.toggleSingle(widget.catalogue)),
              ),
            ],
          ),
          if (_both) ...[
            const SizedBox(height: 8),
            SegmentedButton<bool?>(
              key: const Key('status-articles-kind'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: null, label: Text(context.tr('Tout'))),
                ButtonSegment(value: false, label: Text(context.tr('Articles'))),
                ButtonSegment(value: true, label: Text(context.tr('Services'))),
              ],
              selected: {_services},
              onSelectionChanged: (s) => setState(() => _services = s.first),
            ),
          ],
          if (widget.catalogue.length > 12) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('status-articles-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: context.tr('Chercher…'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (soldOut) ...[
            const SizedBox(height: 8),
            Text(
              context.tr('Un article épuisé paraît « Épuisé » sur l\'image.'),
              key: const Key('status-articles-soldout'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            (_services == true || services
                    ? context.tr('Services')
                    : _services == null && _both
                        ? context.tr('Articles et services')
                        : context.tr('Articles'))
                .toUpperCase(),
            style: label,
          ),
          const SizedBox(height: 2),
          Flexible(
            child: shown.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(context.tr('Rien ne répond à cette recherche.'),
                        textAlign: TextAlign.center),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: shown.length,
                    itemBuilder: (context, k) {
                      final i = shown[k];
                      final order = chosen.indexOf(i.id);
                      return _Row(
                        key: Key('status-article-${i.id}'),
                        item: i,
                        price: priceOf(money, i, context.trLanguage),
                        order: order < 0 ? null : order + 1,
                        single: _selection.single,
                        photos: widget.photos,
                        onTap: () => _tap(i),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('status-articles-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('Terminé')),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.item,
    required this.price,
    required this.order,
    required this.single,
    required this.onTap,
    this.photos,
  });

  final PublicItem item;
  final String price;

  /// Its place among the chosen, from 1; null when not chosen.
  final int? order;
  final bool single;
  final VoidCallback onTap;
  final StatusPhotoLoader? photos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = order != null;
    final state = !item.inStock
        ? context.tr('Épuisé')
        : item.isService
            ? context.tr('Sur rendez-vous')
            : null;
    return Semantics(
      selected: on,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 48,
                  child: _Thumb(item: item, photos: photos),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      [price, ?state].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // The order it was ticked in: what the picture follows.
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // A round for one only, a square to number: radii, so the
                  // change animates (a circle and a radius do not tween).
                  borderRadius: BorderRadius.circular(single ? 15 : 8),
                  color: on ? maraCaramel : Colors.transparent,
                  border: Border.all(color: on ? maraCaramel : theme.colorScheme.outline, width: 2),
                ),
                child: on
                    ? (single
                        ? const Icon(Icons.check, size: 18, color: maraBlack)
                        : Text('$order',
                            style: const TextStyle(
                                color: maraBlack, fontWeight: FontWeight.w900, fontSize: 15)))
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row's small photograph, or its first letter.
class _Thumb extends StatefulWidget {
  const _Thumb({required this.item, this.photos});

  final PublicItem item;
  final StatusPhotoLoader? photos;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    final key = widget.item.photoKey;
    final load = widget.photos;
    if (key != null && load != null) {
      load(key, width: 120).then((b) {
        if (mounted && b != null) setState(() => _bytes = b);
      }, onError: (Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true,
          errorBuilder: (_, _, _) => _letter(context));
    }
    return _letter(context);
  }

  Widget _letter(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.item.name.trim();
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      ),
    );
  }
}
