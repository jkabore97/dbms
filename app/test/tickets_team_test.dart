import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/events/events_repository.dart';
import 'package:kaj_app/core/events/tickets_repository.dart';
import 'package:kaj_app/features/events/tickets_screens.dart';
import 'package:kaj_app/features/events/tickets_team_screens.dart';
import 'package:kaj_app/l10n/strings.dart';

/// 163 in the app: the event's team, a refund, the door's own sale, the
/// figures, the cancellation and its holders, and a member's own way in —
/// the tools of their role alone.
class _Tickets extends TicketsRepository {
  _Tickets() : super(null);

  final calls = <String>[];
  final members = <TeamMember>[
    const TeamMember(userId: 'u2', name: 'Billy', phone: '+22670000002'),
    const TeamMember(userId: 'u3', name: 'Cédric', eventRole: 'controle'),
  ];
  List<StaffEvent> staffOf = const [];
  final reqs = <TicketRequest>[];

  @override
  Future<List<TeamMember>> team(String eventId) async => List.of(members);

  @override
  Future<void> setStaff(String eventId, String userId, String? role) async {
    calls.add('staff:$userId=$role');
    final i = members.indexWhere((m) => m.userId == userId);
    members[i] = TeamMember(userId: userId, name: members[i].name, eventRole: role);
  }

  @override
  Future<List<TicketRequest>> requests(String eventId) async => List.of(reqs);

  @override
  Future<void> refund(String requestId, {String? note}) async {
    calls.add('refund:$requestId');
    final r = reqs.removeAt(0);
    reqs.add(TicketRequest(
        id: r.id, ref: r.ref, name: r.name, whatsapp: r.whatsapp, status: 'refunded', total: r.total,
        currency: r.currency, holdUntil: r.holdUntil, createdAt: r.createdAt, lines: r.lines));
  }

  @override
  Future<List<TicketType>> activeTypes(String eventId) async =>
      const [TicketType(id: 't1', name: 'Standard', price: 2000), TicketType(id: 't2', name: 'VIP', price: 10000)];

  @override
  Future<({String ref, int count, double total})> doorSale(String eventId, Map<String, int> lines, {String? name}) async {
    calls.add('door:${lines.entries.where((e) => e.value > 0).map((e) => '${e.key}x${e.value}').join(',')}');
    return (ref: 'MK-D00R1', count: lines.values.fold(0, (a, b) => a + b), total: 4000.0);
  }

  @override
  Future<Map<String, dynamic>> report(String eventId) async => {
        'currency': 'XOF',
        'paid': {'count': 2, 'total': 9000},
        'pending': {'count': 1, 'total': 2000},
        'refunded': {'count': 1, 'total': 10000},
        'tickets': 6,
        'entered': 4,
        'types': [
          {'name': 'Standard', 'price': 2000, 'capacity': 50, 'sold': 5, 'revenue': 10000, 'entered': 4},
        ],
        'agents': [
          {'name': 'Billy', 'validated': 2, 'validated_total': 9000, 'door_sales': 1, 'door_cash': 6000, 'entered': 0},
        ],
      };

  @override
  Future<List<Map<String, dynamic>>> cancel(String eventId, {String? reason}) async {
    calls.add('cancel:$reason');
    return [
      {'id': 'r1', 'ref': 'MK-3F9A2', 'name': 'Tanti Rose', 'whatsapp': '70123456', 'total': 4000, 'status': 'paid'},
    ];
  }

  @override
  Future<List<StaffEvent>> myStaff() async => staffOf;
}

final _event = EventSummary(
  id: 'e1', orgId: 'o1', kind: 'concert', card: 'rivage', slug: 'concert-fatim-ab12',
  previewToken: 'f00dbabef00dbabef00dbabe', title: 'Concert Fatim', startsAt: DateTime(2027, 6, 5, 20), place: 'CENASA',
  content: const {}, rsvpOn: true, albumOn: false, published: true, createdAt: DateTime(2026, 10, 31),
);

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 1000);
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
  });

  testWidgets('the team: a member given « Billetterie »', (tester) async {
    final t = _Tickets();
    await _pump(tester, EventTeamScreen(tickets: t, event: _event));
    expect(find.text('Billy'), findsOneWidget);
    expect(find.text('Contrôle'), findsOneWidget);
    await tester.tap(find.byKey(const Key('team-role-u2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Billetterie').last);
    await tester.pumpAndSettle();
    expect(t.calls, ['staff:u2=billetterie']);
  });

  testWidgets('a paid request refunded, asked first', (tester) async {
    final t = _Tickets();
    t.reqs.add(TicketRequest(
      id: 'r1', ref: 'MK-3F9A2', name: 'Tanti Rose', whatsapp: '70123456', status: 'paid', total: 4000,
      currency: 'XOF', holdUntil: DateTime.now(), createdAt: DateTime(2026, 11, 1), lines: const [(name: 'Standard', qty: 2)],
    ));
    await _pump(tester, TicketRequestsScreen(tickets: t, event: _event, open: (_) async {}));
    await tester.tap(find.byKey(const Key('tickets-show-paid')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ticket-refund-r1')));
    await tester.pumpAndSettle();
    expect(find.text('Rembourser MK-3F9A2 ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ticket-refund-ok')));
    await tester.pumpAndSettle();
    expect(t.calls, ['refund:r1']);
    expect(find.text('Remboursé : billets annulés.'), findsOneWidget);
  });

  testWidgets('the door sells for cash when it may; the door that only scans does not', (tester) async {
    final t = _Tickets();
    await _pump(tester, TicketDoorScreen(tickets: t, event: _event));
    expect(find.byKey(const Key('door-sell')), findsNothing);
    await _pump(tester, TicketDoorScreen(key: const Key('b'), tickets: t, event: _event, canSell: true));
    await tester.tap(find.byKey(const Key('door-sell')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('door-sale-add-t1')));
    await tester.tap(find.byKey(const Key('door-sale-add-t1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('À encaisser en espèces : 4'), findsOneWidget);
    await tester.tap(find.byKey(const Key('door-sale-ok')));
    await tester.pumpAndSettle();
    expect(t.calls, ['door:t1x2']);
    expect(find.text('2 billet(s) vendu(s) à l’entrée (MK-D00R1).'), findsOneWidget);
  });

  testWidgets('the figures: validated, in, each agent and the cash they hold', (tester) async {
    await _pump(tester, TicketReportScreen(tickets: _Tickets(), eventId: 'e1', title: 'Concert Fatim'));
    expect(find.byKey(const Key('report-entered')), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    expect(find.text('Billy'), findsOneWidget);
    expect(find.text('Espèces à remettre'), findsOneWidget);
    expect(find.text('5 vendus / 50 · 4 entrés'), findsOneWidget);
  });

  testWidgets('cancelled: asked, then each holder written to on WhatsApp', (tester) async {
    final t = _Tickets();
    final opened = <Uri>[];
    await _pump(tester, Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => cancelEvent(context, t, _event, open: (u) async => opened.add(u)),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Pluie');
    await tester.tap(find.byKey(const Key('event-cancel-ok')));
    await tester.pumpAndSettle();
    expect(t.calls, ['cancel:Pluie']);
    expect(find.text('1 acheteur(s) à prévenir. Touchez chacun pour lui écrire sur WhatsApp.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('holder-r1')));
    await tester.pumpAndSettle();
    expect(opened.single.path, '/22670123456');
    expect(opened.single.queryParameters['text'], contains('« Concert Fatim » est annulé (Pluie)'));
  });

  testWidgets('a member at the door: their events, and only the door and the figures', (tester) async {
    final t = _Tickets()
      ..staffOf = [
        StaffEvent(id: 'e1', orgId: 'o1', slug: 'concert-fatim-ab12', title: 'Concert Fatim', role: 'controle',
            startsAt: DateTime(2027, 6, 5, 20)),
        const StaffEvent(id: 'e9', orgId: 'other', slug: 'x', title: 'Ailleurs', role: 'billetterie'),
      ];
    await _pump(tester, Scaffold(body: StaffEventsList(tickets: t, orgId: 'o1')));
    expect(find.text('Concert Fatim'), findsOneWidget);
    expect(find.text('Ailleurs'), findsNothing, reason: 'another business’s event stays there');
    await tester.tap(find.text('Concert Fatim'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('staff-door')), findsOneWidget);
    expect(find.byKey(const Key('staff-report')), findsOneWidget);
    expect(find.byKey(const Key('staff-requests')), findsNothing);
    expect(find.byKey(const Key('staff-journal')), findsNothing);
    await tester.tap(find.byKey(const Key('staff-door')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('door-scan')), findsOneWidget);
    expect(find.byKey(const Key('door-sell')), findsNothing, reason: 'Contrôle scans, nothing else');
  });
}
