// 182: the Événementiel free, with limits — the console's page, the Free /
// Pro comparison, a free card's ticket allowance.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/events/events_repository.dart';
import 'package:kaj_app/core/events/tickets_repository.dart';
import 'package:kaj_app/features/admin/events_console_screen.dart';
import 'package:kaj_app/features/events/tickets_screens.dart';
import 'package:kaj_app/features/pro/pro_plans_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

class _Admin extends AdminRepository {
  _Admin() : super(null);

  final calls = <String>[];
  var console = const EventsConsole(
    numbers: EventsPlanNumbers(freeTickets: 50, assistFreeDay: 5),
    ticketsOn: true,
    templates: [
      EventsConsoleTemplate(key: 'come', name: 'Côme', family: 'classique', premium: false),
      EventsConsoleTemplate(key: 'anime_sahel_p', name: 'Savane d’or', family: 'anime', premium: true),
    ],
  );

  @override
  Future<EventsConsole> eventsConsole() async => console;

  @override
  Future<EventsConsole> setEventsNumbers({required int freeTickets, required int assistFreeDay}) async {
    calls.add('numbers:$freeTickets/$assistFreeDay');
    return console = EventsConsole(
      numbers: EventsPlanNumbers(freeTickets: freeTickets, assistFreeDay: assistFreeDay),
      ticketsOn: console.ticketsOn,
      templates: console.templates,
    );
  }

  @override
  Future<EventsConsole> setEventTemplatePremium(String key, bool premium) async {
    calls.add('premium:$key=$premium');
    return console = EventsConsole(
      numbers: console.numbers,
      ticketsOn: console.ticketsOn,
      templates: [
        for (final t in console.templates)
          t.key == key ? EventsConsoleTemplate(key: t.key, name: t.name, family: t.family, premium: premium) : t,
      ],
    );
  }
}

class _Tickets extends TicketsRepository {
  _Tickets(this.free) : super(null);
  final ({int? cap, int used})? free;
  @override
  Future<({int? cap, int used})?> freeTickets(String eventId) async => free;
}

final _event = EventSummary(
  id: 'e1', orgId: 'o1', kind: 'concert', card: 'rivage', slug: 'concert-ab12',
  previewToken: 'f00dbabef00dbabef00dbabe', editToken: 'ed17ed17ed17ed17ed17ed17', title: 'Concert',
  startsAt: DateTime(2027, 6, 5, 20), place: 'CENASA', content: const {}, rsvpOn: true, albumOn: false,
  published: true, createdAt: DateTime(2026, 10, 31),
);

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 1400);
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
  testWidgets('the console: the two numbers saved, a design switched Premium or free', (tester) async {
    final admin = _Admin();
    await _pump(tester, EventsConsoleScreen(admin: admin));
    expect(find.text('Billets gratuits par carte'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('events-free-tickets')), '30');
    await tester.enterText(find.byKey(const Key('events-assist-free')), '3');
    await tester.tap(find.byKey(const Key('events-numbers-save')));
    await tester.pumpAndSettle();
    expect(admin.calls, ['numbers:30/3']);
    expect(find.text('Enregistré'), findsOneWidget);

    expect(find.text('Premium · Marakaj Pro'), findsOneWidget);
    await tester.tap(find.byKey(const Key('events-template-anime_sahel_p')));
    await tester.pumpAndSettle();
    expect(admin.calls.last, 'premium:anime_sahel_p=false');
    expect(find.text('Premium · Marakaj Pro'), findsNothing, reason: 'shown free once switched');
  });

  test('the Free / Pro comparison of an Événementiel says its numbers', () {
    final rows = ProPlansScreenRows.events(const EventsPlanNumbers(freeTickets: 30, assistFreeDay: 4));
    final all = [for (final (_, r) in rows) ...r];
    final tickets = all.firstWhere((r) => r.label == 'Billets vendus par carte');
    expect((tickets.free, tickets.pro), ('30', 'Illimité'));
    final assist = all.firstWhere((r) => r.label == 'Textes de l\'assistant par jour');
    expect((assist.free, assist.pro), ('4', '40'));
    final album = all.firstWhere((r) => r.label == 'Album photo des invités');
    expect((album.free, album.pro), (null, true), reason: 'the guests\' album is Pro\'s');
    final pdf = all.firstWhere((r) => r.label == 'PDF à imprimer');
    expect((pdf.free, pdf.pro), (true, true), reason: 'the PDF is free');
  });

  testWidgets('a free card says its ticket allowance; full, it says Pro; Pro says nothing', (tester) async {
    await _pump(tester, Scaffold(body: SingleChildScrollView(child: TicketsCard(tickets: _Tickets((cap: 50, used: 12)), event: _event))));
    expect(find.text('12 sur 50 billets gratuits vendus pour cette carte.'), findsOneWidget);
    await _pump(tester, Scaffold(body: SingleChildScrollView(child: TicketsCard(key: const Key('full'), tickets: _Tickets((cap: 50, used: 50)), event: _event))));
    expect(find.text('Les 50 billets gratuits de cette carte sont vendus. Marakaj Pro vend sans limite.'), findsOneWidget);
    await _pump(tester, Scaffold(body: SingleChildScrollView(child: TicketsCard(key: const Key('pro'), tickets: _Tickets((cap: null, used: 80)), event: _event))));
    expect(find.byKey(const Key('tickets-free-left')), findsNothing);
  });
}
