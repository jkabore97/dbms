// Batch 151 (migration 146): « Protections contre la fraude ».
//
//   1. « Ne payez jamais d'avance »: the order sheet (cash, then Wave in
//      its own words), an open order's card (not once paid, not once
//      finished), the vitrine's contact area (a visitor's, never the
//      business's own), each with « Signaler »;
//   2. the order limits and « Bloquer ce client »: the server's refusals
//      in English; the order's ⋮ for the business's admins only, the
//      question, the reason, the call; a server before 146 said so;
//      « Clients bloqués » lists and unblocks;
//   3. the courier's cash cap: the strip (held, cap, full), the refusal
//      at « J'accepte » in its words; none before 146;
//   4. « Clôturer la caisse »: blind count, the gap, the history, the
//      notice before 146; the button on the shop's home;
//   5. the console: the four settings on Réglages › Sécurité, « À
//      vérifier » in « Aujourd'hui » and its sheet;
//   6. English, and 320 px × 1.3 with nothing overflowing.
//
// No person's first name; Ouagadougou the only town; « Cliente 1 »,
// « Client 2 ». B151_SHOTS=<dir> also writes the screenshots.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/analytics/analytics_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/core/credit/credit_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/format/money.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/l10n/en.dart';
import 'package:kaj_app/core/l10n/locale_controller.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/nav/app_scope.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/orders/orders.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/fraud_guards.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/shopper/shopper_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/tontine/tontine_repository.dart';
import 'package:kaj_app/features/account/support.dart';
import 'package:kaj_app/features/admin/center/command_center_shell.dart';
import 'package:kaj_app/features/admin/center/review_sheet.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/admin/center/todo_section.dart';
import 'package:kaj_app/features/courier/courier_screen.dart';
import 'package:kaj_app/features/orders/blocked_customers_screen.dart';
import 'package:kaj_app/features/orders/my_orders_screen.dart';
import 'package:kaj_app/features/orders/shop_orders_screen.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/features/retail/till_close_sheet.dart';
import 'package:kaj_app/features/shopper/report_sheet.dart';
import 'package:kaj_app/features/storefront/pay_safety.dart';
import 'package:kaj_app/features/storefront/shop_style.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

// ---------------------------------------------------------------------------
// The businesses: a shop, a farm, an association.
// ---------------------------------------------------------------------------

const _shop = OrgSummary(
    id: 'b151-shop', name: 'Kiosque Nova', slug: 'kiosque-nova', profile: 'retail',
    roles: ['owner'], currency: 'XOF', visibility: 'full');
const _farm = OrgSummary(
    id: 'b151-farm', name: 'Ferme Horizon', slug: 'ferme-horizon', profile: 'farm',
    roles: ['owner'], currency: 'XOF', visibility: 'full');
const _assoc = OrgSummary(
    id: 'b151-assoc', name: 'Fondation Espoir', slug: 'fondation-espoir', profile: 'association',
    roles: ['owner'], currency: 'XOF', visibility: 'full');

OrgSummary _as(OrgSummary o, List<String> roles) => OrgSummary(
    id: o.id, name: o.name, slug: o.slug, profile: o.profile, plan: o.plan,
    roles: roles, currency: o.currency, visibility: o.visibility);

const _cashFr = 'Ne payez jamais d\'avance à quelqu\'un que vous ne connaissez pas. Payez à la livraison ou au retrait.';
const _cashWaveFr =
    'Ne payez jamais d\'avance à quelqu\'un que vous ne connaissez pas. Payez à la livraison, au retrait, ou par Wave dans Mara.';
const _pickupFr = 'Ne payez jamais d\'avance à quelqu\'un que vous ne connaissez pas. Payez au retrait.';
const _pickupWaveFr =
    'Ne payez jamais d\'avance à quelqu\'un que vous ne connaissez pas. Payez au retrait, ou par Wave dans Mara.';
const _deliveryFr =
    'Ne payez jamais d\'avance à quelqu\'un que vous ne connaissez pas. Payez à la livraison, quand vous recevez la commande.';
const _waveFr =
    'Payez par Wave seulement depuis Mara, une fois la commande acceptée — jamais à un numéro reçu par message ou par appel.';

/// An amount as the app writes it (fr_FR grouping, « FCFA »).
String _f(num n) => moneyFormat('XOF').format(n);

const _savon = PublicItem(id: 'p-savon', name: 'Savon karité', price: 1500, inStock: true);

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _Guards extends FraudGuardsRepository {
  _Guards({this.missing = false}) : super(null);

  final bool missing;
  final blocked = <(String, String?)>[];
  final unblocked = <String>[];
  final closed = <Map<String, Object?>>[];
  List<BlockedCustomer> rows = [
    BlockedCustomer(customerId: 'c1', name: 'Cliente 1', reason: 'Commandes jamais retirées',
        blockedAt: DateTime(2026, 10, 12, 10)),
    BlockedCustomer(customerId: 'c2', name: 'Client 2', blockedAt: DateTime(2026, 10, 14, 18)),
  ];
  List<TillClosing> history = [
    TillClosing(id: 't1', day: DateTime(2026, 10, 14), expected: 42000, counted: 42000, gap: 0,
        closerName: 'Caisse Kiosque Nova', closedAt: DateTime(2026, 10, 14, 19, 5)),
    TillClosing(id: 't2', day: DateTime(2026, 10, 13), expected: 38500, counted: 37500, gap: -1000,
        closerName: 'Caisse Kiosque Nova', closedAt: DateTime(2026, 10, 13, 19, 12)),
  ];

  static const _old = PostgrestException(message: 'Could not find the function', code: 'PGRST202');

  @override
  bool get isConfigured => true;

  @override
  Future<void> blockCustomer(String orderId, {String? reason}) async {
    if (missing) throw _old;
    blocked.add((orderId, reason));
  }

  @override
  Future<void> unblockCustomer(String orgId, String customerId) async {
    unblocked.add(customerId);
    rows = [for (final r in rows) if (r.customerId != customerId) r];
  }

  @override
  Future<List<BlockedCustomer>> blockedCustomers(String orgId) async {
    if (missing) throw const PostgrestException(message: 'Could not find the table', code: 'PGRST205');
    return rows;
  }

  @override
  Future<TillClosing> closeTill(String orgId,
      {required DateTime day, required double counted, double openingFloat = 0, String? note}) async {
    if (missing) throw _old;
    closed.add({'org': orgId, 'counted': counted, 'float': openingFloat, 'note': note});
    // The server's sum: 5 000 float + 9 000 cash sales − 0 returns.
    final expected = openingFloat + 9000;
    final done = TillClosing(
        id: 't-new', day: day, expected: expected, counted: counted, gap: counted - expected,
        openingFloat: openingFloat, cashSales: 9000, closerName: 'Caisse Kiosque Nova', closedAt: day);
    history = [done, ...history];
    return done;
  }

  @override
  Future<List<TillClosing>> tillClosings(String orgId, {int limit = 20}) async {
    if (missing) throw const PostgrestException(message: 'Could not find the table', code: 'PGRST205');
    return history;
  }
}

class _Retail extends RetailRepository {
  _Retail({this.orders = const [], _Guards? guards})
      : _guards = guards ?? _Guards(),
        super(null);
  final List<ShopOrder> orders;
  final _Guards _guards;

  @override
  FraudGuardsRepository get guards => _guards;
  @override
  bool get isConfigured => true;
  @override
  Future<List<ShopOrder>> shopOrders(String orgId) async => orders;
  @override
  Future<Map<String, OrderClock>> orderClocks(String orgId) async => const {};
  @override
  Future<List<CashOwed>> cashOwed(String orgId) async => const [];
  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();
  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 7}) async => const [];
  @override
  Future<int> pendingOrders(String orgId) async => 0;
  @override
  Future<double> lossesAvoided(String orgId, {int within = 30}) async => 0;
}

ShopOrder _order(String id, String name, {String status = 'pending'}) => ShopOrder.fromRow({
      'id': id,
      'customer_name': name,
      'status': status,
      'fulfilment': 'pickup',
      'total': 4500,
      'currency': 'XOF',
      'created_at': '2026-10-15T09:00:00Z',
      'payment_method': 'cash',
      'lines': [
        {'name': 'Savon karité', 'unit_price': 1500, 'quantity': 3},
      ],
    });

CustomerOrder _mine(String id, String status, {String payment = 'cash', bool paid = false}) =>
    CustomerOrder.fromRow({
      'id': id,
      'shop_name': 'Kiosque Nova',
      'shop_slug': 'kiosque-nova',
      'status': status,
      'fulfilment': 'pickup',
      'total': 4500,
      'currency': 'XOF',
      'payment_method': payment,
      'paid_at': paid ? '2026-10-15T09:30:00Z' : null,
      'created_at': '2026-10-15T09:00:00Z',
      'lines': [
        {'name': 'Savon karité', 'unit_price': 1500, 'quantity': 3},
      ],
    });

class _Window extends StorefrontRepository {
  _Window({this.wave}) : super(null);
  final String? wave;
  List<CustomerOrder> mine = const [];

  @override
  bool get isConfigured => true;
  @override
  Future<PublicShop?> shop(String slug) async => PublicShop.fromRow({
        'org_id': 'b151-shop',
        'name': 'Kiosque Nova',
        'slug': slug,
        'profile': 'retail',
        'address': 'Ouagadougou',
        'phone': '+22670000000',
        'wave_merchant': ?wave,
      });
  @override
  Future<List<PublicItem>> items(String slug) async => const [_savon];
  @override
  Future<Set<String>> showcaseSlugs() async => const {};
  @override
  Future<List<CustomerOrder>> myOrders() async => mine;
}

class _Shopper extends ShopperRepository {
  _Shopper() : super(null);
  @override
  bool get isConfigured => true;
  @override
  String? get picture => null;
  @override
  Future<ShopperProfile> profile() async => const ShopperProfile(city: 'Ouagadougou');
  @override
  Future<List<FollowedVitrine>> follows() async => const [];
}

class _Session extends SessionController {
  _Session(LocalDb db, {this.mine = const [], SessionPhase phase = SessionPhase.noOrg})
      : _now = phase,
        super(db: db, auth: AuthRepository(null), admin: AdminRepository(null), accounting: AccountingRepository(null));
  final List<OrgSummary> mine;
  final SessionPhase _now;
  @override
  SessionPhase get phase => _now;
  @override
  List<OrgSummary> get orgs => mine;
  @override
  bool get isPlatformAdmin => false;
}

class _Courier extends CourierRepository {
  _Courier({this.caps = const [], this.refuse}) : super(null);
  final List<CashCap> caps;
  final String? refuse;
  final taken = <String>[];

  @override
  bool get isConfigured => true;
  @override
  Future<String?> status() async => 'approved';
  @override
  Future<List<DeliveryJob>> board({double? lat, double? lng}) async => [
        DeliveryJob(
          orderId: 'o9',
          shopName: 'Kiosque Nova',
          total: 30000,
          currency: 'XOF',
          createdAt: DateTime(2026, 10, 15, 9),
          customerName: 'Cliente 1',
          dropAddress: 'Ouagadougou, Gounghin',
          status: 'ready',
        ),
      ];
  @override
  Future<List<DeliveryJob>> mine() async => const [];
  @override
  Future<List<CourierEarnings>> earnings() async => const [];
  @override
  Future<List<CashHeld>> cash() async => const [];
  @override
  Future<List<CashCap>> cashCap() async => caps;
  @override
  Future<CourierReach> reach() async => const CourierReach(city: 'Ouagadougou');
  @override
  Future<void> take(String orderId) async {
    final r = refuse;
    if (r != null) throw PostgrestException(message: r, code: 'P0001');
    taken.add(orderId);
  }
}

class _NoWhere extends CourierWhere {
  const _NoWhere();
  @override
  Future<LocationPermission> check() async => LocationPermission.deniedForever;
  @override
  Future<LocationPermission> request() async => LocationPermission.denied;
}

class _Center extends CommandCenterRepository {
  _Center({this.queue = const ReviewQueue()}) : super(null);
  PlatformTodo todoAnswer = const PlatformTodo({});
  final ReviewQueue queue;
  @override
  bool get isConfigured => true;
  @override
  Future<PlatformTodo> todo() async => todoAnswer;
  @override
  Future<ReviewQueue> reviewQueue() async => queue;
  @override
  Future<PlatformToday?> today() async => null;
  @override
  Future<PlatformOverview?> overview() async => null;
  @override
  Future<TodayCounts?> todayCounts() async => null;
  @override
  Future<Map<String, SettingValue>> settings() async => {
        'order_open_max_per_shop': const SettingValue(value: 3),
        'order_first_open_max': const SettingValue(value: 2),
        'courier_cash_cap': const SettingValue(value: 50000),
        'till_gap_review': const SettingValue(value: 5000),
        'admin_two_step': const SettingValue(value: true),
        'apple_web_signin': const SettingValue(value: false),
      };
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
}

final _queue = ReviewQueue(
  businesses: const [
    ReviewBusiness(orgId: 'b151-farm', name: 'Ferme Horizon', profile: 'farm', blocks: 3, refused: 1),
  ],
  couriers: const [
    ReviewCourier(userId: 'u-rider', name: 'Livreur Rapide', phone: '+22670111111', held: 85000, cap: 50000),
  ],
  tills: [
    ReviewTill(orgId: 'b151-shop', name: 'Kiosque Nova', day: DateTime(2026, 10, 14), gap: -6000,
        expected: 48000, counted: 42000, closer: 'Caisse Kiosque Nova'),
  ],
  reportsOpen: 2,
  couriersPending: 1,
  cashCap: 50000,
  tillGap: 5000,
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _size(WidgetTester tester, Size size, {double scale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  if (scale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

Future<void> _settle(WidgetTester tester, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Widget _app(Widget home, {String lang = 'fr', ThemeData? theme}) => RepaintBoundary(
      key: const Key('screen'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(lang),
        theme: theme,
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: home,
      ),
    );

Future<bool> _realFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6 && !Directory('${dir.path}/material_fonts').existsSync(); i++) {
    dir = dir.parent;
  }
  final fonts = Directory('${dir.path}/material_fonts');
  if (!fonts.existsSync()) return false;
  final loader = FontLoader('Roboto');
  for (final f in const ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    final file = File('${fonts.path}/$f');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
  final icons = File('${fonts.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer))))
        .load();
  }
  return true;
}

/// The order sheet, as the vitrine opens it.
Widget _orderSheet({String? wave, VoidCallback? onReport, String lang = 'fr'}) => _app(
      Builder(
        builder: (context) => Theme(
          data: ShopStyle.theme(context),
          child: Scaffold(
            body: OrderSheet(
              items: const [_savon],
              basket: const {'p-savon': 2},
              currency: 'XOF',
              waveMerchant: wave,
              delivers: false,
              onReport: onReport,
              onSubmit: ({
                required Map<String, double> lines,
                required String fulfilment,
                String? note,
                String? address,
                String? phone,
                required String payment,
                double? dropLat,
                double? dropLng,
              }) async =>
                  null,
              quote: (lat, lng) async => null,
            ),
          ),
        ),
      ),
      lang: lang,
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
    await _realFonts();
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
    Support.reset();
  });
  tearDown(() async {
    Support.reset();
    await db.close();
  });

  /// The vitrine, inside the app's scope, at [slug].
  Future<void> pumpVitrine(WidgetTester tester, _Session session,
      {String lang = 'fr', Size size = const Size(390, 900), double scale = 1.0, String? wave}) async {
    await _size(tester, size, scale: scale);
    final street = _Window(wave: wave);
    final router = GoRouter(initialLocation: '/s/kiosque-nova', routes: [
      GoRoute(
          path: '/s/:slug',
          builder: (_, state) => StorefrontScreen(
                slug: state.pathParameters['slug']!,
                storefront: street,
                capture: CaptureRepository(null, db: db),
                session: session,
                shopper: _Shopper(),
              )),
      GoRoute(path: Routes.directory, builder: (_, _) => const Scaffold(body: Text('la rue'))),
    ]);
    await tester.pumpWidget(RepaintBoundary(
      key: const Key('screen'),
      child: AppScope(
        session: session,
        localeController: LocaleController(db),
        db: db,
        auth: session.auth,
        admin: session.admin,
        reports: ReportsRepository(null),
        accounting: AccountingRepository(null),
        console: ConsoleRepository(null),
        farm: FarmRepository(null),
        invoicing: InvoicingRepository(null),
        retail: RetailRepository(null),
        staff: StaffRepository(null),
        capture: CaptureRepository(null, db: db),
        onboarding: OnboardingRepository(null),
        credit: CreditRepository(null),
        tontine: TontineRepository(null),
        production: ProductionRepository(null),
        notify: NotificationsRepository(null),
        analytics: AnalyticsRepository(null),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          locale: Locale(lang),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
        ),
      ),
    ));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 800));
  }

  // -------------------------------------------------------------------------
  // 1. « Ne payez jamais d'avance »
  // -------------------------------------------------------------------------
  group('1. never pay in advance', () {
    testWidgets('the line: cash, cash with Wave, Wave, each in English too', (tester) async {
      for (final (way, also, at, fr) in const [
        (PayWay.cash, false, PayAt.either, _cashFr),
        (PayWay.cash, true, PayAt.either, _cashWaveFr),
        (PayWay.cash, false, PayAt.pickup, _pickupFr),
        (PayWay.cash, true, PayAt.pickup, _pickupWaveFr),
        (PayWay.cash, false, PayAt.delivery, _deliveryFr),
        (PayWay.wave, false, PayAt.pickup, _waveFr),
      ]) {
        await tester.pumpWidget(_app(Scaffold(body: PaySafetyLine(way: way, alsoWave: also, at: at))));
        expect(find.text(fr), findsOneWidget);
        expect(find.byKey(const Key('pay-safety-report')), findsNothing, reason: 'nothing to open');
        await tester.pumpWidget(_app(Scaffold(body: PaySafetyLine(way: way, alsoWave: also, at: at)), lang: 'en'));
        expect(find.text(enStrings[fr]!), findsOneWidget);
      }
      expect(enStrings[_cashFr], 'Never pay in advance to someone you do not know. Pay on delivery or at pickup.');
    });

    testWidgets('the order sheet: the cash line, then Wave\'s own words, and « Signaler »', (tester) async {
      await _size(tester, const Size(390, 1200));
      var reported = 0;
      await tester.pumpWidget(_orderSheet(wave: 'https://pay.wave.com/m/kiosque', onReport: () => reported++));
      await tester.pumpAndSettle();
      expect(find.text(_pickupFr), findsOneWidget, reason: 'a pickup: at the counter');
      expect(find.text(_waveFr), findsNothing);
      await tester.tap(find.text('Wave'));
      await tester.pumpAndSettle();
      expect(find.text(_waveFr), findsOneWidget, reason: 'Wave through Mara is never « d\'avance »');
      expect(find.text(_pickupFr), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('pay-safety-report')));
      await tester.tap(find.byKey(const Key('pay-safety-report')));
      expect(reported, 1);
    });

    testWidgets('an open cash order says it, a Wave one says Wave\'s, a paid or finished one nothing', (tester) async {
      await _size(tester, const Size(390, 2400));
      final window = _Window()
        ..mine = [
          _mine('o-cash', 'accepted'),
          _mine('o-wave', 'accepted', payment: 'wave'),
          _mine('o-paid', 'ready', payment: 'wave', paid: true),
          _mine('o-done', 'picked_up'),
        ];
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: window, shopper: _Shopper())));
      await tester.pumpAndSettle();
      expect(find.text(_pickupFr), findsOneWidget);
      expect(find.text(_waveFr), findsOneWidget);
      expect(find.byKey(const Key('pay-safety')), findsNWidgets(2), reason: 'not the paid one, not the finished one');
      // « Signaler »: the report sheet about that order.
      await tester.ensureVisible(find.byKey(const Key('pay-safety-report')).first);
      await tester.tap(find.byKey(const Key('pay-safety-report')).first);
      await tester.pumpAndSettle();
      final sheet = tester.widget<ReportSheet>(find.byType(ReportSheet));
      expect(sheet.orderId, 'o-cash');
    });

    testWidgets('the vitrine: a visitor reads it beside the contact buttons, the owner does not', (tester) async {
      await pumpVitrine(tester, _Session(db));
      expect(find.text(_pickupFr), findsOneWidget, reason: 'a vitrine that does not deliver: never « livraison »');
      expect(find.byKey(const Key('pay-safety-report')), findsOneWidget);
      await pumpVitrine(tester, _Session(db, mine: const [_shop], phase: SessionPhase.ready));
      expect(find.byKey(const Key('pay-safety')), findsNothing);
    });

    testWidgets('a vitrine taking Wave: « ou par Wave dans Mara »', (tester) async {
      await pumpVitrine(tester, _Session(db), wave: 'https://pay.wave.com/m/kiosque');
      expect(find.text(_pickupWaveFr), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 2. Order limits and « Bloquer ce client »
  // -------------------------------------------------------------------------
  group('2. limits and blocking', () {
    test('every refusal of 146 has its English', () {
      for (final fr in const [
        'Cette boutique ne prend pas votre commande pour le moment.',
        'Cette ferme ne prend pas votre commande pour le moment.',
        'Cette association ne prend pas votre commande pour le moment.',
        'Vous avez déjà plusieurs commandes en cours ici : attendez qu\'une soit terminée pour en passer une autre.',
        'Un nouveau compte a peu de commandes en cours à la fois : attendez que l\'une d\'elles soit terminée.',
        'Vous portez déjà assez d\'espèces : remettez l\'argent aux boutiques avant de prendre une autre course payée en espèces.',
        'Cette course dépasse ce qu\'un livreur peut porter en espèces : la boutique la livre elle-même.',
        'Seul le propriétaire ou un administrateur fait un retour de vente.',
        'Une association clôture sa journée, pas une caisse',
        'De 0 (sans limite) à 50 commandes, s\'il vous plaît.',
        'De 1 000 à 10 000 000 FCFA, ou 0 pour aucun, s\'il vous plaît.',
      ]) {
        expect(translate('en', fr), isNot(fr), reason: fr);
        expect(translate('en', fr).toLowerCase(), isNot(contains('block')),
            reason: 'never says « blocked » to the shopper');
      }
    });

    for (final org in [_shop, _farm, _assoc]) {
      testWidgets('${org.profile}: the owner blocks from the order\'s ⋮, with a reason', (tester) async {
        await _size(tester, const Size(390, 900));
        final guards = _Guards();
        await tester.pumpWidget(_app(ShopOrdersScreen(
            org: org, retail: _Retail(orders: [_order('o1', 'Cliente 1')]), guards: guards)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('order-menu-o1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bloquer ce client'));
        await tester.pumpAndSettle();
        expect(find.text('Bloquer Cliente 1 ?'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('block-reason')), 'Commandes jamais retirées');
        await tester.tap(find.byKey(const Key('block-yes')));
        await tester.pumpAndSettle();
        expect(guards.blocked, [('o1', 'Commandes jamais retirées')]);
        expect(find.text('Cliente 1 ne peut plus commander chez vous.'), findsOneWidget);
      });
    }

    testWidgets('an employee sees no ⋮ on an order', (tester) async {
      await _size(tester, const Size(390, 900));
      await tester.pumpWidget(_app(ShopOrdersScreen(
          org: _as(_shop, const ['employee']), retail: _Retail(orders: [_order('o1', 'Cliente 1')]))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-menu-o1')), findsNothing);
    });

    testWidgets('« Annuler » blocks nobody; a server before 146 is said plainly', (tester) async {
      await _size(tester, const Size(390, 900));
      final guards = _Guards(missing: true);
      await tester.pumpWidget(_app(ShopOrdersScreen(
          org: _shop, retail: _Retail(orders: [_order('o1', 'Client 2')]), guards: guards)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-menu-o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bloquer ce client'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(guards.blocked, isEmpty);
      await tester.tap(find.byKey(const Key('order-menu-o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bloquer ce client'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block-yes')));
      await tester.pumpAndSettle();
      expect(find.text('Bloquer un client arrive avec la prochaine mise à jour du serveur.'), findsOneWidget);
    });

    testWidgets('« Clients bloqués »: the list, « Débloquer », then the empty word', (tester) async {
      await _size(tester, const Size(390, 900));
      final guards = _Guards();
      await tester.pumpWidget(_app(BlockedCustomersScreen(org: _farm, guards: guards)));
      await tester.pumpAndSettle();
      expect(find.text('Cliente 1'), findsOneWidget);
      expect(find.text('Client 2'), findsOneWidget);
      expect(find.text('Commandes jamais retirées'), findsOneWidget);
      await tester.tap(find.byKey(const Key('unblock-c1')));
      await tester.pumpAndSettle();
      expect(guards.unblocked, ['c1']);
      expect(find.text('Cliente 1 peut de nouveau commander chez vous.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('unblock-c2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blocked-empty')), findsOneWidget);
    });

    testWidgets('« Clients bloqués » before 146: the notice, no error', (tester) async {
      await tester.pumpWidget(_app(BlockedCustomersScreen(org: _assoc, guards: _Guards(missing: true))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blocked-missing')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 3. The courier's cash cap
  // -------------------------------------------------------------------------
  group('3. the cash cap', () {
    Future<void> open(WidgetTester tester, _Courier courier, {String lang = 'fr', Size size = const Size(390, 900),
        double scale = 1.0}) async {
      await _size(tester, size, scale: scale);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(CourierScreen(courier: courier, where: const _NoWhere()), lang: lang));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('held against the cap, then full', (tester) async {
      await open(tester, _Courier(caps: const [CashCap(currency: 'XOF', held: 30000, cap: 50000)]));
      expect(find.text('Espèces en main : ${_f(30000)} sur ${_f(50000)} au plus'), findsOneWidget);
      expect(find.textContaining('Plafond atteint'), findsNothing);
      await open(tester, _Courier(caps: const [CashCap(currency: 'XOF', held: 55000, cap: 50000)]));
      expect(find.textContaining('Plafond atteint'), findsOneWidget);
    });

    testWidgets('« J\'accepte » refused by the cap: its words, not « trop tard »', (tester) async {
      const words =
          'Vous portez déjà assez d\'espèces : remettez l\'argent aux boutiques avant de prendre une autre course payée en espèces.';
      final courier = _Courier(caps: const [CashCap(currency: 'XOF', held: 30000, cap: 50000)], refuse: words);
      await open(tester, courier);
      await tester.ensureVisible(find.text('J\'accepte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('J\'accepte'));
      await tester.pumpAndSettle();
      expect(find.text(words), findsOneWidget);
      expect(find.textContaining('Trop tard'), findsNothing);
    });

    testWidgets('no cap answered (a server before 146, or a money with none): no strip', (tester) async {
      await open(tester, _Courier(caps: const [CashCap(currency: 'EUR', held: 40)]));
      expect(find.byKey(const Key('courier-cash-cap-EUR')), findsNothing);
      await open(tester, _Courier());
      expect(find.textContaining('Espèces en main'), findsNothing);
    });

    testWidgets('in English', (tester) async {
      await open(tester, _Courier(caps: const [CashCap(currency: 'XOF', held: 30000, cap: 50000)]), lang: 'en');
      expect(find.text('Cash in hand: ${_f(30000)} of ${_f(50000)} at most'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 4. « Clôturer la caisse »
  // -------------------------------------------------------------------------
  group('4. closing the till', () {
    Future<void> sheet(WidgetTester tester, _Guards guards,
        {OrgSummary org = _shop, String lang = 'fr', Size size = const Size(390, 1000), double scale = 1.0}) async {
      await _size(tester, size, scale: scale);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(
          Scaffold(body: TillCloseSheet(org: org, guards: guards, today: DateTime(2026, 10, 15, 19))),
          lang: lang));
      await tester.pumpAndSettle();
    }

    testWidgets('blind: the count and the float sent, the expected and the gap said after', (tester) async {
      final guards = _Guards();
      await sheet(tester, guards);
      expect(find.text('Attendu'), findsNothing, reason: 'counted blind');
      await tester.enterText(find.byKey(const Key('till-counted')), '13500');
      await tester.enterText(find.byKey(const Key('till-float')), '5000');
      await tester.enterText(find.byKey(const Key('till-note')), 'Fin de journée');
      await tester.tap(find.byKey(const Key('till-close')));
      await tester.pumpAndSettle();
      expect(guards.closed, [
        {'org': 'b151-shop', 'counted': 13500.0, 'float': 5000.0, 'note': 'Fin de journée'},
      ]);
      expect(find.byKey(const Key('till-result')), findsOneWidget);
      expect(find.text('Il manque ${_f(500)}'), findsWidgets);
      expect(find.text(_f(14000)), findsOneWidget, reason: 'the expected');
    });

    testWidgets('right on: « Juste »; too much: « en trop »', (tester) async {
      await sheet(tester, _Guards());
      await tester.enterText(find.byKey(const Key('till-counted')), '9000');
      await tester.tap(find.byKey(const Key('till-close')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('till-gap'))).data, 'Juste : la caisse tombe juste');
      await sheet(tester, _Guards());
      await tester.enterText(find.byKey(const Key('till-counted')), '9200');
      await tester.tap(find.byKey(const Key('till-close')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('till-gap'))).data, '${_f(200)} en trop');
    });

    testWidgets('nothing counted: asked again, nothing sent', (tester) async {
      final guards = _Guards();
      await sheet(tester, guards);
      await tester.tap(find.byKey(const Key('till-close')));
      await tester.pumpAndSettle();
      expect(find.text('Indiquez les espèces comptées dans la caisse.'), findsOneWidget);
      expect(guards.closed, isEmpty);
    });

    testWidgets('the history: each closing, its closer and its gap', (tester) async {
      await sheet(tester, _Guards(), org: _farm);
      expect(find.text('Clôtures récentes'), findsOneWidget);
      expect(find.text('Il manque ${_f(1000)}'), findsOneWidget);
      expect(find.text('Juste : la caisse tombe juste'), findsOneWidget);
    });

    testWidgets('before 146: the notice, the sales untouched, no button', (tester) async {
      await sheet(tester, _Guards(missing: true));
      expect(find.byKey(const Key('till-missing')), findsOneWidget);
      expect(find.byKey(const Key('till-close')), findsNothing);
    });

    testWidgets('the shop\'s home has « Clôturer la caisse », which opens the sheet', (tester) async {
      await _size(tester, const Size(480, 1800));
      await tester.pumpWidget(_app(StoreHomeScreen(org: _shop, retail: _Retail())));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      expect(find.byKey(const Key('home-close-till')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-close-till')));
      await _settle(tester);
      expect(find.byType(TillCloseSheet), findsOneWidget);
    });

    testWidgets('an observer\'s home: no closing', (tester) async {
      await _size(tester, const Size(480, 1800));
      await tester.pumpWidget(_app(StoreHomeScreen(org: _as(_shop, const ['observer']), retail: _Retail())));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      expect(find.byKey(const Key('home-close-till')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 5. The console
  // -------------------------------------------------------------------------
  group('5. the console', () {
    test('the four settings, on Réglages › Sécurité › Protections contre la fraude, with their ranges', () {
      for (final k in const ['order_open_max_per_shop', 'order_first_open_max', 'courier_cash_cap', 'till_gap_review']) {
        expect(platformSettingDefs.where((d) => d.key == k), hasLength(1), reason: k);
        expect(settingCardOf(k)?.key, 'securite', reason: k);
        expect(rangedSettings[k], isNotNull, reason: k);
      }
      expect(rangedSettings['order_open_max_per_shop'], (0, 50));
      expect(rangedSettings['courier_cash_cap'], (0, 10000000));
    });

    testWidgets('their names, in French and in English', (tester) async {
      late BuildContext fr;
      late BuildContext en;
      await tester.pumpWidget(_app(Builder(builder: (c) {
        fr = c;
        return const SizedBox();
      })));
      final frName = settingLabel(fr, 'courier_cash_cap');
      await tester.pumpWidget(_app(Builder(builder: (c) {
        en = c;
        return const SizedBox();
      }), lang: 'en'));
      expect(frName, 'Espèces qu\'un livreur porte au plus à la fois — FCFA (0 : sans plafond)');
      expect(settingLabel(en, 'courier_cash_cap'), 'Most cash a courier carries at once — FCFA (0: no cap)');
      expect(settingPartLabel(en, 'fraud'), 'Fraud protection');
    });

    testWidgets('« À vérifier : fraude » in « Aujourd\'hui », urgent, and its sheet', (tester) async {
      await _size(tester, const Size(390, 1000));
      final center = _Center(queue: _queue)..todoAnswer = const PlatformTodo({'review': 3, 'new_7': 1});
      final router = GoRouter(initialLocation: Routes.console, routes: [
        ShellRoute(
          builder: (_, _, child) => CommandCenterShell(center: center, platformAdmin: true, child: child),
          routes: [
            GoRoute(path: Routes.console, builder: (_, _) => TodoSection(center: center, admin: _Admin())),
            GoRoute(path: Routes.consoleCouriers, builder: (_, _) => const Scaffold(body: Text('page livreurs'))),
            GoRoute(
                path: '${Routes.consoleBusinesses}/:id',
                builder: (_, state) => Scaffold(body: Text('fiche ${state.pathParameters['id']}'))),
          ],
        ),
      ]);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('todo-review')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('todo-review'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const Key('todo-new_7'))).dy), reason: 'urgent first');
      await tester.tap(find.byKey(const Key('todo-review')));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewQueueSheet), findsOneWidget);
      expect(find.text('Signalements à lire · 2'), findsOneWidget);
      expect(find.text('Livreurs à valider · 1'), findsOneWidget);
      expect(find.text('Ferme Horizon'), findsOneWidget);
      expect(find.text('3 clients bloqués en 30 j · 1 commande refusée en 7 j'), findsOneWidget);
      expect(find.text('Livreur Rapide'), findsOneWidget);
      expect(find.textContaining('${_f(85000)} en main pour ${_f(50000)} au plus'), findsOneWidget);
      expect(find.textContaining('il manque ${_f(6000)}'), findsOneWidget);
      await tester.tap(find.text('Ferme Horizon'));
      await tester.pumpAndSettle();
      expect(find.text('fiche b151-farm'), findsOneWidget);
    });

    test('a server before 146: no counter (PlatformTodo.has)', () {
      expect(const PlatformTodo({}).has('review'), isFalse);
      expect(const PlatformTodo({'review': 0}).has('review'), isTrue);
    });

    testWidgets('the sheet with nothing to look at says why each list is empty', (tester) async {
      await _size(tester, const Size(390, 1000));
      final center = _Center(queue: const ReviewQueue(cashCap: 50000, tillGap: 5000));
      await tester.pumpWidget(_app(Builder(
          builder: (context) => Scaffold(
              body: ReviewQueueSheet(center: center, outer: context)))));
      await tester.pumpAndSettle();
      expect(find.text('Aucun : chaque livreur porte moins de ${_f(50000)}.'), findsOneWidget);
      expect(find.text('Aucun écart de ${_f(5000)} ou plus.'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 6 and the screenshots: every new screen and state, one tree each.
  // -------------------------------------------------------------------------
  /// Each new screen or state: its name, and how to bring it up.
  final scenes = <(String, Future<void> Function(WidgetTester, String lang, Size size, double scale))>[
    ('01_order_sheet_cash', (tester, lang, size, scale) async {
      await tester.pumpWidget(_orderSheet(wave: 'https://pay.wave.com/m/k', onReport: () {}, lang: lang));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pay-safety')));
      await tester.pumpAndSettle();
    }),
    ('02_order_sheet_wave', (tester, lang, size, scale) async {
      await tester.pumpWidget(_orderSheet(wave: 'https://pay.wave.com/m/k', onReport: () {}, lang: lang));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wave'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pay-safety')));
      await tester.pumpAndSettle();
    }),
    ('03_my_orders', (tester, lang, size, scale) async {
      final window = _Window()..mine = [_mine('o-cash', 'accepted'), _mine('o-wave', 'pending', payment: 'wave')];
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: window, shopper: _Shopper()), lang: lang));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pay-safety')).first);
      await tester.pumpAndSettle();
    }),
    ('04_vitrine_contact', (tester, lang, size, scale) async {
      await pumpVitrine(tester, _Session(db), lang: lang, size: size, scale: scale,
          wave: 'https://pay.wave.com/m/k');
      await tester.ensureVisible(find.byKey(const Key('pay-safety')));
      await _settle(tester, 3);
    }),
    ('05_order_menu', (tester, lang, size, scale) async {
      await tester.pumpWidget(_app(
          ShopOrdersScreen(org: _shop, retail: _Retail(orders: [_order('o1', 'Cliente 1')]), guards: _Guards()),
          lang: lang));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-menu-o1')));
      await tester.pumpAndSettle();
    }),
    ('06_block_confirm', (tester, lang, size, scale) async {
      await tester.pumpWidget(_app(
          ShopOrdersScreen(org: _shop, retail: _Retail(orders: [_order('o1', 'Cliente 1')]), guards: _Guards()),
          lang: lang));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-menu-o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-block-o1')));
      await tester.pumpAndSettle();
    }),
    ('07_blocked_list', (tester, lang, size, scale) async {
      await tester.pumpWidget(_app(BlockedCustomersScreen(org: _shop, guards: _Guards()), lang: lang));
      await tester.pumpAndSettle();
    }),
    ('08_courier_cap', (tester, lang, size, scale) async {
      await tester.pumpWidget(_app(
          CourierScreen(
              courier: _Courier(caps: const [CashCap(currency: 'XOF', held: 30000, cap: 50000)]),
              where: const _NoWhere()),
          lang: lang));
      await tester.pump();
      await tester.pumpAndSettle();
    }),
    ('09_courier_full_refused', (tester, lang, size, scale) async {
      await tester.pumpWidget(_app(
          CourierScreen(
              courier: _Courier(
                  caps: const [CashCap(currency: 'XOF', held: 55000, cap: 50000)],
                  refuse:
                      'Vous portez déjà assez d\'espèces : remettez l\'argent aux boutiques avant de prendre une autre course payée en espèces.'),
              where: const _NoWhere()),
          lang: lang));
      await tester.pump();
      await tester.pumpAndSettle();
      final take = find.text(lang == 'en' ? 'I accept' : 'J\'accepte');
      await tester.ensureVisible(take);
      await tester.pumpAndSettle();
      await tester.tap(take);
      await tester.pumpAndSettle();
    }),
    ('10_till_form', (tester, lang, size, scale) async {
      await tester.pumpWidget(_app(
          Scaffold(body: TillCloseSheet(org: _shop, guards: _Guards(), today: DateTime(2026, 10, 15, 19))),
          lang: lang));
      await tester.pumpAndSettle();
    }),
    ('11_till_result', (tester, lang, size, scale) async {
      await tester.pumpWidget(_app(
          Scaffold(body: TillCloseSheet(org: _shop, guards: _Guards(), today: DateTime(2026, 10, 15, 19))),
          lang: lang));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('till-counted')), '13500');
      await tester.enterText(find.byKey(const Key('till-float')), '5000');
      await tester.tap(find.byKey(const Key('till-close')));
      await tester.pumpAndSettle();
    }),
    ('12_till_missing', (tester, lang, size, scale) async {
      await tester.pumpWidget(_app(
          Scaffold(body: TillCloseSheet(org: _farm, guards: _Guards(missing: true), today: DateTime(2026, 10, 15, 19))),
          lang: lang));
      await tester.pumpAndSettle();
    }),
    ('13_store_home_button', (tester, lang, size, scale) async {
      await tester.pumpWidget(_app(StoreHomeScreen(org: _shop, retail: _Retail()), lang: lang));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.ensureVisible(find.byKey(const Key('home-close-till')));
      await tester.pump(const Duration(milliseconds: 400));
    }),
    ('14_review_queue', (tester, lang, size, scale) async {
      await tester.pumpWidget(_app(
          Builder(builder: (c) => Scaffold(body: ReviewQueueSheet(center: _Center(queue: _queue), outer: c))),
          lang: lang));
      await tester.pumpAndSettle();
    }),
    ('15_settings_fraud', (tester, lang, size, scale) async {
      final center = _Center();
      final router = GoRouter(initialLocation: '${Routes.consoleSettings}/securite', routes: [
        GoRoute(
          path: '${Routes.consoleSettings}/:card',
          builder: (_, state) => SettingsSection(center: center, card: state.pathParameters['card']),
        ),
      ]);
      await tester.pumpWidget(RepaintBoundary(
        key: const Key('screen'),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          locale: Locale(lang),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('setting-till_gap_review')), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }),
  ];

  group('6. small phone, large text: nothing overflows', () {
    for (final lang in const ['fr', 'en']) {
      for (final (name, bring) in scenes) {
        testWidgets('$name at 320 × 1.3 ($lang)', (tester) async {
          const size = Size(320, 700);
          await _size(tester, size, scale: 1.3);
          await bring(tester, lang, size, 1.3);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  final shots = Platform.environment['B151_SHOTS'];
  group('screenshots', () {
    Future<void> capture(WidgetTester tester, String path) async {
      await tester.pump();
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('screen')).first);
        final img = await ro.toImage(pixelRatio: 2);
        final data = await img.toByteData(format: ImageByteFormat.png);
        File(path).writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    for (final (w, h, scale) in const [(390.0, 844.0, 1.0), (320.0, 700.0, 1.3)]) {
      for (final lang in const ['fr', 'en']) {
        final tag = '${lang}_${w.toInt()}_$scale';
        for (final (name, bring) in scenes) {
          testWidgets('$name — $tag', (tester) async {
            Directory(shots!).createSync(recursive: true);
            final size = Size(w, h);
            await _size(tester, size, scale: scale);
            await bring(tester, lang, size, scale);
            await capture(tester, '$shots/${name}_$tag.png');
          }, skip: shots == null);
        }
      }
    }
  });
}
