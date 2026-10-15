import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/cauris/cauris_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/farm/models.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/org_settings_screen.dart';
import 'package:kaj_app/features/cauris/chemin_screen.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/retail/sale_flow.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/features/storefront/directory_screen.dart';
import 'package:kaj_app/features/storefront/shop_skeleton.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The performance audit (October 2026): the screens people open most ask
/// their questions at once rather than one after the other — on 3G each
/// round trip is half a second or more — and a page already on screen is
/// not blanked to its skeleton to be read again.
///
/// Each "at once" test holds every answer back and counts which questions
/// were already asked: one after the other, only the first is.

/// Answers held until [open]: who was asked, and in what order.
class _Gate {
  final asked = <String>[];
  final _held = Completer<void>();

  Future<T> hold<T>(String name, T value) async {
    asked.add(name);
    await _held.future;
    return value;
  }

  void open() {
    if (!_held.isCompleted) _held.complete();
  }
}

// ---------------------------------------------------------------------------
// Réglages
// ---------------------------------------------------------------------------

class _SlowSettings extends AdminRepository {
  _SlowSettings(this.gate) : super(null);
  final _Gate gate;

  @override
  Future<Map<String, dynamic>> fetchOrg(String orgId) => gate.hold('org', {
        'id': orgId,
        'name': 'Boutique Awa',
        'slug': 'boutique-awa',
        'profile': 'retail',
        'default_currency': 'XOF',
      });

  @override
  Future<String?> waveMerchant(String orgId) => gate.hold<String?>('wave', null);

  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) =>
      gate.hold('rates', const <CurrencyRate>[]);

  @override
  Future<
      ({
        bool enabled,
        String? blurb,
        double? lat,
        double? lng,
        double? deliveryBase,
        double? deliveryPerKm,
      })> storefront(String orgId) => gate.hold('storefront', (
        enabled: true,
        blurb: null as String?,
        lat: null as double?,
        lng: null as double?,
        deliveryBase: null as double?,
        deliveryPerKm: null as double?,
      ));

  @override
  Future<double?> deliveryReach(String orgId) => gate.hold<double?>('reach', null);

  @override
  Future<double?> deliveryIncludedKm(String orgId) =>
      gate.hold<double?>('included', null);

  @override
  Future<({String? phone, String? address})> orgContact(String orgId) =>
      gate.hold('contact', (phone: null as String?, address: null as String?));

  @override
  Future<VitrineChecklist?> vitrineChecklist(String orgId) =>
      gate.hold<VitrineChecklist?>('checklist', null);

  @override
  Future<({String plan, DateTime? until, String? note})> orgPlan(String orgId) =>
      gate.hold('plan', (plan: 'pro', until: null as DateTime?, note: null as String?));
}

// ---------------------------------------------------------------------------
// The shop's home and till
// ---------------------------------------------------------------------------

class _SlowTill extends RetailRepository {
  _SlowTill(this.gate) : super(null);
  final _Gate gate;

  @override
  bool get isConfigured => true;

  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) => gate.hold('day', const StoreDay());

  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) =>
      gate.hold('expiring', const <ExpiringProduct>[]);

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) =>
      gate.hold('products', const <Product>[]);

  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) =>
      gate.hold('losses', 0.0);

  @override
  Future<int> pendingOrders(String orgId) => gate.hold('orders', 0);

  @override
  Future<String?> waveMerchant(String orgId) => gate.hold<String?>('wave', 'awa');

  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) =>
      gate.hold('rates', const <CurrencyRate>[]);
}

class _SlowPath extends CaurisRepository {
  _SlowPath(this.gate) : super(null);
  final _Gate gate;

  @override
  Future<void> milestones(String orgId) async => gate.asked.add('milestones');

  @override
  Future<PathState?> pathState(String orgId, {void Function()? onMissing}) =>
      gate.hold<PathState?>('path', null);

  @override
  Future<CaurisWallet?> wallet(String orgId) => gate.hold<CaurisWallet?>('wallet', null);
}

// ---------------------------------------------------------------------------
// The farm's home
// ---------------------------------------------------------------------------

class _SlowFarm extends FarmRepository {
  _SlowFarm(this.gate) : super(null);
  final _Gate gate;

  @override
  bool get isConfigured => true;

  @override
  Future<List<StockItem>> stockOnHand(String orgId) =>
      gate.hold('stock', const <StockItem>[]);

  @override
  Future<List<Flock>> flocks(String orgId, {bool includeClosed = false}) =>
      gate.hold('flocks', const <Flock>[]);

  @override
  Future<FarmShape> shape(String orgId) => gate.hold('shape', const FarmShape());
}

// ---------------------------------------------------------------------------
// The street
// ---------------------------------------------------------------------------

/// The phone already allowed Mara its position (144's quiet position).
class _Gps extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async => Position(
        latitude: 12.37,
        longitude: -1.52,
        timestamp: DateTime(2026, 10, 15),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}

class _Street extends StorefrontRepository {
  _Street() : super(null);

  int directoryCalls = 0;
  int previewCalls = 0;
  final seen = <String>[];

  /// While set, the street's list is held: « près de moi » on a slow line.
  Completer<void>? slow;

  @override
  bool get isConfigured => true;

  @override
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) async {
    directoryCalls++;
    await slow?.future;
    return const [
      DirectoryEntry(orgId: 'o1', name: 'Boutique Awa', slug: 'awa', profile: 'retail'),
      DirectoryEntry(orgId: 'o2', name: 'Ferme Ignace', slug: 'ignace', profile: 'farm'),
    ];
  }

  /// A spot shows only around its business (144): asked with no
  /// position, none; from the phone's, one.
  @override
  Future<List<FeaturedItem>> featured({double? lat, double? lng}) async => lat == null
      ? const []
      : const [
          FeaturedItem(
              id: 'f1', name: 'Pagne wax', price: 7500, inStock: true,
              shopName: 'Boutique Awa', shopSlug: 'awa'),
        ];

  @override
  Future<Set<String>> spotlights({double? lat, double? lng}) async => const {};

  @override
  Future<Set<String>> showcaseSlugs() async => const {};

  @override
  Future<Map<String, List<ShopPreview>>> previews(List<String> slugs) async {
    previewCalls++;
    return const {};
  }

  @override
  Future<void> recordSeen(List<String> productIds) async => seen.addAll(productIds);
}

/// A vitrine whose second reading is held (its owner back from its settings).
class _OwnStreet extends StorefrontRepository {
  _OwnStreet() : super(null);

  int reads = 0;
  final second = Completer<void>();

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async {
    if (++reads > 1) await second.future;
    return const PublicShop(
        orgId: 'o-awa', name: 'Boutique Awa', slug: 'awa', profile: 'retail',
        phone: '+22670000000', address: 'Ouagadougou');
  }

  @override
  Future<List<PublicItem>> items(String slug) async =>
      const [PublicItem(id: 'p1', name: 'Pagne wax', price: 7500, inStock: true)];

  @override
  Future<Set<String>> showcaseSlugs() async => const {};
}

class _Owner extends SessionController {
  _Owner(LocalDb db)
      : super(db: db, auth: AuthRepository(null), admin: AdminRepository(null),
            accounting: AccountingRepository(null));

  @override
  List<OrgSummary> get orgs => const [
        OrgSummary(id: 'o-awa', name: 'Boutique Awa', slug: 'awa', profile: 'retail', roles: ['owner']),
      ];
}

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

/// Lets the local database (a real one, in memory) and the held futures
/// move, a frame at a time.
Future<void> _settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() => db.close());

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('Réglages: its nine questions asked at once, not one after the other',
      (tester) async {
    tall(tester);
    final gate = _Gate();
    await tester.pumpWidget(_app(OrgSettingsScreen(
        admin: _SlowSettings(gate), orgId: 'org-1', canSetPlan: true, initialPart: 'identite')));
    await tester.pump();
    // Before: only « org » here — each question waited for the last.
    expect(gate.asked.toSet(), {
      'org', 'wave', 'rates', 'storefront', 'reach', 'included', 'contact', 'checklist', 'plan',
    });
    gate.open();
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Boutique Awa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Réglages: an extra that fails still costs nothing, the rest shows',
      (tester) async {
    tall(tester);
    final gate = _Gate();
    final admin = _FailingExtras(gate);
    await tester.pumpWidget(_app(OrgSettingsScreen(admin: admin, orgId: 'org-1', initialPart: 'identite')));
    await tester.pump();
    gate.open();
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Boutique Awa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shop\'s home: the day, the shelf, the orders and the path asked at once',
      (tester) async {
    tall(tester);
    final gate = _Gate();
    await tester.pumpWidget(_app(StoreHomeScreen(
      org: const OrgSummary(
          id: 'shop-1', name: 'Boutique Awa', profile: 'retail', roles: ['owner'], currency: 'XOF'),
      retail: _SlowTill(gate),
      cauris: _SlowPath(gate),
    )));
    await tester.pump();
    await tester.pump();
    // Before: only « day » — then expiring, products, losses, orders, the path.
    expect(gate.asked.toSet(),
        containsAll(['day', 'expiring', 'products', 'losses', 'orders', 'path']));
    gate.open();
    await tester.pump();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the till: the rates are not kept waiting behind the Wave handle',
      (tester) async {
    tall(tester);
    final gate = _Gate();
    await tester.pumpWidget(_app(SaleFlow(
      orgId: 'shop-1',
      retail: _SlowTill(gate),
      store: MemoryFlowStore(),
      allowWave: true,
      products: const [Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 5)],
    )));
    await tester.pump();
    expect(gate.asked, containsAll(['wave', 'rates']));
    gate.open();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the farm\'s home: the stock, the batches and the shape asked at once',
      (tester) async {
    tall(tester);
    final gate = _Gate();
    await tester.pumpWidget(_app(FarmHomeScreen(
      db: db,
      org: const OrgSummary(id: 'farm-1', name: 'Ferme Ignace', profile: 'farm', roles: ['owner']),
      farm: _SlowFarm(gate),
    )));
    await _settle(tester);
    // Before: only « stock ».
    expect(gate.asked.toSet(), {'stock', 'flocks', 'shape'});
    gate.open();
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mon chemin: after the milestones, the path and the wallet at once',
      (tester) async {
    final gate = _Gate();
    await tester.pumpWidget(_app(CheminScreen(
      org: const OrgSummary(
          id: 'shop-1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']),
      cauris: _SlowPath(gate),
    )));
    await tester.pump();
    await tester.pump();
    // The milestones first (what they pay is in the answers after them),
    // then both. Before: the wallet waited for the path.
    expect(gate.asked.first, 'milestones');
    expect(gate.asked.toSet(), {'milestones', 'path', 'wallet'});
    gate.open();
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('the street with location already allowed', () {
    late GeolocatorPlatform original;
    setUp(() {
      original = GeolocatorPlatform.instance;
      GeolocatorPlatform.instance = _Gps();
    });
    tearDown(() => GeolocatorPlatform.instance = original);

    SessionController session() => SessionController(
          db: db,
          auth: AuthRepository(null),
          admin: AdminRepository(null),
          accounting: AccountingRepository(null),
        );

    testWidgets('the position asks the spots again — not the whole street, and a spot is counted once',
        (tester) async {
      tall(tester);
      final street = _Street();
      await tester.pumpWidget(_app(DirectoryScreen(
          storefront: street, capture: CaptureRepository(null, db: db), session: session())));
      await _settle(tester);
      // The spot around the phone is on the strip.
      expect(find.text('Pagne wax'), findsOneWidget);
      // Before: the list twice, its previews twice (each two RPCs).
      expect(street.directoryCalls, 1);
      expect(street.previewCalls, 1);
      expect(street.seen, ['f1']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('« Près de moi »: the street stays on screen while it is asked again',
        (tester) async {
      tall(tester);
      final street = _Street();
      await tester.pumpWidget(_app(DirectoryScreen(
          storefront: street, capture: CaptureRepository(null, db: db), session: session())));
      await _settle(tester);
      expect(find.text('Boutique Awa'), findsWidgets);

      street.slow = Completer<void>();
      await tester.tap(find.text('Près de moi'));
      await _settle(tester, 3);
      // Before: the skeleton, the shops gone, the scroll lost.
      expect(find.byType(ShopSkeleton), findsNothing);
      expect(find.text('Boutique Awa'), findsWidgets);

      expect(street.directoryCalls, 2, reason: 'asked again from the position');
      street.slow!.complete();
      await _settle(tester);
      expect(find.text('LES PLUS PROCHES', skipOffstage: false), findsOneWidget);
      // The strip is the same look as before: not counted a second time.
      expect(street.seen, ['f1']);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a vitrine read again for its owner stays on screen, no skeleton',
      (tester) async {
    tall(tester);
    final street = _OwnStreet();
    final owner = _Owner(db);
    final router = GoRouter(initialLocation: '/s/awa', routes: [
      GoRoute(
          path: '/s/:slug',
          builder: (_, _) => StorefrontScreen(
                slug: 'awa',
                storefront: street,
                capture: CaptureRepository(null, db: db),
                session: owner,
              )),
      GoRoute(
          path: '/o/:orgId/administration/parametres/vitrine',
          builder: (_, _) => const Scaffold(body: Text('personnaliser'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      routerConfig: router,
    ));
    await _settle(tester);
    expect(find.text('Pagne wax'), findsWidgets);

    // « Modifier ma vitrine », then back: the vitrine is read again.
    await tester.tap(find.byKey(const Key('vitrine-edit')));
    await _settle(tester);
    expect(find.text('personnaliser'), findsOneWidget);
    GoRouter.of(tester.element(find.text('personnaliser'))).pop();
    await _settle(tester);
    expect(street.reads, 2);
    // Before: the skeleton while the second reading is held.
    expect(find.byType(ShopSkeleton), findsNothing);
    expect(find.text('Pagne wax'), findsWidgets);
    street.second.complete();
    await _settle(tester);
    expect(find.text('Pagne wax'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the order sheet: two quick taps send one order', (tester) async {
    tall(tester);
    var sent = 0;
    final answer = Completer<String?>();
    await tester.pumpWidget(_app(Scaffold(
      body: OrderSheet(
        items: const [PublicItem(id: 'p1', name: 'Savon', price: 450, inStock: true)],
        basket: const {'p1': 2},
        currency: 'XOF',
        quote: (lat, lng) async => null,
        onSubmit: ({
          required lines,
          required fulfilment,
          note,
          address,
          phone,
          required payment,
          dropLat,
          dropLng,
        }) {
          sent++;
          return answer.future;
        },
      ),
    )));
    await tester.pump();
    final send = find.text('Envoyer la commande');
    await tester.ensureVisible(send);
    await tester.pump();
    // Both taps land before the button redraws as busy — a slow phone.
    await tester.tap(send);
    await tester.tap(send, warnIfMissed: false);
    await tester.pump();
    expect(sent, 1, reason: 'an order carries no key: a second call is a second order');
    answer.complete('Erreur');
    await tester.pump();
  });
}

/// The extras (the reach, the contact lines, the checklist) fail: the
/// settings still open, and no error is left unheard.
class _FailingExtras extends _SlowSettings {
  _FailingExtras(super.gate);

  @override
  Future<double?> deliveryReach(String orgId) async => throw StateError('reach');

  @override
  Future<({String? phone, String? address})> orgContact(String orgId) async =>
      throw StateError('contact');

  @override
  Future<VitrineChecklist?> vitrineChecklist(String orgId) async =>
      throw StateError('checklist');
}
