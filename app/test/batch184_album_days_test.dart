import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/events/events_repository.dart';
import 'package:kaj_app/core/events/invitations_repository.dart';
import 'package:kaj_app/features/events/events_screens.dart';
import 'package:kaj_app/features/storefront/my_invitations_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 184 in the app: the days a card's guests add their photos. « Mes
/// invitations » greys « Ajouter des photos » before the first day (« Les
/// photos s'ajoutent à partir du … ») and after the last (« … clos depuis
/// le … »), says the last day while open; the organiser's card shows the
/// days (the default: the event's day and the seven after) and writes the
/// ones chosen, or the default back.
class _Invitations extends InvitationsRepository {
  _Invitations(this.mineList) : super(null, uploadsUrl: '');

  final List<MyInvitation> mineList;
  final calls = <String>[];

  @override
  bool get signedIn => true;

  @override
  Future<List<MyInvitation>> mine() async => mineList;

  @override
  Future<String> addPhoto(String slug, Uint8List bytes, String contentType) async {
    calls.add('photo:$slug');
    return 'events/e1/x.jpg';
  }

  @override
  String? pictureUrl(String key, {int width = 400}) => null;
}

MyInvitation _inv({String? from, String? until, bool open = true}) => MyInvitation.fromJson({
      'id': 'e1',
      'slug': 'mariage-awa-184',
      'title': 'Mariage Awa',
      'starts_at': '2026-11-21T10:00:00Z',
      'tz': 'Africa/Ouagadougou',
      'people': 1,
      'album_on': true,
      'album_allowed': true,
      'photos_used': 0,
      'photos_limit': 5,
      'photos_from': from,
      'photos_until': until,
      'photos_open': open,
    });

class _Events extends EventsRepository {
  _Events({this.from, this.until, this.startsAt}) : super(null);

  final DateTime? from;
  final DateTime? until;
  final DateTime? startsAt;
  final calls = <String>[];

  @override
  Future<EventSummary?> find(String id) async => EventSummary(
        id: 'e1', orgId: 'o1', kind: 'mariage', card: 'come', slug: 'mariage-awa-184', previewToken: 'f00dbabef00dbabef00dbabe',
        title: 'Mariage Awa', startsAt: startsAt, place: null, content: const {}, rsvpOn: true, albumOn: true,
        published: true, createdAt: DateTime(2026, 11, 1), albumFrom: from, albumUntil: until,
        tz: 'Africa/Ouagadougou',
      );

  @override
  Future<List<EventRsvp>> rsvps(String eventId) async => const [];

  @override
  Future<List<EventPicture>> pictures(String eventId) async => const [];

  @override
  String? pictureUrl(String key, {int width = 400}) => null;

  @override
  Future<void> setAlbumDays(String id, DateTime? from, DateTime? until) async =>
      calls.add('days:${from?.toIso8601String().substring(0, 10)}:${until?.toIso8601String().substring(0, 10)}');
}

const _org = OrgSummary(id: 'o1', name: 'Awa', slug: 'awa', profile: 'events', roles: ['owner'], plan: 'pro');

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    locale: const Locale('fr'),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    home: home,
  ));
  await tester.pumpAndSettle();
}

const _add = ValueKey('invitation-add-e1');

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr', null);
  });

  testWidgets('« Mes invitations »: before the first day the add waits and says from when', (tester) async {
    final repo = _Invitations([_inv(from: '2026-11-21', until: '2026-11-28', open: false)]);
    await _pump(tester, MyInvitationsScreen(repo: repo, now: () => DateTime.utc(2026, 11, 14, 12)));
    expect(tester.widget<ButtonStyleButton>(find.byKey(_add)).onPressed, isNull);
    expect(find.text('Les photos s’ajoutent à partir du samedi 21 novembre.'), findsOneWidget);
  });

  testWidgets('« Mes invitations »: after the last day the add is over, and says since when', (tester) async {
    final repo = _Invitations([_inv(from: '2026-11-21', until: '2026-11-28', open: false)]);
    await _pump(tester, MyInvitationsScreen(repo: repo, now: () => DateTime.utc(2026, 11, 30, 12)));
    expect(tester.widget<ButtonStyleButton>(find.byKey(_add)).onPressed, isNull);
    expect(find.text('L’ajout de photos est clos depuis le samedi 28 novembre.'), findsOneWidget);
  });

  testWidgets('« Mes invitations »: on one of the days the add works, and the last day is said', (tester) async {
    final repo = _Invitations([_inv(from: '2026-11-21', until: '2026-11-28')]);
    await _pump(tester, MyInvitationsScreen(
        repo: repo,
        now: () => DateTime.utc(2026, 11, 22, 12),
        pick: (n) async => [(bytes: Uint8List.fromList([1]), type: 'image/jpeg')]));
    expect(find.text('Jusqu’au samedi 28 novembre.'), findsOneWidget);
    await tester.tap(find.byKey(_add));
    await tester.pumpAndSettle();
    expect(repo.calls, ['photo:mariage-awa-184']);
  });

  testWidgets('« Mes invitations »: a server of before 184 (no days) leaves the add as it was', (tester) async {
    final inv = MyInvitation.fromJson({
      'id': 'e1', 'slug': 's', 'title': 'T', 'album_on': true, 'album_allowed': true, 'photos_used': 0, 'photos_limit': 5,
    });
    expect(inv.photosOpen, isTrue);
    expect(inv.canAddPhotos, isTrue);
  });

  testWidgets('the organiser\'s card: the default days said; a reset only once days are set', (tester) async {
    final events = _Events(startsAt: DateTime.utc(2026, 11, 21, 10).toLocal());
    await _pump(tester, EventScreen(events: events, org: _org, eventId: 'e1'));
    final tile = find.byKey(const Key('event-album-days'));
    await tester.ensureVisible(tile);
    expect(find.textContaining('Du samedi 21 novembre au samedi 28 novembre — par défaut'), findsOneWidget);
    expect(find.byKey(const Key('event-album-days-reset')), findsNothing);

    final set = _Events(startsAt: DateTime.utc(2026, 11, 21, 10).toLocal(), from: DateTime(2026, 11, 20), until: DateTime(2026, 12, 5));
    await _pump(tester, EventScreen(events: set, org: _org, eventId: 'e1'));
    await tester.ensureVisible(find.byKey(const Key('event-album-days')));
    expect(find.text('Du vendredi 20 novembre au samedi 5 décembre'), findsOneWidget);
    await tester.tap(find.byKey(const Key('event-album-days-reset')));
    await tester.pumpAndSettle();
    expect(set.calls, ['days:null:null']);
  });

  testWidgets('the organiser\'s card: the calendar writes the days chosen', (tester) async {
    final events = _Events(startsAt: DateTime.utc(2026, 11, 21, 10).toLocal());
    await _pump(tester, EventScreen(events: events, org: _org, eventId: 'e1'));
    await tester.ensureVisible(find.byKey(const Key('event-album-days')));
    await tester.tap(find.byKey(const Key('event-album-days')));
    await tester.pumpAndSettle();
    // the calendar opens on the default days: saved as they are
    await tester.tap(find.text('Enregistrer').last);
    await tester.pumpAndSettle();
    expect(events.calls, ['days:2026-11-21:2026-11-28']);
  });
}
