import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../net/timeout_client.dart';

/// Événementiel (152): the events a business creates — a card with an
/// address, sent to its guests — and what the guests answered.
///
/// Like the admin's repository, none of this is cached: the server's
/// policies decide who may see an event (the business's admins, and only
/// once the platform's switch opens the module to them — events_open), and
/// a stale list would show a screen the server refuses.
class EventsRepository {
  EventsRepository(this._client, {String? uploadsUrl, http.Client? httpClient})
      : _uploads = (uploadsUrl ?? const String.fromEnvironment('UPLOADS_URL')).replaceAll(RegExp(r'/+$'), ''),
        // Bounded, as every request the app makes (freeze_test): a Worker
        // that never answers must not hang the card's page.
        _http = httpClient ?? TimeoutClient.bounded();

  final SupabaseClient? _client;

  /// The uploads Worker's address (154): where a card's pictures are read,
  /// and removed (155). Empty on an installation without one.
  final String _uploads;
  final http.Client _http;

  bool get isConfigured => _client != null;

  SupabaseClient _require() {
    final c = _client;
    if (c == null) throw StateError('Supabase is not configured in this build.');
    return c;
  }

  /// The platform's switch (events_options, readable by anyone): false
  /// when it cannot be asked, or against a database before 152. A
  /// platform admin does not need it: the module is theirs regardless.
  Future<bool> isPublic() async {
    final c = _client;
    if (c == null) return false;
    try {
      final v = await c.rpc('events_options');
      return v is Map && v['public'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<EventSummary>> list(String orgId) async {
    final rows = await _require()
        .from('events')
        .select()
        .eq('org_id', orgId)
        .order('created_at', ascending: false);
    return [for (final r in rows) EventSummary.fromJson(Map<String, dynamic>.from(r))];
  }

  Future<EventSummary?> find(String id) async {
    final r = await _require().from('events').select().eq('id', id).maybeSingle();
    return r == null ? null : EventSummary.fromJson(Map<String, dynamic>.from(r));
  }

  /// A new event: its address and preview token come from the server
  /// (event_create, bound by the policies as a direct write would be).
  /// [startsAt] is the organiser's local time; its offset for that day goes
  /// with it (153), so the hour typed is the hour the card shows.
  Future<EventSummary> create({
    required String orgId,
    required String title,
    required String kind,
    required String card,
    DateTime? startsAt,
    String? place,
  }) async {
    final r = await _require().rpc('event_create', params: {
      'p_org': orgId,
      'p_title': title,
      'p_kind': kind,
      'p_card': card,
      'p_starts_at': startsAt?.toUtc().toIso8601String(),
      'p_place': place,
      'p_tz': startsAt == null ? null : offsetOf(startsAt),
    });
    return EventSummary.fromJson(Map<String, dynamic>.from(r as Map));
  }

  /// « -05:00 »: the phone's offset for [local]'s day, as the server takes
  /// it (event_tz_known). A phone knows its offset for a date; its zone's
  /// name it does not always.
  static String offsetOf(DateTime local) {
    final o = local.timeZoneOffset;
    final sign = o.isNegative ? '-' : '+';
    final h = o.inHours.abs().toString().padLeft(2, '0');
    final m = (o.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '$sign$h:$m';
  }

  /// The designs one may choose (event_templates, 153), in their order:
  /// the classic cards, then the animated layouts, the Premium films among
  /// them. Against a database before 153, or offline, the twelve cards the
  /// app knows.
  Future<List<EventTemplate>> templates() async {
    final c = _client;
    if (c == null) return knownTemplates;
    try {
      final rows = await c.from('event_templates').select().order('sort');
      final list = [for (final r in rows) EventTemplate.fromJson(Map<String, dynamic>.from(r))];
      return list.isEmpty ? knownTemplates : list;
    } catch (_) {
      return knownTemplates;
    }
  }

  /// Every guest's answer across the business's cards, newest first, each
  /// with its card's name.
  Future<List<EventRsvp>> allRsvps(String orgId) async {
    final rows = await _require()
        .from('event_rsvps')
        .select('*, events!inner(id, title, org_id)')
        .eq('events.org_id', orgId)
        .order('created_at', ascending: false)
        .limit(500);
    return [for (final r in rows) EventRsvp.fromJson(Map<String, dynamic>.from(r))];
  }

  Future<void> publish(String id, bool on) async {
    await _require().from('events').update({'published': on}).eq('id', id);
  }

  Future<void> setRsvpOn(String id, bool on) async {
    await _require().from('events').update({'rsvp_on': on}).eq('id', id);
  }

  /// A card's design changed (155b): its words, day and place stay its
  /// own; the pages read them whatever the design.
  Future<void> setCard(String id, String card) async {
    await _require().from('events').update({'card': card}).eq('id', id);
  }

  /// The card's own facts (157): the title, the kind, the day and the hour,
  /// the place — the row's, changed by the business's admins as 152's
  /// policy allows; the pages read them at their next opening. The offset
  /// goes with the hour, as at creation.
  Future<void> update(String id, {required String title, required String kind, DateTime? startsAt, String? place}) async {
    await _require().from('events').update({
      'title': title,
      'kind': kind,
      'starts_at': startsAt?.toUtc().toIso8601String(),
      'place': place,
      if (startsAt != null) 'tz': offsetOf(startsAt),
    }).eq('id', id);
  }

  /// The guests' album open or closed (155).
  Future<void> setAlbumOn(String id, bool on) async {
    await _require().from('events').update({'album_on': on}).eq('id', id);
  }

  /// The guests' pictures of a card (155), newest first — the business's
  /// admins read the rows; the street reads the album by the card's link.
  Future<List<EventPicture>> pictures(String eventId) async {
    final rows = await _require()
        .from('event_pictures')
        .select()
        .eq('event_id', eventId)
        .eq('state', 'stored')
        .eq('source', 'guest')
        .order('done_at', ascending: false)
        .limit(500);
    return [for (final r in rows) EventPicture.fromJson(Map<String, dynamic>.from(r))];
  }

  /// A stored picture's small copy, for a tile (the Worker's `?w=`); null
  /// without an uploads Worker.
  String? pictureUrl(String key, {int width = 400}) =>
      _uploads.isEmpty ? null : '$_uploads/v1/public/objects/${Uri.encodeComponent(key)}?w=$width';

  /// Removes a picture (155): the uploads Worker asks the server as this
  /// admin (the row goes under the business's own policy), then drops the
  /// bytes. The server's refusal comes back in its own words.
  Future<void> removePicture(String key) async {
    final token = _client?.auth.currentSession?.accessToken;
    if (_uploads.isEmpty || token == null) {
      throw const EventsException('Les photos ne sont pas disponibles sur cette installation.');
    }
    final r = await _http.delete(
      Uri.parse('$_uploads/v1/objects/${Uri.encodeComponent(key)}'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (r.statusCode == 204) return;
    var message = 'La photo n’a pas pu être retirée.';
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['error'] is String) message = j['error'] as String;
    } catch (_) {}
    throw EventsException(message);
  }

  Future<void> delete(String id) async {
    await _require().from('events').delete().eq('id', id);
  }

  /// The guest's arrival (158), marked or taken back by the business's
  /// admins — the one column of an answer they may write.
  Future<void> setArrived(String id, bool on) async {
    await _require()
        .from('event_rsvps')
        .update({'arrived_at': on ? DateTime.now().toUtc().toIso8601String() : null})
        .eq('id', id);
  }

  /// The answer's id inside a guest's pass address (158):
  /// `https://marakaj.com/e/<slug>/invite/<id>`, or the id alone as a
  /// scanner may hand it. Null for anything else.
  static String? passIdFrom(String text) {
    final m = RegExp(r'(?:^|/invite/)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/?\s*$', caseSensitive: false)
        .firstMatch(text.trim());
    return m?.group(1)?.toLowerCase();
  }

  Future<List<EventRsvp>> rsvps(String eventId) async {
    final rows = await _require()
        .from('event_rsvps')
        .select()
        .eq('event_id', eventId)
        .order('created_at', ascending: false);
    return [for (final r in rows) EventRsvp.fromJson(Map<String, dynamic>.from(r))];
  }
}

/// The kinds of event a card can be set to (the card pages' presets), in
/// the order the editor lists them.
const eventKinds = <(String, String)>[
  ('mariage', 'Mariage'),
  ('dot', 'Fiançailles, dot'),
  ('anniversaire', 'Anniversaire'),
  ('bapteme', 'Baptême'),
  ('naissance', 'Naissance, dénomination'),
  ('diplome', 'Remise de diplômes'),
  ('gala', 'Soirée, gala'),
  ('inauguration', 'Inauguration'),
  ('retraite', 'Départ à la retraite'),
  ('hommage', 'Hommage'),
];

/// The twelve cards (the pages under /cartes): key, name, the kind each
/// was drawn for.
const eventCards = <(String, String, String)>[
  ('come', 'Côme', 'mariage'),
  ('ravello', 'Ravello', 'mariage'),
  ('sahel', 'Sahel', 'mariage'),
  ('jardin', 'Jardin', 'mariage'),
  ('minuit', 'Minuit', 'mariage'),
  ('anniv', 'Trente', 'anniversaire'),
  ('bapteme', 'Noé', 'bapteme'),
  ('naissance', 'Imani', 'naissance'),
  ('diplome', 'Promotion', 'diplome'),
  ('gala', 'Dix ans', 'gala'),
  ('dot', 'Dot', 'dot'),
  ('hommage', 'Hommage', 'hommage'),
];

String eventKindName(String kind) {
  for (final k in eventKinds) {
    if (k.$1 == kind) return k.$2;
  }
  return kind;
}

String eventCardName(String card) {
  for (final c in eventCards) {
    if (c.$1 == card) return c.$2;
  }
  for (final t in knownTemplates) {
    if (t.key == card) return t.name;
  }
  return card;
}

/// One design (event_templates, 153): a classic card (app/web/cartes) or
/// an animated layout (app/web/evenements), Premium or not.
class EventTemplate {
  const EventTemplate({
    required this.key,
    required this.family,
    required this.name,
    this.premium = false,
    this.sort = 0,
    this.kinds = const [],
    this.line = '',
  });

  factory EventTemplate.fromJson(Map<String, dynamic> j) => EventTemplate(
        key: j['key'] as String,
        family: (j['family'] as String?) ?? 'classique',
        name: (j['name'] as String?) ?? (j['key'] as String),
        premium: (j['premium'] as bool?) ?? false,
        sort: (j['sort'] as num?)?.toInt() ?? 0,
        kinds: j['kinds'] is List ? [for (final k in j['kinds'] as List) '$k'] : const [],
        line: (j['line'] as String?) ?? '',
      );

  final String key;

  /// 'classique' | 'anime'.
  final String family;
  final String name;
  final bool premium;
  final int sort;

  /// The kinds of event it was drawn for; empty: any.
  final List<String> kinds;
  final String line;

  bool get isAnimated => family == 'anime';

  /// Its preview picture on the site (app/web/cartes/apercu).
  String previewPath() => '/cartes/apercu/$key.jpg';

  bool suits(String kind) => kinds.isEmpty || kinds.contains(kind);
}

/// The forty-seven templates 153 seeds, as the app knows them without the
/// server: the twelve cards, the twenty-one animated layouts, the fourteen
/// Premium films.
const knownTemplates = <EventTemplate>[
  EventTemplate(key: 'come', family: 'classique', name: 'Côme', sort: 1, kinds: ['mariage'], line: 'Un lac, une villa, le soir'),
  EventTemplate(key: 'ravello', family: 'classique', name: 'Ravello', sort: 2, kinds: ['mariage'], line: 'Citronniers et terrasses'),
  EventTemplate(key: 'sahel', family: 'classique', name: 'Sahel', sort: 3, kinds: ['mariage'], line: 'Sable, acacias, lumière dorée'),
  EventTemplate(key: 'jardin', family: 'classique', name: 'Jardin', sort: 4, kinds: ['mariage'], line: 'Un jardin sous les arbres'),
  EventTemplate(key: 'minuit', family: 'classique', name: 'Minuit', sort: 5, kinds: ['mariage'], line: 'Ciel étoilé et compte à rebours'),
  EventTemplate(key: 'anniv', family: 'classique', name: 'Trente', sort: 6, kinds: ['anniversaire'], line: 'Une fête, des bougies'),
  EventTemplate(key: 'bapteme', family: 'classique', name: 'Noé', sort: 7, kinds: ['bapteme'], line: 'Blanc, doux, en famille'),
  EventTemplate(key: 'naissance', family: 'classique', name: 'Imani', sort: 8, kinds: ['naissance'], line: 'Un bébé arrive'),
  EventTemplate(key: 'diplome', family: 'classique', name: 'Promotion', sort: 9, kinds: ['diplome'], line: 'La toque et le diplôme'),
  EventTemplate(key: 'gala', family: 'classique', name: 'Dix ans', sort: 10, kinds: ['gala'], line: 'Une soirée habillée'),
  EventTemplate(key: 'dot', family: 'classique', name: 'Dot', sort: 11, kinds: ['dot'], line: 'Les deux familles'),
  EventTemplate(key: 'hommage', family: 'classique', name: 'Hommage', sort: 12, kinds: ['hommage'], line: 'En sa mémoire'),
  EventTemplate(key: 'anime_lettre', family: 'anime', name: 'La Lettre', sort: 13, line: 'Une enveloppe qui s’ouvre'),
  EventTemplate(key: 'anime_jardin', family: 'anime', name: 'Le Jardin', sort: 14, line: 'Une arche fleurie qui pousse'),
  EventTemplate(key: 'anime_nuit', family: 'anime', name: 'La Nuit', sort: 15, line: 'Du coucher de soleil aux étoiles'),
  EventTemplate(key: 'anime_pagne', family: 'anime', name: 'Le Pagne', sort: 16, line: 'Couleurs tissées du Faso'),
  EventTemplate(key: 'anime_mag', family: 'anime', name: 'Le Magazine', sort: 17, line: 'Une couverture et des pages'),
  EventTemplate(key: 'anime_blason', family: 'anime', name: 'Le Blason', sort: 18, line: 'Un monogramme royal'),
  EventTemplate(key: 'anime_carnet', family: 'anime', name: 'Le Carnet', sort: 19, line: 'Polaroïds et petits mots'),
  EventTemplate(key: 'anime_sahel', family: 'anime', name: 'Sahel', sort: 20, line: 'Acacias, girafe, coucher de soleil'),
  EventTemplate(key: 'anime_lotus', family: 'anime', name: 'Le Lotus', sort: 21, line: 'Un étang, des carpes koï, des lotus'),
  EventTemplate(key: 'anime_foret', family: 'anime', name: 'La Forêt', sort: 22, line: 'Brume, rayons de lumière, fougères'),
  EventTemplate(key: 'anime_cerisiers', family: 'anime', name: 'Les Cerisiers', sort: 23, line: 'Une branche en fleurs, des pétales au vent'),
  EventTemplate(key: 'anime_tournesols', family: 'anime', name: 'Les Tournesols', sort: 24, line: 'Des fleurs qui suivent le soleil'),
  EventTemplate(key: 'anime_lanternes', family: 'anime', name: 'Les Lanternes', sort: 25, line: 'Des lanternes qui s’envolent sur l’eau'),
  EventTemplate(key: 'anime_roseraie', family: 'anime', name: 'La Roseraie', sort: 26, line: 'Des rosiers grimpants qui fleurissent'),
  EventTemplate(key: 'anime_desert', family: 'anime', name: 'Le Désert', sort: 27, line: 'Une bande-annonce dans les dunes'),
  EventTemplate(key: 'anime_champagne', family: 'anime', name: 'Champagne', sort: 28, line: 'Bulles, paillettes et lumières'),
  EventTemplate(key: 'anime_papillons', family: 'anime', name: 'Les Papillons', sort: 29, line: 'Un nuage de papillons qui dessine un cœur'),
  EventTemplate(key: 'anime_hiver', family: 'anime', name: 'Boule à neige', sort: 30, line: 'Un village d’hiver qu’on secoue'),
  EventTemplate(key: 'anime_feux', family: 'anime', name: 'Feux d’artifice', sort: 31, line: 'Vos prénoms écrits par les étincelles'),
  EventTemplate(key: 'anime_aurore', family: 'anime', name: 'L’Aurore', sort: 32, line: 'Des aurores boréales sur un lac'),
  EventTemplate(key: 'anime_ocean', family: 'anime', name: 'L’Océan', sort: 33, line: 'Des cartes postales du bord de mer'),
  EventTemplate(key: 'anime_sahel_p', family: 'anime', name: 'Savane d’or', premium: true, sort: 34, line: 'Soleil couchant, acacias, un horizon d’or'),
  EventTemplate(key: 'anime_lotus_p', family: 'anime', name: 'Étang de lotus', premium: true, sort: 35, line: 'Eau vivante, carpes koï, médaillon de verre'),
  EventTemplate(key: 'anime_foret_p', family: 'anime', name: 'Forêt enchantée', premium: true, sort: 36, line: 'Brume, rayons de lumière, lucioles'),
  EventTemplate(key: 'anime_cerisiers_p', family: 'anime', name: 'Paravent de cerisiers', premium: true, sort: 37, line: 'Panneaux d’or, papiers, sceau rouge'),
  EventTemplate(key: 'anime_tournesols_p', family: 'anime', name: 'Champ d’or', premium: true, sort: 38, line: 'Affiche audacieuse, tournesols au soleil'),
  EventTemplate(key: 'anime_lanternes_p', family: 'anime', name: 'Nuit des lanternes', premium: true, sort: 39, line: 'Chaque chapitre est une lanterne'),
  EventTemplate(key: 'anime_roseraie_p', family: 'anime', name: 'Velours & roses', premium: true, sort: 40, line: 'Roses épanouies, cartes ivoire, sceau de cire'),
  EventTemplate(key: 'anime_desert_p', family: 'anime', name: 'Caravane des dunes', premium: true, sort: 41, line: 'Dunes éclairées, piste d’étape en étape'),
  EventTemplate(key: 'anime_ocean_p', family: 'anime', name: 'Carte du rivage', premium: true, sort: 42, line: 'Vagues réelles, rose des vents, écume'),
  EventTemplate(key: 'anime_champagne_p', family: 'anime', name: 'Champagne Gatsby', premium: true, sort: 43, line: 'Bulles, or et cadres Art déco'),
  EventTemplate(key: 'anime_papillons_p', family: 'anime', name: 'Herbier aux papillons', premium: true, sort: 44, line: 'Vieux papier, planches, papillons vrais'),
  EventTemplate(key: 'anime_hiver_p', family: 'anime', name: 'Fenêtre givrée', premium: true, sort: 45, line: 'Le givre gagne la vitre en défilant'),
  EventTemplate(key: 'anime_feux_p', family: 'anime', name: 'Grand soir', premium: true, sort: 46, line: 'Vos prénoms écrits par les étincelles'),
  EventTemplate(key: 'anime_aurore_p', family: 'anime', name: 'Boréale', premium: true, sort: 47, line: 'Aurores sur le lac, une constellation'),
];

class EventSummary {
  const EventSummary({
    required this.id,
    required this.orgId,
    required this.kind,
    required this.card,
    required this.slug,
    required this.previewToken,
    this.editToken = '',
    required this.title,
    required this.startsAt,
    required this.place,
    required this.content,
    required this.rsvpOn,
    required this.albumOn,
    required this.published,
    required this.createdAt,
  });

  factory EventSummary.fromJson(Map<String, dynamic> j) => EventSummary(
        id: j['id'] as String,
        orgId: j['org_id'] as String,
        kind: (j['kind'] as String?) ?? 'mariage',
        card: (j['card'] as String?) ?? 'come',
        slug: j['slug'] as String,
        previewToken: (j['preview_token'] as String?) ?? '',
        editToken: (j['edit_token'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        startsAt: j['starts_at'] == null ? null : DateTime.tryParse(j['starts_at'] as String)?.toLocal(),
        place: j['place'] as String?,
        content: j['content'] is Map ? Map<String, dynamic>.from(j['content'] as Map) : const {},
        rsvpOn: (j['rsvp_on'] as bool?) ?? true,
        albumOn: (j['album_on'] as bool?) ?? true,
        published: (j['published'] as bool?) ?? false,
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
      );

  final String id;
  final String orgId;
  final String kind;
  final String card;
  final String slug;
  final String previewToken;

  /// The card's editor's key (154): the business's admins read it, the
  /// page edits with it. Empty against a database before 154.
  final String editToken;
  final String title;
  final DateTime? startsAt;
  final String? place;
  final Map<String, dynamic> content;
  final bool rsvpOn;
  final bool albumOn;
  final bool published;
  final DateTime createdAt;

  /// The card's address on the site, for the guests.
  String get publicPath => '/e/$slug';

  /// The same, with the preview token: opens before the card is published,
  /// and before the platform opens the module to everyone.
  String get previewPath => '/e/$slug?apercu=$previewToken';

  /// The card's own editor (154): the words and pictures, edited on the
  /// page itself and saved to the server. Null before 154.
  String? get editPath => editToken.isEmpty ? null : '/e/$slug?apercu=$previewToken&modifier=$editToken';
}

class EventRsvp {
  const EventRsvp({
    required this.id,
    required this.name,
    required this.people,
    required this.answer,
    required this.message,
    required this.extra,
    required this.createdAt,
    this.eventId,
    this.eventTitle,
    this.arrivedAt,
  });

  factory EventRsvp.fromJson(Map<String, dynamic> j) => EventRsvp(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        people: (j['people'] as num?)?.toInt() ?? 1,
        answer: (j['answer'] as String?) ?? 'oui',
        message: j['message'] as String?,
        extra: j['extra'] is Map ? Map<String, dynamic>.from(j['extra'] as Map) : const {},
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
        eventId: j['events'] is Map ? (j['events'] as Map)['id'] as String? : j['event_id'] as String?,
        eventTitle: j['events'] is Map ? (j['events'] as Map)['title'] as String? : null,
        arrivedAt: j['arrived_at'] == null ? null : DateTime.tryParse('${j['arrived_at']}')?.toLocal(),
      );

  final String id;
  final String name;
  final int people;

  /// When the organiser marked the guest arrived (158); null until then.
  final DateTime? arrivedAt;

  /// The card answered, when the list spans the business's cards (153).
  final String? eventId;
  final String? eventTitle;

  /// 'oui', 'non', or 'mot' (a word alone, the memorial card's).
  final String answer;
  final String? message;
  final Map<String, dynamic> extra;
  final DateTime createdAt;
}

/// The server's or the Worker's refusal, in the person's words.
class EventsException implements Exception {
  const EventsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One of the guests' pictures (155): its key under the event, the name
/// the guest gave, when its bytes came in.
class EventPicture {
  const EventPicture({required this.key, required this.guest, required this.bytes, required this.doneAt});

  factory EventPicture.fromJson(Map<String, dynamic> j) => EventPicture(
        key: j['key'] as String,
        guest: j['guest'] as String?,
        bytes: (j['bytes'] as num?)?.toInt(),
        doneAt: j['done_at'] == null ? null : DateTime.tryParse(j['done_at'] as String)?.toLocal(),
      );

  final String key;
  final String? guest;
  final int? bytes;
  final DateTime? doneAt;
}
