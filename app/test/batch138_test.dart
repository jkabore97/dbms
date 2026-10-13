import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/association/books_start.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/invoicing/models.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/orders/booking.dart';
import 'package:kaj_app/core/orders/orders.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/church/books_start_card.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/money/income_flow.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/features/orders/my_orders_screen.dart';
import 'package:kaj_app/features/setup/association_setup_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Batch 138 (134): « La caisse et la cotisation » in an association's
/// first setup and on its home, the usual cotisation pre-filled, and a
/// booking its customer cancels until 2 hours before.

class _Actions implements AssociationSetupActions {
  final log = <String>[];

  @override
  Future<void> identify(String orgId,
          {required String name, required String currency, required String kind, required String about}) async =>
      log.add('identify $name');

  @override
  Future<void> addMember(String orgId, {required String name, required String phone}) async =>
      log.add('member $name');

  @override
  Future<void> addService(String orgId, {required String name, required double price}) async =>
      log.add('service $name');

  @override
  Future<void> saveVitrine(String orgId,
          {required bool open, required String about, required String phone, required String address}) async =>
      log.add('vitrine');

  @override
  Future<void> finish(String orgId) async => log.add('finish');
}

class _Books implements BooksStartApi {
  _Books(this.start);

  /// What books_start answers; null: a server without 134.
  BooksStart? start;
  final log = <String>[];
  Object? refuse;

  @override
  Future<BooksStart?> booksStart(String orgId) async => start;

  @override
  Future<void> setOpeningBalance(String orgId, double amount, {String? clientUuid}) async {
    final r = refuse;
    if (r != null) throw r;
    log.add('opening $amount ${clientUuid == null ? 'no-uuid' : 'uuid'}');
  }

  @override
  Future<void> setContributionDefault(String orgId, double? amount, ContributionPeriod period) async =>
      log.add('cotisation $amount ${period.name}');

  @override
  Future<void> dismissBooksStart(String orgId) async => log.add('dismiss');
}

const _fresh = BooksStart(
    association: true, openingSet: false, movements: false, canSet: true, dismissed: false);

const _org = OrgSummary(
    id: 'a1', name: 'Entraide', profile: 'association', roles: ['owner'], slug: 'entraide');

class _Window extends StorefrontRepository {
  _Window(this.mine, this.terms) : super(null);

  List<CustomerOrder> mine;
  BookingCancelTerms? terms;
  final cancelled = <String>[];

  @override
  bool get isConfigured => true;
  @override
  Future<List<CustomerOrder>> myOrders() async => mine;
  @override
  Future<BookingCancelTerms?> bookingCancelTerms(String orderId) async => terms;
  @override
  Future<void> cancelOrder(String orderId) async => cancelled.add(orderId);
}

/// The home's servers (review): books_start offers the card.
class _Reports extends ReportsRepository {
  _Reports() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<BooksStart?> booksStart(String orgId) async => _fresh;
}

class _Shelf extends RetailRepository {
  _Shelf() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();
  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [];
}

class _Bills extends InvoicingRepository {
  _Bills() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<List<InvoiceSummary>> list(String orgId, {bool includePaid = true, int limit = 200}) async => const [];
}

/// The server refusing a cancel with its French words.
class _Refusing extends _Window {
  _Refusing(List<CustomerOrder> mine, this.words) : super(mine, null);

  final String words;

  @override
  Future<void> cancelOrder(String orderId) async =>
      throw Exception(words);
}

CustomerOrder _booking(String status, {String id = 'b1'}) => CustomerOrder.fromRow({
      'id': id,
      'shop_name': 'Salon Awa',
      'shop_slug': 'salon-awa',
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
          'booked_for': '2026-10-14T10:00:00+00:00',
        },
      ],
    });

Widget _app(Widget home, {String lang = 'fr'}) => MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
  });

  Future<void> size(WidgetTester tester, {double h = 1800}) async {
    tester.view.physicalSize = Size(390, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  group('« La caisse et la cotisation » in the first setup', () {
    Future<void> toCaisse(WidgetTester tester, _Actions a, _Books? books) async {
      await tester.pumpWidget(_app(AssociationSetupScreen(
          org: _org, actions: a, onDone: () {}, books: books)));
      await settle(tester);
      await tester.tap(find.byKey(const Key('asetup-kind-tontine')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('asetup-next-0')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('asetup-skip-1')));
      await settle(tester);
    }

    testWidgets('step 3 of 4: the box and the usual cotisation, then the vitrine', (tester) async {
      await size(tester);
      final a = _Actions();
      final books = _Books(_fresh);
      await toCaisse(tester, a, books);
      expect(find.text('La caisse et la cotisation'), findsOneWidget);
      expect(find.text('3 / 4'), findsOneWidget);
      expect(find.text('Combien y a-t-il dans la caisse aujourd\'hui ?'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('asetup-caisse')), '25 000');
      await tester.enterText(find.byKey(const Key('asetup-cotisation')), '1000');
      await tester.tap(find.byKey(const Key('asetup-period-week')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('asetup-next-caisse')));
      await settle(tester);
      expect(books.log, ['opening 25000.0 uuid', 'cotisation 1000.0 week']);
      expect(find.text('Votre vitrine'), findsOneWidget);
      expect(find.text('4 / 4'), findsOneWidget);
    });

    testWidgets('0 is an answer; both questions may be skipped; a refusal is said', (tester) async {
      await size(tester);
      final books = _Books(_fresh)..refuse = Exception('Le solde de départ est déjà enregistré.');
      await toCaisse(tester, _Actions(), books);
      await tester.enterText(find.byKey(const Key('asetup-caisse')), '0');
      await tester.tap(find.byKey(const Key('asetup-next-caisse')));
      await settle(tester);
      expect(find.byKey(const Key('asetup-error')), findsOneWidget);
      expect(find.text('La caisse et la cotisation'), findsOneWidget, reason: 'stays on the step');
      books.refuse = null;
      await tester.tap(find.byKey(const Key('asetup-next-caisse')));
      await settle(tester);
      expect(books.log, ['opening 0.0 uuid']);
      expect(find.text('Votre vitrine'), findsOneWidget);
    });

    testWidgets('a negative box is refused before the server', (tester) async {
      await size(tester);
      final books = _Books(_fresh);
      await toCaisse(tester, _Actions(), books);
      await tester.enterText(find.byKey(const Key('asetup-caisse')), '-5');
      await tester.tap(find.byKey(const Key('asetup-next-caisse')));
      await settle(tester);
      expect(find.text('Un montant de 0 ou plus, s\'il vous plaît.'), findsOneWidget);
      expect(books.log, isEmpty);
      await tester.tap(find.byKey(const Key('asetup-skip-caisse')));
      await settle(tester);
      expect(find.text('Votre vitrine'), findsOneWidget);
      expect(books.log, isEmpty, reason: '« Passer » writes nothing');
    });

    testWidgets('no 134 on the server, or no books: three steps as before', (tester) async {
      await size(tester);
      await toCaisse(tester, _Actions(), _Books(null));
      expect(find.text('Votre vitrine'), findsOneWidget);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('La caisse et la cotisation'), findsNothing);
    });

    testWidgets('Mara turned the step off (setup_off): not drawn', (tester) async {
      await size(tester);
      await tester.pumpWidget(_app(AssociationSetupScreen(
          org: _org,
          actions: _Actions(),
          onDone: () {},
          books: _Books(_fresh),
          stepsOff: () async => {'caisse'})));
      await settle(tester);
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('in English', (tester) async {
      await size(tester);
      await tester.pumpWidget(_app(
          AssociationSetupScreen(org: _org, actions: _Actions(), onDone: () {}, books: _Books(_fresh)),
          lang: 'en'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('asetup-kind-tontine')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('asetup-next-0')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('asetup-skip-1')));
      await settle(tester);
      expect(find.text('The cash box and the dues'), findsOneWidget);
      expect(find.text('How much is in the cash box today?'), findsOneWidget);
      expect(find.text('per month'), findsOneWidget);
    });
  });

  group('« Indiquez votre caisse de départ » on the home', () {
    Widget home(_Books books, {bool moves = false, String lang = 'fr'}) => _app(
        Scaffold(body: ListView(children: [
          BooksStartCard(orgId: 'a1', books: books, hasLocalMoves: moves),
        ])),
        lang: lang);

    testWidgets('offered once: answered in its sheet, then gone', (tester) async {
      await size(tester, h: 900);
      final books = _Books(_fresh);
      await tester.pumpWidget(home(books));
      await tester.pumpAndSettle();
      expect(find.text('Indiquez votre caisse de départ'), findsOneWidget);
      await tester.tap(find.byKey(const Key('books-start-answer')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('books-start-caisse')), '12500');
      await tester.enterText(find.byKey(const Key('books-start-cotisation')), '500');
      await tester.tap(find.byKey(const Key('books-start-period-year')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('books-start-save')));
      await tester.pumpAndSettle();
      expect(books.log, ['opening 12500.0 uuid', 'cotisation 500.0 year']);
      expect(find.byKey(const Key('books-start-card')), findsNothing);
    });

    testWidgets('« Plus tard » puts it away for the business', (tester) async {
      await size(tester, h: 900);
      final books = _Books(_fresh);
      await tester.pumpWidget(home(books));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('books-start-later')));
      await tester.pumpAndSettle();
      expect(books.log, ['dismiss']);
      expect(find.byKey(const Key('books-start-card')), findsNothing);
    });

    testWidgets('never over movements, an opening, a dismissal, a non-admin or no 134', (tester) async {
      await size(tester, h: 900);
      for (final start in <BooksStart?>[
        null,
        const BooksStart(association: true, openingSet: false, movements: true, canSet: false, dismissed: false),
        const BooksStart(association: true, openingSet: true, movements: false, canSet: false, dismissed: false),
        const BooksStart(association: true, openingSet: false, movements: false, canSet: true, dismissed: true),
        const BooksStart(association: false, openingSet: false, movements: false, canSet: false, dismissed: false),
      ]) {
        await tester.pumpWidget(home(_Books(start)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('books-start-card')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
      // Entries on this phone the server has not heard of yet.
      await tester.pumpWidget(home(_Books(_fresh), moves: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('books-start-card')), findsNothing);
    });

    testWidgets('in English', (tester) async {
      await size(tester, h: 900);
      await tester.pumpWidget(home(_Books(_fresh), lang: 'en'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your opening cash'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });
  });

  group('review: the home with the card, at the foot of its list', () {
    for (final (w, scale) in [(390.0, 1.0), (320.0, 1.3), (320.0, 2.0)]) {
      testWidgets('$w px × $scale: « Clôturer la journée » clears the floating buttons, and grows with its text',
          (tester) async {
        tester.view.physicalSize = Size(w, 844);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
        await tester.pumpWidget(_app(ChurchHomeScreen(
          db: db,
          orgId: _org.id,
          orgName: _org.name,
          org: _org,
          reports: _Reports(),
          invoicing: _Bills(),
          retail: _Shelf(),
          onHistory: () {},
        )));
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(find.byKey(const Key('books-start-card')), findsOneWidget);
        final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
        final position = tester.state<ScrollableState>(list).position;
        // A lazy list learns its length as it goes: to the end until it stays.
        for (var i = 0; i < 6; i++) {
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
        }
        final close = tester.getRect(find.byKey(const Key('home-close-day')));
        final label = tester.getRect(find.text('Clôturer la journée'));
        expect(close.height, greaterThanOrEqualTo(52));
        expect(close.top <= label.top && label.bottom <= close.bottom, isTrue,
            reason: 'the words inside their button');
        for (final e in find.byType(FloatingActionButton).evaluate()) {
          final fab = tester.getRect(find.byWidget(e.widget));
          expect(fab.overlaps(close), isFalse, reason: '$fab over $close');
        }
        await tester.runAsync(db.close);
      });
    }
  });

  group('the usual cotisation, pre-filled', () {
    testWidgets('« Cotisation »: its amount there, still editable; another kind takes it back', (tester) async {
      await size(tester, h: 1400);
      final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
      addTearDown(() => tester.runAsync(() async {
            // The flow's own read of the phone's categories finishes first.
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await db!.close();
          }));
      final books = _Books(const BooksStart(
          association: true,
          openingSet: true,
          movements: true,
          canSet: false,
          dismissed: false,
          contribution: ContributionDefault(amount: 2000, period: ContributionPeriod.month)));
      await tester.pumpWidget(_app(IncomeFlow(db: db!, orgId: 'a1', books: books, store: MemoryFlowStore())));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-option-cotisation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      // « De qui ? », optional.
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
          find.descendant(of: find.byKey(const Key('income-amount')), matching: find.byType(TextField)));
      expect(field.controller!.text, '2000');
      expect(find.byKey(const Key('income-usual')), findsOneWidget);
      expect(find.textContaining('Cotisation habituelle'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('income-amount')), '2500');
      await tester.pump();
      expect(field.controller!.text, '2500', reason: 'editable');
    });

    testWidgets('no usual cotisation (or no 134): nothing filled', (tester) async {
      await size(tester, h: 1400);
      final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
      addTearDown(() => tester.runAsync(() async {
            // The flow's own read of the phone's categories finishes first.
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await db!.close();
          }));
      BooksStart.lastKnown.clear();
      await tester.pumpWidget(
          _app(IncomeFlow(db: db!, orgId: 'a2', books: _Books(null), store: MemoryFlowStore())));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-option-cotisation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
          find.descendant(of: find.byKey(const Key('income-amount')), matching: find.byType(TextField)));
      expect(field.controller!.text, '');
      expect(find.byKey(const Key('income-usual')), findsNothing);
    });
  });

  group('« Annuler le rendez-vous » until 2 hours before', () {
    final soon = DateTime.now().toUtc().add(const Duration(days: 1));

    testWidgets('confirmed, before the cutoff: the button, until when, asked first, cancelled', (tester) async {
      await size(tester, h: 1600);
      final w = _Window([_booking('accepted')],
          BookingCancelTerms(hours: 2, until: soon, canCancel: true, phone: '+22670000001'));
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: w)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-cancel-b1')), findsOneWidget);
      expect(find.byKey(const Key('order-cancel-until-b1')), findsOneWidget);
      expect(find.textContaining('Annulable jusqu\'à'), findsOneWidget);
      expect(find.byKey(const Key('order-too-late-b1')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('order-cancel-b1')));
      await tester.tap(find.byKey(const Key('order-cancel-b1')));
      await tester.pumpAndSettle();
      expect(find.text('Annuler ce rendez-vous ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-cancel-yes')));
      await tester.pumpAndSettle();
      expect(w.cancelled, ['b1']);
    });

    testWidgets('after the cutoff: « Trop tard pour annuler — appelez la boutique », call and WhatsApp',
        (tester) async {
      await size(tester, h: 1600);
      final w = _Window([_booking('accepted')],
          BookingCancelTerms(
              hours: 2,
              until: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
              canCancel: false,
              phone: '+226 70 00 00 01'));
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: w)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-cancel-b1')), findsNothing);
      expect(find.text('Trop tard pour annuler — appelez la boutique'), findsOneWidget);
      expect(find.byKey(const Key('order-call-b1')), findsOneWidget);
      expect(find.byKey(const Key('order-whatsapp-b1')), findsOneWidget);
      expect(find.text('Un rendez-vous s\'annule jusqu\'à 2 h avant.'), findsOneWidget);
    });

    testWidgets('the call and WhatsApp buttons open the business', (tester) async {
      await size(tester, h: 900);
      final urls = <String>[];
      await tester.pumpWidget(_app(Scaffold(
          body: BookingCancelArea(
              order: _booking('accepted'),
              busy: false,
              terms: () async => const BookingCancelTerms(
                  hours: 2, until: null, canCancel: false, phone: '+226 70 00 00 01'),
              onCancel: () {},
              onCall: (u) async => urls.add(u)))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-call-b1')));
      await tester.tap(find.byKey(const Key('order-whatsapp-b1')));
      expect(urls, ['tel:+226 70 00 00 01', 'https://wa.me/22670000001']);
    });

    testWidgets('the clock passes the cutoff while the page is open: too late, without asking again',
        (tester) async {
      await size(tester, h: 900);
      final until = DateTime.utc(2026, 10, 14, 8);
      await tester.pumpWidget(_app(Scaffold(
          body: BookingCancelArea(
              order: _booking('accepted'),
              busy: false,
              now: () => until.add(const Duration(minutes: 1)),
              terms: () async =>
                  BookingCancelTerms(hours: 2, until: until, canCancel: true, phone: '+22670000001'),
              onCancel: () {}))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-cancel-b1')), findsNothing);
      expect(find.byKey(const Key('order-too-late-b1')), findsOneWidget);
    });

    testWidgets('paid online: call the business', (tester) async {
      await size(tester, h: 1600);
      final w = _Window([_booking('accepted')],
          BookingCancelTerms(hours: 2, until: soon, canCancel: false, paidOnline: true, phone: '+22670000001'));
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: w)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-cancel-b1')), findsNothing);
      expect(find.text('Ce rendez-vous est déjà payé : appelez la boutique pour l\'annuler.'), findsOneWidget);
    });

    testWidgets('a server without 134: a request keeps its cancel, a confirmed booking none', (tester) async {
      await size(tester, h: 1600);
      final w = _Window([_booking('accepted')], null);
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: w)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-cancel-b1')), findsNothing);
      expect(find.byKey(const Key('order-too-late-b1')), findsNothing);
      w.mine = [_booking('pending')];
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: w)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-cancel-b1')), findsOneWidget);
    });

    testWidgets('review: a request nobody answered whose hour has gone is still withdrawn', (tester) async {
      await size(tester, h: 900);
      final slot = DateTime.utc(2026, 10, 14, 10);
      await tester.pumpWidget(_app(Scaffold(
          body: BookingCancelArea(
              order: _booking('pending'),
              busy: false,
              now: () => slot.add(const Duration(hours: 3)),
              terms: () async => BookingCancelTerms(
                  hours: 2, until: slot.subtract(const Duration(hours: 2)), canCancel: true),
              onCancel: () {}))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-cancel-b1')), findsOneWidget);
      expect(find.byKey(const Key('order-cancel-until-b1')), findsNothing, reason: 'no « until » in the past');
      expect(find.byKey(const Key('order-too-late-b1')), findsNothing);
    });

    testWidgets('review: a confirmed booking whose hour has gone is not', (tester) async {
      await size(tester, h: 900);
      final slot = DateTime.utc(2026, 10, 14, 10);
      await tester.pumpWidget(_app(Scaffold(
          body: BookingCancelArea(
              order: _booking('accepted'),
              busy: false,
              now: () => slot.add(const Duration(hours: 3)),
              terms: () async => BookingCancelTerms(
                  hours: 2, until: slot.subtract(const Duration(hours: 2)), canCancel: false),
              onCancel: () {}))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-cancel-b1')), findsNothing);
      expect(find.byKey(const Key('order-too-late-b1')), findsOneWidget);
    });

    CustomerOrder goods({required bool paid}) => CustomerOrder.fromRow({
          'id': 'g1',
          'shop_name': 'Boutique Awa',
          'shop_slug': 'boutique-awa',
          'status': 'pending',
          'fulfilment': 'pickup',
          'total': 500,
          'currency': 'XOF',
          'created_at': '2026-10-10T09:00:00Z',
          'payment_method': 'wave',
          'paid_at': paid ? '2026-10-10T09:05:00Z' : null,
          'lines': [
            {'name': 'Savon', 'unit_price': 500, 'quantity': 1, 'is_service': false},
          ],
        });

    testWidgets('review: an order of goods already paid offers no cancel', (tester) async {
      await size(tester, h: 1600);
      final w = _Window([goods(paid: true)], null);
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: w)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-cancel-g1')), findsNothing);
      w.mine = [goods(paid: false)];
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: w)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-cancel-g1')), findsOneWidget);
    });

    for (final (server, fr, en) in [
      (
        'Un paiement Wave est en cours : attendez quelques minutes ou appelez la boutique.',
        'Un paiement Wave est en cours : attendez quelques minutes ou appelez la boutique.',
        'A Wave payment is under way: wait a few minutes or call the business.'
      ),
      (
        'Cette commande est déjà payée : appelez la boutique pour l\'annuler.',
        'Cette commande est déjà payée : appelez la boutique pour l\'annuler.',
        'This order is already paid: call the business to cancel it.'
      ),
    ]) {
      for (final lang in ['fr', 'en']) {
        testWidgets('review: the refusal « ${server.substring(0, 24)}… » said ($lang)', (tester) async {
          await size(tester, h: 1600);
          final w = _Refusing([goods(paid: false)], server);
          await tester.pumpWidget(_app(MyOrdersScreen(storefront: w), lang: lang));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('order-cancel-g1')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('order-cancel-yes')));
          await tester.pumpAndSettle();
          expect(find.text(lang == 'fr' ? fr : en), findsOneWidget);
        });
      }
    }

    testWidgets('in English', (tester) async {
      await size(tester, h: 1600);
      final w = _Window([_booking('accepted')],
          BookingCancelTerms(hours: 2, until: soon, canCancel: false, phone: '+22670000001'));
      await tester.pumpWidget(_app(MyOrdersScreen(storefront: w), lang: 'en'));
      await tester.pumpAndSettle();
      expect(find.text('Too late to cancel — call the business'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
    });
  });

  group('the business hears it', () {
    NotificationRow row(String lang) => NotificationRow.fromRow({
          'id': 'n1',
          'kind': 'booking_cancelled',
          'message': 'Rendez-vous annulé par le client — mercredi 14 oct., 10:00',
          'org_id': 'o1',
          'created_at': '2026-10-13T09:00:00Z',
          'params': {
            'to': 'shop',
            'order_id': 'b1',
            'booking': true,
            'name': 'Fati',
            'at': '2026-10-14T10:00:00+00:00',
          },
        });

    for (final lang in ['fr', 'en']) {
      testWidgets('« Rendez-vous annulé par le client — <jour>, <heure> » ($lang)', (tester) async {
        String? line;
        await tester.pumpWidget(_app(Builder(builder: (context) {
          line = notificationLine(context, row(lang));
          return const SizedBox();
        }), lang: lang));
        expect(
            line,
            lang == 'fr'
                ? 'Rendez-vous annulé par le client — mercredi 14 oct., 10:00'
                : 'Booking cancelled by the customer — Wednesday 14 Oct, 10:00');
      });
    }
  });

  group('Réglages', () {
    test('the two new settings, each on one card', () {
      final defs = {for (final d in platformSettingDefs) d.key: d};
      expect(defs['booking_cancel_hours']?.type, SettingType.count);
      expect(defs['cauris_prize_notify']?.type, SettingType.flag01);
      expect(settingCardOf('booking_cancel_hours')?.key, 'vitrines');
      expect(settingCardOf('cauris_prize_notify')?.key, 'cauris');
      expect(rangedSettings['booking_cancel_hours'], (0, 168));
    });
  });
}
