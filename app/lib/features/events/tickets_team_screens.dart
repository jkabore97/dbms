import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_repository.dart' show AuthRepository;
import '../../core/events/events_repository.dart' show EventSummary;
import '../../core/events/tickets_repository.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/theme/kaj_card.dart';
import 'events_screens.dart' show openOutside, whatsappDigits;
import 'tickets_screens.dart';

/// 163: an event's team, its figures, its journal, the door's own sale,
/// the cancellation — and a team member's own way in.

void _say(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

Widget _failed(BuildContext context, String error, VoidCallback retry) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: retry, child: Text(context.tr('Réessayer'))),
        ]),
      ),
    );

/// « Équipe de l'événement »: each member of the business, and their role
/// on this event — Billetterie, Contrôle, Lecture or none.
class EventTeamScreen extends StatefulWidget {
  const EventTeamScreen({super.key, required this.tickets, required this.event});

  final TicketsRepository tickets;
  final EventSummary event;

  @override
  State<EventTeamScreen> createState() => _EventTeamScreenState();
}

class _EventTeamScreenState extends State<EventTeamScreen> {
  List<TeamMember>? _team;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.tickets.team(widget.event.id);
      if (!mounted) return;
      setState(() {
        _team = t;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = AuthRepository.describeError(e));
    }
  }

  Future<void> _set(TeamMember m, String? role) async {
    try {
      await widget.tickets.setStaff(widget.event.id, m.userId, role);
      await _load();
    } catch (e) {
      if (mounted) _say(context, AuthRepository.describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final team = _team;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Équipe de l’événement')), actions: const [bellRoom]),
      body: team == null
          ? (_error == null ? const Center(child: CircularProgressIndicator()) : _failed(context, _error!, _load))
          : ListView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 40 + MediaQuery.viewPaddingOf(context).bottom),
              children: [
                Text(
                  context.tr('Billetterie : valide les paiements, rembourse, vend à l’entrée. Contrôle : scanne les billets, rien d’autre. Lecture : voit les chiffres.'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (team.isEmpty)
                  Text(context.tr('Invitez d’abord vos collaborateurs dans l’équipe de l’activité (Plus › Équipe).'))
                else
                  for (final m in team)
                    KajCard(
                      child: ListTile(
                        key: ValueKey('team-${m.userId}'),
                        title: Text(m.name),
                        subtitle: m.phone == null ? null : Text(m.phone!),
                        trailing: DropdownButton<String?>(
                          key: Key('team-role-${m.userId}'),
                          value: m.eventRole,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final r in const [null, 'billetterie', 'controle', 'lecture'])
                              DropdownMenuItem(value: r, child: Text(context.tr(eventRoleName(r)))),
                          ],
                          onChanged: (r) => _set(m, r),
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

/// « Bilan »: sold per type, validated against expected, refunded, who
/// validated what, the cash each agent took at the door, who let in.
class TicketReportScreen extends StatefulWidget {
  const TicketReportScreen({super.key, required this.tickets, required this.eventId, required this.title});

  final TicketsRepository tickets;
  final String eventId;
  final String title;

  @override
  State<TicketReportScreen> createState() => _TicketReportScreenState();
}

class _TicketReportScreenState extends State<TicketReportScreen> {
  Map<String, dynamic>? _r;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.tickets.report(widget.eventId);
      if (!mounted) return;
      setState(() {
        _r = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = AuthRepository.describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _r;
    num n(Object? x) => x is num ? x : num.tryParse('$x') ?? 0;
    final money = moneyFormat('${r?['currency'] ?? 'XOF'}');
    Widget row(String label, String value, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label)),
            Text(value, key: key, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Bilan')), actions: const [bellRoom]),
      body: r == null
          ? (_error == null ? const Center(child: CircularProgressIndicator()) : _failed(context, _error!, _load))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 40 + MediaQuery.viewPaddingOf(context).bottom),
                children: [
                  Text(widget.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  KajCard(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(children: [
                        row(context.tr('Validé (encaissé)'), money.format(n((r['paid'] as Map?)?['total'])), key: const Key('report-paid')),
                        row(context.tr('En attente de paiement'), money.format(n((r['pending'] as Map?)?['total']))),
                        row(context.tr('Remboursé'), money.format(n((r['refunded'] as Map?)?['total']))),
                        row(context.tr('Billets'), '${n(r['tickets'])}'),
                        row(context.tr('Entrés'), '${n(r['entered'])}', key: const Key('report-entered')),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(context.tr('Par type'), style: theme.textTheme.titleSmall),
                  for (final t in (r['types'] as List? ?? const []))
                    KajCard(
                      child: ListTile(
                        title: Text('${(t as Map)['name']}'),
                        subtitle: Text(context.tr('{sold} vendus{cap} · {in} entrés', {
                          'sold': n(t['sold']),
                          'cap': t['capacity'] == null ? '' : ' / ${t['capacity']}',
                          'in': n(t['entered']),
                        })),
                        trailing: Text(money.format(n(t['revenue'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text(context.tr('Par personne'), style: theme.textTheme.titleSmall),
                  if ((r['agents'] as List? ?? const []).isEmpty)
                    Text(context.tr('Personne n’a encore validé ni scanné.'), style: theme.textTheme.bodySmall),
                  for (final a in (r['agents'] as List? ?? const []))
                    KajCard(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${(a as Map)['name']}', style: theme.textTheme.titleSmall),
                          row(context.tr('Paiements validés'), '${n(a['validated'])} · ${money.format(n(a['validated_total']))}'),
                          row(context.tr('Ventes à l’entrée'), '${n(a['door_sales'])}'),
                          row(context.tr('Espèces à remettre'), money.format(n(a['door_cash']))),
                          row(context.tr('Entrées scannées'), '${n(a['entered'])}'),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// « Journal »: every action on the sale, by whom and when.
class TicketJournalScreen extends StatefulWidget {
  const TicketJournalScreen({super.key, required this.tickets, required this.eventId});

  final TicketsRepository tickets;
  final String eventId;

  @override
  State<TicketJournalScreen> createState() => _TicketJournalScreenState();
}

const _actionNames = {
  'paid': 'Paiement validé',
  'refused': 'Demande refusée',
  'refunded': 'Remboursé',
  'entered': 'Entrée',
  'void': 'Billet annulé',
  'door_sale': 'Vente à l’entrée',
  'cancelled': 'Événement annulé',
};

class _TicketJournalScreenState extends State<TicketJournalScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.tickets.journal(widget.eventId);
      if (!mounted) return;
      setState(() {
        _rows = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = AuthRepository.describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Journal')), actions: const [bellRoom]),
      body: rows == null
          ? (_error == null ? const Center(child: CircularProgressIndicator()) : _failed(context, _error!, _load))
          : rows.isEmpty
              ? Center(child: Text(context.tr('Rien pour le moment.')))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 40 + MediaQuery.viewPaddingOf(context).bottom),
                    children: [
                      for (final x in rows)
                        ListTile(
                          dense: true,
                          title: Text('${context.tr(_actionNames[x['action']] ?? '${x['action']}')} · ${x['who']}'),
                          subtitle: Text([
                            DateFormat('d MMM · HH:mm', context.trLocale)
                                .format(DateTime.tryParse('${x['at']}')?.toLocal() ?? DateTime.now()),
                            if (x['detail'] != null) '${x['detail']}',
                            if (x['amount'] != null) moneyFormat('XOF').format(x['amount'] as num),
                          ].join(' · ')),
                        ),
                    ],
                  ),
                ),
    );
  }
}

/// « Vendre à l'entrée »: how many of each type, paid in cash, let in at
/// once and counted to whoever sold them.
Future<void> showDoorSale(BuildContext context, TicketsRepository tickets, String eventId) async {
  final List<TicketType> types;
  try {
    types = await tickets.activeTypes(eventId);
  } catch (e) {
    if (context.mounted) _say(context, AuthRepository.describeError(e));
    return;
  }
  if (!context.mounted) return;
  if (types.isEmpty) return _say(context, context.tr('Aucun billet en vente.'));
  final qty = {for (final t in types) t.id: 0};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final total = types.fold<double>(0, (a, t) => a + t.price * (qty[t.id] ?? 0));
        return AlertDialog(
          title: Text(context.tr('Vendre à l’entrée')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final t in types)
              Row(children: [
                Expanded(child: Text('${t.name} · ${moneyFormat('XOF').format(t.price)}')),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: (qty[t.id] ?? 0) == 0 ? null : () => set(() => qty[t.id] = qty[t.id]! - 1),
                ),
                Text('${qty[t.id]}', key: Key('door-sale-qty-${t.id}')),
                IconButton(
                  key: Key('door-sale-add-${t.id}'),
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: (qty[t.id] ?? 0) >= 20 ? null : () => set(() => qty[t.id] = qty[t.id]! + 1),
                ),
              ]),
            const SizedBox(height: 8),
            Text(context.tr('À encaisser en espèces : {total}', {'total': moneyFormat('XOF').format(total)}),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('Annuler'))),
            FilledButton(
              key: const Key('door-sale-ok'),
              onPressed: total == 0 && qty.values.every((v) => v == 0) ? null : () => Navigator.pop(ctx, true),
              child: Text(context.tr('Encaissé')),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    final r = await tickets.doorSale(eventId, qty);
    if (context.mounted) {
      _say(context, context.tr('{n} billet(s) vendu(s) à l’entrée ({ref}).', {'n': r.count, 'ref': r.ref}));
    }
  } catch (e) {
    if (context.mounted) _say(context, AuthRepository.describeError(e));
  }
}

/// « Annuler l'événement »: asked twice, then the holders to write to.
Future<void> cancelEvent(BuildContext context, TicketsRepository tickets, EventSummary event,
    {Future<void> Function(Uri uri)? open}) async {
  final why = await showDialog<String>(
    context: context,
    builder: (ctx) => NoteDialog(
      title: context.tr('Annuler l’événement ?'),
      body: context.tr('La vente se ferme pour de bon et l’événement quitte la rue. Vous écrivez ensuite à chaque acheteur ; les remboursements se font de votre téléphone.'),
      label: context.tr('Raison (facultative)'),
      confirm: context.tr('Annuler l’événement'),
      confirmKey: const Key('event-cancel-ok'),
      cancel: context.tr('Garder'),
      danger: true,
    ),
  );
  if (why == null || !context.mounted) return;
  try {
    final holders = await tickets.cancel(event.id, reason: why.isEmpty ? null : why);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HoldersScreen(event: event, holders: holders, reason: why, open: open),
    ));
  } catch (e) {
    if (context.mounted) _say(context, AuthRepository.describeError(e));
  }
}

/// The holders of a cancelled event, each with a WhatsApp message ready.
class HoldersScreen extends StatelessWidget {
  const HoldersScreen({super.key, required this.event, required this.holders, this.reason = '', this.open});

  final EventSummary event;
  final List<Map<String, dynamic>> holders;
  final String reason;
  final Future<void> Function(Uri uri)? open;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Prévenir les acheteurs')), actions: const [bellRoom]),
      body: ListView(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 40 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text(holders.isEmpty
                ? context.tr('Personne n’avait de billet : rien à prévenir.')
                : context.tr('{n} acheteur(s) à prévenir. Touchez chacun pour lui écrire sur WhatsApp.', {'n': holders.length})),
          ),
          for (final h in holders)
            KajCard(
              child: ListTile(
                key: ValueKey('holder-${h['id']}'),
                title: Text('${h['name']} · ${h['ref']}'),
                subtitle: Text(moneyFormat('XOF').format(h['total'] as num? ?? 0)),
                trailing: const Icon(Icons.chat_outlined),
                onTap: () async {
                  final to = whatsappDigits(h['whatsapp']);
                  if (to == null) return _say(context, context.tr('Ce numéro WhatsApp n’est pas valide.'));
                  final text = context.tr(
                      'Bonjour {name}, nous sommes désolés : « {title} » est annulé{why}. Votre demande {ref} : nous revenons vers vous pour le remboursement.',
                      {'name': h['name'], 'title': event.title, 'why': reason.isEmpty ? '' : ' ($reason)', 'ref': h['ref']});
                  await (open ?? openOutside)(Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent(text)}'));
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// A team member's events (163), on their home: each opens the tools
/// their role gives.
class StaffEventsList extends StatefulWidget {
  const StaffEventsList({super.key, required this.tickets, required this.orgId});

  final TicketsRepository tickets;
  final String orgId;

  @override
  State<StaffEventsList> createState() => _StaffEventsListState();
}

class _StaffEventsListState extends State<StaffEventsList> {
  List<StaffEvent>? _events;

  @override
  void initState() {
    super.initState();
    widget.tickets.myStaff().then((e) {
      if (mounted) setState(() => _events = [for (final x in e) if (x.orgId == widget.orgId) x]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    if (events == null) return const Center(child: CircularProgressIndicator());
    if (events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(context.tr('Aucun événement ne vous est confié pour le moment.'),
              key: const Key('staff-events-empty'), textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        for (final e in events)
          KajCard(
            child: ListTile(
              key: ValueKey('staff-event-${e.id}'),
              title: Text(e.title),
              subtitle: Text([
                context.tr(eventRoleName(e.role)),
                if (e.startsAt != null) DateFormat('EEE d MMM · HH:mm', context.trLocale).format(e.startsAt!),
                if (e.cancelled) context.tr('Annulé'),
              ].join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => StaffEventScreen(tickets: widget.tickets, event: e),
              )),
            ),
          ),
      ],
    );
  }
}

/// One event, as a team member sees it: the tools of their role alone.
class StaffEventScreen extends StatelessWidget {
  const StaffEventScreen({super.key, required this.tickets, required this.event});

  final TicketsRepository tickets;
  final StaffEvent event;

  EventSummary get _summary => EventSummary(
        id: event.id, orgId: event.orgId, kind: 'gala', card: '', slug: event.slug, previewToken: '',
        title: event.title, startsAt: event.startsAt, place: event.place, content: const {}, rsvpOn: false,
        albumOn: false, published: true, createdAt: DateTime.now(),
      );

  @override
  Widget build(BuildContext context) {
    void go(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(title: Text(event.title), actions: const [bellRoom]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.tr('Votre rôle : {role}', {'role': context.tr(eventRoleName(event.role))})),
          const SizedBox(height: 12),
          if (event.sells)
            ListTile(
              key: const Key('staff-requests'),
              leading: const Icon(Icons.fact_check_outlined),
              title: Text(context.tr('Demandes de billets')),
              onTap: () => go(TicketRequestsScreen(tickets: tickets, event: _summary)),
            ),
          if (event.door)
            ListTile(
              key: const Key('staff-door'),
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(context.tr('Contrôle à l’entrée')),
              onTap: () => go(TicketDoorScreen(tickets: tickets, event: _summary, canSell: event.sells)),
            ),
          ListTile(
            key: const Key('staff-report'),
            leading: const Icon(Icons.insights_outlined),
            title: Text(context.tr('Bilan')),
            onTap: () => go(TicketReportScreen(tickets: tickets, eventId: event.id, title: event.title)),
          ),
          if (event.role != 'controle')
            ListTile(
              key: const Key('staff-journal'),
              leading: const Icon(Icons.history),
              title: Text(context.tr('Journal')),
              onTap: () => go(TicketJournalScreen(tickets: tickets, eventId: event.id)),
            ),
        ],
      ),
    );
  }
}
