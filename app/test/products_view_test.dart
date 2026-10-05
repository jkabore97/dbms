import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/retail/product_photo.dart';
import 'package:kaj_app/features/retail/products_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The Articles page, as a list or as cards (079): each article carries its
/// picture in both, one call fetches every article's key, and an article
/// with no photograph shows its initial instead of a broken image.
class _Shelf extends RetailRepository {
  _Shelf() : super(null);

  int keyCalls = 0;

  @override
  Future<List<Product>> products(
    String orgId, {
    bool activeOnly = true,
  }) async => const [
    Product(id: 'p1', name: 'Gateau', salePrice: 200, quantity: 30),
    Product(id: 'p2', name: 'yaourt', salePrice: 500, quantity: 10),
  ];

  @override
  Future<Map<String, String>> photoKeys(String orgId) async {
    keyCalls++;
    return const {'p1': 'k-gateau'};
  }
}

// A 1×1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class _Camera extends CaptureRepository {
  _Camera({required super.db}) : super(null);

  final fetched = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<Uint8List> objectBytes(String key) async {
    fetched.add(key);
    return Uint8List.fromList(_png);
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  const org = OrgSummary(
    id: 'org-1',
    name: 'Shop Style',
    profile: 'retail',
    roles: ['owner'],
  );

  Future<(_Shelf, _Camera)> pump(WidgetTester tester) async {
    final shelf = _Shelf();
    final camera = _Camera(db: db);
    await tester.pumpWidget(
      MaterialApp(
        home: ProductsScreen(org: org, retail: shelf, capture: camera),
      ),
    );
    await tester.pumpAndSettle();
    return (shelf, camera);
  }

  testWidgets('a list, each row with its picture or its initial', (
    tester,
  ) async {
    final (shelf, camera) = await pump(tester);
    expect(find.byKey(const ValueKey('product-row-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('product-card-p1')), findsNothing);
    expect(shelf.keyCalls, 1, reason: 'one call for the whole shop');
    expect(camera.fetched, ['k-gateau']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('product-row-p1')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    // No photograph: the initial, never a broken image.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('product-row-p2')),
        matching: find.text('Y'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cards on a tap, and back to the list', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Afficher en cartes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product-card-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('product-card-p2')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('product-card-p1')),
        matching: find.byType(ProductPhoto),
      ),
      findsOneWidget,
    );
    expect(find.text('Gateau'), findsOneWidget);

    await tester.tap(find.byTooltip('Afficher en liste'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product-row-p1')), findsOneWidget);
  });

  testWidgets('the search narrows the cards too', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Afficher en cartes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'yao');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product-card-p1')), findsNothing);
    expect(find.byKey(const ValueKey('product-card-p2')), findsOneWidget);
  });
}
