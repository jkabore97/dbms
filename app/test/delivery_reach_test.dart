import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';

/// A delivery has a reach (069).
///
/// The audit found a shop pinned in New Jersey quoting a customer in
/// Ouagadougou 1 149 450 FCFA for 7 660 km. The database now refuses a
/// delivery beyond the shop's reach; this is the basket saying so before
/// the customer presses anything — the distance, how far the shop goes,
/// and the way out — and never sending an order the shop would refuse.
const _items = [
  PublicItem(id: 'p1', name: 'Savon', price: 450, inStock: true),
];

void main() {
  Future<List<String>> pumpSheet(
    WidgetTester tester,
    DeliveryCheck? Function() answer,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final sent = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OrderSheet(
          items: _items,
          basket: const {'p1': 2},
          currency: 'XOF',
          quote: (lat, lng) async => answer(),
          onSubmit: ({
            required lines,
            required fulfilment,
            note,
            address,
            phone,
            required payment,
            dropLat,
            dropLng,
          }) async {
            sent.add(fulfilment);
            return null;
          },
        ),
      ),
    ));
    await tester.pump();

    // Delivery, an address, and a door pinned from a Maps link.
    await tester.tap(find.text('Livraison'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Où livrer ?'), 'Rue 12, porte 4');
    await tester.tap(find.text('Lien Google Maps'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last,
        'https://www.google.com/maps/@12.3420,-1.5050,17z');
    await tester.tap(find.text('Utiliser'));
    await tester.pumpAndSettle();
    return sent;
  }

  testWidgets('too far: said with the numbers, and the order is not sent',
      (tester) async {
    final sent = await pumpSheet(
      tester,
      () => const DeliveryCheck(distanceKm: 7660, maxKm: 15, tooFar: true),
    );

    expect(find.text('trop loin'), findsOneWidget);
    expect(
        find.textContaining('7660.0 km, livraison jusqu\'à 15 km'), findsOneWidget);
    expect(find.textContaining('Choisissez le retrait en boutique'),
        findsOneWidget);

    final send = find.widgetWithText(FilledButton, 'Envoyer la commande');
    await tester.ensureVisible(send);
    expect(tester.widget<FilledButton>(send).onPressed, isNull,
        reason: 'a delivery the shop would refuse is never sent');
    await tester.tap(send);
    await tester.pump();
    expect(sent, isEmpty);

    // Switching to pickup is the way out, and it sends.
    await tester.tap(find.text('Retrait'));
    await tester.pump();
    await tester.tap(send);
    await tester.pump();
    expect(sent, ['pickup']);
  });

  testWidgets('within reach: priced, and sent', (tester) async {
    final sent = await pumpSheet(
      tester,
      () => const DeliveryCheck(
          fee: 950, distanceKm: 3.2, maxKm: 15, tooFar: false),
    );

    expect(find.text('trop loin'), findsNothing);
    expect(find.textContaining('950'), findsWidgets);

    final send = find.widgetWithText(FilledButton, 'Envoyer la commande');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pump();
    expect(sent, ['delivery']);
  });

  test('reads what delivery_check() sends', () {
    final far = DeliveryCheck.fromRow({
      'fee': null,
      'distance_km': '7660.4',
      'max_km': 15,
      'too_far': true,
    });
    expect(far.fee, isNull);
    expect(far.distanceKm, 7660.4);
    expect(far.maxKm, 15);
    expect(far.tooFar, isTrue);

    final near = DeliveryCheck.fromRow({
      'fee': 950,
      'distance_km': 3.2,
      'max_km': 15,
      'too_far': false,
    });
    expect(near.fee, 950);
    expect(near.tooFar, isFalse);
  });
}
