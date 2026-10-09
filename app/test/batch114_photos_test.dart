import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/capture/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/capture/capture_action.dart';
import 'package:kaj_app/features/farm/for_sale_screen.dart';
import 'package:kaj_app/features/retail/products_screen.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/services/service_flow.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The owner (114): « Enable using an existing pictures in "Photo" to add
/// to an item or service. » — beside « Prendre une photo », « Choisir dans
/// Photos »: the business's own photographs (pictures only, never an
/// invoice, a receipt, a logo or a PDF), one chosen becomes the article's
/// or the service's photo through file_document, as a new one does — and a
/// photo another article wears stays that article's too.

/// A 1×1 PNG: a picture the test can draw.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

/// « Photos »: an unfiled picture, the paperwork (an invoice, a PDF, a
/// receipt, the logo), and a picture another article already wears.
const _shoebox = [
  CapturedDocument(id: 'd1', key: 'org/org-1/a.jpg', contentType: 'image/jpeg'),
  CapturedDocument(id: 'd2', key: 'org/org-1/b.jpg', kind: 'invoice', contentType: 'image/jpeg'),
  CapturedDocument(id: 'd3', key: 'org/org-1/c.pdf', contentType: 'application/pdf'),
  CapturedDocument(id: 'd4', key: 'org/org-1/d.jpg', kind: 'receipt'),
  CapturedDocument(id: 'd5', key: 'org/org-1/e.png', kind: 'logo', contentType: 'image/png'),
  CapturedDocument(
      id: 'd6', key: 'org/org-1/f.jpg', kind: 'product_photo', contentType: 'image/jpeg',
      productId: 'p9', productName: 'Huile Dinor'),
];

class _Photos extends CaptureRepository {
  _Photos({required super.db}) : super(null);

  final filed = <String>[];
  final sent = <String>[];
  bool offline = false;

  @override
  bool get isConfigured => true;

  @override
  Future<List<CapturedDocument>> documents(String orgId,
          {String? kind, int limit = 60, int offset = 0}) async =>
      _shoebox;

  @override
  Future<Uint8List> objectBytes(String key) async => _png;

  @override
  Future<String?> capture({
    required String orgId,
    required Uint8List bytes,
    required String contentType,
    String? kind,
    String? caption,
    String? ocrText,
    DateTime? capturedAt,
  }) async {
    sent.add('$orgId $contentType $kind $caption ${bytes.length}');
    return offline ? null : 'new-doc';
  }

  @override
  Future<void> file({
    required String documentId,
    String? caption,
    String? kind,
    String? entryId,
    String? productId,
  }) async =>
      filed.add('$documentId→$productId${caption == null ? '' : ' « $caption »'}');
}

class _Shelf extends RetailRepository {
  _Shelf() : super(null);

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [
        Product(id: 'p1', name: 'Savon Citec', costPrice: 300, salePrice: 450, quantity: 9),
      ];

  @override
  Future<String> ensureProduct({
    required String orgId,
    required String name,
    double? salePrice,
    double? costPrice,
    String? barcode,
    DateTime? expiresOn,
    bool isService = false,
  }) async =>
      'p-new';

  @override
  Future<void> updateProduct(
    String productId, {
    String? name,
    double? salePrice,
    double? costPrice,
    DateTime? expiresOn,
    double? lowStockAt,
    bool? isActive,
    bool? isIngredient,
    bool? isPublished,
    String? description,
    String? unit,
    DateTime? availableFrom,
    bool clearAvailableFrom = false,
    double? quantity,
    bool? isService,
    bool? priceFrom,
  }) async {}
}

const _shop = OrgSummary(id: 'org-1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);
const _farm = OrgSummary(id: 'org-1', name: 'Ferme Ignace', profile: 'farm', roles: ['owner']);
const _asso = OrgSummary(id: 'org-1', name: 'Entraide', profile: 'association', roles: ['owner']);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// [sheet] pushed over a page, as its screen opens it: saved, it pops.
  Future<void> sheetOn(WidgetTester tester, Widget sheet) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<bool>(builder: (_) => Scaffold(body: sheet))),
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await settle(tester);
  }

  /// From the photo button: the choice, then « Photos ».
  Future<void> openLibrary(WidgetTester tester) async {
    expect(find.text('Prendre une photo'), findsOneWidget);
    expect(find.byKey(const Key('pick-from-photos')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pick-from-photos')));
    await settle(tester);
    expect(find.text('Choisir dans Photos'), findsOneWidget);
  }

  group('CaptureAction.hang — the one path a chosen photo takes', () {
    const picked = CapturedDocument(id: 'd1', key: 'org/org-1/a.jpg', contentType: 'image/jpeg');
    PickedPhoto photo(CapturedDocument? from) =>
        (bytes: Uint8List.fromList(_png), contentType: 'image/jpeg', from: from);

    test('a photo about nothing yet, on an article with none: moved onto it, no second copy', () async {
      final photos = _Photos(db: db);
      final id = await CaptureAction.hang(photos,
          orgId: 'org-1', productId: 'p1', name: 'Savon', photo: photo(picked), hadPhoto: false);
      expect(id, 'd1');
      expect(photos.filed, ['d1→p1 « Savon »'], reason: 'its name given, as a new photo is');
      expect(photos.sent, isEmpty);
    });

    test('a photo another article wears: sent again as this one\'s, the other keeps it', () async {
      final photos = _Photos(db: db);
      final id = await CaptureAction.hang(photos,
          orgId: 'org-1', productId: 'p1', name: 'Savon', photo: photo(_shoebox.last), hadPhoto: false);
      expect(id, 'new-doc');
      expect(photos.sent, ['org-1 image/jpeg product_photo Savon ${_png.length}']);
      expect(photos.filed, ['new-doc→p1']);
    });

    test('an article that has a photo: the chosen one sent as the newest, so it is the one shown', () async {
      final photos = _Photos(db: db);
      await CaptureAction.hang(photos,
          orgId: 'org-1', productId: 'p1', name: 'Savon', photo: photo(picked), hadPhoto: true);
      expect(photos.sent, hasLength(1));
      expect(photos.filed, ['new-doc→p1']);
    });

    test('a photo filed on an entry stays the entry\'s: copied', () async {
      final photos = _Photos(db: db);
      await CaptureAction.hang(photos,
          orgId: 'org-1',
          productId: 'p1',
          name: 'Savon',
          photo: photo(const CapturedDocument(id: 'd7', key: 'k7', entryId: 'e1')),
          hadPhoto: false);
      expect(photos.filed, ['new-doc→p1']);
    });

    test('a new picture with no signal: queued, nothing filed yet', () async {
      final photos = _Photos(db: db)..offline = true;
      final id = await CaptureAction.hang(photos,
          orgId: 'org-1', productId: 'p1', name: 'Savon', photo: photo(null), hadPhoto: false);
      expect(id, isNull);
      expect(photos.filed, isEmpty);
    });
  });

  testWidgets('the shop\'s article: « Choisir dans Photos » shows pictures only, says which article '
      'wears one, and the chosen one becomes the article\'s photo', (tester) async {
    phone(tester);
    final photos = _Photos(db: db);
    await tester.pumpWidget(MaterialApp(
      home: ProductsScreen(org: _shop, retail: _Shelf(), capture: photos),
    ));
    await settle(tester);
    await tester.longPress(find.text('Savon Citec'));
    await settle(tester);
    await tester.tap(find.text('Ajouter une photo'));
    await settle(tester);
    await openLibrary(tester);

    expect(find.byKey(const Key('photo-library-d1')), findsOneWidget);
    expect(find.byKey(const Key('photo-library-d6')), findsOneWidget);
    for (final paper in ['d2', 'd3', 'd4', 'd5']) {
      expect(find.byKey(Key('photo-library-$paper')), findsNothing, reason: '$paper is paperwork');
    }
    expect(find.text('Sur : Huile Dinor'), findsOneWidget);

    await tester.tap(find.byKey(const Key('photo-library-d1')));
    await settle(tester);
    expect(photos.filed, ['d1→p1 « Savon Citec »']);
    expect(photos.sent, isEmpty);
    expect(find.text('Photo de l\'article enregistrée.'), findsOneWidget);
    expect(find.text('Changer la photo'), findsOneWidget);
  });

  testWidgets('a service (shop and association): the photo of another article, reused at « Enregistrer »',
      (tester) async {
    phone(tester);
    for (final org in [_shop, _asso]) {
      final photos = _Photos(db: db);
      // A new service is the « Service » flow (115): its first step, the photo.
      await sheetOn(tester, ServiceFlow(org: org, retail: _Shelf(), capture: photos, store: MemoryFlowStore()));
      await tester.tap(find.byKey(const Key('service-flow-photo-pick')));
      await settle(tester);
      await openLibrary(tester);
      await tester.tap(find.byKey(const Key('photo-library-d6')));
      await settle(tester);
      expect(find.text('Choisir dans Photos'), findsNothing);
      expect(photos.sent, isEmpty, reason: 'nothing sent before « Enregistrer »');

      Future<void> next() async {
        await tester.tap(find.byKey(const Key('flow-next')));
        await settle(tester);
      }

      await next();
      await tester.enterText(find.byKey(const Key('service-flow-name')), 'Coupe homme');
      await tester.pump();
      await next();
      await tester.enterText(find.byKey(const Key('service-flow-price')), '1500');
      await tester.pump();
      await next();
      await next();
      await next();
      await tester.tap(find.byKey(const Key('flow-save')));
      await settle(tester);
      expect(photos.sent, ['org-1 image/jpeg product_photo Coupe homme ${_png.length}'], reason: org.profile);
      expect(photos.filed, ['new-doc→p-new'], reason: org.profile);
      await tester.tap(find.byKey(const Key('flow-finish')));
      await settle(tester);
    }
  });

  testWidgets('the farm\'s « À vendre »: an unfiled photo moved onto the article', (tester) async {
    phone(tester);
    final photos = _Photos(db: db);
    await sheetOn(
        tester,
        ForSaleSheet(
            org: _farm,
            retail: _Shelf(),
            capture: photos,
            product: const Product(id: 'p1', name: 'Poulets', costPrice: 0, salePrice: 3500, quantity: 12)));
    await tester.tap(find.byKey(const Key('for-sale-photo')));
    await settle(tester);
    await openLibrary(tester);
    await tester.tap(find.byKey(const Key('photo-library-d1')));
    await settle(tester);

    final save = find.byKey(const Key('for-sale-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await settle(tester);
    expect(photos.filed, ['d1→p1 « Poulets »']);
    expect(photos.sent, isEmpty);
  });

  testWidgets('elsewhere (the logo, the carnet) the choice is as before: no « Photos »', (tester) async {
    phone(tester);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => CaptureAction.pick(context),
          child: const Text('logo'),
        ),
      ),
    ));
    await tester.tap(find.text('logo'));
    await settle(tester);
    expect(find.text('Prendre une photo'), findsOneWidget);
    expect(find.byKey(const Key('pick-from-photos')), findsNothing);
  });

  testWidgets('no photo yet in « Photos »: said, with the way to take one', (tester) async {
    phone(tester);
    final photos = _Empty(db: db);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => CaptureAction.pick(context, orgId: 'org-1', photos: photos),
          child: const Text('photo'),
        ),
      ),
    ));
    await tester.tap(find.text('photo'));
    await settle(tester);
    await openLibrary(tester);
    expect(find.byKey(const Key('photo-library-empty')), findsOneWidget);
    expect(find.text('Aucune photo dans Photos pour le moment.'), findsOneWidget);
  });
}

class _Empty extends _Photos {
  _Empty({required super.db});
  @override
  Future<List<CapturedDocument>> documents(String orgId,
          {String? kind, int limit = 60, int offset = 0}) async =>
      const [CapturedDocument(id: 'x', key: 'k', kind: 'invoice')];
}
