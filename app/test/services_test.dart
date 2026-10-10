import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/orders/orders.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/for_sale_screen.dart';
import 'package:kaj_app/features/retail/products_screen.dart';
import 'package:kaj_app/features/services/services_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:kaj_app/core/errors.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Services in the vitrine (098): a product with no stock, its own section
/// on the window, « Réserver », and a booking that needs a day and an hour
/// rather than a way to travel.

/// The business's side: an in-memory shelf the services screen reads and
/// writes.
class _Books extends RetailRepository {
  _Books(this.items) : super(null);

  final List<Product> items;
  final created = <String>[];
  final kinds = <bool>[];
  final saved = <Map<String, Object?>>[];
  final removed = <String>[];
  Map<String, String> keys = const {};
  int pending = 0;

  /// A database before 098 (no is_service column).
  bool missing = false;

  @override
  Future<List<Product>> products(
    String orgId, {
    bool activeOnly = true,
  }) async {
    servicesMissing = missing;
    return List.of(items);
  }

  @override
  Future<Map<String, String>> photoKeys(String orgId) async => keys;

  @override
  Future<void> archiveProduct(String productId, {bool archived = true}) async {
    removed.add(productId);
    items.removeWhere((p) => p.id == productId);
  }

  @override
  Future<int> pendingOrders(String orgId) async => pending;

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
    // The server's rule (098): a name belongs to one kind.
    for (final p in items) {
      if (p.name.trim().toLowerCase() == name.trim().toLowerCase() &&
          p.isService != isService) {
        throw PostgrestException(
          message: p.isService
              ? 'Un service porte déjà ce nom'
              : 'Un article porte déjà ce nom',
          code: 'P0001',
        );
      }
    }
    created.add(name);
    kinds.add(isService);
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
      'published': isPublished,
      'service': isService,
      'from': priceFrom,
    });
    items.removeWhere((p) => p.id == productId);
    items.add(
      Product(
        id: productId,
        name: name ?? '',
        salePrice: salePrice ?? 0,
        unit: (unit ?? '').isEmpty ? null : unit,
        isPublished: isPublished ?? false,
        isService: isService ?? false,
        priceFrom: priceFrom ?? false,
      ),
    );
  }
}

/// The street's side: a shop with goods and services.
class _Window extends StorefrontRepository {
  _Window(this.profile, this.goods) : super(null);

  final String profile;
  final List<PublicItem> goods;

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => PublicShop(
    orgId: 'o1',
    name: profile == 'association' ? 'Club Wend-Panga' : 'Salon Awa',
    slug: slug,
    profile: profile,
  );

  @override
  Future<List<PublicItem>> items(String slug) async => goods;
}

const _haircut = PublicItem(
  id: 's1',
  name: 'Tresses',
  price: 5000,
  inStock: true,
  isService: true,
  priceFrom: true,
  unit: 'heure',
);
const _lesson = PublicItem(
  id: 's2',
  name: 'Cours de couture',
  price: 2000,
  inStock: true,
  isService: true,
);
const _shampoo = PublicItem(
  id: 'g1',
  name: 'Shampoing',
  price: 1500,
  inStock: true,
);

const _shopOrg = OrgSummary(
  id: 'o1',
  name: 'Salon Awa',
  profile: 'retail',
  roles: ['owner'],
  slug: 'salon-awa',
);

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('flow-next')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('the rows carry the service', () {
    test('a storefront row: service, « à partir de », never sold out', () {
      final item = PublicItem.fromRow({
        'id': 's1',
        'name': 'Tresses',
        'sale_price': '5000.00',
        'in_stock': false,
        'is_service': true,
        'price_from': true,
        'unit': 'heure',
      });
      expect(item.isService, isTrue);
      expect(item.priceFrom, isTrue);
      expect(
        item.inStock,
        isTrue,
        reason: 'a service has no stock to run out of',
      );
      expect(item.unit, 'heure');
    });

    test('a database before 098: goods at a plain price', () {
      final item = PublicItem.fromRow({
        'id': 'g',
        'name': 'Savon',
        'sale_price': 300,
        'in_stock': false,
      });
      expect(item.isService, isFalse);
      expect(item.priceFrom, isFalse);
      expect(item.inStock, isFalse);
      final p = Product.fromRow({'id': 'g', 'name': 'Savon'});
      expect(p.isService, isFalse);
      expect(p.priceFrom, isFalse);
    });

    test('a product row: a service is never low on stock', () {
      final p = Product.fromRow({
        'id': 's',
        'name': 'Coupe',
        'quantity': 0,
        'low_stock_at': 2,
        'is_service': true,
        'price_from': true,
      });
      expect(p.isService, isTrue);
      expect(p.priceFrom, isTrue);
      expect(p.isLow, isFalse);
    });

    test('an order of services alone is « Sur rendez-vous »', () {
      final order = ShopOrder.fromRow({
        'id': 'o',
        'status': 'pending',
        'fulfilment': 'pickup',
        'total': 4000,
        'lines': [
          {
            'name': 'Cours',
            'unit_price': 2000,
            'quantity': 2,
            'is_service': true,
          },
        ],
      });
      expect(order.lines.single.isService, isTrue);
      expect(order.isBooking, isTrue);
      expect(
        fulfilmentLabel(order.fulfilment, appointment: order.isBooking),
        'Sur rendez-vous',
      );
      final mixed = ShopOrder.fromRow({
        'id': 'o2',
        'fulfilment': 'pickup',
        'lines': [
          {
            'name': 'Cours',
            'unit_price': 2000,
            'quantity': 1,
            'is_service': true,
          },
          {'name': 'Savon', 'unit_price': 300, 'quantity': 1},
        ],
      });
      expect(mixed.isBooking, isFalse);
      expect(orderStatusLabel('picked_up', booking: true), 'Terminée');
      expect(orderStatusLabel('picked_up'), 'Récupérée');
      expect(orderActionLabel('picked_up', booking: order.isBooking), 'Terminée');
      expect(translate('en', 'Terminée'), 'Done');
    });

    test('the server\'s 098 sentences are said in English', () {
      const sentences = {
        'Un service se réserve sur rendez-vous : pas de livraison':
            'A service is booked by appointment: no delivery',
        'Indiquez la date et l\'heure souhaitées':
            'Give the date and time you would like',
        'Un service n\'a pas de stock : rien à réceptionner':
            'A service has no stock: nothing to receive',
        'Un service ne se fabrique pas': 'A service is not produced',
        'Un service ne peut pas être un ingrédient':
            'A service cannot be an ingredient',
        'Un article porte déjà ce nom': 'An item already has this name',
        'Un service porte déjà ce nom': 'A service already has this name',
        'Cet article a du stock : il ne peut pas devenir un service':
            'This item has stock: it cannot become a service',
      };
      addTearDown(() => trCurrent = 'fr');
      for (final e in sentences.entries) {
        final error = PostgrestException(message: e.key, code: 'P0001');
        trCurrent = 'fr';
        expect(describeError(error), e.key);
        trCurrent = 'en';
        expect(describeError(error), e.value);
      }
    });
  });

  group('the window', () {
    late LocalDb db;
    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    Future<void> openWindow(WidgetTester tester, _Window repo) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: StorefrontScreen(
            slug: 'salon-awa',
            storefront: repo,
            capture: CaptureRepository(null, db: db),
            session: SessionController(
              db: db,
              auth: AuthRepository(null),
              admin: AdminRepository(null),
              accounting: AccountingRepository(null),
            ),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> closeWindow(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    }

    testWidgets(
      'services come after the articles, « à partir de », « Réserver »',
      (tester) async {
        await openWindow(
          tester,
          _Window('retail', const [_shampoo, _haircut, _lesson]),
        );
        expect(find.text('LES ARTICLES'), findsOneWidget);
        expect(find.byKey(const Key('shelf-services')), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(const Key('shelf-services'))).dy,
          greaterThan(tester.getTopLeft(find.text('LES ARTICLES')).dy),
          reason: 'the services follow the goods',
        );
        expect(find.byKey(const Key('shelf-service-rows')), findsOneWidget);
        expect(find.textContaining('à partir de'), findsOneWidget);
        expect(find.textContaining('/ heure'), findsOneWidget);
        expect(find.text('Réserver'), findsNWidgets(2));
        expect(find.text('Épuisé'), findsNothing);

        // « Réserver » opens the service's booking sheet (125) — never the
        // basket.
        await tester.tap(find.text('Réserver').first);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('booking-send')), findsOneWidget);
        expect(find.byKey(const Key('basket-bar')), findsNothing);
        await closeWindow(tester);
      },
    );

    testWidgets('a query that empties the articles keeps the filter, focused', (
      tester,
    ) async {
      final goods = [
        for (var i = 1; i <= 5; i++)
          PublicItem(id: 'g$i', name: 'Savon $i', price: 300, inStock: true),
      ];
      await openWindow(
        tester,
        _Window('retail', [...goods, _haircut, _lesson]),
      );
      final field = find.byKey(const Key('shelf-filter'));
      expect(field, findsOneWidget);
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      await tester.tap(field);
      await tester.pump();
      final before = tester.state<EditableTextState>(editable);
      expect(before.widget.focusNode.hasFocus, isTrue);

      // Letter by letter, as a thumb types: « t », « tr », « tre » — the
      // articles section empties on the first, the field must not move.
      for (final q in ['t', 'tr', 'tre']) {
        await tester.enterText(field, q);
        await tester.pump();
        final now = tester.state<EditableTextState>(editable);
        expect(identical(now, before), isTrue, reason: 'the field moved at « $q »');
        expect(now.widget.focusNode.hasFocus, isTrue);
      }
      expect(find.text('LES ARTICLES'), findsNothing);
      expect(find.byKey(const Key('shelf-services')), findsOneWidget);
      expect(find.text('Tresses'), findsOneWidget);
      await closeWindow(tester);
    });

    testWidgets('a service never enters the basket: no « 1 service », no stepper (125)', (
      tester,
    ) async {
      await openWindow(tester, _Window('association', const [_lesson, _haircut]));
      await tester.tap(find.text('Réserver').first);
      await tester.pumpAndSettle();
      // The booking sheet, closed without booking: nothing was basketed.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('basket-bar')), findsNothing);
      expect(find.text('1 service'), findsNothing);
      expect(find.text('Réserver'), findsNWidgets(2));
      await closeWindow(tester);
    });

    testWidgets('an association: services alone, booked by appointment', (
      tester,
    ) async {
      await openWindow(tester, _Window('association', const [_lesson]));
      expect(find.text('LES ARTICLES'), findsNothing);
      expect(find.byKey(const Key('shelf-services')), findsOneWidget);
      expect(find.textContaining('Sur rendez-vous'), findsWidgets);
      expect(find.textContaining('Retrait en boutique'), findsNothing);
      expect(find.textContaining('Association'), findsWidgets);
      await closeWindow(tester);
    });
  });

  group('the checkout', () {
    Future<List<Map<String, Object?>>> openSheet(
      WidgetTester tester,
      List<PublicItem> items,
    ) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final sent = <Map<String, Object?>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => OrderSheet(
                    items: items,
                    basket: {for (final i in items) i.id: 2},
                    currency: 'XOF',
                    delivers: true,
                    quote: (_, _) async => null,
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
                        }) async {
                          sent.add({'fulfilment': fulfilment, 'note': note});
                          return null;
                        },
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return sent;
    }

    testWidgets('a basket of goods chooses as before, the note optional', (
      tester,
    ) async {
      final sent = await openSheet(tester, const [_shampoo]);
      expect(find.text('Votre commande'), findsOneWidget);
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      expect(find.text('Livraison'), findsOneWidget);
      await tester.tap(find.text('Envoyer la commande'));
      await tester.pumpAndSettle();
      expect(sent, [
        {'fulfilment': 'pickup', 'note': null},
      ]);
    });
  });

  group('« Mes services »', () {
    Future<void> openScreen(WidgetTester tester, _Books books) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ServicesScreen(org: _shopOrg, retail: books),
        ),
      );
      await tester.pump();
    }

    testWidgets('adds a service, then edits it', (tester) async {
      final books = _Books([
        const Product(
          id: 'g1',
          name: 'Shampoing',
          salePrice: 1500,
          quantity: 4,
        ),
      ]);
      await openScreen(tester, books);
      expect(find.textContaining('Aucun service'), findsOneWidget);
      expect(
        find.text('Shampoing'),
        findsNothing,
        reason: 'goods stay in Articles',
      );

      // A new one is the « Service » flow (115), one question at a time.
      await tester.tap(find.byKey(const Key('services-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('service-flow-name')), 'Tresses');
      await tester.pump();
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-option-true'))); // à partir de
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('service-flow-price')), '5000');
      await tester.tap(find.byKey(const ValueKey('service-flow-unit-heure')));
      await tester.pump();
      await _next(tester);
      await _next(tester); // no duration
      await _next(tester); // on the vitrine
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-finish')));
      await tester.pumpAndSettle();

      expect(books.created, ['Tresses']);
      expect(books.kinds, [true], reason: 'created as a service');
      expect(books.saved.single, {
        'id': 'new-1',
        'name': 'Tresses',
        'price': 5000,
        'unit': 'heure',
        'published': true,
        'service': true,
        'from': true,
      });
      expect(find.textContaining('à partir de'), findsOneWidget);
      expect(find.textContaining('/ heure'), findsOneWidget);

      await tester.tap(find.text('Tresses'));
      await tester.pumpAndSettle();
      expect(find.text('Modifier le service'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('service-price')), '6000');
      await tester.tap(find.byKey(const Key('service-from')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('service-save')));
      await tester.tap(find.byKey(const Key('service-save')));
      await tester.pumpAndSettle();
      expect(books.created, ['Tresses'], reason: 'an edit creates nothing');
      expect(books.saved.last['price'], 6000);
      expect(books.saved.last['from'], isFalse);
      expect(books.saved.last['service'], isTrue);
      expect(find.textContaining('à partir de'), findsNothing);
    });

    testWidgets('a service may not take an article\'s name', (tester) async {
      final books = _Books([
        const Product(id: 'g1', name: 'Shampoing', salePrice: 1500),
      ]);
      await openScreen(tester, books);
      await tester.tap(find.byKey(const Key('services-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('service-flow-name')),
        'shampoing',
      );
      await tester.pump();
      await _next(tester);
      await tester.enterText(find.byKey(const Key('service-flow-price')), '500');
      await tester.pump();
      await _next(tester);
      await _next(tester);
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(books.created, isEmpty);
      expect(books.saved, isEmpty);
      expect(find.text('Un article porte déjà ce nom'), findsOneWidget,
          reason: 'said under « Enregistrer », the summary stays');
    });

    testWidgets('a database before 098: said, and nothing is added', (
      tester,
    ) async {
      final books = _Books([
        const Product(id: 'g1', name: 'Shampoing', salePrice: 1500),
      ])..missing = true;
      await openScreen(tester, books);
      expect(find.byKey(const Key('services-missing')), findsOneWidget);
      expect(find.textContaining('migration 098'), findsOneWidget);
      expect(find.textContaining('Aucun service'), findsNothing);
      final fab = tester.widget<FloatingActionButton>(
        find.byKey(const Key('services-add')),
      );
      expect(fab.onPressed, isNull);
      await tester.tap(find.byKey(const Key('services-add')));
      await tester.pumpAndSettle();
      expect(find.text('Nouveau service'), findsNothing);
      expect(books.created, isEmpty);
    });

    testWidgets('editing shows the photo; removing asks first', (tester) async {
      final books = _Books([
        const Product(
          id: 's1',
          name: 'Tresses',
          salePrice: 5000,
          isService: true,
          isPublished: true,
        ),
      ])..keys = const {'s1': 'p/s1'};
      await openScreen(tester, books);
      await tester.tap(find.text('Tresses'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('service-photo-current')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('service-remove')));
      await tester.tap(find.byKey(const Key('service-remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('service-remove-confirm')), findsOneWidget);
      await tester.tap(find.text('Retour'));
      await tester.pumpAndSettle();
      expect(books.removed, isEmpty, reason: '« Retour » keeps it');
      expect(find.text('Modifier le service'), findsOneWidget);

      await tester.tap(find.byKey(const Key('service-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('service-remove-yes')));
      await tester.pumpAndSettle();
      expect(books.removed, ['s1']);
      expect(find.text('Modifier le service'), findsNothing);
    });

    testWidgets('Articles and À vendre leave the services out', (tester) async {
      final books = _Books([
        const Product(
          id: 'g1',
          name: 'Shampoing',
          salePrice: 1500,
          quantity: 3,
        ),
        const Product(
          id: 's1',
          name: 'Tresses',
          salePrice: 5000,
          isService: true,
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: ProductsScreen(org: _shopOrg, retail: books),
        ),
      );
      await tester.pump();
      expect(find.text('Shampoing'), findsOneWidget);
      expect(find.text('Tresses'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: ForSaleScreen(org: _shopOrg, retail: books),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Shampoing'), findsOneWidget);
      expect(find.text('Tresses'), findsNothing);
    });
  });

  group('the association\'s home', () {
    late LocalDb db;
    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    Future<void> openHome(
      WidgetTester tester,
      OrgSummary org,
      _Books books,
    ) async {
      tester.view.physicalSize = const Size(480, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          home: ChurchHomeScreen(
            db: db,
            orgId: org.id,
            orgName: org.name,
            org: org,
            retail: books,
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    testWidgets('its administrators find the vitrine and the requests', (
      tester,
    ) async {
      final books = _Books([])..pending = 2;
      await openHome(
        tester,
        const OrgSummary(
          id: 'a1',
          name: 'Club Wend-Panga',
          profile: 'association',
          roles: ['owner'],
        ),
        books,
      );
      expect(find.byKey(const Key('association-services')), findsOneWidget);
      expect(find.text('Ma vitrine et mes services'), findsOneWidget);
      expect(find.byKey(const Key('association-requests')), findsOneWidget);
      expect(find.text('Demandes'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('association-requests')),
          matching: find.text('2'),
        ),
        findsOneWidget,
        reason: 'the requests waiting are counted',
      );
    });

    testWidgets('a member sees neither', (tester) async {
      await openHome(
        tester,
        const OrgSummary(
          id: 'a1',
          name: 'Club Wend-Panga',
          profile: 'association',
          roles: ['employee'],
        ),
        _Books([]),
      );
      expect(find.byKey(const Key('association-services')), findsNothing);
      expect(find.byKey(const Key('association-requests')), findsNothing);
    });
  });
}
