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
import 'templates_gallery_screen.dart';

/// Where the cards live: the site itself on the web (a preview deploy
/// keeps its own address), marakaj.com from the phone apps.
String eventSiteOrigin() => kIsWeb ? Uri.base.origin : 'https://marakaj.com';

/// What « Nouvelle carte » asks before the design (153): the name, the
/// kind, the day and hour, the place — and the design itself when it was
/// chosen first, from the gallery.
class EventDraft {
  const EventDraft({
    required this.title,
    required this.kind,
    this.startsAt,
    this.place,
    this.card,
  });

  final String title;
  final String kind;
  final DateTime? startsAt;
  final String? place;
  final String? card;
}

/// « Nouvelle carte », start to finish: the sheet for the words, then the
/// gallery for the design — or the sheet alone when [card] was chosen
/// already — and the card made on the server. Null when the person left.
Future<EventSummary?> startNewCard(
  BuildContext context,
  EventsRepository events,
  OrgSummary org, {
  DateTime Function()? now,
  String? card,
}) async {
  final draft = await showModalBottomSheet<EventDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => NewEventSheet(org: org, now: now, card: card),
  );
  if (draft == null || !context.mounted) return null;
  if (draft.card == null) {
    return Navigator.of(context).push<EventSummary>(MaterialPageRoute(
      builder: (_) => TemplatesGalleryScreen(events: events, org: org, draft: draft, now: now),
    ));
  }
  try {
    return await events.create(
      orgId: org.id,
      title: draft.title,
      kind: draft.kind,
      card: draft.card!,
      startsAt: draft.startsAt,
      place: draft.place,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthRepository.describeError(e))));
    }
    return null;
  }
}

/// Événementiel (152, 153): the business's events — each a card with an
/// address for its guests — created here, previewed on the site,
/// published or kept as a draft, and the guests' answers read. The card's
/// words and pictures are edited on the site itself (piece 2). On its own
/// page here; the Événementiel's home draws [EventsList] under its bar.
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
  int _tick = 0;

  Future<void> _create() async {
    final made = await startNewCard(context, widget.events, widget.org, now: widget.now);
    if (made == null || !mounted) return;
    setState(() => _tick++);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EventScreen(events: widget.events, org: widget.org, eventId: made.id, first: made),
    ));
    if (mounted) setState(() => _tick++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Événements')), actions: const [bellRoom]),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('event-new'),
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(context.tr('Nouvelle carte')),
      ),
      body: EventsList(events: widget.events, org: widget.org, reloadTick: _tick),
    );
  }
}

/// The business's cards, newest first; empty, a word; refused, the word
/// and « Réessayer ». Reloads when [reloadTick] changes.
class EventsList extends StatefulWidget {
  const EventsList({super.key, required this.events, required this.org, this.reloadTick = 0});

  final EventsRepository events;
  final OrgSummary org;
  final int reloadTick;

  @override
  State<EventsList> createState() => _EventsListState();
}

class _EventsListState extends State<EventsList> {
  List<EventSummary> _events = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EventsList old) {
    super.didUpdateWidget(old);
    if (old.reloadTick != widget.reloadTick) _load();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
          ]),
        ),
      );
    }
    if (_events.isEmpty) {
      return Center(
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
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 96 + MediaQuery.viewPaddingOf(context).bottom),
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
        subtitle: Text('${context.tr(eventKindName(event.kind))} · ${eventCardName(event.card)}\n$when'),
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

/// « Nouvelle carte »: a name, the kind of event, the day and hour, the
/// place. Hands back an [EventDraft]: the design comes next, from the
/// gallery — unless [card] was chosen there first.
class NewEventSheet extends StatefulWidget {
  const NewEventSheet({super.key, required this.org, this.now, this.card});

  final OrgSummary org;
  final DateTime Function()? now;

  /// The design chosen before the words (browsing the gallery).
  final String? card;

  @override
  State<NewEventSheet> createState() => _NewEventSheetState();
}

class _NewEventSheetState extends State<NewEventSheet> {
  final _title = TextEditingController();
  final _place = TextEditingController();
  String _kind = 'mariage';
  DateTime? _day;
  TimeOfDay _time = const TimeOfDay(hour: 15, minute: 0);
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

  void _next() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = context.tr('Donnez un nom à l’événement : les prénoms, le nom de la fête.'));
      return;
    }
    final starts = _day == null ? null : DateTime(_day!.year, _day!.month, _day!.day, _time.hour, _time.minute);
    Navigator.of(context).pop(EventDraft(
      title: title,
      kind: _kind,
      startsAt: starts,
      place: _place.text.trim().isEmpty ? null : _place.text.trim(),
      card: widget.card,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayText = _day == null
        ? context.tr('Choisir le jour et l’heure')
        : '${DateFormat('EEEE d MMMM yyyy', context.trLocale).format(_day!)} · ${_time.format(context)}';
    final card = widget.card;
    return Padding(
      // Above the keyboard, and above the phone's bar at the foot (the
      // owner's screenshot: the button cut under the edge).
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom + MediaQuery.viewPaddingOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('Nouvelle carte'), style: theme.textTheme.titleLarge),
            if (card != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr('Modèle : {name}', {'name': eventCardName(card)}),
                  key: const Key('event-card-chosen'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
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
                setState(() => _kind = v);
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
            FilledButton.icon(
              key: const Key('event-save'),
              onPressed: _next,
              icon: Icon(card == null ? Icons.arrow_forward : Icons.check),
              label: Text(card == null ? context.tr('Choisir le modèle') : context.tr('Créer la carte')),
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
                padding: EdgeInsets.fromLTRB(16, 12, 16, 40 + MediaQuery.viewPaddingOf(context).bottom),
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
                              '${context.tr(eventKindName(e.kind))} · ${context.tr('modèle')} ${eventCardName(e.card)}',
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
                          // The card's own editor (154): the words and the
                          // pictures, touched on the page, saved to the server.
                          if (e.editPath != null)
                            FilledButton.icon(
                              key: const Key('event-edit'),
                              onPressed: () => _open(e.editPath!),
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(context.tr('Modifier la carte')),
                            ),
                          (e.editPath == null ? FilledButton.icon : OutlinedButton.icon)(
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
                        if (e.editPath != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              context.tr(
                                  'Sur la carte : touchez un texte pour l’écrire, une photo pour la remplacer, glissez-la pour la recadrer, puis « Enregistrer ».'),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
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
                    for (final r in _rsvps) RsvpTile(rsvp: r),
                ],
              ),
            ),
    );
  }
}

/// A guest's answer: who, came or not or a word, what they added.
class RsvpTile extends StatelessWidget {
  const RsvpTile({super.key, required this.rsvp, this.cardTitle});

  final EventRsvp rsvp;

  /// The card answered, when the list spans several (« Invités »).
  final String? cardTitle;

  @override
  Widget build(BuildContext context) {
    final r = rsvp;
    final lines = [
      if (cardTitle != null && cardTitle!.isNotEmpty) cardTitle!,
      switch (r.answer) {
        'non' => context.tr('Ne viendra pas'),
        'mot' => context.tr('Un mot'),
        _ => '${context.tr('Vient')} · ${r.people}',
      },
      if (r.message != null && r.message!.isNotEmpty) r.message!,
      for (final x in r.extra.entries)
        if ('${x.value}'.isNotEmpty) '${x.key} : ${x.value}',
    ];
    return KajCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(switch (r.answer) {
          'non' => Icons.cancel_outlined,
          'mot' => Icons.chat_bubble_outline,
          _ => Icons.check_circle_outline,
        }),
        title: Text(r.name),
        subtitle: Text(lines.join('\n')),
        isThreeLine: lines.length > 1,
      ),
    );
  }
}

/// « Invités » (153): every answer across the business's cards, newest
/// first, each under its card's name.
class GuestsScreen extends StatefulWidget {
  const GuestsScreen({super.key, required this.events, required this.org, this.embedded = false});

  final EventsRepository events;
  final OrgSummary org;

  /// Drawn inside the home (its bar around it): no AppBar.
  final bool embedded;

  @override
  State<GuestsScreen> createState() => _GuestsScreenState();
}

class _GuestsScreenState extends State<GuestsScreen> {
  List<EventRsvp> _rsvps = const [];
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
      final list = await widget.events.allRsvps(widget.org.id);
      if (!mounted) return;
      setState(() {
        _rsvps = list;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = _loading
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
            : _rsvps.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.people_outline, size: 48, color: theme.colorScheme.primary),
                        const SizedBox(height: 14),
                        Text(context.tr('Aucune réponse pour le moment'),
                            key: const Key('guests-empty'), style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          context.tr('Les réponses de toutes vos cartes, les plus récentes d’abord.'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ]),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                          child: Text('${context.tr('Réponses des invités')} · ${_rsvps.length}',
                              style: theme.textTheme.titleMedium),
                        ),
                        for (final r in _rsvps) RsvpTile(rsvp: r, cardTitle: r.eventTitle),
                      ],
                    ),
                  );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Invités')), actions: const [bellRoom]),
      body: body,
    );
  }
}
