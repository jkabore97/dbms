import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/events/events_repository.dart';
import 'package:kaj_app/features/events/events_screens.dart';
import 'package:kaj_app/l10n/strings.dart';

/// 164 in the app: the album's two rules on the card's page — « 5 photos
/// par invité », « Photos visibles après validation » — shown once the
/// album is open, and the organiser's « Valider » on a waiting picture.
class _Events extends EventsRepository {
  _Events({this.albumOn = true}) : super(null);

  final bool albumOn;
  final calls = <String>[];

  @override
  Future<EventSummary?> find(String id) async => EventSummary(
        id: 'e1', orgId: 'o1', kind: 'gala', card: 'rivage', slug: 'gala-ab12', previewToken: 'f00dbabef00dbabef00dbabe',
        title: 'Gala', startsAt: DateTime(2027, 6, 5, 20), place: null, content: const {}, rsvpOn: true, albumOn: albumOn,
        published: true, createdAt: DateTime(2026, 10, 31), albumReview: true,
      );

  @override
  Future<List<EventRsvp>> rsvps(String eventId) async => const [];

  @override
  Future<List<EventPicture>> pictures(String eventId) async => [
        const EventPicture(key: 'events/e1/a.jpg', guest: 'Nora', bytes: 1, doneAt: null, approved: false),
        const EventPicture(key: 'events/e1/b.jpg', guest: 'Julie', bytes: 1, doneAt: null),
      ];

  @override
  String? pictureUrl(String key, {int width = 400}) => null;

  @override
  Future<void> setAlbumRules(String id, {bool? limit, bool? review}) async => calls.add('rules:limit=$limit,review=$review');

  @override
  Future<void> approvePicture(String key) async => calls.add('approve:$key');
}

const _org = OrgSummary(id: 'o1', name: 'Awa', slug: 'awa', profile: 'events', roles: ['owner'], plan: 'pro');

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    home: home,
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => initializeDateFormatting('fr_FR', null));

  testWidgets('the album closed: no rules to set', (tester) async {
    await _pump(tester, EventScreen(events: _Events(albumOn: false), org: _org, eventId: 'e1'));
    expect(find.byKey(const Key('event-album-limit')), findsNothing);
  });

  testWidgets('the rules set; a waiting picture validated, the others as they are', (tester) async {
    final events = _Events();
    await _pump(tester, EventScreen(events: events, org: _org, eventId: 'e1'));
    await tester.tap(find.byKey(const Key('event-album-limit')));
    await tester.pumpAndSettle();
    expect(events.calls, ['rules:limit=true,review=null']);
    expect(find.byKey(const Key('picture-approve-events/e1/b.jpg')), findsNothing, reason: 'already in the album');
    await tester.ensureVisible(find.byKey(const Key('picture-approve-events/e1/a.jpg')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('picture-approve-events/e1/a.jpg')));
    await tester.pumpAndSettle();
    expect(events.calls.last, 'approve:events/e1/a.jpg');
    expect(find.text('Photo validée'), findsOneWidget);
  });
}
