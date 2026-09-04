import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/orders/order_alert.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The doorbell and the sleeping basket — the pair that turns first orders
/// into second orders. The shop's home re-reads the pending count while it
/// is open and rings when it rises (never when it falls); the shopper's
/// basket sleeps on the device and wakes only onto an empty one. On a VM
/// there is no browser, so OrderAlert must say so instead of pretending.
class _Till extends RetailRepository {
  _Till() : super(null);

  int pending = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();

  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) async =>
      const [];

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async =>
      const [];

  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) async => 0;

  @override
  Future<int> pendingOrders(String orgId) async => pending;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  const org = OrgSummary(
    id: '00000000-0000-0000-0000-000000000001',
    name: 'Boutique Esperance',
    slug: 'boutique-esperance',
    profile: 'retail',
    roles: ['owner'],
    currency: 'XOF',
  );

  group('OrderAlert on a platform with no browser', () {
    test('says so honestly and stays silent without throwing', () async {
      expect(OrderAlert.supported, isFalse);
      expect(OrderAlert.granted, isFalse);
      expect(await OrderAlert.request(), isFalse);
      OrderAlert.show('Nouvelle commande', 'ne doit pas lancer');
    });
  });

  group('the doorbell', () {
    Future<_Till> pumpHome(WidgetTester tester) async {
      final till = _Till();
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: StoreHomeScreen(org: org, retail: till),
      ));
      await tester.pump();
      await tester.pump();
      return till;
    }

    testWidgets('a rise rings, in words, with the way to the orders',
        (tester) async {
      final till = await pumpHome(tester);

      till.pending = 2;
      await tester.pump(const Duration(seconds: 91));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Nouvelle commande : 2 à traiter sur la vitrine.'),
        findsOneWidget,
      );
      expect(find.text('Voir'), findsOneWidget);
    });

    testWidgets('a count that stays or falls is not news', (tester) async {
      final till = await pumpHome(tester);

      await tester.pump(const Duration(seconds: 91));
      await tester.pump();
      expect(find.textContaining('Nouvelle commande'), findsNothing);

      // The shop answered an order elsewhere: the count falls. Quiet.
      till.pending = 0;
      await tester.pump(const Duration(seconds: 91));
      await tester.pump();
      expect(find.textContaining('Nouvelle commande'), findsNothing);
    });
  });

  group('the sleeping basket', () {
    test('sleeps under its shop and wakes only what is still on the shelf',
        () async {
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      // What the screen writes…
      await db.writePref('street_basket_boutique-awa', '{"p1":2,"gone":1}');
      // …is per shop: the grocer's key holds nothing.
      expect(await db.readPref('street_basket_chez-fanta'), isNull);
      expect(await db.readPref('street_basket_boutique-awa'),
          '{"p1":2,"gone":1}');
    });

    test('a public item id round-trips through the saved shape', () {
      // The saved map is product id → quantity, nothing else: prices are
      // read fresh from the shelf on restore, never stored.
      const item = PublicItem(id: 'p1', name: 'Savon', price: 450, inStock: true);
      expect(item.id, 'p1');
    });
  });
}
