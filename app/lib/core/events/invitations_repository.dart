import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../net/timeout_client.dart';
import 'events_repository.dart' show EventsException, eventZoneOffset;

/// « Confirmer ma présence » and « Mes invitations » (183): a guest's side
/// of a card, signed in. The card's one button opens `/presence/<slug>`; the
/// guest confirms (event_presence_confirm), and the cards confirmed are
/// listed here with their photos — five per guest, counted by the server
/// (event_album_add_guest, through the uploads Worker as the guest).
///
/// The tests extend it and answer each method themselves.
class InvitationsRepository {
  InvitationsRepository(this._client, {String? uploadsUrl, http.Client? httpClient})
      : _uploads = (uploadsUrl ?? const String.fromEnvironment('UPLOADS_URL')).replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? TimeoutClient.bounded();

  final SupabaseClient? _client;
  final String _uploads;
  final http.Client _http;

  /// Somebody is signed in (the street's bar asks nothing otherwise).
  bool get signedIn => _client?.auth.currentUser != null;

  SupabaseClient _require() {
    final c = _client;
    if (c == null) throw StateError('Supabase is not configured in this build.');
    return c;
  }

  /// The card as the confirmation screen shows it, and the account's own
  /// answer if any. Null when the card is not open to this person.
  Future<PresenceCard?> card(String slug, String? preview) async {
    final r = await _require().rpc('event_presence_info', params: {'p_slug': slug, 'p_preview': preview});
    return r is Map ? PresenceCard.fromJson(Map<String, dynamic>.from(r)) : null;
  }

  /// « Je confirme »: [first] is false when the account had confirmed
  /// before (the people and the word changed, nobody told again).
  Future<({String title, bool first})> confirm(String slug, String? preview, {required int people, String? message}) async {
    final r = await _require().rpc('event_presence_confirm', params: {
      'p_slug': slug,
      'p_preview': preview,
      'p_people': people,
      'p_message': (message ?? '').trim().isEmpty ? null : message!.trim(),
    });
    final m = r is Map ? r : const {};
    return (title: '${m['title'] ?? ''}', first: m['first'] == true);
  }

  /// « Mes invitations »: the cards this account confirmed.
  Future<List<MyInvitation>> mine() async {
    final r = await _require().rpc('my_event_invitations');
    return [for (final x in (r as List? ?? const [])) MyInvitation.fromJson(Map<String, dynamic>.from(x as Map))];
  }

  /// One photo into the card's album, as the guest: the server says no in
  /// its own words (the five, the album closed…).
  Future<String> addPhoto(String slug, Uint8List bytes, String contentType) async {
    final token = _client?.auth.currentSession?.accessToken;
    if (_uploads.isEmpty || token == null) {
      throw const EventsException('Les photos ne sont pas disponibles sur cette installation.');
    }
    final r = await _http.post(
      Uri.parse('$_uploads/v1/events/${Uri.encodeComponent(slug)}/album/guest'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': contentType},
      body: bytes,
    );
    Object? j;
    try {
      j = jsonDecode(r.body);
    } catch (_) {}
    if (r.statusCode == 201 && j is Map && j['key'] is String) return j['key'] as String;
    throw EventsException(j is Map && j['error'] is String ? j['error'] as String : 'La photo n’est pas passée. Réessayez.');
  }

  /// A picture of the card or of its album (the uploads Worker's public
  /// address); null on an installation without one.
  String? pictureUrl(String key, {int width = 400}) =>
      _uploads.isEmpty ? null : '$_uploads/v1/public/objects/${Uri.encodeComponent(key)}?w=$width';
}

/// The confirmation screen's card (event_presence_info).
class PresenceCard {
  const PresenceCard({
    required this.title,
    this.dateFr,
    this.place,
    this.orgName,
    this.open = true,
    this.album = false,
    this.myPeople,
    this.myMessage,
  });

  factory PresenceCard.fromJson(Map<String, dynamic> j) {
    final mine = j['mine'] is Map ? Map<String, dynamic>.from(j['mine'] as Map) : null;
    return PresenceCard(
      title: '${j['title'] ?? ''}',
      dateFr: j['date_fr'] as String?,
      place: j['place'] as String?,
      orgName: j['org_name'] as String?,
      open: j['open'] != false,
      album: j['album'] == true,
      myPeople: (mine?['people'] as num?)?.toInt(),
      myMessage: mine?['message'] as String?,
    );
  }

  final String title;
  final String? dateFr;
  final String? place;
  final String? orgName;

  /// The answers open (or the tickets on sale).
  final bool open;

  /// The album takes the guests' photos (on, and Marakaj Pro's).
  final bool album;

  /// The account's own confirmation, when there is one.
  final int? myPeople;
  final String? myMessage;
  bool get confirmed => myPeople != null;
}

/// One card of « Mes invitations » (my_event_invitations).
class MyInvitation {
  const MyInvitation({
    required this.id,
    required this.slug,
    required this.title,
    this.preview,
    this.kind,
    this.startsAt,
    this.tz,
    this.place,
    this.cardPreview,
    this.orgName,
    this.people = 1,
    this.albumOn = false,
    this.albumAllowed = false,
    this.albumReview = false,
    this.photosUsed = 0,
    this.photosLimit = 5,
    this.photos = const [],
  });

  factory MyInvitation.fromJson(Map<String, dynamic> j) => MyInvitation(
        id: '${j['id']}',
        slug: '${j['slug']}',
        title: '${j['title'] ?? ''}',
        preview: j['preview'] as String?,
        kind: j['kind'] as String?,
        startsAt: j['starts_at'] == null ? null : DateTime.tryParse('${j['starts_at']}')?.toLocal(),
        tz: j['tz'] as String?,
        place: j['place'] as String?,
        cardPreview: j['card_preview'] as String?,
        orgName: j['org_name'] as String?,
        people: (j['people'] as num?)?.toInt() ?? 1,
        albumOn: j['album_on'] == true,
        albumAllowed: j['album_allowed'] == true,
        albumReview: j['album_review'] == true,
        photosUsed: (j['photos_used'] as num?)?.toInt() ?? 0,
        photosLimit: (j['photos_limit'] as num?)?.toInt() ?? 5,
        photos: [
          for (final p in (j['photos'] as List? ?? const []))
            if (p is Map && p['key'] is String) (key: p['key'] as String, approved: p['approved'] != false),
        ],
      );

  final String id;
  final String slug;
  final String title;

  /// A draft's link, when the guest confirmed through it.
  final String? preview;
  final String? kind;
  final DateTime? startsAt;
  final String? tz;
  final String? place;

  /// The card's own picture (177), drawn by Studio.
  final String? cardPreview;
  final String? orgName;
  final int people;
  final bool albumOn;

  /// The album takes guests' photos at all: Marakaj Pro's (182).
  final bool albumAllowed;

  /// The organiser validates each photo before it shows.
  final bool albumReview;
  final int photosUsed;
  final int photosLimit;

  /// The guest's own photos sent, newest first.
  final List<({String key, bool approved})> photos;

  bool get canAddPhotos => albumOn && albumAllowed && photosUsed < photosLimit;
  int get photosLeft => (photosLimit - photosUsed).clamp(0, photosLimit);

  /// When it starts on the card's own clock, as EventSummary.startsWall.
  DateTime? get startsWall {
    final s = startsAt;
    if (s == null) return null;
    final off = eventZoneOffset(tz);
    if (off == null) return s;
    final w = s.toUtc().add(off);
    return DateTime(w.year, w.month, w.day, w.hour, w.minute);
  }

  /// The card's address on the site, the draft's link with it.
  String get path => '/e/$slug${preview == null || preview!.isEmpty ? '' : '?apercu=$preview'}';
}
