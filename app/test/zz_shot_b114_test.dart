import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/capture/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/retail/products_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const pad = '/tmp/claude-0/-home-user-dbms/6b841e07-559f-5c6e-8be9-8db87f01d3f1/scratchpad';

Future<void> loadFonts() async {
  const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons');
  icons.addFont(Future.value(ByteData.sublistView(File('$dir/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

final shotKey = GlobalKey();

class _Photos extends CaptureRepository {
  _Photos({required super.db}) : super(null);
  @override
  bool get isConfigured => true;
  final pics = {
    'a': File('$pad/photo.png').readAsBytesSync(),
    'b': File('$pad/tile.png').readAsBytesSync(),
    'c': File('$pad/aub.png').readAsBytesSync(),
  };
  @override
  Future<List<CapturedDocument>> documents(String orgId, {String? kind, int limit = 60, int offset = 0}) async => const [
        CapturedDocument(id: 'd1', key: 'a', contentType: 'image/png'),
        CapturedDocument(id: 'd2', key: 'x', kind: 'invoice'),
        CapturedDocument(id: 'd3', key: 'b', contentType: 'image/png', productId: 'p9', productName: 'Huile Dinor 1 L'),
        CapturedDocument(id: 'd4', key: 'c', contentType: 'image/png'),
        CapturedDocument(id: 'd5', key: 'a', contentType: 'image/png', productId: 'p8', productName: 'Riz parfumé'),
        CapturedDocument(id: 'd6', key: 'b', contentType: 'image/png'),
        CapturedDocument(id: 'd7', key: 'c', contentType: 'image/png', productId: 'p7', productName: 'Savon'),
      ];
  @override
  Future<Uint8List> objectBytes(String key) async => pics[key]!;
}

class _Shelf extends RetailRepository {
  _Shelf() : super(null);
  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [
        Product(id: 'p1', name: 'Savon Citec', costPrice: 300, salePrice: 450, quantity: 9),
      ];
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  testWidgets('b114 shots', (tester) async {
    await loadFonts();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = await LocalDb.open(path: inMemoryDatabasePath);
    await tester.pumpWidget(RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        theme: kajTheme(kajPalette),
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: ProductsScreen(org: const OrgSummary(id: 'org-1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']),
            retail: _Shelf(), capture: _Photos(db: db)),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }
    await settle();
    await tester.longPress(find.text('Savon Citec'));
    await settle();
    await tester.tap(find.text('Ajouter une photo'));
    await settle();
    await expectLater(find.byKey(shotKey), matchesGoldenFile('zz_shots/b114_choice_390.png'));
    await tester.tap(find.byKey(const Key('pick-from-photos')));
    await settle();
    for (final e in find.byType(Image).evaluate()) {
      final img = (e.widget as Image).image;
      await tester.runAsync(() => precacheImage(img, e));
    }
    await settle();
    await expectLater(find.byKey(shotKey), matchesGoldenFile('zz_shots/b114_picker_390.png'));
    await tester.runAsync(db.close);
  });
}
