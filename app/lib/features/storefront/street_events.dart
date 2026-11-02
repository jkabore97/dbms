import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/events/street_event.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/storefront/storefront_repository.dart';
import '../events/events_screens.dart' show eventSiteOrigin, openOutside, openSitePage, whatsappDigits;
import 'lazy_photo.dart';
import 'shop_style.dart';

/// The street's « Événements » (162): the public events, soonest first, in
/// their own strip — not mixed with the shops. Nothing at all when there
/// is none, or when they cannot be asked.
class StreetEventsStrip extends StatefulWidget {
  const StreetEventsStrip({super.key, required this.storefront, required this.capture, this.now});

  final StorefrontRepository storefront;
  final CaptureRepository capture;

  /// The clock, for the tests.
  final DateTime Function()? now;

  @override
  State<StreetEventsStrip> createState() => _StreetEventsStripState();
}

class _StreetEventsStripState extends State<StreetEventsStrip> {
  List<StreetEvent> _events = const [];

  @override
  void initState() {
    super.initState();
    widget.storefront.streetEvents().then((e) {
      if (mounted) setState(() => _events = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty) return const SizedBox.shrink();
    final now = (widget.now ?? DateTime.now)();
    return Column(
      key: const Key('street-events'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        ShopSectionLabel(context.tr('Événements')),
        const SizedBox(height: 14),
        SizedBox(
          height: 268,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _events.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => _EventTile(
              event: _events[i],
              capture: widget.capture,
              now: now,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => EventVitrineScreen(
                  storefront: widget.storefront,
                  capture: widget.capture,
                  first: _events[i],
                  now: widget.now,
                ),
              )),
            ),
          ),
        ),
      ],
    );
  }
}

String _countdown(BuildContext context, DateTime startsAt, DateTime now) {
  final c = eventCountdown(startsAt, now);
  return context.tr(c.phrase, {'n': c.n});
}

String _priceLine(BuildContext context, StreetEvent e) {
  if (!e.tickets) return context.tr('Entrée libre');
  if (e.fromPrice == null) return context.tr('Billets en vente');
  return context.tr('Billets dès {price}', {'price': moneyFormat(e.currency).format(e.fromPrice)});
}

class _Poster extends StatelessWidget {
  const _Poster({required this.event, required this.capture});

  final StreetEvent event;
  final CaptureRepository capture;

  @override
  Widget build(BuildContext context) {
    const blank = ColoredBox(
      color: ShopStyle.stone,
      child: Center(child: Icon(Icons.celebration_outlined, size: 36, color: ShopStyle.mist)),
    );
    final key = event.poster;
    if (key == null) return blank;
    return LazyPhoto(
      id: key,
      load: (width) => capture.publicObjectBytes(key, width: width),
      placeholder: blank,
      builder: (context, bytes, width) => Image.memory(bytes, fit: BoxFit.cover, cacheWidth: width),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.capture, required this.now, required this.onTap});

  final StreetEvent event;
  final CaptureRepository capture;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: InkWell(
        key: Key('street-event-${event.slug}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 150,
              width: 200,
              child: Stack(fit: StackFit.expand, children: [
                _Poster(event: event, capture: capture),
                Positioned(
                  left: 8,
                  top: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: ShopStyle.ink, borderRadius: BorderRadius.circular(999)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Text(_countdown(context, event.startsAt, now),
                          style: const TextStyle(color: ShopStyle.paper, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text(event.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: ShopStyle.ink)),
          if (event.dateFr != null)
            Text(event.dateFr!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
          if (event.place != null && event.place!.isNotEmpty)
            Text(event.place!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
          Text(_priceLine(context, event), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ShopStyle.ink)),
        ]),
      ),
    );
  }
}

/// One public event on the street (162): its poster, the date and the
/// place large, how far off, the tickets with their places left,
/// « Réserver », the invitation itself, WhatsApp and share.
class EventVitrineScreen extends StatefulWidget {
  const EventVitrineScreen({
    super.key,
    required this.storefront,
    required this.capture,
    required this.first,
    this.now,
    this.open,
    this.share,
  });

  final StorefrontRepository storefront;
  final CaptureRepository capture;

  /// What the strip knew, drawn at once.
  final StreetEvent first;
  final DateTime Function()? now;

  /// Opens a page or WhatsApp (the tests look).
  final Future<void> Function(Uri uri)? open;

  /// Shares a text (the tests look).
  final Future<void> Function(String text)? share;

  @override
  State<EventVitrineScreen> createState() => _EventVitrineScreenState();
}

class _EventVitrineScreenState extends State<EventVitrineScreen> {
  late StreetEvent _e = widget.first;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await widget.storefront.streetEvent(widget.first.slug);
      if (!mounted) return;
      setState(() {
        if (e == null) {
          _gone = true;
        } else {
          _e = e;
        }
      });
    } catch (_) {
      // No signal: what the strip knew stays.
    }
  }

  Future<void> _go(String path) async {
    final uri = Uri.parse('${eventSiteOrigin()}$path');
    final open = widget.open;
    if (open != null) return open(uri);
    await openSitePage(uri);
  }

  Future<void> _whatsapp() async {
    final to = whatsappDigits(_e.payWhatsapp);
    if (to == null) return;
    final text = context.tr('Bonjour, au sujet de « {title} ».', {'title': _e.title});
    await (widget.open ?? openOutside)(Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent(text)}'));
  }

  Future<void> _share() async {
    final text = '${_e.title} — ${_e.dateFr ?? ''}\nhttps://marakaj.com${_e.cardPath}';
    final share = widget.share;
    if (share != null) return share(text);
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    final now = (widget.now ?? DateTime.now)();
    final money = moneyFormat(e.currency);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final poster = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(aspectRatio: 4 / 5, child: _Poster(event: e, capture: widget.capture)),
    );
    final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_countdown(context, e.startsAt, now).toUpperCase(),
          key: const Key('event-vitrine-countdown'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: ShopStyle.mist)),
      const SizedBox(height: 6),
      Text(e.title, style: const TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w800, color: ShopStyle.ink)),
      const SizedBox(height: 12),
      if (e.dateFr != null)
        Row(children: [
          const Icon(Icons.event, size: 20, color: ShopStyle.ink),
          const SizedBox(width: 8),
          Expanded(child: Text(e.dateFr!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        ]),
      if (e.place != null && e.place!.isNotEmpty) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.place_outlined, size: 20, color: ShopStyle.ink),
          const SizedBox(width: 8),
          Expanded(child: Text(e.place!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        ]),
      ],
      if (e.orgName != null) ...[
        const SizedBox(height: 6),
        Text(context.tr('Organisé par {name}', {'name': e.orgName}), style: const TextStyle(color: ShopStyle.mist)),
      ],
      const SizedBox(height: 18),
      if (_gone)
        Text(context.tr('Cet événement n’est plus sur la rue.'), style: const TextStyle(color: ShopStyle.mist))
      else if (e.tickets) ...[
        for (final t in e.types)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: Text(t.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              Text(money.format(t.price), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Text(
                t.left == null
                    ? ''
                    : t.left == 0
                        ? context.tr('Complet')
                        : context.tr('{n} places', {'n': t.left}),
                style: const TextStyle(color: ShopStyle.mist),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('event-vitrine-book'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: e.salesOpen ? () => _go(e.ticketsPath) : null,
          icon: const Icon(Icons.confirmation_number_outlined),
          label: Text(e.salesOpen ? context.tr('Réserver mes billets') : context.tr('Vente terminée')),
        ),
        const SizedBox(height: 6),
        Text(context.tr('Le paiement se fait directement à l’organisateur. Marakaj n’encaisse rien.'),
            style: const TextStyle(fontSize: 12, color: ShopStyle.mist)),
      ] else
        Text(context.tr('Entrée libre'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 8, children: [
        OutlinedButton.icon(
          key: const Key('event-vitrine-card'),
          onPressed: () => _go(e.cardPath),
          icon: const Icon(Icons.mail_outline),
          label: Text(context.tr('Voir l’invitation')),
        ),
        if (whatsappDigits(e.payWhatsapp) != null)
          OutlinedButton.icon(
            key: const Key('event-vitrine-wa'),
            onPressed: _whatsapp,
            icon: const Icon(Icons.chat_outlined),
            label: Text(context.tr('WhatsApp')),
          ),
        OutlinedButton.icon(
          key: const Key('event-vitrine-share'),
          onPressed: _share,
          icon: const Icon(Icons.share_outlined),
          label: Text(context.tr('Partager')),
        ),
      ]),
    ]);
    return Scaffold(
      backgroundColor: ShopStyle.paper,
      appBar: AppBar(title: Text(context.tr('Événement')), actions: const [bellRoom]),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 40 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 420, child: poster),
                      const SizedBox(width: 36),
                      Expanded(child: details),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: poster)),
                      const SizedBox(height: 18),
                      details,
                    ]),
            ),
          ),
        ],
      ),
    );
  }
}
