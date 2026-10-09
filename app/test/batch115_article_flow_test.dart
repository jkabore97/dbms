import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/capture/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/retail/article_flow.dart';
import 'package:kaj_app/features/retail/products_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// « Ajouter un article », one entry at a time (115, W1): one or many, the
/// shop's and the farm's — which keeps its supplies apart.
class _Shelf extends RetailRepository {
  _Shelf({this.shelf = const [], this.offline = false}) : super(null);

  final List<Product> shelf;
  final bool offline;
  final log = <String>[];
  final updates = <Map<String, Object?>>[];

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => shelf;

  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {};

  @override
  Future<String> ensureProduct({
    required String orgId,
    required String name,
    double? salePrice,
    double? costPrice,
    String? barcode,
    DateTime? expiresOn,
    bool isService = false,
  }) async {
    if (offline) throw const SocketException('Failed host lookup');
    log.add('ensure $name price=$salePrice cost=$costPrice code=$barcode service=$isService');
    for (final p in shelf) {
      if (p.name == name) return p.id;
    }
    return 'new-${log.length}';
  }

  @override
  Future<void> receive({
    required String orgId,
    required String productId,
    required double quantity,
    double? unitCost,
    DateTime? expiresOn,
    String method = 'cash',
    String? clientUuid,
  }) async =>
      log.add('receive $productId $quantity cost=$unitCost');

  @override
  Future<void> setSerial(String productId, String serial) async =>
      log.add('serial $productId $serial');

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
  }) async {
    updates.add({
      'id': productId,
      'unit': unit,
      'low': lowStockAt,
      'published': isPublished,
      'ingredient': isIngredient,
      'quantity': quantity,
      'from': availableFrom,
    });
  }
}

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class _Photos extends CaptureRepository {
  _Photos({required super.db}) : super(null);
  final filed = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<List<CapturedDocument>> documents(String orgId,
          {String? kind, int limit = 60, int offset = 0}) async =>
      const [CapturedDocument(id: 'd1', key: 'org/o1/a.jpg', contentType: 'image/jpeg')];

  @override
  Future<Uint8List> objectBytes(String key) async => _png;

  @override
  Future<void> file({
    required String documentId,
    String? caption,
    String? kind,
    String? entryId,
    String? productId,
  }) async =>
      filed.add('$documentId→$productId');
}

const _shop = OrgSummary(id: 'o1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);
const _farm = OrgSummary(id: 'f1', name: 'Ferme Ignace', profile: 'farm', roles: ['owner']);

Widget _host(Future<bool?> Function(BuildContext) open, List<bool?> closed) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => closed.add(await open(context)),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();
  }

  String question(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('flow-question'))).data!;

  Future<void> start(WidgetTester tester, Future<bool?> Function(BuildContext) open,
      List<bool?> closed) async {
    await tester.pumpWidget(_host(open, closed));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('the shop: a new article, every step, then « Ajouter un autre »',
      (tester) async {
    await phone(tester);
    final shelf = _Shelf();
    final closed = <bool?>[];
    await start(
        tester,
        (c) => ArticleFlow.open(c, org: _shop, retail: shelf, store: MemoryFlowStore()),
        closed);

    expect(question(tester), 'Quel article ?', reason: 'no camera in this build: no photo step');
    await tester.enterText(find.byKey(const Key('article-name')), 'Savon Citec');
    await tester.pump();
    await next(tester);
    expect(question(tester), 'Prix de vente ?');
    await tester.enterText(find.byKey(const Key('article-price')), '450');
    await tester.pump();
    await next(tester);
    expect(question(tester), 'Prix d\'achat ?');
    expect(find.text('(facultatif)'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('article-cost')), '300');
    await tester.pump();
    await next(tester);
    expect(question(tester), 'Combien en avez-vous ?');
    await tester.enterText(find.byKey(const Key('article-quantity')), '24');
    await tester.tap(find.byKey(const ValueKey('article-unit-pièce')));
    await tester.pump();
    await next(tester);
    expect(question(tester), 'Prévenir quand il en reste peu ?');
    await tester.enterText(find.byKey(const Key('article-low')), '5');
    await tester.pump();
    await next(tester);
    expect(question(tester), 'Sur la vitrine ?');
    await tester.tap(find.byKey(const Key('flow-option-true')));
    await tester.pumpAndSettle();
    await next(tester);
    expect(question(tester), 'Utilisé en production ?');
    await next(tester); // Non, the default
    expect(question(tester), 'Autres détails');
    await tester.enterText(find.byKey(const Key('article-serial')), 'SN-1');
    await next(tester);
    expect(find.byKey(const Key('flow-summary')), findsOneWidget);
    expect(find.text('24 pièce'), findsOneWidget);
    await tester.tap(find.byKey(const Key('flow-save')));
    await tester.pumpAndSettle();

    expect(shelf.log, [
      'ensure Savon Citec price=450.0 cost=300.0 code=null service=false',
      'serial new-1 SN-1',
      'receive new-1 24.0 cost=300.0',
    ]);
    expect(shelf.updates.single,
        {'id': 'new-1', 'unit': 'pièce', 'low': 5.0, 'published': true, 'ingredient': false, 'quantity': null, 'from': null});
    expect(find.text('Savon Citec ajouté'), findsOneWidget);

    // Many: « Ajouter un autre article » starts again, empty.
    await tester.tap(find.byKey(const Key('article-another')));
    await tester.pumpAndSettle();
    expect(question(tester), 'Quel article ?');
    expect(tester.widget<TextField>(find.byKey(const Key('article-name'))).controller!.text, '');
    // Leaving the second one empty still tells the page: one was saved.
    await tester.tap(find.byKey(const Key('flow-close')));
    await tester.pumpAndSettle();
    expect(closed, [true]);
  });

  testWidgets('a name already carried: its stock grows, its settings stay — the « Entrée de stock »',
      (tester) async {
    await phone(tester);
    final shelf = _Shelf(shelf: const [
      Product(id: 'p1', name: 'Savon Citec', costPrice: 300, salePrice: 450, quantity: 9, unit: 'pièce'),
    ]);
    await start(
        tester,
        (c) => ArticleFlow.open(c, org: _shop, retail: shelf, store: MemoryFlowStore()),
        []);
    await tester.enterText(find.byKey(const Key('article-name')), 'savon citec');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('article-known')), findsOneWidget);
    await next(tester);
    expect(question(tester), 'Prix d\'achat ?', reason: 'its price is set already');
    await next(tester);
    expect(question(tester), 'Combien arrivent ?');
    expect(find.text('Déjà en stock : 9'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('article-quantity')), '12');
    await tester.pump();
    await next(tester);
    expect(question(tester), 'Autres détails', reason: 'no alert, vitrine, production: set already');
    await next(tester);
    expect(find.text('21'), findsOneWidget, reason: 'stock after');
    await tester.tap(find.byKey(const Key('flow-save')));
    await tester.pumpAndSettle();
    expect(shelf.log, [
      'ensure Savon Citec price=null cost=null code=null service=false',
      'receive p1 12.0 cost=null',
    ]);
    expect(shelf.updates, isEmpty, reason: 'nothing of the article itself is rewritten');
  });

  testWidgets('a refused offline sale\'s « Corriger le stock »: opens on the article and the number missing',
      (tester) async {
    await phone(tester);
    final shelf = _Shelf(shelf: const [Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 2)]);
    await start(
        tester,
        (c) => ArticleFlow.open(c,
            org: _shop, retail: shelf, initialName: 'Savon', initialQuantity: 1, store: MemoryFlowStore()),
        []);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('article-known')), findsOneWidget);
    await next(tester);
    await next(tester);
    expect(tester.widget<FlowNumberField>(find.byKey(const Key('article-quantity'))).controller.text, '1');
  });

  testWidgets('a scanned code never seen goes onto the new article', (tester) async {
    await phone(tester);
    final shelf = _Shelf();
    await start(
        tester,
        (c) => ArticleFlow.open(c, org: _shop, retail: shelf, barcode: '6001', store: MemoryFlowStore()),
        []);
    await tester.enterText(find.byKey(const Key('article-name')), 'Lait');
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      if (find.byKey(const Key('flow-next')).evaluate().isEmpty) break;
      if (question(tester) == 'Prix de vente ?') {
        await tester.enterText(find.byKey(const Key('article-price')), '500');
        await tester.pump();
      }
      await next(tester);
    }
    await tester.tap(find.byKey(const Key('flow-save')));
    await tester.pumpAndSettle();
    expect(shelf.log.first, contains('code=6001'));
  });

  testWidgets('Production\'s « Ajoutez d\'abord vos ingrédients » (W3): opens on Oui', (tester) async {
    await phone(tester);
    final shelf = _Shelf();
    await start(
        tester,
        (c) => ArticleFlow.open(c, org: _shop, retail: shelf, ingredient: true, store: MemoryFlowStore()),
        []);
    await tester.enterText(find.byKey(const Key('article-name')), 'Farine');
    await tester.pump();
    while (question(tester) != 'Utilisé en production ?') {
      if (question(tester) == 'Prix de vente ?') {
        await tester.enterText(find.byKey(const Key('article-price')), '0');
        await tester.pump();
      }
      await next(tester);
    }
    final yes = tester.widget<Material>(find
        .ancestor(of: find.byKey(const Key('flow-option-true')), matching: find.byType(Material))
        .first);
    expect(yes.color, isNot(Colors.transparent));
    expect(find.descendant(of: find.byKey(const Key('flow-option-true')), matching: find.byIcon(Icons.check_circle)),
        findsOneWidget);
  });

  testWidgets('no signal: said, nothing saved, the answers kept — online only, as the sheet was',
      (tester) async {
    await phone(tester);
    final store = MemoryFlowStore();
    await start(
        tester,
        (c) => ArticleFlow.open(c, org: _shop, retail: _Shelf(offline: true), store: store),
        []);
    await tester.enterText(find.byKey(const Key('article-name')), 'Savon');
    await tester.pump();
    while (find.byKey(const Key('flow-next')).evaluate().isNotEmpty) {
      if (question(tester) == 'Prix de vente ?') {
        await tester.enterText(find.byKey(const Key('article-price')), '450');
        await tester.pump();
      }
      await next(tester);
    }
    await tester.tap(find.byKey(const Key('flow-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flow-error')), findsOneWidget);
    expect(find.byKey(const Key('flow-summary')), findsOneWidget);
    expect(store.values['step_flow:article:o1'], contains('Savon'));
  });

  testWidgets('a photo « Choisir dans Photos » goes onto the new article', (tester) async {
    await phone(tester);
    final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
    addTearDown(() => tester.runAsync(db.close));
    final photos = _Photos(db: db);
    final shelf = _Shelf();
    await start(
        tester,
        (c) => ArticleFlow.open(c, org: _shop, retail: shelf, capture: photos, store: MemoryFlowStore()),
        []);
    expect(question(tester), 'Une photo ?');
    await tester.tap(find.byKey(const Key('article-photo-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-from-photos')));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo-library-d1')));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('Changer la photo'), findsOneWidget);
    await next(tester);
    await tester.enterText(find.byKey(const Key('article-name')), 'Savon');
    await tester.pump();
    while (find.byKey(const Key('flow-next')).evaluate().isNotEmpty) {
      if (question(tester) == 'Prix de vente ?') {
        await tester.enterText(find.byKey(const Key('article-price')), '450');
        await tester.pump();
      }
      await next(tester);
    }
    await tester.tap(find.byKey(const Key('flow-save')));
    await tester.pumpAndSettle();
    expect(photos.filed, ['d1→new-1']);
  });

  group('the farm', () {
    testWidgets('first: for sale or a supply — a supply goes on to « Réception » (offline, as always)',
        (tester) async {
      await phone(tester);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      await start(
          tester,
          (c) => ArticleFlow.open(c, org: _farm, retail: _Shelf(), db: db, store: MemoryFlowStore()),
          []);
      expect(question(tester), 'C\'est pour quoi ?');
      expect(find.text('C\'est pour vendre'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-option-supply')));
      await tester.pumpAndSettle();
      expect(find.text('Réception'), findsWidgets, reason: 'the farm\'s Réception flow');
      expect(find.text('C\'est pour quoi ?'), findsNothing);
    });

    testWidgets('for sale, grown: counted by hand, no purchase; on the vitrine by default',
        (tester) async {
      await phone(tester);
      final shelf = _Shelf();
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      await start(
          tester,
          (c) => ArticleFlow.open(c, org: _farm, retail: shelf, db: db, store: MemoryFlowStore()),
          []);
      await tester.tap(find.byKey(const Key('flow-option-sell')));
      await tester.pumpAndSettle();
      await next(tester);
      expect(question(tester), 'Quel produit ?');
      await tester.enterText(find.byKey(const Key('article-name')), 'Œufs frais');
      await tester.pump();
      await next(tester);
      await tester.enterText(find.byKey(const Key('article-price')), '2500');
      await tester.pump();
      await next(tester);
      expect(find.textContaining('ce que vous produisez n\'en a pas'), findsOneWidget);
      await next(tester);
      await tester.enterText(find.byKey(const Key('article-quantity')), '30');
      await tester.tap(find.byKey(const ValueKey('article-unit-plateau')));
      await tester.pump();
      await next(tester);
      await next(tester);
      await next(tester); // vitrine: Oui by default on a farm
      await next(tester);
      expect(question(tester), 'Déjà prêt ?');
      await next(tester);
      expect(find.text('Produit par la ferme : compté, sans achat.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(shelf.log, ['ensure Œufs frais price=2500.0 cost=null code=null service=false']);
      expect(shelf.updates.single['quantity'], 30.0);
      expect(shelf.updates.single['published'], isTrue);
      expect(shelf.updates.single['unit'], 'plateau');
    });

    testWidgets('for sale, bought to resell: received, the purchase booked', (tester) async {
      await phone(tester);
      final shelf = _Shelf();
      await start(
          tester,
          (c) => ArticleFlow.open(c, org: _farm, retail: shelf, forSale: true, store: MemoryFlowStore()),
          []);
      expect(question(tester), 'Quel produit ?', reason: 'from « À vendre »: no kind question');
      await tester.enterText(find.byKey(const Key('article-name')), 'Poussins');
      await tester.pump();
      await next(tester);
      await tester.enterText(find.byKey(const Key('article-price')), '800');
      await tester.pump();
      await next(tester);
      await tester.enterText(find.byKey(const Key('article-cost')), '500');
      await tester.pump();
      await next(tester);
      await tester.enterText(find.byKey(const Key('article-quantity')), '100');
      await tester.pump();
      while (find.byKey(const Key('flow-next')).evaluate().isNotEmpty) {
        await next(tester);
      }
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(shelf.log.last, 'receive new-1 100.0 cost=500.0');
      expect(shelf.updates.single['quantity'], isNull);
    });
  });

  testWidgets('Articles: « Ajouter un article » opens the flow (the old « Entrée de stock » sheet is gone)',
      (tester) async {
    await phone(tester);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: ProductsScreen(org: _shop, retail: _Shelf()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Entrée de stock'), findsNothing);
    await tester.tap(find.byKey(const Key('products-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flow-step-name')), findsOneWidget);
  });
}
