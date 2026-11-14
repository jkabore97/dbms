import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/events/my_tickets.dart';
import '../../core/events/street_event.dart' show eventCountdown;
import '../../core/events/tickets_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../events/events_screens.dart' show eventSiteOrigin, openSitePage;
import 'shop_style.dart';

/// The slim bar over the street (part 4): the buyer's next event with its
/// tickets — « Concert Fatim · Dans 3 j », then « Aujourd'hui » — one tap
/// from its QR codes. Nothing when there is no ticket on this phone.
class StreetTicketsBar extends StatefulWidget {
  const StreetTicketsBar({super.key, required this.store, this.now});

  final MyTicketsStore store;
  final DateTime Function()? now;

  @override
  State<StreetTicketsBar> createState() => _StreetTicketsBarState();
}

class _StreetTicketsBarState extends State<StreetTicketsBar> {
  List<MyTickets> _mine = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = (widget.now ?? DateTime.now)();
    final kept = await widget.store.kept(now: now);
    if (mounted && kept.isNotEmpty) setState(() => _mine = kept);
    final fresh = await widget.store.refresh(now: now);
    if (mounted) setState(() => _mine = fresh);
  }

  @override
  Widget build(BuildContext context) {
    if (_mine.isEmpty) return const SizedBox.shrink();
    final next = _mine.first;
    final now = (widget.now ?? DateTime.now)();
    final c = next.startsAt == null ? null : eventCountdown(next.startsAt!, now);
    final today = c != null && (c.phrase == 'Aujourd’hui' || c.phrase == 'En cours');
    final color = today ? const Color(0xFF1E7B3A) : ShopStyle.ink;
    return Material(
      key: const Key('street-tickets-bar'),
      color: color,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MyTicketsScreen(store: widget.store, now: widget.now),
        )).then((_) => _load()),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(children: [
              const Icon(Icons.confirmation_number_outlined, size: 18, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  [
                    next.title,
                    if (c != null) context.tr(c.phrase, {'n': c.n}),
                    if (_mine.length > 1) context.tr('+{n} autre(s)', {'n': _mine.length - 1}),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              Text(context.tr('Mes billets'), style: const TextStyle(color: Colors.white, fontSize: 13)),
              const Icon(Icons.chevron_right, color: Colors.white, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}

/// « Mes billets »: every ticket kept on this phone, its QR drawn here —
/// so it opens at the door with no signal. [keepId], from a link
/// (`/billets/<id>`), is kept first.
class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key, required this.store, this.keepId, this.now, this.open, this.invitations});

  final MyTicketsStore store;
  final String? keepId;
  final DateTime Function()? now;

  /// Opens the ticket page on the site (the tests look).
  final Future<void> Function(Uri uri)? open;

  /// « Mes invitations » next door (183): the cards confirmed, their photos.
  final VoidCallback? invitations;

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  List<MyTickets>? _mine;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = (widget.now ?? DateTime.now)();
    final id = widget.keepId;
    if (id != null) await widget.store.keep(id);
    final kept = await widget.store.kept(now: now);
    if (mounted) setState(() => _mine = kept);
    final fresh = await widget.store.refresh(now: now);
    if (!mounted) return;
    setState(() {
      _mine = fresh;
      _offline = fresh.isNotEmpty && !widget.store.reached;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: ShopStyle.paper,
      appBar: AppBar(title: Text(context.tr('Mes billets')), actions: [
        if (widget.invitations != null)
          TextButton.icon(
            key: const Key('my-tickets-invitations'),
            onPressed: widget.invitations,
            icon: const Icon(Icons.celebration_outlined, size: 18),
            label: Text(context.tr('Mes invitations')),
          ),
        bellRoom,
      ]),
      body: mine == null
          ? const Center(child: CircularProgressIndicator())
          : mine.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(context.tr('Aucun billet sur ce téléphone.'),
                        key: const Key('my-tickets-empty'), textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 40 + MediaQuery.viewPaddingOf(context).bottom),
                    children: [
                      if (_offline)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(context.tr('Sans réseau : vos billets tels que gardés sur ce téléphone.'),
                              style: theme.textTheme.bodySmall),
                        ),
                      for (final r in mine) ...[
                        Text(r.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ShopStyle.ink)),
                        if (r.dateFr != null) Text(r.dateFr!, style: const TextStyle(fontSize: 15)),
                        if (r.place != null && r.place!.isNotEmpty) Text(r.place!, style: const TextStyle(color: ShopStyle.mist)),
                        const SizedBox(height: 10),
                        // 185: the event cancelled — said, and no code to show at a door
                        if (r.cancelled)
                          cancelledNotice(context, r.cancelReason,
                              more: context.tr('L’organisateur revient vers vous pour le remboursement.'),
                              key: ValueKey('ticket-cancelled-${r.requestId}'))
                        else if (r.status != 'paid')
                          Card(
                            child: ListTile(
                              key: ValueKey('pending-${r.requestId}'),
                              leading: const Icon(Icons.hourglass_top),
                              title: Text(context.tr('En attente de paiement · {ref}', {'ref': r.ref})),
                              subtitle: Text(context.tr('Les billets arrivent ici dès que l’organisateur valide.')),
                              trailing: const Icon(Icons.open_in_new),
                              onTap: () {
                                final uri = Uri.parse('${eventSiteOrigin()}/e/${r.slug}/billets/${r.requestId}');
                                (widget.open ?? openSitePage)(uri);
                              },
                            ),
                          )
                        else
                          for (final (i, t) in r.tickets.indexed)
                            Card(
                              key: ValueKey('ticket-${t.id}'),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(children: [
                                  Text(context.tr('Billet {n} · {type}', {'n': i + 1, 'type': t.type}),
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 10),
                                  if (t.status == 'valid')
                                    QrImageView(
                                      data: r.qrOf(t.id),
                                      size: 220,
                                      backgroundColor: Colors.white,
                                      semanticsLabel: context.tr('Code du billet'),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(t.status == 'used' ? context.tr('Déjà utilisé') : context.tr('Billet annulé'),
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                                    ),
                                  const SizedBox(height: 8),
                                  Text(t.holder),
                                  Text(context.tr('Valable une fois, à présenter à l’entrée'), style: theme.textTheme.bodySmall),
                                ]),
                              ),
                            ),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
    );
  }
}

/// « Événement annulé » (185), its reason, and what comes next — on a
/// ticket, an invitation, the organiser's card.
Widget cancelledNotice(BuildContext context, String? reason, {String? more, Key? key}) => Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFB91C1C))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.event_busy, color: Color(0xFFB91C1C)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('Événement annulé'),
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF7F1D1D), fontSize: 16)),
            if (reason != null && reason.isNotEmpty) Text(reason, style: const TextStyle(color: Color(0xFF7F1D1D))),
            if (more != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(more, style: const TextStyle(fontSize: 13))),
          ]),
        ),
      ]),
    );
