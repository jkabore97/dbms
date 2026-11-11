import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/events/events_repository.dart';
import 'package:kaj_app/features/events/events_screens.dart';
import 'package:kaj_app/l10n/strings.dart';

/// 175 in the app: « Photo sur la rue » on the card's page — the owner:
/// « allow them to put their own image or choose between those you
/// generated ». Shown for a public event only; the choice written, the
/// page saying it.
class _Events extends EventsRepository {
  _Events({this.listed = true}) : super(null);

  final bool listed;
  String? street;
  final written = <String?>[];

  @override
  Future<EventSummary?> find(String id) async => EventSummary(
        id: 'e1', orgId: 'o1', kind: 'mariage', card: 'come', slug: 'mariage-ab12', previewToken: 'f00dbabef00dbabef00dbabe',
        title: 'Mariage Awa & Paul', startsAt: DateTime(2027, 6, 5, 20), place: null, content: const {}, rsvpOn: true,
        albumOn: false, published: true, createdAt: DateTime(2026, 10, 31), listed: listed, streetPicture: street,
      );

  @override
  Future<List<EventRsvp>> rsvps(String eventId) async => const [];

  @override
  Future<List<EventPicture>> pictures(String eventId) async => const [];

  @override
  Future<List<String>> cardPictures(String eventId) async => const ['events/e1/own.jpg'];

  @override
  String? pictureUrl(String key, {int width = 400}) => 'https://up.test/$key';

  @override
  Future<void> setStreetPicture(String id, String? choice) async {
    written.add(choice);
    street = choice;
  }
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

  testWidgets('a private event: no « Photo sur la rue »', (tester) async {
    await _pump(tester, EventScreen(events: _Events(listed: false), org: _org, eventId: 'e1'));
    expect(find.byKey(const Key('event-street-picture')), findsNothing);
  });

  testWidgets('a gallery picture chosen, then the card\'s own, then automatic again', (tester) async {
    final events = _Events();
    await _pump(tester, EventScreen(events: events, org: _org, eventId: 'e1'));
    expect(find.text('Automatique : l’aperçu de votre carte, sinon sa photo ou celle de son type d’événement.'), findsOneWidget);

    Future<void> choose(Key key) async {
      await tester.ensureVisible(find.byKey(const Key('event-street-picture')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event-street-picture')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }

    await choose(const Key('street-picture-fete-gala'));
    expect(events.written, ['fete:gala']);
    expect(find.text('Photo sur la rue enregistrée'), findsOneWidget);
    expect(find.text('Une photo de la galerie Marakaj.'), findsOneWidget);

    await choose(const Key('street-picture-own-events/e1/own.jpg'));
    expect(events.written.last, 'events/e1/own.jpg');
    expect(find.text('Une photo de votre carte.'), findsOneWidget);

    await choose(const Key('street-picture-auto'));
    expect(events.written, ['fete:gala', 'events/e1/own.jpg', null]);
  });
}
