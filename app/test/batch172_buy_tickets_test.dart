// 172: tickets are bought signed in, one name per ticket (the owner).
//
//   * the kinds and their prices; « + » adds a name field per ticket, the
//     first one already the account's name;
//   * a missing name or the same name twice is said, nothing sent;
//   * sent: the lines and one {type, name} per ticket, in order.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/features/events/buy_tickets_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

void main() {
  final offer = {
    'on': true, 'open': true, 'slug': 'anniv', 'title': 'Esperance Anniversaire', 'date_fr': 'samedi 16 janvier 2027',
    'place': 'Ouagadougou', 'currency': 'XOF', 'hold_hours': 72, 'org_name': 'Mariage Phanuel & Esperance',
    'types': [
      {'id': 'vip', 'name': 'VIP', 'price': 10000, 'left': null},
      {'id': 'std', 'name': 'Simple', 'price': 2000, 'left': 0},
    ],
  };

  Future<List<Map<String, dynamic>>> pump(WidgetTester tester) async {
    final calls = <Map<String, dynamic>>[];
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => BuyTicketsScreen(
                  client: null,
                  slug: 'anniv',
                  myName: 'Wendtoin Kabore',
                  myPhone: '+22670443328',
                  rpc: (fn, p) async {
                    calls.add({'fn': fn, ...p});
                    if (fn == 'event_ticket_offer') return offer;
                    return {'id': '0b9f3c2e-1d2a-4c5b-9e8f-7a6b5c4d3e2f', 'ref': 'MK-AAAAA'};
                  },
                ),
              )),
              child: const Text('Acheter'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Acheter'));
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('one name per ticket, the first the account\'s; sent in order', (tester) async {
    final calls = await pump(tester);
    expect(find.text('VIP'), findsOneWidget);
    expect(find.text('Complet'), findsOneWidget);
    expect(find.byKey(const Key('buy-more-std')), findsNothing, reason: 'a sold-out kind cannot be added');
    await tester.tap(find.byKey(const Key('buy-more-vip')));
    await tester.tap(find.byKey(const Key('buy-more-vip')));
    await tester.tap(find.byKey(const Key('buy-more-vip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('buy-name-vip-0')), findsOneWidget);
    expect(find.byKey(const Key('buy-name-vip-2')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('buy-name-vip-0'))).controller!.text, 'Wendtoin Kabore');
    expect(tester.widget<TextField>(find.byKey(const Key('buy-whatsapp'))).controller!.text, '+22670443328');
    expect(find.text('30 000 FCFA'), findsOneWidget);

    // a name missing
    await tester.ensureVisible(find.byKey(const Key('buy-send')));
    await tester.tap(find.byKey(const Key('buy-send')));
    await tester.pumpAndSettle();
    expect(find.text('Un nom par billet : chaque personne a le sien.'), findsWidgets);
    // the same person twice
    await tester.enterText(find.byKey(const Key('buy-name-vip-1')), 'Awa');
    await tester.enterText(find.byKey(const Key('buy-name-vip-2')), 'awa ');
    await tester.ensureVisible(find.byKey(const Key('buy-send')));
    await tester.tap(find.byKey(const Key('buy-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('est écrit deux fois'), findsOneWidget);
    expect(calls.where((c) => c['fn'] == 'event_ticket_request'), isEmpty, reason: 'nothing sent yet');
    // right: sent
    await tester.enterText(find.byKey(const Key('buy-name-vip-2')), 'Petit Paul');
    await tester.ensureVisible(find.byKey(const Key('buy-send')));
    await tester.tap(find.byKey(const Key('buy-send')));
    await tester.pumpAndSettle();
    final sent = calls.lastWhere((c) => c['fn'] == 'event_ticket_request');
    expect(sent['p_lines'], [{'type': 'vip', 'qty': 3}]);
    expect(sent['p_holders'], [
      {'type': 'vip', 'name': 'Wendtoin Kabore'},
      {'type': 'vip', 'name': 'Awa'},
      {'type': 'vip', 'name': 'Petit Paul'},
    ]);
    expect(sent['p_name'], 'Wendtoin Kabore');
    expect(find.byType(BuyTicketsScreen), findsNothing, reason: 'on to « Mes billets »');
  });

  testWidgets('one fewer takes its name field away', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('buy-more-vip')));
    await tester.tap(find.byKey(const Key('buy-more-vip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('buy-less-vip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('buy-name-vip-1')), findsNothing);
    expect(find.byKey(const Key('buy-name-vip-0')), findsOneWidget);
  });
}

