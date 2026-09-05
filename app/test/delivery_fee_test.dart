import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/core/orders/orders.dart';

/// The delivery fee (061) on the app's side of the wire: read whether
/// PostgREST sends it as a number or a string, absent on a pickup, and
/// added to the goods only where a customer or a courier counts money.
void main() {
  group('CustomerOrder', () {
    test('carries the fee and the grand total the customer will hand over',
        () {
      final order = CustomerOrder.fromRow({
        'id': 'o1',
        'shop_name': 'Boutique Awa',
        'shop_slug': 'boutique-awa',
        'status': 'accepted',
        'fulfilment': 'delivery',
        'total': '17500',
        'currency': 'XOF',
        'created_at': '2026-09-05T10:00:00Z',
        'delivery_fee': '800',
        'lines': [],
      });
      expect(order.deliveryFee, 800);
      expect(order.grandTotal, 18300);
    });

    test('a pickup has no fee and the grand total is the goods', () {
      final order = CustomerOrder.fromRow({
        'id': 'o2',
        'shop_name': 'Boutique Awa',
        'shop_slug': 'boutique-awa',
        'status': 'pending',
        'fulfilment': 'pickup',
        'total': 450,
        'currency': 'XOF',
        'created_at': '2026-09-05T10:00:00Z',
        'lines': [],
      });
      expect(order.deliveryFee, isNull);
      expect(order.grandTotal, 450);
    });
  });

  test('ShopOrder reads the fee beside the customer\'s pin', () {
    final order = ShopOrder.fromRow({
      'id': 'o3',
      'customer_name': 'Awa',
      'status': 'ready',
      'fulfilment': 'delivery',
      'total': 17500,
      'currency': 'XOF',
      'created_at': '2026-09-05T10:00:00Z',
      'drop_lat': 12.3894,
      'drop_lng': -1.5197,
      'delivery_fee': 800,
      'lines': [],
    });
    expect(order.hasDropPin, isTrue);
    expect(order.deliveryFee, 800);
  });

  test('DeliveryJob carries what the run pays and how far it is', () {
    final job = DeliveryJob.fromRow({
      'order_id': 'o4',
      'shop_name': 'Boutique Awa',
      'total': '17500',
      'currency': 'XOF',
      'created_at': '2026-09-05T10:00:00Z',
      'delivery_fee': '800',
      'distance_km': '2.0016',
    });
    expect(job.deliveryFee, 800);
    expect(job.distanceKm, closeTo(2.0016, 1e-9));

    final unpriced = DeliveryJob.fromRow({
      'order_id': 'o5',
      'shop_name': 'Boutique Sans Pin',
      'total': 3200,
      'currency': 'XOF',
      'created_at': '2026-09-05T10:00:00Z',
    });
    expect(unpriced.deliveryFee, isNull);
    expect(unpriced.distanceKm, isNull);
  });
}
