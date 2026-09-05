import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/features/courier/courier_screen.dart';

/// An approved courier with an empty board, for walking the screen itself.
class _ApprovedCourier extends CourierRepository {
  _ApprovedCourier() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<String?> status() async => 'approved';
  @override
  Future<List<DeliveryJob>> available() async => const [];
  @override
  Future<List<DeliveryJob>> mine() async => const [];
}

/// The courier's job card (056): what a row from the server becomes.
void main() {
  testWidgets('the tab lives in the URL, so a refresh keeps it',
      (tester) async {
    // /livreur?onglet=courses must open on Mes courses, not Disponibles:
    // that is what makes the tab a page of its own that a reload restores.
    final router = GoRouter(
      initialLocation: '/livreur?onglet=courses',
      routes: [
        GoRoute(
          path: '/livreur',
          builder: (_, _) => CourierScreen(courier: _ApprovedCourier()),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }

    expect(find.text('Aucune course. Prenez-en une dans Disponibles.'),
        findsOneWidget,
        reason: 'the ?onglet=courses tab was not restored');
  });

  test('a board row has the shop, the door and the total — no customer yet',
      () {
    final job = DeliveryJob.fromRow({
      'order_id': 'o1',
      'shop_name': 'Boutique Espérance',
      'shop_address': 'Rood Woko',
      'shop_lat': '12.3714',
      'shop_lng': -1.5197,
      'drop_address': 'Dassasgho, en face de la pharmacie',
      'drop_lat': '12.3901',
      'drop_lng': -1.4877,
      'total': '17500',
      'currency': 'XOF',
      'created_at': '2026-09-03T10:00:00Z',
    });
    expect(job.shopHasPin, isTrue);
    expect(job.hasDropPin, isTrue);
    expect(job.dropLat, closeTo(12.3901, 1e-9));
    expect(job.customerName, isNull);
    expect(job.phone, isNull);
    expect(job.total, 17500);
    expect(job.status, isNull);
  });

  test('a taken course carries the customer and runs until delivered', () {
    DeliveryJob at(String status) => DeliveryJob.fromRow({
          'order_id': 'o1',
          'shop_name': 'Boutique Espérance',
          'customer_name': 'Awa Client',
          'phone': '+22670000029',
          'drop_address': 'Dassasgho',
          'status': status,
          'total': 17500,
          'currency': 'XOF',
          'created_at': '2026-09-03T10:00:00Z',
        });
    expect(at('ready').isRunning, isTrue);
    expect(at('in_transit').isRunning, isTrue);
    expect(at('delivered').isRunning, isFalse);
    expect(at('cancelled').isRunning, isFalse);
    expect(at('ready').customerName, 'Awa Client');
  });

  test('an unplaced shop offers no itinerary', () {
    final job = DeliveryJob.fromRow({
      'order_id': 'o1',
      'shop_name': 'Boutique Voisine',
      'total': 500,
      'currency': 'XOF',
      'created_at': '2026-09-03T10:00:00Z',
    });
    expect(job.shopHasPin, isFalse);
    expect(job.hasDropPin, isFalse,
        reason: 'no pin shared means no itinerary invented');
  });
}
