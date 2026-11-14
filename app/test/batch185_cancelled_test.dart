import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/events/events_repository.dart';
import 'package:kaj_app/core/events/invitations_repository.dart';
import 'package:kaj_app/core/events/my_tickets.dart';
import 'package:kaj_app/core/events/tickets_repository.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/features/events/events_screens.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/features/storefront/my_invitations_screen.dart';
import 'package:kaj_app/features/storefront/my_tickets_screens.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 185 in the app: a cancelled event says so — the buyer's « Mes billets »
/// (no code to show at a door), the guest's « Mes invitations » (no photo
/// to add), the organiser's card (« Annulé », the banner, no second
/// cancel); the two bells, in French and English, and where they go.
class _Store extends MyTicketsStore {
  _Store(this.list) : super(null, null);
  final List<MyTickets> list;
  @override
  Future<void> keep(String requestId) async {}
  @override
  Future<List<MyTickets>> kept({DateTime? now}) async => list;
  @override
  Future<List<MyTickets>> refresh({DateTime? now}) async => list;
}

class _Invitations extends InvitationsRepository {
  _Invitations(this.list) : super(null, uploadsUrl: '');
  final List<MyInvitation> list;
  @override
  bool get signedIn => true;
  @override
  Future<List<MyInvitation>> mine() async => list;
  @override
  String? pictureUrl(String key, {int width = 400}) => null;
}

class _Events extends EventsRepository {
  _Events(this.cancelled) : super(null);
  final bool cancelled;
  @override
  Future<EventSummary?> find(String id) async => EventSummary.fromJson({
        'id': 'e1', 'org_id': 'o1', 'kind': 'gala', 'card': 'gala', 'slug': 'gala-185', 'title': 'Gala 185',
        'starts_at': '2027-01-16T23:00:00Z', 'tz': 'Africa/Ouagadougou', 'published': true, 'album_on': true,
        'created_at': '2026-11-01T00:00:00Z',
        'cancelled_at': cancelled ? '2026-11-14T05:52:21Z' : null,
        'cancel_reason': cancelled ? 'la salle est fermée' : null,
      });
  @override
  Future<List<EventRsvp>> rsvps(String eventId) async => const [];
  @override
  Future<List<EventPicture>> pictures(String eventId) async => const [];
  @override
  String? pictureUrl(String key, {int width = 400}) => null;
}

const _org = OrgSummary(id: 'o1', name: 'Awa', slug: 'awa', profile: 'events', roles: ['owner'], plan: 'pro');

Future<void> _pump(WidgetTester tester, Widget home, {String lang = 'fr'}) async {
  tester.view.physicalSize = const Size(420, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    locale: Locale(lang),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    home: home,
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr', null);
  });

  testWidgets('« Mes billets »: a cancelled event says so and why, the refund to come; no QR to show', (tester) async {
    final t = MyTickets.fromJson({
      'id': 'r1', 'slug': 'gala-185', 'title': 'Gala 185', 'status': 'paid', 'ref': 'MK-DE587',
      'starts_at': '2027-01-16T23:00:00Z', 'cancelled': true, 'cancel_reason': 'la salle est fermée',
      'tickets': [{'id': 't1', 'type': 'Standard', 'holder': 'Wendtoin', 'status': 'valid'}],
    });
    expect(MyTickets.fromJson(t.toJson()).cancelled, isTrue, reason: 'kept on the phone with it');
    await _pump(tester, MyTicketsScreen(store: _Store([t]), now: () => DateTime(2026, 11, 14)));
    expect(find.byKey(const ValueKey('ticket-cancelled-r1')), findsOneWidget);
    expect(find.text('Événement annulé'), findsOneWidget);
    expect(find.text('la salle est fermée'), findsOneWidget);
    expect(find.text('L’organisateur revient vers vous pour le remboursement.'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('« Mes invitations »: a cancelled event says so; no photo to add', (tester) async {
    final inv = MyInvitation.fromJson({
      'id': 'e1', 'slug': 'gala-185', 'title': 'Gala 185', 'album_on': true, 'album_allowed': true,
      'photos_used': 0, 'photos_limit': 5, 'cancelled': true, 'cancel_reason': 'la salle est fermée',
    });
    expect(inv.canAddPhotos, isFalse);
    await _pump(tester, MyInvitationsScreen(repo: _Invitations([inv]), now: () => DateTime(2026, 11, 14)));
    expect(find.byKey(const ValueKey('invitation-cancelled-e1')), findsOneWidget);
    expect(find.byKey(const ValueKey('invitation-add-e1')), findsNothing);
  });

  testWidgets('the organiser\'s card: « Annulé », the banner and its reason, no second « Annuler l’événement »', (tester) async {
    await _pump(tester, EventScreen(events: _Events(true), org: _org, eventId: 'e1'));
    expect(find.byKey(const Key('event-cancelled')), findsOneWidget);
    expect(find.text('la salle est fermée'), findsOneWidget);
    expect(find.text('Annulé'), findsOneWidget);
    expect(find.byKey(const Key('tickets-cancel')), findsNothing);

    await _pump(tester, EventScreen(events: _Events(false), org: _org, eventId: 'e1'));
    expect(find.byKey(const Key('event-cancelled')), findsNothing);
    expect(find.text('Publiée'), findsOneWidget);
  });

  testWidgets('the two bells: French as the server wrote, English here; the buyer\'s to « Mes billets », the guest\'s to « Mes invitations »', (tester) async {
    final buyer = NotificationRow(
        id: 'n1', kind: 'event_cancelled_buyer', createdAt: DateTime(2026, 11, 14),
        message: '« Gala 185 » est annulé (la salle est fermée).',
        params: const {'to': 'customer', 'slug': 'gala-185', 'title': 'Gala 185', 'reason': 'la salle est fermée'});
    final guest = NotificationRow(
        id: 'n2', kind: 'event_cancelled_guest', createdAt: DateTime(2026, 11, 14),
        message: '« Gala 185 » est annulé.', params: const {'to': 'customer', 'slug': 'gala-185', 'title': 'Gala 185', 'reason': null});
    for (final lang in ['fr', 'en']) {
      late List<String> out;
      await _pump(tester, Builder(builder: (context) {
        out = [notificationLine(context, buyer), notificationLine(context, guest)];
        return const SizedBox();
      }), lang: lang);
      expect(out, lang == 'fr'
          ? ['« Gala 185 » est annulé (la salle est fermée).', '« Gala 185 » est annulé.']
          : ['“Gala 185” is cancelled (la salle est fermée).', '“Gala 185” is cancelled.']);
    }
    expect(notificationTarget(buyer), '/billets');
    expect(notificationTarget(guest), '/invitations');
  });
}
