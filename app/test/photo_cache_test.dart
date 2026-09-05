import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A picture is fetched once for the life of the app, not once per tile:
/// the street, the shop and the way back share one memory, bounded so a
/// long afternoon of browsing never grows without limit, and the least
/// recently seen leaves first.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  late int fetched;

  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
    fetched = 0;
  });

  tearDown(() => db.close());

  /// A Worker that answers every key with as many bytes as its name says
  /// ("k-100" is a hundred bytes) and counts how often it was asked.
  http.Client worker() => MockClient((request) async {
        fetched++;
        final key = Uri.decodeComponent(request.url.pathSegments.last);
        final size = int.parse(key.split('-').last);
        return http.Response.bytes(Uint8List(size), 200);
      });

  CaptureRepository repo({int budget = 1000}) => CaptureRepository(
        null,
        db: db,
        uploadsUrl: 'https://kaj-uploads.example.workers.dev',
        httpClient: worker(),
        photoCacheBudget: budget,
      );

  test('the same picture is fetched once', () async {
    final r = repo();
    final a = await r.publicObjectBytes('k-100');
    final b = await r.publicObjectBytes('k-100');
    expect(a.length, 100);
    expect(identical(a, b), isTrue);
    expect(fetched, 1);
    expect(r.cachedPhotos, 1);
  });

  test('past the budget the least recently seen leaves first', () async {
    // Four pictures fill 960 of a 1000-byte budget (each under the
    // budget/4 ceiling that keeps one giant file from evicting the rest).
    final r = repo(budget: 1000);
    for (final k in ['a-240', 'b-240', 'c-240', 'd-240']) {
      await r.publicObjectBytes(k);
    }
    // Seeing "a" again makes "b" the oldest.
    await r.publicObjectBytes('a-240');
    await r.publicObjectBytes('e-240'); // 1200 > 1000: "b" goes.
    expect(r.cachedPhotos, 4);
    expect(fetched, 5);

    await r.publicObjectBytes('a-240'); // still held
    expect(fetched, 5);
    await r.publicObjectBytes('b-240'); // gone, fetched again
    expect(fetched, 6);
  });

  test('one oversized picture is served but never evicts the street',
      () async {
    final r = repo(budget: 1000);
    await r.publicObjectBytes('a-100');
    final big = await r.publicObjectBytes('big-600'); // > budget / 4
    expect(big.length, 600);
    expect(r.cachedPhotos, 1); // "a" stays; "big" was not kept
  });

  test('a failed fetch is not remembered', () async {
    final r = CaptureRepository(
      null,
      db: db,
      uploadsUrl: 'https://kaj-uploads.example.workers.dev',
      httpClient: MockClient((_) async => http.Response('non', 404)),
    );
    await expectLater(r.publicObjectBytes('k-1'), throwsA(isA<CaptureException>()));
    expect(r.cachedPhotos, 0);
  });
}
