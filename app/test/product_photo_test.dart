import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/capture/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/retail/products_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The article's photograph, from the shop's side: the edit sheet offers to
/// take one exactly when a camera path exists, finds the article's current
/// one the same way the vitrine does (the newest document hung on it), and
/// stays honest — no capture path, no dead button.
class _Shelf extends RetailRepository {
  _Shelf() : super(null);

  @override
  Future<List<Product>> products(String orgId,
          {bool activeOnly = true}) async =>
      const [
        Product(
          id: 'p1',
          name: 'Savon Citec',
          costPrice: 300,
          salePrice: 450,
          quantity: 9,
        ),
      ];
}

class _Camera extends CaptureRepository {
  _Camera({required super.db}) : super(null);

  List<CapturedDocument> shoebox = const [];

  @override
  Future<List<CapturedDocument>> documents(
    String orgId, {
    String? kind,
    int limit = 60,
    int offset = 0,
  }) async =>
      shoebox;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;

  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });

  tearDown(() => db.close());

  const org = OrgSummary(id: 'org-1', name: 'Boutique Awa', profile: 'retail');

  group('productPhotoKey', () {
    test('finds the newest document hung on the article', () async {
      final camera = _Camera(db: db)
        ..shoebox = const [
          CapturedDocument(id: 'd1', key: 'k-new', productId: 'p1'),
          CapturedDocument(id: 'd2', key: 'k-old', productId: 'p1'),
          CapturedDocument(id: 'd3', key: 'k-other', productId: 'p2'),
        ];
      // documents() answers newest first, so the first match is the photo.
      expect(await camera.productPhotoKey('org-1', 'p1'), 'k-new');
      expect(await camera.productPhotoKey('org-1', 'p2'), 'k-other');
    });

    test('an article with no photo answers null, not an error', () async {
      final camera = _Camera(db: db)
        ..shoebox = const [
          CapturedDocument(id: 'd1', key: 'k1', productId: 'other'),
          CapturedDocument(id: 'd2', key: 'k2'),
        ];
      expect(await camera.productPhotoKey('org-1', 'p1'), isNull);
    });
  });

  group('the edit sheet', () {
    Future<void> openSheet(WidgetTester tester,
        {CaptureRepository? capture}) async {
      await tester.pumpWidget(MaterialApp(
        home: ProductsScreen(
          org: org,
          retail: _Shelf(),
          capture: capture,
        ),
      ));
      await tester.pump();
      await tester.pump();
      // Editing is a long press, on purpose — a scrolling thumb must not
      // fall into a sheet that changes prices.
      await tester.longPress(find.text('Savon Citec'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
    }

    testWidgets('offers the photo when a camera path exists', (tester) async {
      await openSheet(tester, capture: _Camera(db: db));
      expect(find.text('Ajouter une photo'), findsOneWidget);
      expect(
        find.text('La photo paraît sur la vitrine et dans la recherche.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed photo fetch still leaves a live button',
        (tester) async {
      final camera = _Camera(db: db)
        ..shoebox = const [
          CapturedDocument(id: 'd1', key: 'k1', productId: 'p1'),
        ];
      await openSheet(tester, capture: camera);
      // The bytes fetch dies in a test (no Worker answers), so the
      // thumbnail stays a placeholder — but the section must survive the
      // failure with its button offered, not vanish or crash.
      expect(find.text('Ajouter une photo'), findsOneWidget);
    });

    testWidgets('no camera path, no photo section', (tester) async {
      await openSheet(tester);
      expect(find.text('Ajouter une photo'), findsNothing);
      expect(
        find.text('La photo paraît sur la vitrine et dans la recherche.'),
        findsNothing,
      );
    });
  });
}
