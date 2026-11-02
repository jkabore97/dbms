import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/events/events_repository.dart';
import 'package:kaj_app/core/events/tickets_repository.dart';
import 'package:kaj_app/features/events/events_screens.dart';
import 'package:kaj_app/features/events/tickets_screens.dart';
import 'package:kaj_app/l10n/strings.dart';

/// 161, part 1 in the app: the card's « Billetterie » for a business that
/// may sell, the sale laid out (types, where to pay, on), the requests
/// validated or refused with the buyer written to on WhatsApp, and the
/// door — online, then with no signal from the list kept on the phone.
const _ticket = '0c0ffee0-0000-4000-8000-000000000001';
const _ticket2 = '0c0ffee0-0000-4000-8000-000000000002';

class _Tickets extends TicketsRepository {
  _Tickets() : super(null);

  final calls = <String>[];
  bool may = true;
  TicketSettings s = const TicketSettings(on: false, payMethods: []);
  final types = <TicketType>[];
  final reqs = <TicketRequest>[];
  final used = <String>{};
  bool offline = false;

  @override
  Future<bool> allowed(String orgId) async => may;

  @override
  Future<TicketSettings> settings(String eventId) async => TicketSettings(
        on: s.on, payMethods: s.payMethods, payWhatsapp: s.payWhatsapp, holdHours: s.holdHours,
        salesCloseAt: s.salesCloseAt, types: List.of(types));

  @override
  Future<void> saveSettings(String eventId, TicketSettings next) async {
    calls.add('settings:on=${next.on},methods=${next.payMethods.length},wa=${next.payWhatsapp},hold=${next.holdHours}');
    s = next;
  }

  @override
  Future<void> saveType(String eventId, TicketType t) async {
    calls.add('type:${t.name}/${t.price.round()}/${t.capacity}');
    types.add(TicketType(id: 't${types.length + 1}', name: t.name, price: t.price, capacity: t.capacity));
  }

  @override
  Future<List<TicketRequest>> requests(String eventId) async => List.of(reqs);

  @override
  Future<void> decide(String requestId, {required bool paid, String? note, String? method}) async {
    calls.add('decide:$requestId=$paid');
    final i = reqs.indexWhere((r) => r.id == requestId);
    final r = reqs[i];
    reqs[i] = TicketRequest(
      id: r.id, ref: r.ref, name: r.name, whatsapp: r.whatsapp, status: paid ? 'paid' : 'refused', total: r.total,
      currency: r.currency, holdUntil: r.holdUntil, createdAt: r.createdAt, lines: r.lines,
    );
  }

  @override
  Future<ScanResult> scan(String ticketId) async {
    calls.add('scan:$ticketId');
    if (offline) throw Exception('Failed host lookup');
    if (ticketId != _ticket && ticketId != _ticket2) return const ScanResult(result: 'unknown');
    if (used.add(ticketId)) return const ScanResult(result: 'valid', holder: 'Tanti Rose', type: 'VIP');
    return const ScanResult(result: 'used', holder: 'Tanti Rose', type: 'VIP');
  }

  @override
  Future<List<DoorTicket>> doorList(String eventId) async => [
        DoorTicket(id: _ticket, holder: 'Tanti Rose', type: 'VIP', status: used.contains(_ticket) ? 'used' : 'valid'),
        DoorTicket(id: _ticket2, holder: 'Oncle Sam', type: 'Standard', status: used.contains(_ticket2) ? 'used' : 'valid'),
      ];

  @override
  Future<List<String>> doorSync(String eventId, List<({String id, DateTime at})> scans) async {
    calls.add('sync:${scans.map((s) => s.id).join(',')}');
    return const [];
  }
}

class _Events extends EventsRepository {
  _Events(this.fake) : super(null);

  final _Tickets fake;

  @override
  TicketsRepository get tickets => fake;

  @override
  Future<EventSummary?> find(String id) async => _event;

  @override
  Future<List<EventRsvp>> rsvps(String eventId) async => const [];

  @override
  Future<List<EventPicture>> pictures(String eventId) async => const [];
}

final _event = EventSummary(
  id: 'e1', orgId: 'o1', kind: 'concert', card: 'rivage', slug: 'concert-fatim-ab12',
  previewToken: 'f00dbabef00dbabef00dbabe', editToken: 'ed17ed17ed17ed17ed17ed17', title: 'Concert Fatim',
  startsAt: DateTime(2027, 6, 5, 20), place: 'CENASA', content: const {}, rsvpOn: true, albumOn: false,
  published: true, createdAt: DateTime(2026, 10, 31),
);

const _org = OrgSummary(id: 'o1', name: 'Awa Événements', slug: 'awa-evenements', profile: 'events', roles: ['owner'], plan: 'pro');

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 900);
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
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
  });

  test('a ticket QR is read; a guest pass or another link is not', () {
    expect(TicketsRepository.ticketIdFrom('https://marakaj.com/e/concert-fatim-ab12/billet/$_ticket'), _ticket);
    expect(TicketsRepository.ticketIdFrom('https://marakaj.com/e/x/billet/${_ticket.toUpperCase()}/'), _ticket);
    expect(TicketsRepository.ticketIdFrom('https://marakaj.com/e/x/invite/$_ticket'), isNull);
    expect(TicketsRepository.ticketIdFrom(_ticket), isNull);
    expect(EventsRepository.passIdFrom('https://marakaj.com/e/x/billet/$_ticket'), isNull,
        reason: 'a ticket is never taken for a guest pass');
  });

  testWidgets('the card shows « Billetterie » only to a business that may sell', (tester) async {
    final t = _Tickets()..may = false;
    await _pump(tester, EventScreen(events: _Events(t), org: _org, eventId: 'e1'));
    expect(find.byKey(const Key('tickets-card')), findsNothing);
    t.may = true;
    await _pump(tester, EventScreen(key: const Key('again'), events: _Events(t), org: _org, eventId: 'e1'));
    await tester.scrollUntilVisible(find.byKey(const Key('tickets-card')), 200);
    expect(find.text('Billetterie'), findsOneWidget);
    expect(find.text('Le paiement se fait directement à l’organisateur. Marakaj n’encaisse rien.'), findsOneWidget);
  });

  testWidgets('the sale: refused open with nothing to sell; a type, a number, then open', (tester) async {
    final t = _Tickets();
    await _pump(tester, TicketSetupScreen(tickets: t, event: _event));
    await tester.tap(find.byKey(const Key('tickets-on')));
    await tester.pumpAndSettle();
    expect(find.text('Ajoutez d’abord un type de billet.'), findsOneWidget);
    expect(t.calls, isEmpty);

    await tester.tap(find.byKey(const Key('tickets-type-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ticket-type-name')), 'VIP');
    await tester.enterText(find.byKey(const Key('ticket-type-price')), '5 000');
    await tester.enterText(find.byKey(const Key('ticket-type-places')), '50');
    await tester.tap(find.byKey(const Key('ticket-type-ok')));
    await tester.pumpAndSettle();
    expect(t.calls, ['type:VIP/5000/50']);
    expect(find.textContaining('50 places'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tickets-on')));
    await tester.pumpAndSettle();
    expect(find.text('Ajoutez d’abord un numéro où payer.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tickets-method-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ticket-method-number')), '70 00 00 01');
    await tester.enterText(find.byKey(const Key('ticket-method-name')), 'Awa K.');
    await tester.tap(find.byKey(const Key('ticket-method-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Orange Money · 70 00 00 01'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('tickets-whatsapp')), '+226 70 00 00 01');
    await tester.tap(find.byKey(const Key('tickets-on')));
    await tester.pumpAndSettle();
    expect(t.calls.last, 'settings:on=true,methods=1,wa=+226 70 00 00 01,hold=72');
    expect(find.text('Vente ouverte : le bouton « Réserver » est sur la carte.'), findsOneWidget);
  });

  testWidgets('a request: WhatsApp with its link, « Payé » confirmed, then the tickets sent', (tester) async {
    final t = _Tickets();
    t.reqs.add(TicketRequest(
      id: 'r1', ref: 'MK-3F9A2', name: 'Tanti Rose', whatsapp: '70 12 34 56', status: 'pending', total: 9000,
      currency: 'XOF', holdUntil: DateTime.now().add(const Duration(days: 2)), createdAt: DateTime(2026, 11, 1),
      txnRef: 'PP2611.1234', lines: const [(name: 'Standard', qty: 2), (name: 'VIP', qty: 1)],
    ));
    final opened = <Uri>[];
    await _pump(tester, TicketRequestsScreen(tickets: t, event: _event, open: (u) async => opened.add(u)));
    expect(find.text('Tanti Rose'), findsOneWidget);
    expect(find.text('Transaction indiquée : PP2611.1234'), findsOneWidget);
    expect(find.text('À valider · 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ticket-wa-r1')));
    await tester.pumpAndSettle();
    expect(opened.single.host, 'wa.me');
    expect(opened.single.path, '/22670123456');
    expect(opened.single.queryParameters['text'], contains('https://marakaj.com/e/concert-fatim-ab12/billets/r1'));

    await tester.tap(find.byKey(const Key('ticket-paid-r1')));
    await tester.pumpAndSettle();
    expect(find.text('Paiement reçu ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ticket-decide-ok')));
    await tester.pumpAndSettle();
    expect(t.calls, ['decide:r1=true']);
    expect(opened.length, 2, reason: 'the tickets go to the buyer on WhatsApp');
    expect(opened.last.queryParameters['text'], contains('votre paiement est bien reçu'));
    expect(find.text('Tanti Rose'), findsNothing, reason: 'no longer waiting');
    await tester.tap(find.byKey(const Key('tickets-show-paid')));
    await tester.pumpAndSettle();
    expect(find.text('Tanti Rose'), findsOneWidget);
  });

  testWidgets('the door: valid once, then used; with no signal, the list on the phone decides and the scans wait',
      (tester) async {
    final t = _Tickets();
    var next = 'https://marakaj.com/e/concert-fatim-ab12/billet/$_ticket';
    await _pump(tester, TicketDoorScreen(tickets: t, event: _event, scan: (_) async => next));

    await tester.tap(find.byKey(const Key('door-scan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('door-result-valid')), findsOneWidget);
    expect(find.text('Tanti Rose · VIP'), findsOneWidget);
    await tester.tap(find.byKey(const Key('door-scan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('door-result-used')), findsOneWidget);

    next = 'https://marakaj.com/autre';
    await tester.tap(find.byKey(const Key('door-scan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('door-result-unknown')), findsOneWidget);

    // The list downloaded; then the signal goes.
    await tester.tap(find.byKey(const Key('door-download')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 billets sur ce téléphone · 1 entrés'), findsOneWidget);
    t.offline = true;
    next = 'https://marakaj.com/e/concert-fatim-ab12/billet/$_ticket2';
    await tester.tap(find.byKey(const Key('door-scan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('door-result-valid')), findsOneWidget);
    expect(find.text('Sans réseau : d’après la liste du téléphone'), findsOneWidget);
    await tester.tap(find.byKey(const Key('door-scan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('door-result-used')), findsOneWidget, reason: 'the same ticket twice in the hall');

    // Back online: the waiting scan is sent.
    t.offline = false;
    await tester.tap(find.byKey(const Key('door-send')));
    await tester.pumpAndSettle();
    expect(t.calls.last, 'sync:$_ticket2');
    expect(find.byKey(const Key('door-send')), findsNothing);
    expect(await t.keptScans('e1'), isEmpty);
  });
}
