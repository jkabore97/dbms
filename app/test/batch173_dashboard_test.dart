// 173: the card's « Tableau de bord » and the guests' answers to the
// organiser's questions, in the app.
//
//   * the dashboard shows the openings, the shares and the people expected,
//     fourteen bars, and what counts;
//   * before publication it says the openings start once published;
//   * a guest's answers read « Réponse 1 : … », in order, the empty ones left out.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/events/events_repository.dart';
import 'package:kaj_app/features/events/events_screens.dart';
import 'package:kaj_app/l10n/strings.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));

void main() {
  final today = DateTime.now();
  final stats = EventStats.fromJson({
    'views': 42,
    'shares': 7,
    'days': [
      {'day': today.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10), 'views': 30, 'shares': 5},
      {'day': today.toIso8601String().substring(0, 10), 'views': 12, 'shares': 2},
    ],
    'oui': 9,
    'non': 2,
    'mot': 1,
    'people': 23,
  });

  testWidgets('the dashboard: openings, shares, people, fourteen days', (tester) async {
    await _pump(tester, EventDashboard(stats: stats, published: true));
    expect(find.text('Tableau de bord'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('dash-views'))).data, '42');
    expect(tester.widget<Text>(find.byKey(const Key('dash-shares'))).data, '7');
    expect(tester.widget<Text>(find.byKey(const Key('dash-people'))).data, '23');
    expect(find.textContaining('9 oui · 2 non · 1 mots'), findsOneWidget);
    final bars = find.descendant(of: find.byKey(const Key('event-dashboard')), matching: find.byType(Container));
    expect(bars, findsNWidgets(14));
    final heights = [for (final e in bars.evaluate()) (e.renderObject! as RenderBox).size.height];
    expect(heights.last, greaterThan(3), reason: 'today has openings');
    expect(heights[12], greaterThan(heights.last), reason: 'yesterday had more');
    expect(heights.first, 3, reason: 'an empty day is a thin line');
  });

  testWidgets('a card not yet published says when counting starts', (tester) async {
    await _pump(tester, EventDashboard(stats: EventStats.fromJson(const {}), published: false));
    expect(find.text('Les ouvertures se comptent une fois la carte publiée.'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('dash-views'))).data, '0');
  });

  testWidgets('the guests\' answers to the questions, in order', (tester) async {
    final r = EventRsvp.fromJson({
      'id': 'r1',
      'name': 'Fati',
      'people': 2,
      'answer': 'oui',
      'extra': {
        'whatsapp': '+22670000000',
        'answers': ['Riz gras', '', 'Coupé-décalé'],
      },
      'created_at': '2026-11-10T10:00:00Z',
    });
    await _pump(tester, RsvpTile(rsvp: r));
    final sub = find.textContaining('Réponse 1 : Riz gras');
    expect(sub, findsOneWidget);
    final text = tester.widget<Text>(sub).data!;
    expect(text, contains('Réponse 3 : Coupé-décalé'));
    expect(text, isNot(contains('Réponse 2')));
    expect(text, isNot(contains('answers')));
    expect(text, contains('WhatsApp : +22670000000'));
  });
}
