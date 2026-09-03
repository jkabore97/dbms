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

    test('on a motorbike, the shop can only confirm the end', () {
      expect(order('in_transit', fulfilment: 'delivery').nextStatuses,
          ['delivered']);
      expect(orderIsOpen('in_transit'), isTrue);
      expect(orderStatusLabel('in_transit'), 'En route');
    });

    test('a final order offers nothing', () {
      for (final s in ['picked_up', 'delivered', 'refused', 'cancelled']) {
        expect(order(s).nextStatuses, isEmpty, reason: s);
        expect(orderIsOpen(s), isFalse, reason: s);
      }
    });
  });

  group('how an order is paid (057)', () {
    CustomerOrder wave(String status, {String? paidAt, String? shopWave}) =>
        CustomerOrder.fromRow({
          'id': 'o1',
          'shop_name': 'A',
          'shop_slug': 'a',
          'status': status,
          'fulfilment': 'delivery',
          'payment_method': 'wave',
          'paid_at': paidAt,
          'shop_wave': shopWave,
          'total': 17500,
          'currency': 'XOF',
          'created_at': '2026-09-03T10:00:00Z',
        });

    test('a Wave order can be paid once accepted, until confirmed', () {
      const link = 'https://pay.wave.com/m/esperance';
      expect(wave('pending', shopWave: link).canPayNow, isFalse,
          reason: 'paying before the shop says yes is money in limbo');
      expect(wave('accepted', shopWave: link).canPayNow, isTrue);
      expect(wave('ready', shopWave: link).canPayNow, isTrue);
      expect(wave('in_transit', shopWave: link).canPayNow, isTrue);
      expect(
          wave('accepted', shopWave: link, paidAt: '2026-09-03T11:00:00Z')
              .canPayNow,
          isFalse,
          reason: 'confirmed paid asks for no more money');
      expect(wave('accepted').canPayNow, isFalse,
          reason: 'no link, no button');
    });

    test('cash is the default and labels read in French', () {
      final o = CustomerOrder.fromRow({
        'id': 'o2',
        'shop_name': 'A',
        'shop_slug': 'a',
        'status': 'pending',
        'fulfilment': 'pickup',
        'total': 500,
        'currency': 'XOF',
        'created_at': '2026-09-03T10:00:00Z',
      });
      expect(o.paymentMethod, 'cash');
      expect(o.isPaid, isFalse);
      expect(paymentLabel('cash'), 'Espèces');
      expect(paymentLabel('wave'), 'Wave');
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
        'courier_name': 'Moussa Moto',
        'lines': [
          {'name': 'Riz parfumé 25kg', 'unit_price': 17500, 'quantity': 2},
        ],
      });
      expect(o.courierName, 'Moussa Moto');
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
