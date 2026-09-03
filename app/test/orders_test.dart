import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/orders/orders.dart';

/// Orders on the app's side (055): what each side may do next, and how a
/// row from the server becomes what the screens show.
void main() {
  group('what the shop may do next', () {
    ShopOrder order(String status, {String fulfilment = 'pickup'}) =>
        ShopOrder(
          id: 'o1',
          customerName: 'Awa',
          status: status,
          fulfilment: fulfilment,
          total: 1000,
          currency: 'XOF',
          createdAt: DateTime.now(),
          lines: const [],
        );

    test('a pending order is accepted or refused, nothing else', () {
      expect(order('pending').nextStatuses, ['accepted', 'refused']);
    });

    test('a pickup ends picked up; a delivery ends delivered', () {
      expect(order('accepted').nextStatuses,
          ['ready', 'picked_up', 'cancelled']);
      expect(order('accepted', fulfilment: 'delivery').nextStatuses,
          ['ready', 'delivered', 'cancelled']);
      expect(order('ready').nextStatuses, ['picked_up', 'cancelled']);
      expect(order('ready', fulfilment: 'delivery').nextStatuses,
          ['delivered', 'cancelled']);
    });

    test('a final order offers nothing', () {
      for (final s in ['picked_up', 'delivered', 'refused', 'cancelled']) {
        expect(order(s).nextStatuses, isEmpty, reason: s);
        expect(orderIsOpen(s), isFalse, reason: s);
      }
    });
  });

  group('a row becomes an order', () {
    test('the customer side, lines included', () {
      final o = CustomerOrder.fromRow({
        'id': 'o1',
        'shop_name': 'Boutique Espérance',
        'shop_slug': 'esperance',
        'status': 'accepted',
        'fulfilment': 'delivery',
        'address': 'Dassasgho',
        'total': '35000',
        'currency': 'XOF',
        'created_at': '2026-09-03T10:00:00Z',
        'lines': [
          {'name': 'Riz parfumé 25kg', 'unit_price': 17500, 'quantity': 2},
        ],
      });
      expect(o.isOpen, isTrue);
      expect(o.total, 35000);
      expect(o.lines.single.total, 35000);
      expect(fulfilmentLabel(o.fulfilment), 'Livraison');
      expect(orderStatusLabel(o.status), 'Acceptée');
    });

    test('a row with no lines still stands', () {
      final o = ShopOrder.fromRow({
        'id': 'o2',
        'customer_name': 'Awa',
        'status': 'pending',
        'fulfilment': 'pickup',
        'total': 500,
        'currency': 'XOF',
        'created_at': '2026-09-03T10:00:00Z',
      });
      expect(o.lines, isEmpty);
      expect(o.isOpen, isTrue);
    });
  });
}
