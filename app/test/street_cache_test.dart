import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/storefront/street_cache.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The street's last look (street_cache.dart): written on every answer,
/// shown at once on the next visit, and all there is with no network —
/// said as such.

const _shopRow = {
  'org_id': 'o1',
  'name': 'Boutique Témoin',
  'slug': 'temoin',
  'profile': 'retail',
  'currency': 'XOF',
  'style': <String, Object?>{},
};
final _products = [
  {'id': 'p1', 'name': 'Savon', 'sale_price': 450, 'in_stock': true},
  {'id': 'p2', 'name': 'Riz', 'sale_price': 15000, 'in_stock': true},
];

/// A Supabase whose RPCs answer from [answers], or fail like a dead
/// connection while [offline] is set.
class _Server {
  bool offline = false;
  final asked = <String>[];
  final Map<String, Object?> answers = {
    'storefront': [_shopRow],
    'storefront_products': _products,
    'storefront_stock': [
      {'id': 'p1', 'stock_left': 3},
    ],
    'showcase_slugs': <Object?>[],
    'storefront_directory': [_shopRow],
    'storefront_previews': [
      {'slug': 'temoin', 'product_id': 'p1', 'name': 'Savon', 'sale_price': 450},
    ],
  };

  /// Held answers, to see which questions are in flight together.
  final Map<String, Completer<void>> hold = {};

  late final client = SupabaseClient(
    'https://db.example',
    'anon',
    // No refresh ticker: a test owns its timers.
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      final fn = request.url.pathSegments.last;
      asked.add(fn);
      if (offline) throw http.ClientException('Connection refused', request.url);
      await hold[fn]?.future;
      return http.Response(jsonEncode(answers[fn] ?? []), 200,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() => db.close());

  group('the repository', () {
    test('an answer is kept, and is what comes back with no network', () async {
      final server = _Server();
      final repo = StorefrontRepository(server.client, keep: StreetCache(db));
      expect((await repo.shop('temoin'))!.name, 'Boutique Témoin');
      final online = await repo.items('temoin');
      expect(online.map((i) => i.id), ['p1', 'p2']);
      expect(online.first.stockLeft, 3, reason: 'the stock count is kept with the shelf');
      expect(repo.keptAt, isNull, reason: 'fresh');
      await repo.directory();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      server.offline = true;
      expect((await repo.shop('temoin'))!.name, 'Boutique Témoin');
      expect(repo.keptAt, isNotNull, reason: 'said to come from the phone');
      final kept = await repo.items('temoin');
      expect(kept.map((i) => i.name), ['Savon', 'Riz']);
      expect(kept.first.stockLeft, 3);
      expect((await repo.directory()).single.slug, 'temoin');
    });

    test('nothing kept and no network: the failure, as before', () async {
      final server = _Server()..offline = true;
      final repo = StorefrontRepository(server.client, keep: StreetCache(db));
      await expectLater(repo.shop('temoin'), throwsA(isA<Exception>()));
      expect(await repo.keptVitrine('temoin'), isNull);
    });

    test('without a keep, nothing is written anywhere', () async {
      final server = _Server();
      final repo = StorefrontRepository(server.client);
      await repo.shop('temoin');
      expect(await repo.keptVitrine('temoin'), isNull);
      expect(await StreetCache(db).get('storefront:temoin'), isNull);
    });

    test('the shelf and its stock are asked at once, not in turn', () async {
      final server = _Server();
      server.hold['storefront_products'] = Completer<void>();
      final repo = StorefrontRepository(server.client);
      final shelf = repo.items('temoin');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.asked, containsAll(['storefront_products', 'storefront_stock']),
          reason: 'stock asked while the products are still on their way');
      server.hold['storefront_products']!.complete();
      expect((await shelf).length, 2);
    });

    test('keptVitrine and keptStreet read the last look before any network', () async {
      final server = _Server();
      final repo = StorefrontRepository(server.client, keep: StreetCache(db));
      await repo.shop('temoin');
      await repo.items('temoin');
      await repo.directory();
      await repo.previews(['temoin']);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      server.asked.clear();

      final vitrine = await repo.keptVitrine('temoin');
      expect(vitrine!.shop.name, 'Boutique Témoin');
      expect(vitrine.items.length, 2);
      expect(vitrine.at, isNotNull);
      final street = await repo.keptStreet();
      expect(street!.entries.single.name, 'Boutique Témoin');
      expect(street.previews['temoin']!.single.name, 'Savon');
      expect(server.asked, isEmpty, reason: 'read from the phone only');
    });
  });

  test('the cache keeps the last vitrines opened, the oldest dropped first', () async {
    final cache = StreetCache(db, vitrines: 2);
    for (final slug in ['a', 'b', 'c']) {
      await cache.put('storefront:$slug', [
        {'slug': slug},
      ]);
      await cache.put('items:$slug', const []);
    }
    expect(await cache.get('storefront:a'), isNull);
    expect(await cache.get('items:a'), isNull);
    expect(await cache.get('storefront:b'), isNotNull);
    expect(await cache.get('storefront:c'), isNotNull);
    // Opening b again makes c the oldest.
    await cache.put('storefront:b', const []);
    await cache.put('storefront:d', const []);
    expect(await cache.get('storefront:c'), isNull);
    expect(await cache.get('storefront:b'), isNotNull);
  });

  group('the vitrine', () {
    Future<void> pump(WidgetTester tester, StorefrontRepository repo) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: StorefrontScreen(
          slug: 'temoin',
          storefront: repo,
          capture: CaptureRepository(null, db: db),
          session: SessionController(
            db: db,
            auth: AuthRepository(null),
            admin: AdminRepository(null),
            accounting: AccountingRepository(null),
          ),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 800));
    }

    testWidgets('no network: the shop as last seen, and it says so', (tester) async {
      final server = _Server();
      final repo = StorefrontRepository(server.client, keep: StreetCache(db));
      await tester.runAsync(() async {
        await repo.shop('temoin');
        await repo.items('temoin');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      server.offline = true;
      await pump(tester, repo);
      expect(find.text('Savon'), findsWidgets);
      expect(find.textContaining('dernière visite'), findsOneWidget);
      expect(find.textContaining("n'a pas pu être chargée"), findsNothing);
    });

    testWidgets('never opened and no network: the page says the network failed', (tester) async {
      final server = _Server()..offline = true;
      await pump(tester, StorefrontRepository(server.client, keep: StreetCache(db)));
      expect(find.textContaining("n'a pas pu être chargée"), findsOneWidget);
    });
  });
}
