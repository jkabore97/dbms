import 'package:supabase_flutter/supabase_flutter.dart';

/// Événementiel (152): the events a business creates — a card with an
/// address, sent to its guests — and what the guests answered.
///
/// Like the admin's repository, none of this is cached: the server's
/// policies decide who may see an event (the business's admins, and only
/// once the platform's switch opens the module to them — events_open), and
/// a stale list would show a screen the server refuses.
class EventsRepository {
  EventsRepository(this._client);

  final SupabaseClient? _client;

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
    });
    return EventSummary.fromJson(Map<String, dynamic>.from(r as Map));
  }

  Future<void> publish(String id, bool on) async {
    await _require().from('events').update({'published': on}).eq('id', id);
  }

  Future<void> setRsvpOn(String id, bool on) async {
    await _require().from('events').update({'rsvp_on': on}).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _require().from('events').delete().eq('id', id);
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
  return card;
}

class EventSummary {
  const EventSummary({
    required this.id,
    required this.orgId,
    required this.kind,
    required this.card,
    required this.slug,
    required this.previewToken,
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
  });

  factory EventRsvp.fromJson(Map<String, dynamic> j) => EventRsvp(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        people: (j['people'] as num?)?.toInt() ?? 1,
        answer: (j['answer'] as String?) ?? 'oui',
        message: j['message'] as String?,
        extra: j['extra'] is Map ? Map<String, dynamic>.from(j['extra'] as Map) : const {},
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
      );

  final String id;
  final String name;
  final int people;

  /// 'oui', 'non', or 'mot' (a word alone, the memorial card's).
  final String answer;
  final String? message;
  final Map<String, dynamic> extra;
  final DateTime createdAt;
}
