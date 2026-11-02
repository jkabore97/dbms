import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_repository.dart' show AuthRepository;
import '../../core/events/events_repository.dart' show EventSummary;
import '../../core/events/tickets_repository.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/theme/kaj_card.dart';
import '../capture/barcode_sheet.dart';
import 'events_screens.dart' show openOutside, whatsappDigits;

/// Ticket sales (161), on the card's page: the three doors — the sale's
/// setup, the requests to validate, the door. Shown only to a business
/// that may sell (Marakaj Pro, or Marakaj's own while the platform's
/// switch is off): the server says so, and refuses the rest anyway.
class TicketsCard extends StatelessWidget {
  const TicketsCard({super.key, required this.tickets, required this.event, this.open});

  final TicketsRepository tickets;
  final EventSummary event;
  final Future<void> Function(Uri uri)? open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void go(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return KajCard(
      key: const Key('tickets-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
          child: Text(context.tr('Billetterie'), style: theme.textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(context.tr('Le paiement se fait directement à l’organisateur. Marakaj n’encaisse rien.'),
              style: theme.textTheme.bodySmall),
        ),
        ListTile(
          key: const Key('tickets-setup'),
          leading: const Icon(Icons.confirmation_number_outlined),
          title: Text(context.tr('Vente de billets')),
          subtitle: Text(context.tr('Types de billets, prix, où payer')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => go(TicketSetupScreen(tickets: tickets, event: event)),
        ),
        ListTile(
          key: const Key('tickets-requests'),
          leading: const Icon(Icons.fact_check_outlined),
          title: Text(context.tr('Demandes de billets')),
          subtitle: Text(context.tr('Valider un paiement reçu, refuser')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => go(TicketRequestsScreen(tickets: tickets, event: event, open: open)),
        ),
        ListTile(
          key: const Key('tickets-door'),
          leading: const Icon(Icons.qr_code_scanner),
          title: Text(context.tr('Contrôle à l’entrée')),
          subtitle: Text(context.tr('Scanner les billets, même sans réseau')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => go(TicketDoorScreen(tickets: tickets, event: event)),
        ),
      ]),
    );
  }
}

/// How long an unpaid request holds its places.
const ticketHoldChoices = [6, 12, 24, 48, 72, 120, 168];

/// The sale laid out: on or off, the types and their prices and places,
/// where the buyer pays, the WhatsApp the buyer writes to, how long a
/// request holds, when the sale closes.
class TicketSetupScreen extends StatefulWidget {
  const TicketSetupScreen({super.key, required this.tickets, required this.event});

  final TicketsRepository tickets;
  final EventSummary event;

  @override
  State<TicketSetupScreen> createState() => _TicketSetupScreenState();
}

class _TicketSetupScreenState extends State<TicketSetupScreen> {
  TicketSettings? _s;
  String? _error;
  bool _saving = false;
  final _whatsapp = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _whatsapp.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.tickets.settings(widget.event.id);
      if (!mounted) return;
      setState(() {
        _s = s;
        _error = null;
        _whatsapp.text = s.payWhatsapp ?? '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = AuthRepository.describeError(e));
    }
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save({bool? on}) async {
    final s = _s;
    if (s == null) return;
    final next = s.copyWith(on: on, payWhatsapp: _whatsapp.text);
    if (next.on) {
      if (!next.types.any((t) => t.active)) return _say(context.tr('Ajoutez d’abord un type de billet.'));
      if (next.payMethods.isEmpty) return _say(context.tr('Ajoutez d’abord un numéro où payer.'));
    }
    setState(() => _saving = true);
    try {
      await widget.tickets.saveSettings(widget.event.id, next);
      if (!mounted) return;
      setState(() => _s = next);
      _say(next.on ? context.tr('Vente ouverte : le bouton « Réserver » est sur la carte.') : context.tr('Enregistré'));
    } catch (e) {
      if (mounted) _say(AuthRepository.describeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editType([TicketType? t]) async {
    final made = await showDialog<TicketType>(context: context, builder: (_) => _TypeDialog(initial: t));
    if (made == null || !mounted) return;
    try {
      await widget.tickets.saveType(widget.event.id, made);
      await _load();
    } catch (e) {
      if (mounted) _say(AuthRepository.describeError(e));
    }
  }

  Future<void> _removeType(TicketType t) async {
    try {
      await widget.tickets.removeType(t);
      await _load();
    } catch (e) {
      if (mounted) _say(AuthRepository.describeError(e));
    }
  }

  Future<void> _editMethod([int? i]) async {
    final s = _s!;
    final made = await showDialog<PayMethod>(
        context: context, builder: (_) => _MethodDialog(initial: i == null ? null : s.payMethods[i]));
    if (made == null || !mounted) return;
    final list = [...s.payMethods];
    if (i == null) {
      list.add(made);
    } else {
      list[i] = made;
    }
    setState(() => _s = s.copyWith(payMethods: list));
    await _save();
  }

  Future<void> _removeMethod(int i) async {
    final s = _s!;
    final list = [...s.payMethods]..removeAt(i);
    setState(() => _s = s.copyWith(payMethods: list, on: list.isEmpty ? false : null));
    await _save();
  }

  Future<void> _pickClose() async {
    final s = _s!;
    final now = DateTime.now();
    final last = widget.event.startsAt ?? now.add(const Duration(days: 365));
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: last.isBefore(now) ? now.add(const Duration(days: 1)) : last,
      initialDate: s.salesCloseAt ?? (last.isBefore(now) ? now : last),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 23, minute: 59));
    if (!mounted) return;
    final t = time ?? const TimeOfDay(hour: 23, minute: 59);
    setState(() => _s = s.copyWith(salesCloseAt: DateTime(day.year, day.month, day.day, t.hour, t.minute)));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _s;
    final money = moneyFormat('XOF');
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Vente de billets')), actions: const [bellRoom]),
      body: s == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
                      ]),
                    ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 40 + MediaQuery.viewPaddingOf(context).bottom),
              children: [
                KajCard(
                  child: SwitchListTile(
                    key: const Key('tickets-on'),
                    title: Text(context.tr('Vente ouverte')),
                    subtitle: Text(context.tr('Le bouton « Réserver » apparaît sur la carte.')),
                    value: s.on,
                    onChanged: _saving ? null : (v) => _save(on: v),
                  ),
                ),
                const SizedBox(height: 16),
                Text(context.tr('Types de billets'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                for (final t in s.types.where((t) => t.active))
                  KajCard(
                    child: ListTile(
                      title: Text(t.name),
                      subtitle: Text(
                          '${money.format(t.price)} · ${t.capacity == null ? context.tr('places illimitées') : context.tr('{n} places', {'n': t.capacity})}'),
                      onTap: () => _editType(t),
                      trailing: IconButton(
                        tooltip: context.tr('Retirer'),
                        icon: const Icon(Icons.close),
                        onPressed: () => _removeType(t),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('tickets-type-add'),
                    onPressed: () => _editType(),
                    icon: const Icon(Icons.add),
                    label: Text(context.tr('Ajouter un type de billet')),
                  ),
                ),
                const SizedBox(height: 12),
                Text(context.tr('Où payer'), style: theme.textTheme.titleMedium),
                Text(context.tr('Le numéro que l’acheteur paie, sur son propre téléphone.'), style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                for (var i = 0; i < s.payMethods.length; i++)
                  KajCard(
                    child: ListTile(
                      title: Text('${PayMethod.kinds[s.payMethods[i].kind] ?? s.payMethods[i].kind} · ${s.payMethods[i].number}'),
                      subtitle: s.payMethods[i].name == null ? null : Text(s.payMethods[i].name!),
                      onTap: () => _editMethod(i),
                      trailing: IconButton(
                        tooltip: context.tr('Retirer'),
                        icon: const Icon(Icons.close),
                        onPressed: () => _removeMethod(i),
                      ),
                    ),
                  ),
                if (s.payMethods.length < 4)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('tickets-method-add'),
                      onPressed: () => _editMethod(),
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('Ajouter un numéro')),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('tickets-whatsapp'),
                  controller: _whatsapp,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: context.tr('WhatsApp pour les acheteurs'),
                    helperText: context.tr('Ils y envoient la preuve de paiement.'),
                  ),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: const Key('tickets-hold'),
                  initialValue: ticketHoldChoices.contains(s.holdHours) ? s.holdHours : 72,
                  decoration: InputDecoration(
                    labelText: context.tr('Places gardées sans paiement'),
                    helperText: context.tr('Passé ce délai, la demande expire et ses places reviennent en vente.'),
                  ),
                  items: [
                    for (final h in ticketHoldChoices)
                      DropdownMenuItem(
                        value: h,
                        child: Text(h % 24 == 0 ? context.tr('{n} jours', {'n': h ~/ 24}) : context.tr('{n} heures', {'n': h})),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _s = s.copyWith(holdHours: v));
                    _save();
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('Fin de la vente')),
                  subtitle: Text(s.salesCloseAt == null
                      ? context.tr('Jusqu’au début de l’événement')
                      : DateFormat('EEEE d MMMM · HH:mm', context.trLocale).format(s.salesCloseAt!)),
                  onTap: _pickClose,
                  trailing: s.salesCloseAt == null
                      ? const Icon(Icons.event_outlined)
                      : IconButton(
                          tooltip: context.tr('Retirer'),
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() => _s = s.copyWith(clearClose: true));
                            _save();
                          },
                        ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('tickets-save'),
                  onPressed: _saving ? null : () => _save(),
                  child: Text(context.tr('Enregistrer')),
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr(
                      'Le paiement se fait directement à l’organisateur. Marakaj n’encaisse rien : vous validez chaque demande quand l’argent est arrivé sur votre téléphone.'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}

class _TypeDialog extends StatefulWidget {
  const _TypeDialog({this.initial});

  final TicketType? initial;

  @override
  State<_TypeDialog> createState() => _TypeDialogState();
}

class _TypeDialogState extends State<_TypeDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _price = TextEditingController(text: widget.initial == null ? '' : widget.initial!.price.round().toString());
  late final _places = TextEditingController(text: widget.initial?.capacity?.toString() ?? '');
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _places.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.'));
    final places = _places.text.trim().isEmpty ? null : int.tryParse(_places.text.trim());
    if (name.isEmpty || name.length > 60) return setState(() => _problem = context.tr('Un nom, en 60 caractères au plus.'));
    if (price == null || price < 0) return setState(() => _problem = context.tr('Un prix, 0 pour un billet gratuit.'));
    if (_places.text.trim().isNotEmpty && (places == null || places < 1)) {
      return setState(() => _problem = context.tr('Un nombre de places, ou rien pour illimité.'));
    }
    final i = widget.initial;
    Navigator.pop(
      context,
      TicketType(id: i?.id ?? '', name: name, price: price, capacity: places, sort: i?.sort ?? 0, active: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? context.tr('Nouveau type de billet') : context.tr('Type de billet')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('ticket-type-name'),
            controller: _name,
            decoration: InputDecoration(labelText: context.tr('Nom'), hintText: context.tr('Standard, VIP…')),
          ),
          TextField(
            key: const Key('ticket-type-price'),
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.tr('Prix (FCFA)')),
          ),
          TextField(
            key: const Key('ticket-type-places'),
            controller: _places,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.tr('Places'), helperText: context.tr('Vide : illimité')),
          ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Annuler'))),
        FilledButton(key: const Key('ticket-type-ok'), onPressed: _done, child: Text(context.tr('Enregistrer'))),
      ],
    );
  }
}

class _MethodDialog extends StatefulWidget {
  const _MethodDialog({this.initial});

  final PayMethod? initial;

  @override
  State<_MethodDialog> createState() => _MethodDialogState();
}

class _MethodDialogState extends State<_MethodDialog> {
  late String _kind = widget.initial?.kind ?? 'orange';
  late final _number = TextEditingController(text: widget.initial?.number ?? '');
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  String? _problem;

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Où payer')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _kind,
            items: [for (final k in PayMethod.kinds.entries) DropdownMenuItem(value: k.key, child: Text(context.tr(k.value)))],
            onChanged: (v) => setState(() => _kind = v ?? 'orange'),
          ),
          TextField(
            key: const Key('ticket-method-number'),
            controller: _number,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: context.tr('Numéro')),
          ),
          TextField(
            key: const Key('ticket-method-name'),
            controller: _name,
            decoration: InputDecoration(labelText: context.tr('Au nom de'), helperText: context.tr('Ce que l’acheteur voit en payant')),
          ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Annuler'))),
        FilledButton(
          key: const Key('ticket-method-ok'),
          onPressed: () {
            final n = _number.text.trim();
            if (n.replaceAll(RegExp(r'\D'), '').length < 6 || n.length > 24) {
              return setState(() => _problem = context.tr('Un numéro de téléphone.'));
            }
            Navigator.pop(context, PayMethod(kind: _kind, number: n, name: _name.text.trim().isEmpty ? null : _name.text.trim()));
          },
          child: Text(context.tr('Enregistrer')),
        ),
      ],
    );
  }
}

/// The requests: those waiting for their money first, each validated when
/// the organiser has seen the payment arrive, or refused; the buyer
/// written to on WhatsApp.
class TicketRequestsScreen extends StatefulWidget {
  const TicketRequestsScreen({super.key, required this.tickets, required this.event, this.open});

  final TicketsRepository tickets;
  final EventSummary event;

  /// Opens WhatsApp (the tests look).
  final Future<void> Function(Uri uri)? open;

  @override
  State<TicketRequestsScreen> createState() => _TicketRequestsScreenState();
}

class _TicketRequestsScreenState extends State<TicketRequestsScreen> {
  List<TicketRequest>? _all;
  String? _error;
  String _show = 'pending';
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.tickets.requests(widget.event.id);
      if (!mounted) return;
      setState(() {
        _all = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = AuthRepository.describeError(e));
    }
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _decide(TicketRequest r, bool paid) async {
    final note = TextEditingController();
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(paid ? context.tr('Paiement reçu ?') : context.tr('Refuser cette demande ?')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(paid
              ? context.tr('{total} de {name} : vérifiez sur votre téléphone que l’argent est bien arrivé. Les billets partent alors à l’acheteur.',
                  {'total': moneyFormat(r.currency).format(r.total), 'name': r.name})
              : context.tr('Ses places reviennent en vente.')),
          TextField(
            controller: note,
            maxLength: 300,
            decoration: InputDecoration(labelText: context.tr('Note (facultative)')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('Annuler'))),
          FilledButton(
            key: const Key('ticket-decide-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(paid ? context.tr('Oui, payé') : context.tr('Refuser')),
          ),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (sure != true || !mounted) return;
    setState(() => _busy.add(r.id));
    try {
      await widget.tickets.decide(r.id, paid: paid, note: text.isEmpty ? null : text);
      if (!mounted) return;
      _say(paid ? context.tr('Validé : {n} billet(s) créé(s).', {'n': r.count}) : context.tr('Demande refusée'));
      await _load();
      if (paid && mounted) await _write(r, sendTickets: true);
    } catch (e) {
      if (mounted) _say(AuthRepository.describeError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  /// WhatsApp to the buyer: the reminder of where to pay, or the link to
  /// the tickets once paid.
  Future<void> _write(TicketRequest r, {bool sendTickets = false}) async {
    final to = whatsappDigits(r.whatsapp);
    if (to == null) return _say(context.tr('Ce numéro WhatsApp n’est pas valide.'));
    final link = 'https://marakaj.com/e/${widget.event.slug}/billets/${r.id}';
    final text = sendTickets || r.status == 'paid'
        ? context.tr('Bonjour {name}, votre paiement est bien reçu. Vos billets pour « {title} » (réf. {ref}) : {link}',
            {'name': r.name, 'title': widget.event.title, 'ref': r.ref, 'link': link})
        : context.tr('Bonjour {name}, nous avons bien reçu votre demande de billets pour « {title} » (réf. {ref}). Pour payer et suivre : {link}',
            {'name': r.name, 'title': widget.event.title, 'ref': r.ref, 'link': link});
    final uri = Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent(text)}');
    await (widget.open ?? openOutside)(uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = _all;
    final shown = all == null
        ? const <TicketRequest>[]
        : [
            for (final r in all)
              if (_show == 'pending'
                  ? r.status == 'pending'
                  : _show == 'paid'
                      ? r.status == 'paid'
                      : r.status != 'pending' && r.status != 'paid')
                r,
          ];
    final paid = all?.where((r) => r.status == 'paid') ?? const <TicketRequest>[];
    final pending = all?.where((r) => r.status == 'pending') ?? const <TicketRequest>[];
    final money = moneyFormat('XOF');
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Demandes de billets')), actions: const [bellRoom]),
      body: all == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
                      ]),
                    ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 40 + MediaQuery.viewPaddingOf(context).bottom),
                children: [
                  KajCard(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(spacing: 24, runSpacing: 8, children: [
                        _Figure(label: context.tr('Billets vendus'), value: '${paid.fold<int>(0, (a, r) => a + r.count)}'),
                        _Figure(label: context.tr('Encaissé (validé)'), value: money.format(paid.fold<double>(0, (a, r) => a + r.total))),
                        _Figure(label: context.tr('En attente'), value: money.format(pending.fold<double>(0, (a, r) => a + r.total))),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, children: [
                    for (final f in [
                      ('pending', context.tr('À valider · {n}', {'n': pending.length})),
                      ('paid', context.tr('Payées · {n}', {'n': paid.length})),
                      ('other', context.tr('Autres')),
                    ])
                      ChoiceChip(
                        key: Key('tickets-show-${f.$1}'),
                        label: Text(f.$2),
                        selected: _show == f.$1,
                        onSelected: (_) => setState(() => _show = f.$1),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(context.tr('Aucune demande ici.'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                    ),
                  for (final r in shown)
                    KajCard(
                      key: ValueKey('ticket-request-${r.id}'),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(r.name, style: theme.textTheme.titleSmall)),
                            Text(r.ref, style: theme.textTheme.labelMedium),
                          ]),
                          const SizedBox(height: 4),
                          Text('${[for (final l in r.lines) '${l.qty} × ${l.name}'].join(' · ')} — ${moneyFormat(r.currency).format(r.total)}'),
                          if (r.txnRef != null)
                            Text(context.tr('Transaction indiquée : {txn}', {'txn': r.txnRef}), style: theme.textTheme.bodySmall),
                          Text(
                            r.status == 'pending'
                                ? context.tr('Places gardées jusqu’au {date}',
                                    {'date': DateFormat('d MMM · HH:mm', context.trLocale).format(r.holdUntil)})
                                : context.tr(_statusName(r.status)),
                            style: theme.textTheme.bodySmall,
                          ),
                          if (r.note != null) Text(r.note!, style: theme.textTheme.bodySmall),
                          const SizedBox(height: 6),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            if (r.status == 'pending' || r.status == 'expired')
                              FilledButton(
                                key: Key('ticket-paid-${r.id}'),
                                onPressed: _busy.contains(r.id) ? null : () => _decide(r, true),
                                child: Text(context.tr('Payé')),
                              ),
                            if (r.status == 'pending' || r.status == 'expired')
                              OutlinedButton(
                                key: Key('ticket-refuse-${r.id}'),
                                onPressed: _busy.contains(r.id) ? null : () => _decide(r, false),
                                child: Text(context.tr('Refuser')),
                              ),
                            TextButton.icon(
                              key: Key('ticket-wa-${r.id}'),
                              onPressed: () => _write(r),
                              icon: const Icon(Icons.chat_outlined),
                              label: Text(context.tr('WhatsApp')),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

String _statusName(String s) => switch (s) {
      'paid' => 'Payée',
      'refused' => 'Refusée',
      'expired' => 'Expirée : places remises en vente',
      'refunded' => 'Remboursée',
      _ => 'En attente',
    };

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: theme.textTheme.titleLarge),
      Text(label, style: theme.textTheme.bodySmall),
    ]);
  }
}

/// The door: each ticket's QR scanned, valid once. With signal the server
/// decides; without, the list downloaded beforehand does, and the scans
/// are sent once the signal is back — a ticket shown twice in the hall is
/// reported then.
class TicketDoorScreen extends StatefulWidget {
  const TicketDoorScreen({super.key, required this.tickets, required this.event, this.scan});

  final TicketsRepository tickets;
  final EventSummary event;

  /// Reads a QR (the tests hand one); the camera by default.
  final Future<String?> Function(BuildContext context)? scan;

  @override
  State<TicketDoorScreen> createState() => _TicketDoorScreenState();
}

class _TicketDoorScreenState extends State<TicketDoorScreen> {
  List<DoorTicket>? _kept;
  DateTime? _keptAt;
  List<({String id, DateTime at})> _waiting = const [];
  ({String result, String? holder, String? type, bool offline})? _last;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final k = await widget.tickets.keptDoor(widget.event.id);
    final w = await widget.tickets.keptScans(widget.event.id);
    if (!mounted) return;
    setState(() {
      _kept = k?.tickets;
      _keptAt = k?.at;
      _waiting = w;
    });
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final list = await widget.tickets.doorList(widget.event.id);
      // A ticket scanned here without signal stays used in the copy.
      final waiting = {for (final s in _waiting) s.id};
      final merged = [for (final t in list) waiting.contains(t.id) ? t.used() : t];
      await widget.tickets.keepDoor(widget.event.id, merged);
      if (!mounted) return;
      setState(() {
        _kept = merged;
        _keptAt = DateTime.now();
      });
      _say(context.tr('{n} billets gardés sur ce téléphone.', {'n': merged.length}));
    } catch (e) {
      if (mounted) _say(AuthRepository.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_waiting.isEmpty) return;
    setState(() => _busy = true);
    try {
      final twice = await widget.tickets.doorSync(widget.event.id, _waiting);
      await widget.tickets.keepScans(widget.event.id, const []);
      if (!mounted) return;
      setState(() => _waiting = const []);
      _say(twice.isEmpty
          ? context.tr('Scans envoyés.')
          : context.tr('Scans envoyés. {n} billet(s) étaient déjà utilisés ailleurs.', {'n': twice.length}));
    } catch (e) {
      if (mounted) _say(AuthRepository.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final text = await (widget.scan ?? (c) => BarcodeSheet.scan(c, title: c.tr('Un billet')))(context);
    if (!mounted || text == null) return;
    final id = TicketsRepository.ticketIdFrom(text);
    if (id == null) {
      setState(() => _last = (result: 'unknown', holder: null, type: null, offline: false));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await widget.tickets.scan(id);
      if (!mounted) return;
      setState(() => _last = (result: r.result, holder: r.holder, type: r.type, offline: false));
      // The copy on the phone follows.
      final kept = _kept;
      if (kept != null && r.result == 'valid') {
        final next = [for (final t in kept) t.id == id ? t.used() : t];
        _kept = next;
        await widget.tickets.keepDoor(widget.event.id, next);
      }
    } catch (_) {
      // No signal: the list on the phone decides.
      await _offline(id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offline(String id) async {
    final kept = _kept;
    if (kept == null) {
      if (mounted) _say(context.tr('Pas de réseau, et pas de liste sur ce téléphone : téléchargez-la avant l’ouverture des portes.'));
      return;
    }
    final t = kept.where((x) => x.id == id).firstOrNull;
    if (t == null) {
      setState(() => _last = (result: 'unknown', holder: null, type: null, offline: true));
      return;
    }
    if (t.status != 'valid') {
      setState(() => _last = (result: t.status, holder: t.holder, type: t.type, offline: true));
      return;
    }
    final next = [for (final x in kept) x.id == id ? x.used() : x];
    final waiting = [..._waiting, (id: id, at: DateTime.now())];
    await widget.tickets.keepDoor(widget.event.id, next);
    await widget.tickets.keepScans(widget.event.id, waiting);
    if (!mounted) return;
    setState(() {
      _kept = next;
      _waiting = waiting;
      _last = (result: 'valid', holder: t.holder, type: t.type, offline: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _last;
    final kept = _kept;
    final (Color color, IconData icon, String word) = switch (last?.result) {
      'valid' => (const Color(0xFF1E7B3A), Icons.check_circle, context.tr('Billet valide')),
      'used' => (const Color(0xFFB45309), Icons.error, context.tr('Déjà utilisé')),
      'void' => (const Color(0xFFB91C1C), Icons.cancel, context.tr('Billet annulé')),
      _ => (const Color(0xFFB91C1C), Icons.cancel, context.tr('Billet inconnu')),
    };
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Contrôle à l’entrée')), actions: const [bellRoom]),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 40 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Text(widget.event.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          if (last != null)
            Container(
              key: Key('door-result-${last.result}'),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Icon(icon, color: Colors.white, size: 56),
                const SizedBox(height: 8),
                Text(word, style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                if (last.holder != null)
                  Text('${last.holder} · ${last.type ?? ''}',
                      textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
                if (last.offline)
                  Text(context.tr('Sans réseau : d’après la liste du téléphone'),
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white)),
              ]),
            ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('door-scan'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(context.tr('Scanner un billet')),
          ),
          const SizedBox(height: 18),
          KajCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('Sans réseau dans la salle ?'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  kept == null
                      ? context.tr('Téléchargez la liste des billets avant l’ouverture : le téléphone contrôle alors seul.')
                      : context.tr('{n} billets sur ce téléphone · {in} entrés · liste du {date}', {
                          'n': kept.length,
                          'in': kept.where((t) => t.status == 'used').length,
                          'date': _keptAt == null ? '' : DateFormat('d MMM · HH:mm', context.trLocale).format(_keptAt!),
                        }),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  OutlinedButton.icon(
                    key: const Key('door-download'),
                    onPressed: _busy ? null : _download,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(kept == null ? context.tr('Télécharger la liste') : context.tr('Mettre à jour la liste')),
                  ),
                  if (_waiting.isNotEmpty)
                    FilledButton.tonalIcon(
                      key: const Key('door-send'),
                      onPressed: _busy ? null : _send,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(context.tr('Envoyer {n} scan(s)', {'n': _waiting.length})),
                    ),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
