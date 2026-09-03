import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';

/// The courier's job card (056): what a row from the server becomes.
void main() {
  test('a board row has the shop, the door and the total — no customer yet',
      () {
    final job = DeliveryJob.fromRow({
      'order_id': 'o1',
      'shop_name': 'Boutique Espérance',
      'shop_address': 'Rood Woko',
      'shop_lat': '12.3714',
      'shop_lng': -1.5197,
      'drop_address': 'Dassasgho, en face de la pharmacie',
      'total': '17500',
      'currency': 'XOF',
      'created_at': '2026-09-03T10:00:00Z',
    });
    expect(job.shopHasPin, isTrue);
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
  });
}
