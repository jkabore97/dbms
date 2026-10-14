import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/store_rules.dart';
import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/retail/duration.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/theme/mara_mark.dart';
import 'package:kaj_app/core/theme/mara_sheet.dart';
import '../../core/nav/app_scope.dart';
import '../capture/capture_action.dart';
import 'photo_quota.dart';
import 'product_photo.dart';

/// What an item says before it is ordered (136, batch 141): its words —
/// the « Décrivez-le en quelques mots » step of every add flow and the
/// same field in every edit sheet — and its photos, the first its cover.
/// One file for the shop, the farm and the association, goods and services.

/// The example under the field, in the kind's own words.
String describeExample(BuildContext context, OrgSummary org, {bool service = false}) {
  if (service) return context.tr('Coupe, shampoing et coiffage, environ 45 min');
  if (org.isAssociation) return context.tr('Salle de 80 places, chaises et sono comprises');
  if (org.profile == 'farm') return context.tr('Poulets élevés en plein air, 45 jours, environ 1,8 kg');
  return context.tr('Coton, taille M à XL, lavable en machine');
}

/// How long a description is, as Postgres counts it (char_length: code
/// points, so a flag is 2 and an emoji 1) — the add flows, the field's
/// counter and the database say the same number.
int descriptionLength(String text) => text.runes.length;

/// Keeps a text to [max] code points (a paste cut, typing stopped).
class RuneLimitFormatter extends TextInputFormatter {
  RuneLimitFormatter(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (descriptionLength(newValue.text) <= max) return newValue;
    if (descriptionLength(oldValue.text) >= max && newValue.text.length >= oldValue.text.length) {
      return oldValue;
    }
    final cut = String.fromCharCodes(newValue.text.runes.take(max));
    return TextEditingValue(text: cut, selection: TextSelection.collapsed(offset: cut.length));
  }
}

/// A few lines, up to [maxLength] (1,000 since 136, 300 before) counted as
/// the database counts them, with its counter and the kind's example. Line
/// breaks are kept: the vitrine shows them as written.
class DescriptionField extends StatelessWidget {
  const DescriptionField({
    super.key,
    required this.controller,
    required this.example,
    required this.maxLength,
    this.label,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String example;
  final int maxLength;
  final String? label;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      minLines: 3,
      maxLines: 8,
      maxLength: maxLength,
      // Counted in code points by the formatter, as Postgres counts.
      maxLengthEnforcement: MaxLengthEnforcement.none,
      inputFormatters: [RuneLimitFormatter(maxLength)],
      buildCounter: (context, {required currentLength, required isFocused, maxLength}) => Text(
        '${descriptionLength(controller.text)}/$maxLength',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: context.tr('Par exemple : {example}', {'example': example}),
        hintMaxLines: 3,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// A service's duration, one tap each, or typed in minutes (136).
class DurationPicker extends StatefulWidget {
  const DurationPicker({
    super.key,
    required this.minutes,
    required this.onChanged,
    this.enabled = true,
  });

  final int? minutes;
  final ValueChanged<int?> onChanged;
  final bool enabled;

  /// The lengths offered (the flow's since 115, « 45 min » and « 1 h 30 »
  /// added); a half day reads 4 h, a day 8 h.
  static const choices = [15, 30, 45, 60, 90, 120, 240, 480];

  @override
  State<DurationPicker> createState() => _DurationPickerState();
}

class _DurationPickerState extends State<DurationPicker> {
  late bool _other =
      widget.minutes != null && !DurationPicker.choices.contains(widget.minutes);
  late final _typed = TextEditingController(
      text: _other && widget.minutes != null ? '${widget.minutes}' : '');

  /// The column's range (1 minute to 7 days).
  static const _most = 10080;

  /// Typed but not a duration the server takes: said, not dropped.
  bool get _outOfRange {
    final m = int.tryParse(_typed.text.trim());
    return _typed.text.trim().isNotEmpty && (m == null || m < 1 || m > _most);
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  String _label(BuildContext context, int m) => switch (m) {
        240 => context.tr('une demi-journée'),
        480 => context.tr('une journée'),
        _ => formatDuration(m),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in DurationPicker.choices)
              ChoiceChip(
                key: ValueKey('duration-$m'),
                label: Text(_label(context, m), style: const TextStyle(fontSize: 16)),
                selected: !_other && widget.minutes == m,
                onSelected: !widget.enabled
                    ? null
                    : (on) {
                        setState(() => _other = false);
                        widget.onChanged(on ? m : null);
                      },
              ),
            ChoiceChip(
              key: const ValueKey('duration-other'),
              label: Text(context.tr('Autre'), style: const TextStyle(fontSize: 16)),
              selected: _other,
              onSelected: !widget.enabled
                  ? null
                  : (on) {
                      setState(() => _other = on);
                      widget.onChanged(on ? int.tryParse(_typed.text.trim()) : null);
                    },
            ),
          ],
        ),
        if (_other) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('duration-minutes'),
            controller: _typed,
            enabled: widget.enabled,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 5,
            onChanged: (v) {
              final m = int.tryParse(v.trim());
              setState(() {});
              widget.onChanged(m != null && m >= 1 && m <= _most ? m : null);
            },
            decoration: InputDecoration(
              labelText: context.tr('En minutes'),
              errorText: _outOfRange ? context.tr('De 1 à 10 080 minutes (7 jours).') : null,
              errorMaxLines: 2,
              hintText: '45',
              suffixText: 'min',
              counterText: '',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }
}

/// « Plusieurs photos par article » is Mara Pro's (136): the door, as the
/// other Pro tools open it — the Pro page where Pro is sold, its plain
/// words where it is not (the iPhone app, 125).
class MorePhotosProSheet extends StatelessWidget {
  const MorePhotosProSheet({super.key, required this.org});

  final OrgSummary org;

  static Future<void> open(BuildContext context, OrgSummary org) => showMaraSheet<void>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (_) => MorePhotosProSheet(org: org),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('more-photos-pro'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: maraDeep,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.collections_outlined, color: maraCaramel, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(context.tr('Plusieurs photos par article'),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              context.tr('Avec Mara Pro, un article montre plusieurs photos : vos clients les font défiler sur la vitrine avant de commander. Sans Pro, un article garde une photo.'),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 18),
            if (sellsProInApp)
              FilledButton(
                key: const Key('more-photos-pro-open'),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(Routes.inside(org.id, 'kaj-pro'));
                },
                child: Text(context.tr('Découvrir Mara Pro')),
              )
            else
              FilledButton(
                key: const Key('more-photos-pro-close'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('Fermer')),
              ),
          ],
        ),
      ),
    );
  }
}

/// The item's photos in a row (136) — the sheet's one photo control: the
/// cover first (« Remplacer la photo »), « Mettre en premier », a long press
/// to drag, « Retirer », and « + » for one more — the first as 100's photo
/// places allow, Mara Pro's past it (the door on Basic), up to
/// max_item_photos_pro. Every change goes to the server at once.
///
/// Drawn on a database with 136; when the gallery cannot be read it says
/// so through [onUnavailable] and draws nothing, and the sheet shows its
/// older photo button instead.
class ItemPhotoStrip extends StatefulWidget {
  const ItemPhotoStrip({
    super.key,
    required this.org,
    required this.retail,
    required this.capture,
    required this.productId,
    required this.name,
    this.onChanged,
    this.onUnavailable,
    this.initial,
  });

  final OrgSummary org;
  final RetailRepository retail;
  final CaptureRepository capture;
  final String productId;
  final String name;

  /// After any change, the gallery as it now is: the cover may be another,
  /// the item may have gained or lost its only photo.
  final ValueChanged<ItemGallery>? onChanged;

  /// The gallery could not be read (a database before 136, no network):
  /// the sheet's older photo button takes over.
  final VoidCallback? onUnavailable;

  /// A gallery already read (a test gives it); null reads it.
  final ItemGallery? initial;

  @override
  State<ItemPhotoStrip> createState() => _ItemPhotoStripState();
}

class _ItemPhotoStripState extends State<ItemPhotoStrip> {
  ItemGallery? _gallery;
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _gallery = widget.initial;
    if (_gallery == null) _load();
  }

  Future<void> _load() async {
    try {
      final g = await widget.retail.gallery(widget.productId);
      if (!mounted) return;
      setState(() {
        _gallery = g;
        _failed = g == null;
      });
      if (g == null) widget.onUnavailable?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onUnavailable?.call();
    }
  }

  /// [restore]: what to draw again when the server refuses (a drag drawn
  /// at once in its new place).
  Future<void> _run(Future<ItemGallery?> Function() call, {ItemGallery? restore}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final g = await call();
      if (!mounted) return;
      if (g != null) {
        setState(() => _gallery = g);
        widget.onChanged?.call(g);
      }
    } catch (e) {
      if (mounted && restore != null) setState(() => _gallery = restore);
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final g = _gallery;
    if (g == null || _busy) return;
    if (!g.hasRoom) {
      if (g.coverOnly) {
        await MorePhotosProSheet.open(context, widget.org);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('Pas plus de {n} photos par article.', {'n': g.limit})),
      ));
      return;
    }
    final first = g.photos.isEmpty;
    // The item's first photo takes one of a Basic business's places (100).
    if (first && (!await photoAllowed(context, widget.org, hasPhoto: false) || !mounted)) return;
    final picked = await CaptureAction.pick(context, orgId: widget.org.id, photos: widget.capture);
    if (picked == null || !mounted) return;
    final session = AppScope.read(context)?.session;
    final messenger = ScaffoldMessenger.of(context);
    final waits = context.tr('Photo gardée, en attente de réseau. Une fois envoyée, liez-la à l\'article depuis Documents.');
    await _run(() async {
      final from = picked.from;
      // A photo from « Photos » about nothing yet goes on as it is; any
      // other is sent as the item's own (as CaptureAction.hang does).
      String? id;
      if (from != null && from.productId == null && from.entryId == null) {
        id = from.id;
      } else {
        id = await widget.capture.capture(
          orgId: widget.org.id,
          bytes: picked.bytes,
          contentType: picked.contentType,
          kind: 'product_photo',
          caption: widget.name,
        );
      }
      if (id == null) {
        messenger.showSnackBar(SnackBar(content: Text(waits)));
        return null;
      }
      final after = await widget.retail.addPhoto(widget.productId, id);
      if (first) await session?.reloadFeatures(widget.org.id);
      return after;
    });
  }

  /// « Remplacer la photo »: the cover, as « Changer la photo » always did —
  /// the new photo filed on the item takes the cover's place (136's
  /// documents trigger); the old one stays in Photos.
  Future<void> _replace() async {
    final picked = await CaptureAction.pick(context, orgId: widget.org.id, photos: widget.capture);
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final waits = context.tr('Photo gardée, en attente de réseau. Une fois envoyée, liez-la à l\'article depuis Documents.');
    await _run(() async {
      final id = await CaptureAction.hang(
        widget.capture,
        orgId: widget.org.id,
        productId: widget.productId,
        name: widget.name,
        photo: picked,
        hadPhoto: true,
      );
      if (id == null) {
        messenger.showSnackBar(SnackBar(content: Text(waits)));
        return null;
      }
      return widget.retail.gallery(widget.productId);
    });
  }

  Future<void> _first(GalleryPhoto p) async {
    final g = _gallery!;
    final ids = [p.documentId, for (final q in g.photos) if (q.documentId != p.documentId) q.documentId];
    await _run(() => widget.retail.orderPhotos(widget.productId, ids));
  }

  Future<void> _move(int from, int to) async {
    final g = _gallery!;
    final list = [...g.photos];
    final p = list.removeAt(from);
    list.insert(to, p);
    // Drawn at once in its new place; the server's answer follows (refused,
    // the order it keeps is drawn again).
    setState(() => _gallery = ItemGallery(photos: list, limit: g.limit));
    await _run(() => widget.retail.orderPhotos(widget.productId, [for (final q in list) q.documentId]),
        restore: g);
  }

  Future<void> _remove(GalleryPhoto p) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        key: const Key('item-photo-remove-confirm'),
        title: Text(dialog.tr('Retirer cette photo ?')),
        content: Text(dialog.tr('Elle quitte l\'article et la vitrine, et reste dans vos Photos.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(dialog.tr('Retour')),
          ),
          FilledButton(
            key: const Key('item-photo-remove-yes'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(dialog.tr('Retirer')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _run(() => widget.retail.removePhoto(widget.productId, p.documentId));
  }

  Future<void> _menu(GalleryPhoto p, int index) async {
    final choice = await showMaraSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index == 0)
              ListTile(
                key: const Key('item-photo-replace'),
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(sheet.tr('Remplacer la photo')),
                subtitle: Text(sheet.tr('La photo paraît sur la vitrine et dans la recherche.')),
                onTap: () => Navigator.of(sheet).pop('replace'),
              ),
            if (index > 0)
              ListTile(
                key: const Key('item-photo-first'),
                leading: const Icon(Icons.star_outline),
                title: Text(sheet.tr('Mettre en premier')),
                subtitle: Text(sheet.tr('La première photo est celle de la vitrine et de la recherche.')),
                onTap: () => Navigator.of(sheet).pop('first'),
              ),
            ListTile(
              key: const Key('item-photo-remove'),
              leading: const Icon(Icons.delete_outline),
              title: Text(sheet.tr('Retirer la photo')),
              onTap: () => Navigator.of(sheet).pop('remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'replace') await _replace();
    if (choice == 'first') await _first(p);
    if (choice == 'remove') await _remove(p);
  }

  @override
  Widget build(BuildContext context) {
    final g = _gallery;
    const side = 76.0;
    if (_failed) return const SizedBox.shrink();
    if (g == null) {
      // Read in a moment: its room kept, so nothing jumps.
      return const Padding(
        key: Key('item-photo-strip-loading'),
        padding: EdgeInsets.only(top: 12),
        child: SizedBox(
          height: side,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    Widget tile(GalleryPhoto p, int i) => Padding(
          key: ValueKey('item-photo-${p.documentId}'),
          padding: const EdgeInsets.only(right: 8),
          child: ReorderableDelayedDragStartListener(
            index: i,
            enabled: !_busy && g.photos.length > 1,
            child: Semantics(
              button: true,
              label: i == 0
                  ? context.tr('Photo {n}, la couverture', {'n': i + 1})
                  : context.tr('Photo {n}', {'n': i + 1}),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _busy ? null : () => _menu(p, i),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: side,
                        height: side,
                        child: ProductPhoto(
                            name: widget.name, photoKey: p.photoKey, capture: widget.capture),
                      ),
                    ),
                    if (i == 0)
                      Positioned(
                        left: 4,
                        right: 4,
                        bottom: 4,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: maraDeep.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(context.tr('Couverture'),
                              maxLines: 1,
                              style: const TextStyle(color: maraPaper, fontSize: 11)),
                        ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
    return Padding(
      key: const Key('item-photo-strip'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            g.coverOnly
                ? context.tr('Photos de l\'article')
                : context.tr('Photos de l\'article · {n} / {limit}', {'n': g.photos.length, 'limit': g.limit}),
            style: theme.textTheme.titleSmall,
          ),
          if (g.photos.length > 1)
            Text(context.tr('Appui long pour déplacer ; la première est la couverture.'),
                style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          SizedBox(
            height: side,
            child: Row(
              children: [
                Flexible(
                  child: ReorderableListView(
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    onReorderItem: _move,
                    children: [for (var i = 0; i < g.photos.length; i++) tile(g.photos[i], i)],
                  ),
                ),
                if (g.coverOnly || g.hasRoom)
                  Semantics(
                    button: true,
                    label: context.tr('Ajouter une photo'),
                    child: InkWell(
                      key: const Key('item-photo-add'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: _busy ? null : _add,
                      child: Container(
                        width: side,
                        height: side,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.colorScheme.outlineVariant),
                        ),
                        child: _busy
                            ? const Center(
                                child: SizedBox(
                                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined,
                                      color: g.hasRoom ? theme.colorScheme.primary : maraBrown),
                                  if (!g.hasRoom)
                                    const Text('Pro',
                                        style: TextStyle(
                                            fontSize: 11, fontWeight: FontWeight.w800, color: maraBrown)),
                                ],
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (g.coverOnly && g.photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.tr('Plusieurs photos par article avec Mara Pro.'),
                  style: theme.textTheme.bodySmall?.copyWith(color: maraBrown)),
            ),
        ],
      ),
    );
  }
}

/// Whether the strip is the sheet's photo control: a build that can send
/// photos, a database with 136 (an item with no photo yet too: its « + »
/// adds the first).
bool photoStripOffered(RetailRepository retail, CaptureRepository? capture) =>
    capture != null && capture.isConfigured && !retail.itemPhotosMissing;
