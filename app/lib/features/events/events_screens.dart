import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_repository.dart' show AuthRepository;
import '../../core/auth/models.dart' show OrgSummary;
import '../../core/events/events_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/theme/kaj_card.dart';

/// Where the cards live: the site itself on the web (a preview deploy
/// keeps its own address), marakaj.com from the phone apps.
String eventSiteOrigin() => kIsWeb ? Uri.base.origin : 'https://marakaj.com';

/// Événementiel (152), piece 1: the business's events — each a card with
/// an address for its guests — created here, previewed on the site,
/// published or kept as a draft, and the guests' answers read. The card's
/// words and pictures are edited on the site itself (piece 2).
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key, required this.events, required this.org, this.now});

  final EventsRepository events;
  final OrgSummary org;

  /// The clock, for the tests.
  final DateTime Function()? now;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<EventSummary> _events = const [];
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
    try {
      final list = await widget.events.list(widget.org.id);
      if (!mounted) return;
      setState(() {
        _events = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final made = await showModalBottomSheet<EventSummary>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => NewEventSheet(events: widget.events, org: widget.org, now: widget.now),
    );
    if (made == null || !mounted) return;
    await _load();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EventScreen(events: widget.events, org: widget.org, eventId: made.id, first: made),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Événements')), actions: const [bellRoom]),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('event-new'),
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(context.tr('Nouvelle carte')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
                    ]),
                  ),
                )
              : _events.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.celebration_outlined, size: 48, color: theme.colorScheme.primary),
                          const SizedBox(height: 14),
                          Text(context.tr('Aucune carte pour le moment'), style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(
                            context.tr(
                                'Un mariage, une dot, un anniversaire, une soirée : créez la carte, envoyez son adresse aux invités, et lisez leurs réponses ici.'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ]),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        itemCount: _events.length,
                        itemBuilder: (context, i) => _EventTile(
                          event: _events[i],
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => EventScreen(
                                  events: widget.events, org: widget.org, eventId: _events[i].id, first: _events[i]),
                            ));
                            if (mounted) _load();
                          },
                        ),
                      ),
                    ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.onTap});

  final EventSummary event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = event.startsAt == null
        ? context.tr('Date à fixer')
        : DateFormat('EEEE d MMMM yyyy · HH:mm', context.trLocale).format(event.startsAt!);
    return KajCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        key: Key('event-${event.id}'),
        onTap: onTap,
        leading: CircleAvatar(child: Icon(_kindIcon(event.kind))),
        title: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${context.tr(eventKindName(event.kind))} · ${context.tr(eventCardName(event.card))}\n$when'),
        isThreeLine: true,
        trailing: _StatusChip(published: event.published),
        titleTextStyle: theme.textTheme.titleMedium,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.published});
  final bool published;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(published ? context.tr('Publiée') : context.tr('Brouillon')),
      backgroundColor: published ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

IconData _kindIcon(String kind) => switch (kind) {
      'anniversaire' => Icons.cake_outlined,
      'bapteme' || 'naissance' => Icons.child_care_outlined,
      'diplome' => Icons.school_outlined,
      'gala' || 'inauguration' || 'retraite' => Icons.business_center_outlined,
      'hommage' => Icons.spa_outlined,
      _ => Icons.favorite_outline,
    };

/// « Nouvelle carte »: a name, the kind of event, the card, the day and
/// hour, the place. The server gives the card its address and its first
/// words.
class NewEventSheet extends StatefulWidget {
  const NewEventSheet({super.key, required this.events, required this.org, this.now});

  final EventsRepository events;
  final OrgSummary org;
  final DateTime Function()? now;

  @override
  State<NewEventSheet> createState() => _NewEventSheetState();
}

class _NewEventSheetState extends State<NewEventSheet> {
  final _title = TextEditingController();
  final _place = TextEditingController();
  String _kind = 'mariage';
  String _card = 'come';
  bool _cardChosen = false;
  DateTime? _day;
  TimeOfDay _time = const TimeOfDay(hour: 15, minute: 0);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    super.dispose();
  }

  DateTime _now() => (widget.now ?? DateTime.now)();

  Future<void> _pickDay() async {
    final now = _now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: _time);
    if (!mounted) return;
    setState(() {
      _day = d;
      if (t != null) _time = t;
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = context.tr('Donnez un nom à l’événement : les prénoms, le nom de la fête.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final starts = _day == null ? null : DateTime(_day!.year, _day!.month, _day!.day, _time.hour, _time.minute);
      final made = await widget.events.create(
        orgId: widget.org.id,
        title: title,
        kind: _kind,
        card: _card,
        startsAt: starts,
        place: _place.text.trim().isEmpty ? null : _place.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(made);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AuthRepository.describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayText = _day == null
        ? context.tr('Choisir le jour et l’heure')
        : '${DateFormat('EEEE d MMMM yyyy', context.trLocale).format(_day!)} · ${_time.format(context)}';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('Nouvelle carte'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(
              key: const Key('event-title'),
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: context.tr('Nom de l’événement'),
                hintText: context.tr('Inès & Thomas, Les 30 ans de Rokia…'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('event-kind'),
              initialValue: _kind,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('Genre d’événement'), border: const OutlineInputBorder()),
              items: [
                for (final k in eventKinds)
                  DropdownMenuItem(value: k.$1, child: Text(context.tr(k.$2), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _kind = v;
                  // The card drawn for this kind, unless one was chosen.
                  if (!_cardChosen) {
                    _card = eventCards.firstWhere((c) => c.$3 == v, orElse: () => eventCards.first).$1;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('event-card'),
              initialValue: _card,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('Carte'), border: const OutlineInputBorder()),
              items: [
                for (final c in eventCards)
                  DropdownMenuItem(
                    value: c.$1,
                    child: Text('${context.tr(c.$2)} · ${context.tr(eventKindName(c.$3))}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _card = v;
                  _cardChosen = true;
                });
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('event-day'),
              onPressed: _pickDay,
              icon: const Icon(Icons.event_outlined),
              label: Align(alignment: Alignment.centerLeft, child: Text(dayText)),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('event-place'),
              controller: _place,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.tr('Lieu'),
                hintText: context.tr('Jardins de Koulouba, Ouagadougou'),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('event-save'),
              onPressed: _busy ? null : _save,
              child: Text(context.tr('Créer la carte')),
            ),
          ],
        ),
      ),
    );
  }
}

/// One event: its address for the guests, its preview, published or not,
/// and the answers.
class EventScreen extends StatefulWidget {
  const EventScreen({
    super.key,
    required this.events,
    required this.org,
    required this.eventId,
    this.first,
    this.open,
  });

  final EventsRepository events;
  final OrgSummary org;
  final String eventId;

  /// What the list already knew, drawn before the server answers.
  final EventSummary? first;

  /// Opens a link (the tests look); the browser by default.
  final Future<void> Function(Uri uri)? open;

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  EventSummary? _event;
  List<EventRsvp> _rsvps = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _event = widget.first;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final e = await widget.events.find(widget.eventId);
      final r = e == null ? const <EventRsvp>[] : await widget.events.rsvps(e.id);
      if (!mounted) return;
      setState(() {
        _event = e;
        _rsvps = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      await _load();
      if (done != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthRepository.describeError(e))));
    }
  }

  Future<void> _open(String path) async {
    final uri = Uri.parse('${eventSiteOrigin()}$path');
    final open = widget.open;
    if (open != null) return open(uri);
    await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  }

  Future<void> _copy(String path) async {
    final link = '${eventSiteOrigin()}$path';
    try {
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Lien copié'))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(link)));
    }
  }

  Future<void> _delete() async {
    final e = _event;
    if (e == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Supprimer cette carte ?')),
        content: Text(context.tr('Son adresse ne mènera plus nulle part, et les réponses des invités seront effacées.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('Supprimer'))),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await widget.events.delete(e.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthRepository.describeError(err))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = _event;
    return Scaffold(
      appBar: AppBar(
        title: Text(e?.title ?? context.tr('Carte')),
        actions: [
          if (e != null)
            IconButton(
              key: const Key('event-delete'),
              tooltip: context.tr('Supprimer'),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          // The page's bell, last on every AppBar (115).
          bellRoom,
        ],
      ),
      body: e == null
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error ?? context.tr('Cette carte n’existe plus.'), textAlign: TextAlign.center),
                    ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  KajCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              '${context.tr(eventKindName(e.kind))} · ${context.tr('carte')} ${context.tr(eventCardName(e.card))}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          _StatusChip(published: e.published),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          e.startsAt == null
                              ? context.tr('Date à fixer')
                              : DateFormat('EEEE d MMMM yyyy · HH:mm', context.trLocale).format(e.startsAt!),
                          style: theme.textTheme.titleMedium,
                        ),
                        if (e.place != null && e.place!.isNotEmpty) Text(e.place!, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 14),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          FilledButton.icon(
                            key: const Key('event-preview'),
                            onPressed: () => _open(e.previewPath),
                            icon: const Icon(Icons.visibility_outlined),
                            label: Text(context.tr('Voir la carte')),
                          ),
                          OutlinedButton.icon(
                            key: const Key('event-copy'),
                            onPressed: () => _copy(e.published ? e.publicPath : e.previewPath),
                            icon: const Icon(Icons.link),
                            label: Text(context.tr('Copier le lien')),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                          e.published
                              ? context.tr('Le lien à envoyer aux invités : la carte est publiée.')
                              : context.tr(
                                  'Brouillon : le lien copié est celui de l’aperçu, qui ouvre la carte avant sa publication. Publiez-la pour l’adresse courte à envoyer aux invités.'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  KajCard(
                    child: Column(children: [
                      SwitchListTile(
                        key: const Key('event-published'),
                        title: Text(context.tr('Carte publiée')),
                        subtitle: Text(context.tr('Visible par toute personne qui a le lien.')),
                        value: e.published,
                        onChanged: (v) => _run(() => widget.events.publish(e.id, v),
                            done: v ? context.tr('Carte publiée') : context.tr('Carte remise en brouillon')),
                      ),
                      SwitchListTile(
                        key: const Key('event-rsvp-on'),
                        title: Text(context.tr('Réponses ouvertes')),
                        subtitle: Text(context.tr('Les invités peuvent répondre sur la carte.')),
                        value: e.rsvpOn,
                        onChanged: (v) => _run(() => widget.events.setRsvpOn(e.id, v)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${context.tr('Réponses des invités')} · ${_rsvps.length}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_rsvps.isEmpty)
                    Text(context.tr('Personne n’a encore répondu.'), style: theme.textTheme.bodyMedium)
                  else
                    for (final r in _rsvps)
                      KajCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(switch (r.answer) {
                            'non' => Icons.cancel_outlined,
                            'mot' => Icons.chat_bubble_outline,
                            _ => Icons.check_circle_outline,
                          }),
                          title: Text(r.name),
                          subtitle: Text([
                            switch (r.answer) {
                              'non' => context.tr('Ne viendra pas'),
                              'mot' => context.tr('Un mot'),
                              _ => '${context.tr('Vient')} · ${r.people}',
                            },
                            if (r.message != null && r.message!.isNotEmpty) r.message!,
                            for (final x in r.extra.entries)
                              if ('${x.value}'.isNotEmpty) '${x.key} : ${x.value}',
                          ].join('\n')),
                          isThreeLine: r.message != null && r.message!.isNotEmpty,
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
