import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/farm/for_sale_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A farm has a vitrine (083): « À vendre » puts eggs by the tray and a
/// batch still growing on it, and the street reads them that way.
class _Farm extends RetailRepository {
  _Farm() : super(null);

  final items = <Product>[];
  final created = <String>[];
  final prices = <double?>[];
  final received = <double>[];
  final saved = <Map<String, Object?>>[];

  @override
  Future<void> receive({
    required String orgId,
    required String productId,
    required double quantity,
    double? unitCost,
    DateTime? expiresOn,
    String method = 'cash',
    String? clientUuid,
  }) async =>
      received.add(quantity);

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async =>
      List.of(items);

  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {};

  @override
  Future<String> ensureProduct({
    required String orgId,
    required String name,
    double? salePrice,
    double? costPrice,
    String? barcode,
    DateTime? expiresOn,
    bool isService = false,
  }) async {
    expect(isService, isFalse, reason: 'À vendre creates articles');
    created.add(name);
    prices.add(salePrice);
    return 'new-${created.length}';
  }

  @override
  Future<void> updateProduct(
    String productId, {
    String? name,
    double? salePrice,
    double? costPrice,
    DateTime? expiresOn,
    double? lowStockAt,
    bool? isActive,
    bool? isIngredient,
    bool? isPublished,
    String? description,
    String? unit,
    DateTime? availableFrom,
    bool clearAvailableFrom = false,
    double? quantity,
    bool? isService,
    bool? priceFrom,
  }) async {
    saved.add({
      'id': productId,
      'name': name,
      'price': salePrice,
      'unit': unit,
      'quantity': quantity,
      'published': isPublished,
      'from': availableFrom,
      'clear': clearAvailableFrom,
    });
    items.add(Product(
      id: productId,
      name: name ?? created.last,
      salePrice: salePrice ?? prices.last ?? 0,
      quantity: quantity ?? 0,
      unit: unit,
      isPublished: isPublished ?? false,
      availableFrom: availableFrom,
    ));
  }
}

class _FarmShop extends StorefrontRepository {
  _FarmShop() : super(null);

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => const PublicShop(
        orgId: 'f1',
        name: 'Ferme du Kadiogo',
        slug: 'ferme-kadiogo',
        profile: 'farm',
      );

  @override
  Future<List<PublicItem>> items(String slug) async => [
        const PublicItem(
            id: 'e', name: 'Œufs frais', price: 2500, inStock: true, unit: 'plateau'),
        PublicItem(
            id: 'p',
            name: 'Poulets de chair',
            price: 3500,
            inStock: true,
            unit: 'tête',
            availableFrom: DateTime(2030, 11, 15)),
      ];
}

const _org = OrgSummary(
    id: 'f1', name: 'Ferme du Kadiogo', profile: 'farm', roles: ['owner'],
    slug: 'ferme-kadiogo');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('« Mettre en vente »: eggs by the tray reach the vitrine',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final farm = _Farm();
    await tester.pumpWidget(MaterialApp(
      home: ForSaleScreen(org: _org, retail: farm),
    ));
    await tester.pump();
    expect(find.textContaining('Rien en vente'), findsOneWidget);

    // « Mettre en vente » is the « Ajouter un produit » flow (115), one
    // question at a time, already on « pour vendre ».
    await tester.tap(find.byKey(const Key('for-sale-add')));
    await tester.pumpAndSettle();
    Future<void> next() async {
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
    }

    expect(find.text('Quel produit ?'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('article-name')), 'Œufs frais');
    await tester.pump();
    await next();
    await tester.enterText(find.byKey(const Key('article-price')), '2500');
    await tester.pump();
    await next();
    await next(); // no buying price: grown, not bought
    await tester.enterText(find.byKey(const Key('article-quantity')), '12');
    await tester.tap(find.byKey(const ValueKey('article-unit-plateau')));
    await tester.pump();
    await next();
    await next(); // no alert
    await next(); // on the vitrine, by default
    await next(); // not an ingredient
    await next(); // ready now
    expect(find.byKey(const Key('flow-summary')), findsOneWidget);
    await tester.tap(find.byKey(const Key('flow-save')));
    await tester.pumpAndSettle();
    expect(find.text('Œufs frais ajouté'), findsOneWidget);
    await tester.tap(find.byKey(const Key('flow-finish')));
    await tester.pumpAndSettle();

    expect(farm.created, ['Œufs frais']);
    expect(farm.prices, [2500]);
    expect(farm.received, isEmpty, reason: 'grown, not bought: no purchase');
    final s = farm.saved.single;
    expect(s['unit'], 'plateau');
    expect(s['quantity'], 12);
    expect(s['published'], isTrue, reason: 'on the vitrine by default');
    expect(s['from'], isNull, reason: 'there now: no date');
    // The list reads it back the way a buyer would.
    expect(find.textContaining('/ plateau'), findsOneWidget);
    expect(find.textContaining('12 disponibles'), findsOneWidget);
  });

  testWidgets('the street reads a farm: by the unit, a pre-order, pickup at '
      'the farm', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = await tester.runAsync(
        () => LocalDb.open(path: inMemoryDatabasePath));
    await tester.pumpWidget(MaterialApp(
      home: StorefrontScreen(
        slug: 'ferme-kadiogo',
        storefront: _FarmShop(),
        capture: CaptureRepository(null, db: db!),
        session: SessionController(
          db: db,
          auth: AuthRepository(null),
          admin: AdminRepository(null),
          accounting: AccountingRepository(null),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    // The strip cross-fades from the street's line to the farm's.
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Retrait à la ferme'), findsWidgets);
    expect(find.text('Retrait à la ferme, ou livraison dans le quartier'),
        findsOneWidget, reason: 'the strip speaks of the farm, not a shop');
    expect(find.textContaining('Retrait en boutique'), findsNothing);
    expect(find.textContaining('/ plateau'), findsWidgets);
    expect(find.textContaining('/ tête'), findsWidgets);
    expect(find.byKey(const Key('preorder-line')), findsOneWidget);
    expect(find.text('Disponible à partir du 15/11'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
    await tester.runAsync(() => db.close());
  });
}
