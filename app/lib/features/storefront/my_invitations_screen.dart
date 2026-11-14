import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/events/events_repository.dart' show EventsException;
import '../../core/events/invitations_repository.dart';
import '../../core/events/street_event.dart' show eventCountdown;
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../events/events_screens.dart' show eventSiteOrigin, openSitePage;
import 'shop_style.dart';

/// A photo chosen on the phone, ready to send.
typedef PickedPhoto = ({Uint8List bytes, String type});

/// The phone's gallery (183): at most [limit] photos, made smaller first —
/// a party's photo reads well at 1600 px, and a market's line carries it.
/// A browser's picker ignores the limit: one more than it is read then, so
/// the caller knows some were left out and says so.
Future<List<PickedPhoto>> pickGuestPhotos(int limit) async {
  final picker = ImagePicker();
  final files = limit >= 2
      ? await picker.pickMultiImage(maxWidth: 1600, imageQuality: 80, limit: limit)
      : [?await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80)];
  return [
    for (final f in files.take(limit + 1))
      (
        bytes: await f.readAsBytes(),
        type: switch (f.mimeType ?? '') {
          'image/png' => 'image/png',
          'image/webp' => 'image/webp',
          _ => f.name.toLowerCase().endsWith('.png')
              ? 'image/png'
              : f.name.toLowerCase().endsWith('.webp')
                  ? 'image/webp'
                  : 'image/jpeg',
        },
      ),
  ];
}

/// « Ajouter des photos » for one confirmed card: no more than are left of
/// the five, sent one after the other (each counted by the server after
/// those before it). Says what happened; returns how many went.
Future<int> addInvitationPhotos(
  BuildContext context,
  InvitationsRepository repo,
  MyInvitation inv, {
  Future<List<PickedPhoto>> Function(int limit)? pick,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final full = context.tr('Vous avez déposé vos {n} photos : c’est le maximum par invité.', {'n': inv.photosLimit});
  final net = context.tr('Pas de réseau : réessayez.');
  final review = inv.albumReview;
  String said(int n) => review
      ? (n > 1
          ? context.tr('{n} photos envoyées : visibles après validation.', {'n': n})
          : context.tr('Photo envoyée : visible après validation.'))
      : (n > 1 ? context.tr('{n} photos ajoutées à l’album.', {'n': n}) : context.tr('Photo ajoutée à l’album.'));
  void say(String m) => messenger?.showSnackBar(SnackBar(content: Text(m)));
  final left = inv.photosLeft;
  final cutSaid = context.tr('Seules vos {n} premières photos sont envoyées (5 par invité).', {'n': left});
  if (left == 0) {
    say(full);
    return 0;
  }
  List<PickedPhoto> files;
  try {
    files = await (pick ?? pickGuestPhotos)(left);
  } catch (_) {
    return 0;
  }
  if (files.isEmpty) return 0;
  var sent = 0;
  String? refused;
  for (final f in files.take(left)) {
    try {
      await repo.addPhoto(inv.slug, f.bytes, f.type);
      sent++;
    } on EventsException catch (e) {
      refused = e.message;
      break;
    } catch (_) {
      refused = net;
      break;
    }
  }
  // more chosen than are left (a browser's picker has no limit): said
  final cut = files.length > left && refused == null ? cutSaid : null;
  if (sent > 0) {
    say(refused == null ? (cut == null ? said(sent) : '${said(sent)} — $cut') : '${said(sent)} — $refused');
  } else if (refused != null) {
    say(refused);
  }
  return sent;
}

/// « Mes invitations » (183): the cards this account confirmed, shown as
/// « Mes billets » shows tickets — the title, the day on the card's own
/// clock, the place, the card's picture — each with « Voir l'invitation »
/// and « Ajouter des photos » (five per guest), and the guest's own photos.
class MyInvitationsScreen extends StatefulWidget {
  const MyInvitationsScreen({super.key, required this.repo, this.open, this.pick, this.now});

  final InvitationsRepository repo;

  /// Opens the card on the site (the tests look).
  final Future<void> Function(Uri uri)? open;

  /// The gallery (the tests answer it).
  final Future<List<PickedPhoto>> Function(int limit)? pick;
  final DateTime Function()? now;

  @override
  State<MyInvitationsScreen> createState() => _MyInvitationsScreenState();
}

class _MyInvitationsScreenState extends State<MyInvitationsScreen> {
  List<MyInvitation>? _mine;
  String? _problem;
  String? _sending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.repo.mine();
      if (!mounted) return;
      setState(() {
        _mine = sortInvitations(all, (widget.now ?? DateTime.now)());
        _problem = null;
      });
    } catch (_) {
      if (mounted) setState(() => _problem = context.tr('Pas de réseau : réessayez.'));
    }
  }

  Future<void> _add(MyInvitation inv) async {
    if (_sending != null) return;
    setState(() => _sending = inv.id);
    try {
      final n = await addInvitationPhotos(context, widget.repo, inv, pick: widget.pick);
      if (n > 0) await _load();
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    return Scaffold(
      backgroundColor: ShopStyle.paper,
      appBar: AppBar(title: Text(context.tr('Mes invitations')), actions: const [bellRoom]),
      body: _problem != null && mine == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_problem!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
                ]),
              ),
            )
          : mine == null
              ? const Center(child: CircularProgressIndicator())
              : mine.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          context.tr('Aucune invitation confirmée pour le moment. Sur une carte, touchez « Confirmer ma présence » : elle s’affiche ici, avec vos photos.'),
                          key: const Key('my-invitations-empty'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 40 + MediaQuery.viewPaddingOf(context).bottom),
                        children: [for (final inv in mine) _card(context, inv)],
                      ),
                    ),
    );
  }

  Widget _card(BuildContext context, MyInvitation inv) {
    final theme = Theme.of(context);
    final wall = inv.startsWall;
    final picture = inv.cardPreview == null ? null : widget.repo.pictureUrl(inv.cardPreview!, width: 800);
    final sending = _sending == inv.id;
    final albumOpen = inv.albumOn && inv.albumAllowed;
    return Card(
      key: ValueKey('invitation-${inv.id}'),
      margin: const EdgeInsets.only(bottom: 18),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (picture != null)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(picture, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(inv.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ShopStyle.ink)),
            if (wall != null)
              Text(DateFormat('EEEE d MMMM yyyy · HH:mm', context.trLocale).format(wall),
                  key: ValueKey('invitation-date-${inv.id}'), style: const TextStyle(fontSize: 15)),
            if (inv.place != null && inv.place!.isNotEmpty) Text(inv.place!, style: const TextStyle(color: ShopStyle.mist)),
            Text(
              inv.people > 1
                  ? context.tr('Présence confirmée · {n} personnes', {'n': inv.people})
                  : context.tr('Présence confirmée'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                key: ValueKey('invitation-open-${inv.id}'),
                onPressed: () => (widget.open ?? openSitePage)(Uri.parse('${eventSiteOrigin()}${inv.path}')),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(context.tr('Voir l’invitation')),
              ),
              if (albumOpen)
                FilledButton.icon(
                  key: ValueKey('invitation-add-${inv.id}'),
                  onPressed: sending || !inv.canAddPhotos ? null : () => _add(inv),
                  icon: sending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: Text(context.tr('Ajouter des photos')),
                ),
              if (albumOpen)
                Text('${inv.photosUsed} / ${inv.photosLimit}',
                    key: ValueKey('invitation-count-${inv.id}'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            if (!albumOpen)
              Text(context.tr('L’album de cette carte est fermé.'), style: theme.textTheme.bodySmall)
            else if (!inv.canAddPhotos)
              Text(context.tr('Vous avez déposé vos {n} photos : c’est le maximum par invité.', {'n': inv.photosLimit}),
                  style: theme.textTheme.bodySmall)
            else
              Text(
                inv.albumReview
                    ? context.tr('Jusqu’à {n} photos chacun. Elles s’affichent sur la carte une fois validées par l’organisateur.', {'n': inv.photosLimit})
                    : context.tr('Jusqu’à {n} photos chacun : elles s’affichent sur la carte, sous votre nom.', {'n': inv.photosLimit}),
                style: theme.textTheme.bodySmall,
              ),
            if (inv.photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(context.tr('Vos photos'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in inv.photos) _photo(context, p),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _photo(BuildContext context, ({String key, bool approved}) p) {
    final url = widget.repo.pictureUrl(p.key, width: 200);
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: url == null
              ? const ColoredBox(color: Color(0xFFE8E2D6))
              : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFE8E2D6))),
        ),
        if (!p.approved)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(context.tr('En attente'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
      ]),
    );
  }
}

/// Still to come first (soonest first), then those past (latest first).
List<MyInvitation> sortInvitations(List<MyInvitation> all, DateTime now) {
  final cut = now.subtract(const Duration(days: 1));
  bool coming(MyInvitation x) => x.startsAt == null || x.startsAt!.isAfter(cut);
  final next = [for (final x in all) if (coming(x)) x]
    ..sort((a, b) => (a.startsAt ?? DateTime(9999)).compareTo(b.startsAt ?? DateTime(9999)));
  final past = [for (final x in all) if (!coming(x)) x]..sort((a, b) => b.startsAt!.compareTo(a.startsAt!));
  return [...next, ...past];
}

/// The slim bar over the street (183), as the tickets' one: the next card
/// this account confirmed — « Mariage Awa · Dans 3 j » — one tap from
/// « Mes invitations ». Nothing signed out, or with none to come.
class StreetInvitationsBar extends StatefulWidget {
  const StreetInvitationsBar({super.key, required this.repo, this.now});

  final InvitationsRepository repo;
  final DateTime Function()? now;

  @override
  State<StreetInvitationsBar> createState() => _StreetInvitationsBarState();
}

class _StreetInvitationsBarState extends State<StreetInvitationsBar> {
  List<MyInvitation> _next = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.repo.signedIn) return;
    try {
      final now = (widget.now ?? DateTime.now)();
      final cut = now.subtract(const Duration(days: 1));
      final all = sortInvitations(await widget.repo.mine(), now);
      if (mounted) setState(() => _next = [for (final x in all) if (x.startsAt == null || x.startsAt!.isAfter(cut)) x]);
    } catch (_) {
      // signed out, no network: no bar
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_next.isEmpty) return const SizedBox.shrink();
    final next = _next.first;
    final now = (widget.now ?? DateTime.now)();
    final c = next.startsAt == null ? null : eventCountdown(next.startsAt!, now);
    return Material(
      key: const Key('street-invitations-bar'),
      color: const Color(0xFF6B4E2E),
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => MyInvitationsScreen(repo: widget.repo, now: widget.now)))
            .then((_) => _load()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(children: [
            const Icon(Icons.celebration_outlined, size: 18, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                [
                  next.title,
                  if (c != null) context.tr(c.phrase, {'n': c.n}),
                  if (_next.length > 1) context.tr('+{n} autre(s)', {'n': _next.length - 1}),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
            Text(context.tr('Mes invitations'), style: const TextStyle(color: Colors.white, fontSize: 13)),
            const Icon(Icons.chevron_right, color: Colors.white, size: 18),
          ]),
        ),
      ),
    );
  }
}
