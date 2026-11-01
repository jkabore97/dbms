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
import '../capture/barcode_sheet.dart';
import 'templates_gallery_screen.dart';

/// Where the cards live: the site itself on the web (a preview deploy
/// keeps its own address), marakaj.com from the phone apps.
String eventSiteOrigin() => kIsWeb ? Uri.base.origin : 'https://marakaj.com';

/// A page of the site opened from the app (155c): inside the app on a
/// phone — the browser's own tab over the app (Chrome Custom Tabs,
/// SFSafariViewController), with its cookies and accounts, closed by its
/// cross — and a new tab on the web app, which is a browser already.
Future<void> openSitePage(Uri uri) async {
  await launchUrl(
    uri,
    mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
    webOnlyWindowName: '_blank',
  );
}

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

/// A guest's WhatsApp as they typed it with their answer (159), as wa.me
/// wants it: digits only, a Burkina number of eight given its code. Null
/// when it is no number.
String? whatsappDigits(Object? raw) {
  if (raw is! String) return null;
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 8) d = '226$d';
  return RegExp(r'^\d{10,15}$').hasMatch(d) ? d : null;
}

/// The reminder written for one guest (159): the organiser sends it on
/// WhatsApp the day before, or whenever they like.
String reminderText(BuildContext context, EventSummary e, String guest) {
  final when = e.startsAt == null
      ? ''
      : ' ${DateFormat('EEEE d MMMM', context.trLocale).format(e.startsAt!)} ${context.tr('à')} ${DateFormat('HH:mm').format(e.startsAt!)}';
  final place = e.place == null || e.place!.isEmpty ? '' : ', ${e.place}';
  return context.tr('Bonjour {name}, petit rappel : « {title} », c’est{when}{place}. À très vite !',
      {'name': guest, 'title': e.title, 'when': when, 'place': place});
}

/// Opens an address in the app it belongs to (WhatsApp for wa.me).
Future<void> openOutside(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

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
  const NewEventSheet({super.key, required this.org, this.now, this.card, this.initial});

  final OrgSummary org;
  final DateTime Function()? now;

  /// The design chosen before the words (browsing the gallery).
  final String? card;

  /// The card whose facts are changed (157): its own prefilled, « Enregistrer ».
  final EventSummary? initial;

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
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i == null) return;
    _title.text = i.title;
    _kind = i.kind;
    final at = i.startsAt;
    if (at != null) {
      _day = DateTime(at.year, at.month, at.day);
      _time = TimeOfDay(hour: at.hour, minute: at.minute);
    }
    _place.text = i.place ?? '';
  }

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
    final editing = widget.initial != null;
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
            Text(context.tr(editing ? 'Modifier les infos' : 'Nouvelle carte'), style: theme.textTheme.titleLarge),
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
              icon: Icon(editing || card != null ? Icons.check : Icons.arrow_forward),
              label: Text(editing
                  ? context.tr('Enregistrer')
                  : card == null
                      ? context.tr('Choisir le modèle')
                      : context.tr('Créer la carte')),
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

  /// The guests' album (155): their pictures, newest first.
  List<EventPicture> _pictures = const [];
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
      // The album is read apart: a database before 155 has no album, and
      // the card's page must still open.
      var p = const <EventPicture>[];
      if (e != null) {
        try {
          p = await widget.events.pictures(e.id);
        } catch (_) {
          p = const [];
        }
      }
      if (!mounted) return;
      setState(() {
        _event = e;
        _rsvps = r;
        _pictures = p;
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
    await openSitePage(uri);
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

  /// « Changer de modèle » (155b): the gallery for this card; back with
  /// true, the page reads the card again.
  /// The guest's arrival (158), marked from the list; the list re-read.
  Future<void> _arrived(EventRsvp r, bool on) async {
    try {
      await widget.events.setArrived(r.id, on);
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthRepository.describeError(err))));
      return;
    }
    await _load();
  }

  Future<void> _editInfo(EventSummary e) async {
    final draft = await showModalBottomSheet<EventDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => NewEventSheet(org: widget.org, initial: e),
    );
    if (draft == null || !mounted) return;
    try {
      await widget.events.update(e.id, title: draft.title, kind: draft.kind, startsAt: draft.startsAt, place: draft.place);
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthRepository.describeError(err))));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Infos enregistrées : la carte les montre à sa prochaine ouverture.'))));
    await _load();
  }

  Future<void> _changeCard(EventSummary e) async {
    final changed = await Navigator.of(context).push<Object>(MaterialPageRoute<Object>(
      builder: (_) => TemplatesGalleryScreen(events: widget.events, org: widget.org, forEvent: e),
    ));
    if (changed == true && mounted) {
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Modèle changé'))));
    }
  }

  /// A guest's picture removed (155): the uploads Worker asks the server
  /// as this admin, then drops the bytes; the album no longer shows it.
  Future<void> _removePicture(EventPicture p) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Retirer cette photo ?')),
        content: Text(context.tr('Elle disparaît de l’album et de la carte.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('Retirer'))),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _run(() => widget.events.removePicture(p.key), done: context.tr('Photo retirée'));
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
                          // The card's facts (157): the title, the kind, the
                          // day and the hour, the place — changed here; the
                          // card shows them at its next opening.
                          OutlinedButton.icon(
                            key: const Key('event-info-edit'),
                            onPressed: () => _editInfo(e),
                            icon: const Icon(Icons.tune),
                            label: Text(context.tr('Modifier les infos')),
                          ),
                          // Another design for this card (155b): the gallery,
                          // its words, day and place kept.
                          OutlinedButton.icon(
                            key: const Key('event-card-change'),
                            onPressed: () => _changeCard(e),
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: Text(context.tr('Changer de modèle')),
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
                      // The guests' album (155): open, the card takes their
                      // pictures; closed, it says so and takes none.
                      SwitchListTile(
                        key: const Key('event-album-on'),
                        title: Text(context.tr('Album des invités ouvert')),
                        subtitle: Text(context.tr('Les invités déposent leurs photos sur la carte ; elles arrivent ici.')),
                        value: e.albumOn,
                        onChanged: (v) => _run(() => widget.events.setAlbumOn(e.id, v)),
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
                      RsvpTile(
                        rsvp: r,
                        onArrived: (on) => _arrived(r, on),
                        remind: (text: () => reminderText(context, e, r.name), open: widget.open ?? openOutside),
                      ),
                  const SizedBox(height: 18),
                  Text(
                    '${context.tr('Album des invités')} · ${_pictures.length}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_pictures.isEmpty)
                    Text(context.tr('Aucune photo d’invité pour le moment.'), style: theme.textTheme.bodyMedium)
                  else
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      children: [
                        for (final p in _pictures)
                          _PictureTile(
                            key: ValueKey(p.key),
                            picture: p,
                            url: widget.events.pictureUrl(p.key),
                            onRemove: () => _removePicture(p),
                          ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

/// One of the guests' pictures (155): its small copy, the name under it,
/// and the cross that removes it.
class _PictureTile extends StatelessWidget {
  const _PictureTile({super.key, required this.picture, required this.url, required this.onRemove});

  final EventPicture picture;

  /// The small copy's address, or null without an uploads Worker.
  final String? url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blank = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.photo_outlined, color: theme.colorScheme.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(fit: StackFit.expand, children: [
        if (url == null)
          blank
        else
          Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => blank),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
            child: Text(
              picture.guest ?? context.tr('Un invité'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            key: Key('picture-remove-${picture.key}'),
            tooltip: context.tr('Retirer'),
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(backgroundColor: Colors.black38, foregroundColor: Colors.white),
            icon: const Icon(Icons.close, size: 18),
          ),
        ),
      ]),
    );
  }
}

/// A guest's answer: who, came or not or a word, what they added.
class RsvpTile extends StatelessWidget {
  const RsvpTile({super.key, required this.rsvp, this.cardTitle, this.onArrived, this.remind});

  final EventRsvp rsvp;

  /// The organiser's mark (158): the guest arrived, or not after all.
  final Future<void> Function(bool on)? onArrived;

  /// The reminder (159): the words to send this guest, and how to open
  /// WhatsApp with them — when the guest left a number.
  final ({String Function() text, Future<void> Function(Uri uri) open})? remind;

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
        if ('${x.value}'.isNotEmpty) '${x.key == 'whatsapp' ? 'WhatsApp' : x.key} : ${x.value}',
      if (r.arrivedAt != null) context.tr('Arrivé à {time}', {'time': DateFormat('HH:mm').format(r.arrivedAt!)}),
    ];
    final arrival = r.answer == 'oui' && onArrived != null;
    final wa = remind == null ? null : whatsappDigits(r.extra['whatsapp']);
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
        trailing: !arrival && wa == null
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (wa != null)
                  IconButton(
                    key: Key('rsvp-whatsapp-${r.id}'),
                    tooltip: context.tr('Rappeler sur WhatsApp'),
                    icon: const Icon(Icons.chat_outlined),
                    onPressed: () => remind!.open(
                        Uri.parse('https://wa.me/$wa?text=${Uri.encodeComponent(remind!.text())}')),
                  ),
                if (arrival)
                  FilterChip(
                    key: Key('rsvp-arrived-${r.id}'),
                    label: Text(r.arrivedAt == null ? context.tr('Présent') : context.tr('Arrivé')),
                    selected: r.arrivedAt != null,
                    onSelected: (v) => onArrived!(v),
                  ),
              ]),
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

  /// The business's cards by id (159): the reminder names the day and the place.
  Map<String, EventSummary> _cards = const {};
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
      final cards = await widget.events.list(widget.org.id);
      if (!mounted) return;
      setState(() {
        _rsvps = list;
        _cards = {for (final c in cards) c.id: c};
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

  Future<void> _arrived(EventRsvp r, bool on) async {
    try {
      await widget.events.setArrived(r.id, on);
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthRepository.describeError(err))));
      return;
    }
    await _load();
  }

  /// At the door (158): the guest's QR scanned with the phone, the answer
  /// it names found among the business's, the arrival marked.
  Future<void> _scan() async {
    final text = await BarcodeSheet.scan(context, title: context.tr('La carte d’invité'));
    if (!mounted || text == null) return;
    await _arrivedFromPass(text);
  }

  Future<void> _arrivedFromPass(String text) async {
    final id = EventsRepository.passIdFrom(text);
    final messenger = ScaffoldMessenger.of(context);
    if (id == null) {
      messenger.showSnackBar(SnackBar(content: Text(context.tr('Ce code n’est pas une carte d’invité.'))));
      return;
    }
    final r = _rsvps.where((x) => x.id == id).firstOrNull;
    if (r == null) {
      messenger.showSnackBar(SnackBar(content: Text(context.tr('Carte d’invité inconnue : pas une réponse de vos cartes.'))));
      return;
    }
    await _arrived(r, true);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(context.tr('{name} : arrivé·e.', {'name': r.name}))));
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
                        // The door (158): a guest's QR scanned, their arrival marked.
                        OutlinedButton.icon(
                          key: const Key('guests-scan'),
                          onPressed: _scan,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(context.tr('Scanner une carte d’invité')),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                          child: Text('${context.tr('Réponses des invités')} · ${_rsvps.length}',
                              style: theme.textTheme.titleMedium),
                        ),
                        for (final r in _rsvps)
                          RsvpTile(
                            rsvp: r,
                            cardTitle: r.eventTitle,
                            onArrived: (on) => _arrived(r, on),
                            remind: _cards[r.eventId] == null
                                ? null
                                : (text: () => reminderText(context, _cards[r.eventId]!, r.name), open: openOutside),
                          ),
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
