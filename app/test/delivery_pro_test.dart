import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/org_settings_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';

/// Delivery is Kaj Pro (081): the window says whether the shop delivers,
/// and the basket offers « Livraison » only then — pickup for everyone
/// else, with no toggle to tap into a refusal.
const _items = [PublicItem(id: 'p1', name: 'Savon', price: 450, inStock: true)];

class _Admin extends AdminRepository {
  _Admin({this.included}) : super(null);

  final double? included;

  @override
  Future<Map<String, dynamic>> fetchOrg(String orgId) async => {
    'id': orgId,
    'name': 'Boutique Awa',
    'slug': 'boutique-awa',
    'profile': 'retail',
    'default_currency': 'XOF',
  };

  @override
  Future<String?> waveMerchant(String orgId) async => null;

  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) async => const [];

  @override
  Future<
    ({
      bool enabled,
      String? blurb,
      double? lat,
      double? lng,
      double? deliveryBase,
      double? deliveryPerKm,
    })
  >
  storefront(String orgId) async => (
    enabled: true,
    blurb: null as String?,
    lat: 12.37,
    lng: -1.52,
    deliveryBase: 1000.0,
    deliveryPerKm: 200.0,
  );

  @override
  Future<double?> deliveryReach(String orgId) async => null;

  @override
  Future<double?> deliveryIncludedKm(String orgId) async => included;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  test('the window says whether the shop delivers, and it needs a pin', () {
    final pinned = PublicShop.fromRow({
      'org_id': 'o1',
      'name': 'Boutique',
      'slug': 'b',
      'profile': 'retail',
      'lat': 12.37,
      'lng': -1.52,
      'style': {'delivers': true},
    });
    expect(pinned.delivers, isTrue);
    expect(
      pinned.style.isEmpty,
      isTrue,
      reason: 'delivering is no Pro dressing of the window',
    );

    final free = PublicShop.fromRow({
      'org_id': 'o1',
      'name': 'Boutique',
      'slug': 'b',
      'profile': 'retail',
      'lat': 12.37,
      'lng': -1.52,
      'style': {'delivers': false},
    });
    expect(free.delivers, isFalse);

    // Before 081 the window said nothing: no delivery is promised.
    final old = PublicShop.fromRow({
      'org_id': 'o1',
      'name': 'Boutique',
      'slug': 'b',
      'profile': 'retail',
      'lat': 12.37,
      'lng': -1.52,
    });
    expect(old.delivers, isFalse);
  });

  Future<void> pumpSheet(WidgetTester tester, {required bool delivers}) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderSheet(
            items: _items,
            basket: const {'p1': 1},
            currency: 'XOF',
            delivers: delivers,
            quote: (lat, lng) async => null,
            onSubmit:
                ({
                  required lines,
                  required fulfilment,
                  note,
                  address,
                  phone,
                  required payment,
                  dropLat,
                  dropLng,
                }) async => null,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a shop that does not deliver: pickup, and no toggle', (
    tester,
  ) async {
    await pumpSheet(tester, delivers: false);
    expect(find.text('Livraison'), findsNothing);
    expect(find.byType(SegmentedButton<String>), findsNothing);
  });

  testWidgets('a Pro shop on the map: pickup or delivery', (tester) async {
    await pumpSheet(tester, delivers: true);
    expect(find.text('Livraison'), findsOneWidget);
    expect(find.text('Retrait'), findsOneWidget);
  });

  group('Paramètres › Livraison', () {
    Future<void> open(
      WidgetTester tester,
      _Admin admin, {
      String plan = 'free',
    }) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: OrgSettingsScreen(admin: admin, orgId: 'org-1', plan: plan),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Livraison'));
      await tester.pump();
    }

    testWidgets('a Free shop is told delivery is Mara Pro', (tester) async {
      await open(tester, _Admin());
      expect(find.byKey(const Key('delivery-pro-note')), findsOneWidget);
      expect(find.text('La livraison fait partie de Mara Pro'), findsOneWidget);
    });

    testWidgets('a Pro shop: no note; « Minimum, puis au km » asks how far', (
      tester,
    ) async {
      await open(tester, _Admin(), plan: 'pro');
      expect(find.byKey(const Key('delivery-pro-note')), findsNothing);
      expect(find.byKey(const Key('delivery-included')), findsNothing);
      expect(find.text('Base'), findsOneWidget);
      await tester.tap(find.text('Minimum, puis au km'));
      await tester.pump();
      expect(find.byKey(const Key('delivery-included')), findsOneWidget);
      expect(
        find.text('Minimum'),
        findsOneWidget,
        reason: 'the base reads as the minimum in this mode',
      );
    });

    testWidgets('a shop saved with included kilometres reopens in that mode', (
      tester,
    ) async {
      await open(tester, _Admin(included: 3), plan: 'pro');
      expect(find.byKey(const Key('delivery-included')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('delivery-included')))
            .controller!
            .text,
        '3',
      );
    });
  });
}
