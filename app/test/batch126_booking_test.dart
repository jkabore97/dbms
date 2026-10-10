import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/whatsapp_phone.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/orders/booking.dart';
import 'package:kaj_app/core/orders/orders.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/features/orders/my_orders_screen.dart';
import 'package:kaj_app/features/orders/order_walkthrough.dart';
import 'package:kaj_app/features/orders/shop_orders_screen.dart';
import 'package:kaj_app/features/storefront/booking_sheet.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, User;

/// Batch 126 (migration 125): a service is booked, not basketed — a day
/// and a time from the vitrine's hours, how many only by the person or the
/// hour, the sign-in kept, « Demande envoyée »; the business confirms,
/// proposes another time or refuses; the customer accepts; the bells say
/// the day and the time and open that booking; without 125, « Réservation
/// indisponible » and the goods ordered as ever. The same for a shop, a
/// farm and an association.

const _slug = 'salon-awa';

const _coupe = PublicItem(
    id: 's1', name: 'Coupe', price: 3000, inStock: true, isService: true, unit: 'séance');
const _visite = PublicItem(
    id: 's2', name: 'Visite de la ferme', price: 1000, inStock: true, isService: true, unit: 'personne');
const _cours = PublicItem(
    id: 's3', name: 'Cours de couture', price: 2000, inStock: true, isService: true, unit: 'heure');
const _savon = PublicItem(id: 'g1', name: 'Savon', price: 500, inStock: true);

class _Server extends AuthRepository {
  _Server() : super(null);
  bool live = false;
  User? user;
  int launches = 0;
  @override
  bool get isConfigured => true;
  @override
  bool get hasLiveSession => live;
  @override
  User? get currentUser => user;
  @override
  Future<bool> googleAvailable() async => true;
  @override
  Future<void> signInWithGoogle() async => launches++;
  @override
  Future<List<OrgSummary>> fetchOrgs() async => const [];
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<bool> isPlatformAdmin() async => false;
  @override
  Future<int> claimMyInvitations() async => 0;
  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;
}

class _Phone implements WhatsAppPhone {
  @override
  Future<OrderPhoneGate?> gate() async => null;
  @override
  Future<void> sendCode(String e164) async {}
  @override
  Future<void> confirm(String e164, String code) async {}
}

/// The street: a vitrine of three services and an article, its [style],
/// answering « Réserver ».
class _Window extends StorefrontRepository {
  _Window({this.profile = 'retail', this.style, this.phone}) : super(null);
  final String profile;
  final Map<String, dynamic>? style;
  final String? phone;
  final booked = <Map<String, Object?>>[];
  int orders = 0;
  Object? refuse;
  bool before125 = false;
  List<CustomerOrder> mine = const [];
  final accepted = <String>[];
  final cancelled = <String>[];

  @override
  bool get isConfigured => true;
  @override
  Future<PublicShop?> shop(String slug) async => PublicShop.fromRow({
        'org_id': 'o1',
        'name': profile == 'farm' ? 'Ferme Ignace' : profile == 'association' ? 'Entraide' : 'Salon Awa',
        'slug': slug,
        'profile': profile,
        'style': ?style,
        'phone': ?phone,
      });
  @override
  Future<List<PublicItem>> items(String slug) async => const [_coupe, _visite, _cours, _savon];
  @override
  Future<String> bookService(String slug,
      {required String productId, required DateTime at, int quantity = 1, String? note, String? phone}) async {
    if (before125) throw const BookingUnavailable();
    final r = refuse;
    if (r != null) {
      refuse = null;
      throw r;
    }
    booked.add({'product': productId, 'at': at, 'quantity': quantity, 'note': note});
    return 'b1';
  }

  @override
  Future<String> placeOrder(String slug,
      {required Map<String, double> lines,
      required String fulfilment,
      String? note,
      String? address,
      String? phone,
      String payment = 'cash',
      double? dropLat,
      double? dropLng}) async {
    orders++;
    return 'order-1';
  }

  @override
  Future<List<CustomerOrder>> myOrders() async => mine;
  @override
  Future<void> acceptBookingTime(String orderId) async => accepted.add(orderId);
  @override
  Future<void> cancelOrder(String orderId) async => cancelled.add(orderId);
}

class _Retail extends RetailRepository {
  _Retail({this.orders = const []}) : super(null);
  List<ShopOrder> orders;
  final moves = <String>[];
  @override
  Future<List<ShopOrder>> shopOrders(String orgId) async => orders;
  @override
  Future<Map<String, OrderClock>> orderClocks(String orgId) async => const {};
  @override
  Future<List<CashOwed>> cashOwed(String orgId) async => const [];
  @override
  Future<void> decideOrder(String orderId, String status) async => moves.add('$orderId:$status');
  @override
  Future<void> refuseOrder(String orderId, String reason) async => moves.add('$orderId:refused:$reason');
  @override
  Future<void> proposeBookingTime(String orderId, DateTime at) async =>
      moves.add('$orderId:propose:${at.toUtc().toIso8601String()}');
  /// The business's booking hours (125's booking_hours); null as when they
  /// cannot be read.
  VitrineSchedule? hours;
  final hoursAsked = <String>[];
  @override
  Future<VitrineSchedule?> bookingHours(String orgId) async {
    hoursAsked.add(orgId);
    return hours;
  }
}

const _awa = User(
  id: 'awa-1',
  appMetadata: {'provider': 'google'},
  userMetadata: {'full_name': 'Awa Ouédraogo'},
  aud: 'authenticated',
  email: 'awa@example.com',
  createdAt: '2026-10-08T00:00:00Z',
);

/// Tomorrow at [h]:[m] on Ouagadougou's clock (UTC): always bookable in
/// the default hours, whatever day the test runs.
DateTime _tomorrow(int h, [int m = 0]) {
  final n = DateTime.now().toUtc();
  return DateTime.utc(n.year, n.month, n.day + 1, h, m);
}

String _dayKey(DateTime d) => 'booking-day-${d.toIso8601String().substring(0, 10)}';

Widget _app(Widget home, {String lang = 'fr'}) => MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

ShopOrder _booking(String status, {DateTime? at, DateTime? proposed, String id = 'b1', double qty = 1}) =>
    ShopOrder.fromRow({
      'id': id,
      'customer_name': 'Fati',
      'status': status,
      'fulfilment': 'pickup',
      'note': 'Pour ma fille',
      'total': 3000 * qty,
      'currency': 'XOF',
      'created_at': '2026-10-10T09:00:00Z',
      'payment_method': 'cash',
      'lines': [
        {
          'name': 'Coupe',
          'unit_price': 3000,
          'quantity': qty,
          'is_service': true,
          'booked_for': (at ?? DateTime.utc(2026, 10, 13, 10)).toIso8601String(),
          'proposed_for': proposed?.toIso8601String(),
        },
      ],
    });

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('the slots (125)', () {
    // Monday 12 October 2026, 09:10 in Ouagadougou (UTC).
    final monday = DateTime.utc(2026, 10, 12, 9, 10);

    test('no hours set: every day 08:00–20:00, every 30 minutes, the next 14 days', () {
      final days = bookingDays(null, now: monday);
      expect(days.first.date, DateTime.utc(2026, 10, 12));
      // Today: from the next half-hour, 09:30; the last at 19:30.
      expect(days.first.slots.first, DateTime.utc(2026, 10, 12, 9, 30));
      expect(days.first.slots.last, DateTime.utc(2026, 10, 12, 19, 30));
      final tomorrow = days[1].slots;
      expect(tomorrow.length, 24, reason: '08:00 to 19:30');
      for (var i = 1; i < tomorrow.length; i++) {
        expect(tomorrow[i].difference(tomorrow[i - 1]), const Duration(minutes: 30));
      }
      expect(tomorrow.every((t) => t.minute == 0 || t.minute == 30), isTrue);
      // The 14th day only up to now + 14 days (09:10): 08:00, 08:30, 09:00.
      expect(days.last.date, DateTime.utc(2026, 10, 26));
      expect(days.last.slots, [
        DateTime.utc(2026, 10, 26, 8),
        DateTime.utc(2026, 10, 26, 8, 30),
        DateTime.utc(2026, 10, 26, 9),
      ]);
      expect(days.length, 15);
    });

    test('the closed days are hidden, the times outside the hours too', () {
      const hours = VitrineSchedule(days: [1, 2, 3, 4, 5, 6], open: '08:00', close: '18:00');
      final days = bookingDays(hours, now: monday);
      expect(days.any((d) => d.date.weekday == DateTime.sunday), isFalse);
      expect(days.map((d) => d.date), contains(DateTime.utc(2026, 10, 17)), reason: 'Saturday');
      for (final d in days) {
        expect(d.slots.every((t) => t.hour >= 8 && (t.hour < 18)), isTrue);
      }
    });

    test('today\'s past times are hidden; a day with none left is not offered', () {
      final late = DateTime.utc(2026, 10, 12, 15, 45);
      const hours = VitrineSchedule(days: [1, 2, 3, 4, 5, 6], open: '08:00', close: '18:00');
      expect(bookingDays(hours, now: late).first.slots.first, DateTime.utc(2026, 10, 12, 16));
      final evening = DateTime.utc(2026, 10, 12, 18, 5);
      expect(bookingDays(hours, now: evening).first.date, DateTime.utc(2026, 10, 13));
    });

    test('a night (Friday 20:00–02:00): its hours after midnight are Saturday\'s calendar day', () {
      const night = VitrineSchedule(days: [5], open: '20:00', close: '02:00');
      final days = bookingDays(night, now: monday);
      final friday = days.firstWhere((d) => d.date == DateTime.utc(2026, 10, 16));
      expect(friday.slots.first, DateTime.utc(2026, 10, 16, 20));
      expect(friday.slots.last, DateTime.utc(2026, 10, 16, 23, 30));
      final saturday = days.firstWhere((d) => d.date == DateTime.utc(2026, 10, 17));
      expect(saturday.slots.first, DateTime.utc(2026, 10, 17));
      expect(saturday.slots.last, DateTime.utc(2026, 10, 17, 1, 30));
      expect(days.map((d) => d.date.weekday).toSet(), {DateTime.friday, DateTime.saturday});
      expect(openAt(night, DateTime.utc(2026, 10, 17, 2)), isFalse);
      expect(openAt(night, DateTime.utc(2026, 10, 15, 21)), isFalse, reason: 'Thursday');
    });

    test('how many: only by the person or by the hour', () {
      expect(bookingAsksQuantity('personne'), isTrue);
      expect(bookingAsksQuantity('heure'), isTrue);
      expect(bookingAsksQuantity(' Heure '), isTrue);
      expect(bookingAsksQuantity('séance'), isFalse);
      expect(bookingAsksQuantity('jour'), isFalse);
      expect(bookingAsksQuantity(null), isFalse);
    });

    test('the day and the time, in French and in English, on Ouagadougou\'s clock', () {
      final at = DateTime.utc(2026, 10, 14, 10);
      expect(bookingWhen(at, 'fr'), 'mercredi 14 octobre, 10:00');
      expect(bookingWhen(at, 'en'), 'Wednesday 14 October, 10:00');
      expect(bookingWhen(at, 'fr', short: true), 'mercredi 14 oct., 10:00');
      expect(bookingWhen(at, 'en', short: true), 'Wednesday 14 Oct, 10:00');
      expect(bookingWhen(DateTime.utc(2026, 10, 13, 10), 'fr'), 'mardi 13 octobre, 10:00');
      expect(bookingWhen(DateTime.utc(2026, 10, 13, 10), 'en'), 'Tuesday 13 October, 10:00');
      // Whatever zone the phone is in, the salon's 10:00 stays 10:00.
      expect(bookingWhen(DateTime.parse('2026-10-14T12:00:00+02:00'), 'fr'), 'mercredi 14 octobre, 10:00');
      expect(bookingTimeLabel(DateTime.utc(2026, 10, 14, 9, 30)), '09:30');
    });

    test('the lists carry the slot on the booking\'s line; an order of goods none', () {
      final asked = _booking('pending');
      expect(asked.hasSlot, isTrue);
      expect(asked.bookedFor, DateTime.utc(2026, 10, 13, 10));
      expect(asked.awaitsCustomer, isFalse);
      final proposed = _booking('pending', proposed: DateTime.utc(2026, 10, 13, 11));
      expect(proposed.awaitsCustomer, isTrue);
      expect(bookingStateOf('pending', proposedFor: proposed.proposedFor), BookingState.proposed);
      expect(bookingStateOf('accepted'), BookingState.confirmed);
      expect(bookingStateOf('picked_up'), BookingState.done);
      expect(bookingStateOf('refused'), BookingState.declined);
      final goods = CustomerOrder.fromRow({
        'id': 'g',
        'status': 'pending',
        'lines': [
          {'name': 'Savon', 'unit_price': 500, 'quantity': 2},
        ],
      });
      expect(goods.hasSlot, isFalse);
      // A booking made before 125: its day in the note, no slot.
      final old = CustomerOrder.fromRow({
        'id': 'old',
        'status': 'pending',
        'fulfilment': 'pickup',
        'note': 'Samedi 10 h',
        'lines': [
          {'name': 'Coupe', 'unit_price': 3000, 'quantity': 1, 'is_service': true},
        ],
      });
      expect(old.isBooking, isTrue);
      expect(old.hasSlot, isFalse);
    });

    test('a choice kept through a sign-in reads back the same', () {
      final c = BookingChoice(productId: 's2', at: DateTime.utc(2026, 10, 13, 10), quantity: 3, note: 'x');
      final back = BookingChoice.fromJson(jsonDecode(jsonEncode(c.toJson())))!;
      expect(back.productId, 's2');
      expect(back.at, DateTime.utc(2026, 10, 13, 10));
      expect(back.quantity, 3);
      expect(back.note, 'x');
      expect(BookingChoice.fromJson({'product': 's1', 'quantity': 99})!.quantity, bookingMaxQuantity);
      expect(BookingChoice.fromJson('nonsense'), isNull);
    });
  });

  group('the vitrine', () {
    late LocalDb db;
    setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
    tearDown(() => db.close());

    SessionController sessionOn(_Server server) =>
        SessionController(db: db, auth: server, admin: _Admin(), accounting: AccountingRepository(null));

    Future<SessionController> stranger(WidgetTester tester) async {
      final s = sessionOn(_Server());
      await tester.runAsync(s.boot);
      expect(s.phase, SessionPhase.signedOut);
      return s;
    }

    Future<SessionController> shopper(WidgetTester tester, [_Server? server]) async {
      final srv = (server ?? _Server())
        ..live = true
        ..user = _awa;
      final s = sessionOn(srv);
      await tester.runAsync(s.resolveOrgs);
      expect(s.phase, SessionPhase.noOrg);
      return s;
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester, SessionController session, _Window window,
        {String lang = 'fr'}) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final router = GoRouter(initialLocation: Routes.storefront(_slug), routes: [
        GoRoute(
          path: '/s/:slug',
          builder: (_, state) => StorefrontScreen(
            slug: state.pathParameters['slug']!,
            storefront: window,
            capture: CaptureRepository(null, db: db),
            session: session,
            whatsApp: _Phone(),
          ),
        ),
        GoRoute(path: Routes.signIn, builder: (_, state) => const Scaffold(body: Text('connexion'))),
        GoRoute(path: Routes.myOrders, builder: (_, _) => const Scaffold(body: Text('mes commandes'))),
      ]);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        locale: Locale(lang),
      ));
      await settle(tester);
    }

    Future<void> tapBook(WidgetTester tester, String name) async {
      final row = find.ancestor(of: find.text(name).first, matching: find.byType(InkWell)).first;
      final button = find.descendant(of: row, matching: find.byKey(const Key('book-service')));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await settle(tester);
    }

    Future<void> chooseTomorrow(WidgetTester tester, String time) async {
      final day = find.byKey(Key(_dayKey(_tomorrow(0))));
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pumpAndSettle();
      final t = find.byKey(Key('booking-time-$time'));
      await tester.ensureVisible(t);
      await tester.tap(t);
      await tester.pumpAndSettle();
    }

    testWidgets('« Réserver »: the sheet — days, times, no stepper for a « séance » — then « Demande envoyée » with the day and time',
        (tester) async {
      final window = _Window();
      await open(tester, await shopper(tester), window);
      await tapBook(tester, 'Coupe');
      expect(find.byKey(const Key('booking-days')), findsOneWidget);
      expect(find.byKey(const Key('booking-quantity')), findsNothing, reason: 'a « séance » is booked once');
      expect(find.text('Horaires non précisés : tous les jours, de 8 h à 20 h.'), findsOneWidget);
      // Nothing chosen: « Réserver » waits.
      expect(tester.widget<FilledButton>(find.byKey(const Key('booking-send'))).onPressed, isNull);
      await chooseTomorrow(tester, '10:00');
      // 30-minute steps, inside 08:00–20:00.
      expect(find.byKey(const Key('booking-time-08:00')), findsOneWidget);
      expect(find.byKey(const Key('booking-time-10:30')), findsOneWidget);
      expect(find.byKey(const Key('booking-time-19:30')), findsOneWidget);
      expect(find.byKey(const Key('booking-time-20:00')), findsNothing);
      expect(find.byKey(const Key('booking-time-07:30')), findsNothing);
      await tester.enterText(find.byKey(const Key('booking-note')), 'Tresses courtes');
      await tester.tap(find.byKey(const Key('booking-send')));
      await settle(tester);
      expect(window.booked, [
        {'product': 's1', 'at': _tomorrow(10), 'quantity': 1, 'note': 'Tresses courtes'},
      ]);
      expect(find.byKey(const Key('booking-sent')), findsOneWidget);
      expect(find.text('Demande de rendez-vous envoyée'), findsOneWidget);
      expect(find.text(bookingWhen(_tomorrow(10), 'fr')), findsOneWidget);
      // Never the basket.
      await tester.tap(find.text('Fermer'));
      await settle(tester);
      expect(find.byKey(const Key('basket-bar')), findsNothing);
      expect(find.byKey(const Key('basket-inline')), findsNothing);
      expect(await tester.runAsync(() => db.readPref(pendingBookingKey(_slug))), isNull);
    });

    testWidgets('how many: « Pour combien de personnes ? » and « Combien d\'heures ? », 1 to 20',
        (tester) async {
      final window = _Window(profile: 'farm');
      await open(tester, await shopper(tester), window);
      await tapBook(tester, 'Visite de la ferme');
      expect(find.text('Pour combien de personnes ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('booking-more')));
      await tester.tap(find.byKey(const Key('booking-more')));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      await chooseTomorrow(tester, '09:30');
      await tester.tap(find.byKey(const Key('booking-send')));
      await settle(tester);
      expect(window.booked.single['quantity'], 3);
      expect(window.booked.single['at'], _tomorrow(9, 30));
      await tester.tap(find.text('Fermer'));
      await settle(tester);

      await tapBook(tester, 'Cours de couture');
      expect(find.text('Combien d\'heures ?'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('booking-less'))).onPressed, isNull,
          reason: 'never fewer than 1');
    });

    testWidgets('a service never enters the basket — not from « Réserver », not from a basket kept before',
        (tester) async {
      await tester.runAsync(() => db.writePref('street_basket_$_slug', jsonEncode({'s1': 2, 'g1': 1})));
      final window = _Window();
      await open(tester, await shopper(tester), window);
      // The goods kept; the service left out.
      final bar = find.byKey(const Key('basket-inline'));
      await tester.ensureVisible(bar);
      expect(find.descendant(of: bar, matching: find.text('1 article')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.textContaining('service')), findsNothing);
      expect(find.descendant(of: bar, matching: find.text('Coupe')), findsNothing);
      // And the goods ordered as ever.
      await tester.tap(find.descendant(of: bar, matching: find.text('Commander')));
      await settle(tester);
      expect(find.text('Votre commande'), findsOneWidget);
      expect(find.text('1 × Savon'), findsOneWidget);
      expect(find.descendant(of: find.byType(OrderSheet), matching: find.textContaining('Coupe')), findsNothing);
    });

    testWidgets('signed out: the sheet, then the sign-in (the booking kept), then back — the same booking, sent',
        (tester) async {
      final window = _Window(profile: 'association');
      final out = await stranger(tester);
      await open(tester, out, window);
      await tapBook(tester, 'Coupe');
      await chooseTomorrow(tester, '11:00');
      await tester.enterText(find.byKey(const Key('booking-note')), 'Première fois');
      await tester.tap(find.byKey(const Key('booking-send')));
      await settle(tester);
      expect(find.text('Connectez-vous pour réserver'), findsOneWidget);
      expect(find.text('Votre réservation est gardée : vous revenez ici juste après.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-sign-in-google')));
      await settle(tester);
      expect(window.booked, isEmpty, reason: 'nothing sent signed out');
      final raw = await tester.runAsync<String?>(() => db.readPref(pendingBookingKey(_slug)));
      final kept = BookingChoice.fromJson(jsonDecode(raw!));
      expect(kept!.at, _tomorrow(11));
      // The note says what asked for the sign-in: this booking.
      expect(await tester.runAsync(() => db.readPref(streetResumeKey)), allOf(startsWith('$_slug|'), endsWith('|booking')));

      // Back signed in (Google's reload): the sheet opens by itself, chosen.
      await tester.pumpWidget(const SizedBox());
      final inSession = await shopper(tester);
      inSession.stashReturnTo(Routes.storefront(_slug));
      await open(tester, inSession, window);
      expect(find.byKey(const Key('booking-send')), findsOneWidget);
      expect(find.text('Réserver · ${bookingWhen(_tomorrow(11), 'fr', short: true)}'), findsOneWidget);
      expect(find.text('Première fois'), findsOneWidget);
      await tester.tap(find.byKey(const Key('booking-send')));
      await settle(tester);
      expect(window.booked, [
        {'product': 's1', 'at': _tomorrow(11), 'quantity': 1, 'note': 'Première fois'},
      ]);
      expect(find.text('Demande de rendez-vous envoyée'), findsOneWidget);
      expect(await tester.runAsync(() => db.readPref(streetResumeKey)), isNull);
      expect(await tester.runAsync(() => db.readPref(pendingBookingKey(_slug))), isNull);
    });

    testWidgets('a booking left on the device never takes an order\'s place after a sign-in',
        (tester) async {
      // A sign-in abandoned for a booking: the booking still on the device,
      // and a basket of goods besides.
      await tester.runAsync(() async {
        await db.writePref(pendingBookingKey(_slug),
            jsonEncode(BookingChoice(productId: 's1', at: _tomorrow(10)).toJson()));
        await db.writePref('street_basket_$_slug', jsonEncode({'g1': 2}));
      });
      final window = _Window();
      await open(tester, await stranger(tester), window);
      // « Commander » the basket, signed out: the order's sign-in.
      final bar = find.byKey(const Key('basket-inline'));
      await tester.ensureVisible(bar);
      await tester.tap(find.descendant(of: bar, matching: find.text('Commander')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('order-sign-in-google')));
      await settle(tester);
      expect(await tester.runAsync(() => db.readPref(streetResumeKey)), endsWith('|order'));
      expect(await tester.runAsync(() => db.readPref(pendingBookingKey(_slug))), isNull,
          reason: '« Commander » lets the forgotten booking go');

      // Back signed in: the order's sheet, not the booking's.
      await tester.pumpWidget(const SizedBox());
      final inSession = await shopper(tester);
      inSession.stashReturnTo(Routes.storefront(_slug));
      await open(tester, inSession, window);
      expect(find.text('Votre commande'), findsOneWidget);
      expect(find.text('2 × Savon'), findsOneWidget);
      expect(find.byKey(const Key('booking-send')), findsNothing);
    });

    testWidgets('a booking still on the device, an order\'s note: only the order opens again', (tester) async {
      // The booking kept from earlier; the sign-in was the basket's.
      await tester.runAsync(() async {
        await db.writePref(pendingBookingKey(_slug),
            jsonEncode(BookingChoice(productId: 's1', at: _tomorrow(10)).toJson()));
        await db.writePref('street_basket_$_slug', jsonEncode({'g1': 1}));
        await db.writePref(streetResumeKey, streetResumeNote(_slug, booking: false));
      });
      final inSession = await shopper(tester);
      inSession.stashReturnTo(Routes.storefront(_slug));
      await open(tester, inSession, _Window());
      expect(find.text('Votre commande'), findsOneWidget);
      expect(find.byKey(const Key('booking-send')), findsNothing);
      expect(await tester.runAsync(() => db.readPref(pendingBookingKey(_slug))), isNull);
    });

    testWidgets('a refusal from the server: the sheet again, its words, the choice kept', (tester) async {
      final window = _Window()
        ..refuse = const PostgrestException(
            message: 'Fermé à cette heure : choisissez une heure d\'ouverture', code: 'P0001');
      await open(tester, await shopper(tester), window);
      await tapBook(tester, 'Coupe');
      await chooseTomorrow(tester, '12:00');
      await tester.tap(find.byKey(const Key('booking-send')));
      await settle(tester);
      expect(find.byKey(const Key('booking-error')), findsOneWidget);
      expect(find.text('Fermé à cette heure : choisissez une heure d\'ouverture'), findsOneWidget);
      await tester.tap(find.byKey(const Key('booking-send')));
      await settle(tester);
      expect(window.booked.single['at'], _tomorrow(12));
    });

    testWidgets('without 125: « Réservation indisponible pour le moment », and the goods ordered as ever',
        (tester) async {
      final window = _Window(phone: '+226 70 12 34 56')..before125 = true;
      await open(tester, await shopper(tester), window);
      await tapBook(tester, 'Coupe');
      await chooseTomorrow(tester, '10:00');
      await tester.tap(find.byKey(const Key('booking-send')));
      await settle(tester);
      expect(find.byKey(const Key('booking-unavailable')), findsOneWidget);
      expect(find.text('Réservation indisponible pour le moment'), findsOneWidget);
      // The shop's own doors, in the dialog.
      final dialog = find.byKey(const Key('booking-unavailable'));
      expect(find.descendant(of: dialog, matching: find.byKey(const Key('booking-unavailable-call'))), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.byKey(const Key('booking-unavailable-whatsapp'))), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Appeler')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Écrire sur WhatsApp')), findsOneWidget);
      await tester.tap(find.descendant(of: dialog, matching: find.text('Compris')));
      await settle(tester);
      expect(await tester.runAsync(() => db.readPref(pendingBookingKey(_slug))), isNull);
      // The goods: « + », « Commander », sent.
      final add = find.byTooltip('Ajouter un Savon au panier');
      final plus = add.evaluate().isEmpty ? find.bySemanticsLabel('Ajouter un Savon au panier') : add;
      await tester.ensureVisible(plus.first);
      await tester.tap(plus.first);
      await settle(tester);
      final bar = find.byKey(const Key('basket-inline'));
      await tester.ensureVisible(bar);
      await tester.tap(find.descendant(of: bar, matching: find.text('Commander')));
      await settle(tester);
      await tester.tap(find.text('Envoyer la commande'));
      await settle(tester);
      expect(window.orders, 1);
    });

    testWidgets('the vitrine\'s own hours: its closed days are not offered; in English', (tester) async {
      final window = _Window(style: {
        'schedule': {'days': [1, 2, 3, 4, 5, 6], 'open': '08:00', 'close': '18:00'},
      });
      await open(tester, await shopper(tester), window, lang: 'en');
      await tapBook(tester, 'Coupe');
      expect(tester.widget<Text>(find.byKey(const Key('booking-hours'))).data, 'Mon–Sat 8:00–18:00');
      expect(find.text('Which day?'), findsOneWidget);
      final now = DateTime.now().toUtc();
      for (var d = 0; d < 14; d++) {
        final date = DateTime.utc(now.year, now.month, now.day + d);
        if (date.weekday == DateTime.sunday) {
          expect(find.byKey(Key(_dayKey(date))), findsNothing, reason: 'Sunday ${date.toIso8601String()}');
        }
      }
      final monday = [
        for (var d = 1; d < 9; d++) DateTime.utc(now.year, now.month, now.day + d),
      ].firstWhere((x) => x.weekday == DateTime.monday);
      final chip = find.byKey(Key(_dayKey(monday)));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('booking-time-17:30')), findsOneWidget);
      expect(find.byKey(const Key('booking-time-18:00')), findsNothing);
    });

    testWidgets('the article sheet\'s « Réserver » opens the booking sheet in its place', (tester) async {
      final window = _Window();
      await open(tester, await shopper(tester), window);
      final name = find.text('Coupe').first;
      await tester.ensureVisible(name);
      await tester.pumpAndSettle();
      await tester.tap(name);
      await settle(tester);
      expect(find.byType(ArticleSheet), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(ArticleSheet), matching: find.text('Réserver')));
      await settle(tester);
      expect(find.byType(ArticleSheet), findsNothing);
      expect(find.byKey(const Key('booking-send')), findsOneWidget);
    });

    testWidgets('a showcase: « Pas à proximité », nothing sent', (tester) async {
      final window = _ShowcaseWindow();
      await open(tester, await shopper(tester), window);
      await tapBook(tester, 'Coupe');
      expect(find.byKey(const Key('showcase-far')), findsOneWidget);
      expect(find.byKey(const Key('booking-send')), findsNothing);
      expect(window.booked, isEmpty);
    });
  });

  group('Commandes: the business answers', () {
    const shop = OrgSummary(
        id: 'o1', name: 'Salon Awa', profile: 'retail', roles: ['owner'], currency: 'XOF', slug: _slug);
    const farm = OrgSummary(
        id: 'o2', name: 'Ferme Ignace', profile: 'farm', roles: ['owner'], currency: 'XOF', slug: 'ferme');

    Future<void> big(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
    }

    testWidgets('« Rendez-vous demandé — mardi 13 oct., 10:00 », the note, then « Confirmer »', (tester) async {
      await big(tester);
      final retail = _Retail(orders: [_booking('pending')]);
      await tester.pumpWidget(_app(ShopOrdersScreen(org: shop, retail: retail)));
      await tester.pumpAndSettle();
      expect(find.text('Rendez-vous demandé — mardi 13 oct., 10:00'), findsOneWidget);
      expect(find.text('Note : Pour ma fille'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-walk-b1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('walk-slot')), findsOneWidget);
      expect(find.byKey(const Key('flow-option-accepted')), findsOneWidget);
      expect(find.byKey(const Key('flow-option-propose')), findsOneWidget);
      expect(find.byKey(const Key('flow-option-refused')), findsOneWidget);
      expect(find.text('Confirmer'), findsOneWidget);
      expect(find.text('Proposer une autre heure'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-option-accepted')));
      await tester.pump();
      await next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(retail.moves, ['b1:accepted']);
      expect(find.text('Réservation confirmée. Fati est prévenu.'), findsOneWidget);
    });

    testWidgets('« Proposer une autre heure »: the same picker, the time sent, the customer told', (tester) async {
      await big(tester);
      // The business's own booking hours (booking_hours): every day to 15:00.
      final retail = _Retail()
        ..hours = const VitrineSchedule(days: [1, 2, 3, 4, 5, 6, 7], open: '08:00', close: '15:00');
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () => OrderWalkthrough.open(context,
              org: farm, retail: retail, order: _booking('pending', at: _tomorrow(10), qty: 4)),
          child: const Text('Ouvrir'),
        ),
      )));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('4 × Coupe'), findsOneWidget, reason: 'how many, when it counts');
      await tester.tap(find.byKey(const Key('flow-option-propose')));
      await tester.pump();
      await next(tester);
      expect(find.text('Quelle autre heure ?'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('flow-next'))).onPressed, isNull);
      await tester.tap(find.byKey(Key(_dayKey(_tomorrow(0)))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('booking-time-10:00')), findsNothing, reason: 'the time asked is not another');
      expect(retail.hoursAsked, ['o2'], reason: 'the business\'s own hours, not the street\'s');
      expect(find.byKey(const Key('booking-time-14:30')), findsOneWidget);
      expect(find.byKey(const Key('booking-time-15:00')), findsNothing, reason: 'closed from 15:00');
      await tester.tap(find.byKey(const Key('booking-time-14:30')));
      await tester.pumpAndSettle();
      await next(tester);
      expect(find.text(bookingWhen(_tomorrow(14, 30), 'fr', short: true)), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(retail.moves, ['b1:propose:${_tomorrow(14, 30).toIso8601String()}']);
      expect(find.text('Autre heure proposée. Fati est prévenu.'), findsOneWidget);
      expect(find.byKey(const Key('order-next-stage')), findsNothing, reason: 'the customer\'s turn');
    });

    testWidgets('« Refuser » with a booking\'s reason', (tester) async {
      await big(tester);
      final retail = _Retail();
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () => OrderWalkthrough.open(context, org: shop, retail: retail, order: _booking('pending')),
          child: const Text('Ouvrir'),
        ),
      )));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-option-refused')));
      await tester.pump();
      await next(tester);
      await tester.tap(find.byKey(const Key('flow-option-Pas de place à cette heure')));
      await tester.pump();
      await next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(retail.moves, ['b1:refused:Pas de place à cette heure']);
      expect(find.text('Réservation refusée. Fati est prévenu.'), findsOneWidget);
    });

    testWidgets('another time proposed: « en attente du client », off the red banner, not to confirm',
        (tester) async {
      await big(tester);
      final waiting = _booking('pending', proposed: DateTime.utc(2026, 10, 14, 11), id: 'b2');
      final retail = _Retail(orders: [waiting, _booking('accepted', id: 'b3')]);
      await tester.pumpWidget(_app(ShopOrdersScreen(org: shop, retail: retail)));
      await tester.pumpAndSettle();
      // The headline says the time; the chip says whose turn it is.
      expect(find.text('Autre heure proposée — mercredi 14 oct., 11:00'), findsOneWidget);
      expect(find.textContaining('(en attente du client)'), findsNothing);
      expect(find.byKey(const Key('order-awaits-b2')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('order-awaits-b2')), matching: find.text('En attente du client')),
          findsOneWidget);
      // A confirmed booking's chip: « Confirmé », not the goods' « Acceptée ».
      expect(find.descendant(of: find.byKey(const Key('order-status-b3')), matching: find.text('Confirmé')),
          findsOneWidget);
      expect(find.byKey(const Key('order-waiting-b2')), findsNothing);
      expect(find.byKey(const Key('orders-attention')), findsNothing);
      expect(find.text('Rendez-vous confirmé — mardi 13 oct., 10:00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-walk-b2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('flow-option-accepted')), findsNothing);
      expect(find.byKey(const Key('flow-option-propose')), findsOneWidget);
      expect(find.byKey(const Key('flow-option-refused')), findsOneWidget);
    });

    testWidgets('a notification\'s order opens at its step', (tester) async {
      await big(tester);
      final retail = _Retail(orders: [_booking('pending', id: 'b9')]);
      await tester.pumpWidget(_app(ShopOrdersScreen(org: shop, retail: retail, focusId: 'b9')));
      await tester.pumpAndSettle();
      expect(find.text('Fati demande un rendez-vous'), findsOneWidget);
    });

    testWidgets('another notification while Commandes is open: its order opens too (read again when new)',
        (tester) async {
      await big(tester);
      final retail = _Retail(orders: [_booking('pending', id: 'b9')]);
      await tester.pumpWidget(_app(ShopOrdersScreen(org: shop, retail: retail)));
      await tester.pumpAndSettle();
      expect(find.text('Fati demande un rendez-vous'), findsNothing);
      // The router hands the same page a new `?commande=`: an order the list
      // does not have yet — read again, then opened.
      retail.orders = [_booking('pending', id: 'b7'), _booking('pending', id: 'b9')];
      await tester.pumpWidget(_app(ShopOrdersScreen(org: shop, retail: retail, focusId: 'b7')));
      await tester.pumpAndSettle();
      expect(find.text('Fati demande un rendez-vous'), findsOneWidget);
    });

    testWidgets('a booking an older app made (no slot, its day in the note): Commandes as before 125',
        (tester) async {
      await big(tester);
      ShopOrder old(String status, String id) => ShopOrder.fromRow({
            'id': id,
            'customer_name': 'Moussa',
            'status': status,
            'fulfilment': 'pickup',
            'note': 'Samedi 10 h',
            'total': 3000,
            'currency': 'XOF',
            'created_at': '2026-10-10T09:00:00Z',
            'payment_method': 'cash',
            'lines': [
              {'name': 'Coupe', 'unit_price': 3000, 'quantity': 1, 'is_service': true},
            ],
          });
      final retail = _Retail(orders: [old('pending', 'L1'), old('accepted', 'L2')]);
      await tester.pumpWidget(_app(ShopOrdersScreen(org: shop, retail: retail)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-slot-L1')), findsNothing, reason: 'no booking headline');
      expect(find.text('Note : Samedi 10 h'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('order-status-L2')), matching: find.text('Acceptée')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('order-walk-L1')));
      await tester.pumpAndSettle();
      expect(find.text('Accepter le rendez-vous'), findsOneWidget);
      expect(find.byKey(const Key('flow-option-propose')), findsNothing, reason: 'no other time to propose');
      expect(retail.hoursAsked, isEmpty);
    });
  });

  group('« Mes commandes »: the customer', () {
    Future<void> big(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    CustomerOrder mine(String status, {DateTime? proposed}) => CustomerOrder.fromRow({
          'id': 'b1',
          'shop_name': 'Salon Awa',
          'shop_slug': _slug,
          'status': status,
          'fulfilment': 'pickup',
          'total': 3000,
          'currency': 'XOF',
          'created_at': '2026-10-10T09:00:00Z',
          'lines': [
            {
              'name': 'Coupe',
              'unit_price': 3000,
              'quantity': 1,
              'is_service': true,
              'booked_for': '2026-10-13T10:00:00+00:00',
              'proposed_for': proposed?.toIso8601String(),
            },
          ],
        });

    testWidgets('« Rendez-vous », the day and time, the new time: « Accepter 11:00 »', (tester) async {
      await big(tester);
      final window = _Window()..mine = [mine('pending', proposed: DateTime.utc(2026, 10, 14, 11))];
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: window)));
      await tester.pumpAndSettle();
      expect(find.text('Rendez-vous'), findsOneWidget);
      expect(find.text('mardi 13 octobre, 10:00'), findsOneWidget);
      expect(find.text('Salon Awa propose une autre heure :'), findsOneWidget);
      expect(find.text('mercredi 14 octobre, 11:00'), findsOneWidget);
      expect(find.text('Autre heure proposée'), findsOneWidget, reason: 'the state');
      expect(find.byKey(const Key('order-cancel-b1')), findsNothing, reason: 'answered in its box');
      await tester.tap(find.byKey(const Key('accept-time-b1')));
      await tester.pumpAndSettle();
      expect(window.accepted, ['b1']);
      expect(find.text('Rendez-vous confirmé : mercredi 14 octobre, 11:00'), findsOneWidget);
    });

    testWidgets('« Annuler » a proposal: asked first, then cancelled', (tester) async {
      await big(tester);
      final window = _Window()..mine = [mine('pending', proposed: DateTime.utc(2026, 10, 14, 11))];
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: window)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('refuse-time-b1')));
      await tester.pumpAndSettle();
      expect(find.text('Annuler ce rendez-vous ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-cancel-yes')));
      await tester.pumpAndSettle();
      expect(window.cancelled, ['b1']);
    });

    testWidgets('a booking an older app made (no slot): shown as before 125 — no day line, nothing to accept',
        (tester) async {
      await big(tester);
      final window = _Window()
        ..mine = [
          CustomerOrder.fromRow({
            'id': 'L1',
            'shop_name': 'Salon Awa',
            'shop_slug': _slug,
            'status': 'pending',
            'fulfilment': 'pickup',
            'note': 'Samedi 10 h',
            'total': 3000,
            'currency': 'XOF',
            'created_at': '2026-10-10T09:00:00Z',
            'lines': [
              {'name': 'Coupe', 'unit_price': 3000, 'quantity': 1, 'is_service': true},
            ],
          }),
        ];
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: window)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('accept-time-L1')), findsNothing);
      expect(find.text('Annuler le rendez-vous'), findsNothing);
      expect(find.text('Annuler la commande'), findsOneWidget);
      expect(find.textContaining('octobre, '), findsNothing, reason: 'no slot to say');
    });

    testWidgets('requested and confirmed, in English', (tester) async {
      await big(tester);
      final window = _Window()..mine = [mine('accepted')];
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: window), lang: 'en'));
      await tester.pumpAndSettle();
      expect(find.text('Appointment'), findsOneWidget);
      expect(find.text('Tuesday 13 October, 10:00'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      window.mine = [mine('pending')];
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: window), lang: 'en'));
      await tester.pumpAndSettle();
      expect(find.text('Requested'), findsOneWidget);
      expect(find.text('Waiting for Salon Awa\'s answer'), findsOneWidget);
      expect(find.text('Cancel the appointment'), findsOneWidget);
    });
  });

  group('the bell', () {
    NotificationRow row(String kind, Map<String, dynamic> params, {String message = 'm'}) =>
        NotificationRow.fromRow({
          'id': 'n1',
          'kind': kind,
          'message': message,
          'org_id': 'o1',
          'created_at': '2026-10-10T09:00:00Z',
          'params': params,
        });

    testWidgets('each answer said in English with its day and time; French as the server wrote it',
        (tester) async {
      final lines = <String>[];
      final fr = <String>[];
      final rows = [
        row('booking_confirmed', {'to': 'customer', 'order_id': 'b1', 'shop': 'Salon Awa', 'at': '2026-10-13T10:00:00+00:00'}),
        row('booking_proposed', {'to': 'customer', 'order_id': 'b1', 'shop': 'Salon Awa', 'at': '2026-10-14T11:00:00+00:00'}),
        row('booking_declined', {'to': 'customer', 'order_id': 'b1', 'shop': 'Salon Awa', 'reason': 'Complet'}),
        row('booking_accepted', {'to': 'shop', 'order_id': 'b1', 'name': 'Fati', 'at': '2026-10-14T11:00:00+00:00'}),
        row('new_order', {'to': 'shop', 'order_id': 'b1', 'booking': true, 'name': 'Fati', 'total': 3000,
          'currency': 'XOF', 'at': '2026-10-13T10:00:00+00:00'}),
      ];
      await tester.pumpWidget(_app(Builder(builder: (context) {
        lines.addAll([for (final r in rows) notificationLine(context, r)]);
        return const SizedBox();
      }), lang: 'en'));
      await tester.pumpWidget(_app(Builder(builder: (context) {
        fr.addAll([for (final r in rows) notificationLine(context, r)]);
        return const SizedBox();
      })));
      expect(lines, [
        'Your appointment at Salon Awa is confirmed: Tuesday 13 Oct, 10:00',
        'Salon Awa offers another time for your appointment: Wednesday 14 Oct, 11:00. Accept it in My orders.',
        'Your appointment request at Salon Awa was declined — Complet',
        'Fati accepts the appointment: Wednesday 14 Oct, 11:00',
        'Appointment requested by Fati — Tuesday 13 Oct, 10:00: ${lines.last.split(': ').last}',
      ]);
      expect(lines.last, contains('3'));
      expect(fr, everyElement('m'));
    });

    test('a tap opens that booking: the customer\'s card, the business\'s step', () {
      final id = '12500000-aaaa-0000-0000-000000000001';
      expect(notificationTarget(row('booking_confirmed', {'to': 'customer', 'order_id': id})),
          '${Routes.myOrders}?commande=$id');
      expect(notificationTarget(row('booking_proposed', {'to': 'customer', 'order_id': id})),
          '${Routes.myOrders}?commande=$id');
      expect(notificationTarget(row('booking_accepted', {'to': 'shop', 'order_id': id})),
          '${Routes.inside('o1', 'commandes')}?commande=$id');
      expect(notificationTarget(row('new_order', {'to': 'shop', 'order_id': id, 'booking': true, 'at': 'x'})),
          '${Routes.inside('o1', 'commandes')}?commande=$id');
      // An order of goods: as before.
      expect(notificationTarget(row('new_order', {'to': 'shop', 'order_id': id, 'booking': false})),
          Routes.inside('o1', 'commandes'));
    });
  });
}

class _ShowcaseWindow extends _Window {
  @override
  Future<Set<String>> showcaseSlugs() async => {_slug};
}
