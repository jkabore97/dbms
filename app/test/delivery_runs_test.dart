import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/core/orders/orders.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/courier/courier_screen.dart';
import 'package:kaj_app/features/orders/order_tracking_panel.dart';
import 'package:kaj_app/features/orders/shop_orders_screen.dart';

/// A delivery that runs itself (073).
///
/// The audit: one status word for the shopper, nothing telling the shop an
/// order was stuck, "Livré" in one tap at any door, no outcome for a door
/// that did not open, and nobody's ledger for the courier's cash.
class _Courier extends CourierRepository {
  _Courier() : super(null);

  final delivered = <String>[];
  final failed = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<String?> status() async => 'approved';

  @override
  Future<List<DeliveryJob>> available() async => const [];

  @override
  Future<List<DeliveryJob>> mine() async => [
        DeliveryJob(
          orderId: 'o1',
          shopName: 'Boutique Awa',
          total: 5000,
          currency: 'XOF',
          createdAt: DateTime(2026, 10, 5, 9),
          customerName: 'Fati',
          status: 'in_transit',
        ),
      ];

  @override
  Future<List<CourierEarnings>> earnings() async => const [];

  @override
  Future<List<CashHeld>> cash() async => const [
        CashHeld(orderId: 'o0', shopName: 'Boutique Awa', total: 3000),
        CashHeld(orderId: 'o9', shopName: 'Boutique Awa', total: 1500),
      ];

  @override
  Future<void> deliver(String orderId, String code) async =>
      delivered.add('$orderId:$code');

  @override
  Future<void> fail(String orderId, String reason) async =>
      failed.add('$orderId:$reason');
}

class _Shop extends RetailRepository {
  _Shop() : super(null);

  final selfDelivered = <String>[];
  final received = <String>[];

  @override
  Future<List<ShopOrder>> shopOrders(String orgId) async => [
        ShopOrder(
          id: 'o1',
          customerName: 'Fati',
          status: 'ready',
          fulfilment: 'delivery',
          total: 5000,
          currency: 'XOF',
          createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
          lines: const [],
        ),
      ];

  @override
  Future<Map<String, OrderClock>> orderClocks(String orgId) async => {
        'o1': OrderClock(
            since: DateTime.now().subtract(const Duration(minutes: 25)),
            stuck: true),
      };

  @override
  Future<List<CashOwed>> cashOwed(String orgId) async => const [
        CashOwed(orderId: 'o0', courierName: 'Moussa', total: 3000),
      ];

  @override
  Future<void> deliverSelf(String orderId) async => selfDelivered.add(orderId);

  @override
  Future<void> confirmCashReceived(String orderId) async =>
      received.add(orderId);
}

class _Street extends StorefrontRepository {
  _Street(this.t) : super(null);

  final OrderTracking t;

  @override
  Future<OrderTracking?> tracking(String orderId) async => t;
}

const _org = OrgSummary(
  id: 'org1',
  name: 'Boutique Awa',
  slug: 'awa',
  profile: 'retail',
  roles: ['owner'],
  currency: 'XOF',
);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('a clock says how long, in the shop\'s words', () {
    final now = DateTime(2026, 10, 5, 12);
    String at(Duration d) => OrderClock(since: now.subtract(d)).sinceLabel(now);
    expect(at(const Duration(seconds: 20)), "à l'instant");
    expect(at(const Duration(minutes: 25)), 'depuis 25 min');
    expect(at(const Duration(hours: 2, minutes: 5)), 'depuis 2 h 05');
    expect(at(const Duration(hours: 3)), 'depuis 3 h');
    expect(deliveryOutcomeLabel('absent'), 'client absent');
  });

  testWidgets('the door needs the code; a closed door has its reasons',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final courier = _Courier();
    await tester.pumpWidget(MaterialApp(home: CourierScreen(courier: courier)));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('À remettre aux boutiques'), findsOneWidget);
    await tester.tap(find.textContaining('Mes courses'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Livré'));
    await tester.pumpAndSettle();
    expect(find.text('Code du client'), findsOneWidget);
    final validate = find.widgetWithText(FilledButton, 'Valider la livraison');
    expect(tester.widget<FilledButton>(validate).onPressed, isNull,
        reason: 'four digits, not fewer');
    await tester.enterText(find.byType(TextField), '4821');
    await tester.pump();
    await tester.tap(validate);
    await tester.pumpAndSettle();
    expect(courier.delivered, ['o1:4821']);

    await tester.tap(find.text('Échec'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Client absent'));
    await tester.pumpAndSettle();
    expect(courier.failed, ['o1:absent']);
  });

  testWidgets('a stuck order says so, and the shop can carry it',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final shop = _Shop();
    await tester.pumpWidget(
        MaterialApp(home: ShopOrdersScreen(org: _org, retail: shop)));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('depuis 25 min'), findsOneWidget);
    // 101: the order books its own sale; the till must not ring it again.
    expect(find.textContaining('ne la passez pas à la caisse'), findsOneWidget);
    expect(find.textContaining("Aucun livreur ne l'a prise"), findsOneWidget);
    expect(find.textContaining('Argent chez les livreurs'), findsOneWidget);

    await tester.tap(find.text('Je livre moi-même'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Je livre moi-même').last);
    await tester.pumpAndSettle();
    expect(shop.selfDelivered, ['o1']);

    await tester.tap(find.textContaining('Argent chez les livreurs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reçu'));
    await tester.pumpAndSettle();
    expect(shop.received, ['o0']);
    expect(find.text('Tout est réglé.'), findsOneWidget);
  });

  testWidgets('the shopper sees each step, the courier and the code',
      (tester) async {
    final t = OrderTracking.fromJson({
      'status': 'in_transit',
      'fulfilment': 'delivery',
      'since': DateTime.now().subtract(const Duration(minutes: 8)).toIso8601String(),
      'shop': {'name': 'Boutique Awa', 'phone': '+22670000000'},
      'courier': {'name': 'Moussa', 'phone': '+22670111111'},
      'code': '4821',
      'events': [
        {'status': 'pending', 'at': '2026-10-05T09:00:00Z'},
        {'status': 'accepted', 'at': '2026-10-05T09:04:00Z'},
        {'status': 'ready', 'at': '2026-10-05T09:20:00Z'},
        {'status': 'in_transit', 'at': '2026-10-05T09:31:00Z'},
      ],
    });
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OrderTrackingPanel(
              orderId: 'o1', storefront: _Street(t), onCall: calls.add),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Envoyée'), findsOneWidget);
    expect(find.text('En route'), findsOneWidget);
    expect(find.text('Livrée'), findsOneWidget);
    expect(find.textContaining('Moussa · depuis 8 min'), findsOneWidget);
    expect(find.text('4821'), findsOneWidget);
    await tester.tap(find.text('Appeler Moussa'));
    expect(calls, ['tel:+22670111111']);
  });
}
