import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/storefront/visitor_id.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/features/storefront/visitors_badge.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A vitrine's visitors (123), from the app's side: the visit is sent once
/// per opening with the device's random id, never in the page's way; the
/// eye shows the count in the reader's way, from 1, in the vitrine's own
/// colour; nothing at 0, nothing when the server says nothing (a database
/// before 123), nothing broken when the call fails.

/// The street: one vitrine of [profile], storefront() saying [said]
/// visitors, the visit answering [answer] — or throwing.
class _Street extends StorefrontRepository {
  _Street({this.profile = 'retail', this.said, this.answer, this.fails = false})
      : super(null);

  final String profile;
  final int? said;
  final int? answer;
  final bool fails;
  final visits = <(String, String)>[];
  final cauris = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => PublicShop.fromRow({
        'org_id': 'o1',
        'name': 'Vitrine 123',
        'slug': slug,
        'profile': profile,
        'style': {'delivers': false, 'accent': '#1F6FEB', 'visitors': ?said},
      });

  @override
  Future<List<PublicItem>> items(String slug) async => const [
        PublicItem(id: 'p1', name: 'Savon', price: 450, inStock: true),
      ];

  @override
  Future<Set<String>> showcaseSlugs() async => const {};

  @override
  Future<void> recordVisit(String slug, String kind, {String? productId}) async {}

  @override
  Future<void> recordVisitor(String slug, String visitorId) async => cauris.add(visitorId);

  @override
  Future<int?> recordVitrineVisit(String slug, String visitorId) async {
    visits.add((slug, visitorId));
    if (fails) throw Exception('offline');
    return answer;
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LocalDb db;
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() async => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester, _Street street, {String language = 'fr'}) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: Locale(language),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: StorefrontScreen(
        slug: 'vitrine-123',
        storefront: street,
        capture: CaptureRepository(null, db: db),
        session: SessionController(
          db: db,
          auth: AuthRepository(null),
          admin: AdminRepository(null),
          accounting: AccountingRepository(null),
        ),
      ),
    ));
    await settle(tester);
  }

  group('the count, said', () {
    test('grouped in the reader\'s way, short from 10 000', () {
      expect(visitorCount(1, 'fr'), '1');
      expect(visitorCount(999, 'en'), '999');
      expect(visitorCount(1234, 'fr'), '1 234');
      expect(visitorCount(1234, 'en'), '1,234');
      expect(visitorCount(9999, 'fr'), '9 999');
      expect(visitorCount(12345, 'fr'), '12,3 k');
      expect(visitorCount(12345, 'en'), '12.3k');
      expect(visitorCount(250000, 'en'), '250k');
      expect(visitorCount(1234567, 'fr'), '1,2 M');
      expect(visitorCount(1234567, 'en'), '1.2M');
    });

    test('storefront() says it in the style; absent before 123 or at 0', () {
      PublicShop shop(Map<String, dynamic> style) => PublicShop.fromRow(
          {'org_id': 'o', 'name': 'n', 'slug': 's', 'profile': 'retail', 'style': style});
      expect(shop({'visitors': 1234}).visitors, 1234);
      expect(shop({'delivers': true}).visitors, isNull);
      expect(PublicShop.fromRow(const {'org_id': 'o', 'name': 'n', 'slug': 's'}).visitors, isNull);
    });

    test('no client: the visit answers null, silently', () async {
      expect(await StorefrontRepository(null).recordVitrineVisit('s', 'abcdefghijklmnop'), isNull);
    });
  });

  group('the device\'s random id', () {
    test('made once, kept, in the form the server takes; a bad one replaced', () async {
      final first = await deviceVisitorId(db);
      expect(first, matches(RegExp(r'^[A-Za-z0-9-]{16,64}$')));
      expect(await deviceVisitorId(db), first);
      expect(await db.readPref(visitorIdKey), first);
      await db.writePref(visitorIdKey, 'short');
      final fresh = await deviceVisitorId(db);
      expect(fresh, isNot('short'));
      expect(fresh, matches(RegExp(r'^[A-Za-z0-9-]{16,64}$')));
    });
  });

  group('the vitrine', () {
    for (final kind in ['retail', 'farm', 'association']) {
      testWidgets('$kind: one visit per opening with the device id, the eye in French', (tester) async {
        final street = _Street(profile: kind, said: 1233, answer: 1234);
        await open(tester, street);
        expect(street.visits, hasLength(1));
        final id = (await tester.runAsync(() => db.readPref(visitorIdKey)))!;
        expect(street.visits.single, ('vitrine-123', id));
        expect(street.cauris, [id], reason: '084\'s cauris still counted with the same id');
        // Rebuilds — a resize, the filter typed into — send nothing more.
        tester.view.physicalSize = const Size(1280, 1400);
        await settle(tester);
        await tester.pump();
        expect(street.visits, hasLength(1));
        expect(find.byKey(const Key('shop-visitors')), findsOneWidget);
        expect(find.text('1 234'), findsOneWidget, reason: 'the visit\'s answer, fresher than storefront()');
        expect(find.bySemanticsLabel('1 234 visiteurs'), findsOneWidget);
        final icon = tester.widget<Icon>(find.descendant(
            of: find.byKey(const Key('shop-visitors')), matching: find.byType(Icon)));
        expect(icon.icon, Icons.visibility_outlined);
        expect(icon.color, const Color(0xFF1F6FEB), reason: 'the vitrine\'s own colour');
      });
    }

    testWidgets('a second opening is a second visit (the server counts it once a day)', (tester) async {
      final street = _Street(said: 3, answer: 3);
      await open(tester, street);
      await tester.pumpWidget(const SizedBox());
      await open(tester, street);
      expect(street.visits, hasLength(2));
      expect(street.visits[0].$2, street.visits[1].$2, reason: 'the same device, the same id');
    });

    testWidgets('in English: « 12.3k », « 12,345 visitors »; « 1 visitor »', (tester) async {
      await open(tester, _Street(said: 12345, answer: 12345), language: 'en');
      expect(find.text('12.3k'), findsOneWidget);
      expect(find.bySemanticsLabel('12,345 visitors'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await open(tester, _Street(answer: 1), language: 'en');
      expect(find.text('1'), findsOneWidget);
      expect(find.bySemanticsLabel('1 visitor'), findsOneWidget);
    });

    testWidgets('French singular: « 1 visiteur »', (tester) async {
      await open(tester, _Street(answer: 1));
      expect(find.bySemanticsLabel('1 visiteur'), findsOneWidget);
    });

    testWidgets('hidden at 0 and when nothing says it (a database before 123)', (tester) async {
      await open(tester, _Street(answer: 0));
      expect(find.byKey(const Key('shop-visitors')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await open(tester, _Street());
      expect(find.byKey(const Key('shop-visitors')), findsNothing);
      expect(find.text('Vitrine 123'), findsWidgets);
    });

    testWidgets('a failed visit is silent: the page, storefront()\'s count', (tester) async {
      final street = _Street(said: 42, fails: true);
      await open(tester, street);
      expect(street.visits, hasLength(1));
      expect(tester.takeException(), isNull);
      expect(find.text('Savon'), findsWidgets);
      expect(find.text('42'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
