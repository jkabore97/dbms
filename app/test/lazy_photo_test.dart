import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/features/storefront/lazy_photo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A vitrine's shelf is a shrink-wrapped grid inside a list: every tile is
/// built at once. Its photos must not all be asked for at once — only
/// those near the screen, at the size they are drawn.
void main() {
  Future<({List<int> asked, List<int> widths})> pumpShelf(WidgetTester tester,
      {double ratio = 2}) async {
    tester.view.physicalSize = Size(390 * ratio, 844 * ratio);
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    final asked = <int>[];
    final widths = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            const SizedBox(height: 300),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisExtent: 195),
              itemCount: 40,
              itemBuilder: (context, i) => LazyPhoto(
                key: ValueKey(i),
                load: (w) async {
                  asked.add(i);
                  widths.add(w);
                  return Uint8List(0);
                },
                placeholder: const SizedBox.expand(),
                builder: (context, bytes, w) => const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return (asked: asked, widths: widths);
  }

  testWidgets('only the tiles near the screen ask for their photo', (tester) async {
    final shelf = await pumpShelf(tester);
    final first = shelf.asked.length;
    // On screen and one screen ahead: (844 - 300 + 844) / 195 rows × 2.
    expect(first, inInclusiveRange(10, 18));
    expect(shelf.asked.every((i) => i < 18), isTrue, reason: 'the top of the shelf first');

    // Scrolling down brings the next ones in, each asked once.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();
    await tester.pump();
    expect(shelf.asked.length, greaterThan(first));
    expect(shelf.asked.toSet().length, shelf.asked.length);
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pump();
    expect(shelf.asked.toSet().length, shelf.asked.length, reason: 'never twice');
  });

  testWidgets('the photo is asked for at the size it is drawn', (tester) async {
    final shelf = await pumpShelf(tester, ratio: 2);
    // A tile is (390 / 2) wide and 195 high; at 2 pixels per point the
    // longer side is 390 pixels.
    expect(shelf.widths.first, 390);
    expect(CaptureRepository.thumbWidth(shelf.widths.first), 400);
  });

  group('the public read', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('asks the Worker for the small copy, and the original serves any size', () async {
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      final asked = <Uri>[];
      final capture = CaptureRepository(
        null,
        db: db,
        uploadsUrl: 'https://up.example/',
        httpClient: MockClient((request) async {
          asked.add(request.url);
          final w = request.url.queryParameters['w'];
          return http.Response.bytes(Uint8List(w == null ? 900 : int.parse(w)), 200);
        }),
      );
      const key = 'org/o1/2026/01/a.jpg';
      expect((await capture.publicObjectBytes(key, width: 390)).length, 400);
      expect(asked.single.toString(),
          'https://up.example/v1/public/objects/${Uri.encodeComponent(key)}?w=400');
      // The same tile again: held, not asked.
      await capture.publicObjectBytes(key, width: 380);
      expect(asked, hasLength(1));
      // The full photograph (a product sheet), then any tile from it.
      expect((await capture.publicObjectBytes(key)).length, 900);
      expect(asked.last.hasQuery, isFalse);
      expect((await capture.publicObjectBytes(key, width: 150)).length, 900);
      expect(asked, hasLength(2));
    });
  });

  test('thumbnail widths: the smallest that covers, the original past 800', () {
    expect(CaptureRepository.thumbWidth(1), 200);
    expect(CaptureRepository.thumbWidth(200), 200);
    expect(CaptureRepository.thumbWidth(201), 400);
    expect(CaptureRepository.thumbWidth(800), 800);
    expect(CaptureRepository.thumbWidth(801), isNull);
  });
}
