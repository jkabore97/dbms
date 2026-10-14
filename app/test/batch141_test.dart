// Batch 141 (136): read and see an item before ordering it — a description
// in every add flow and edit sheet, a service's duration in its own field,
// several photos per item (the cover first; Mara Pro past the first), and
// the vitrine's item page: a carousel, full screen with pinch-zoom, the
// words with « Lire la suite », the basket's button pinned at the foot.
//
// B141_SHOTS=<dir> also writes the screenshots (390 × 844 and 320 px at
// text × 1.3, French and English).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/capture/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/retail/duration.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/farm/for_sale_screen.dart';
import 'package:kaj_app/features/retail/article_flow.dart';
import 'package:kaj_app/features/retail/item_details.dart';
import 'package:kaj_app/features/retail/products_screen.dart';
import 'package:kaj_app/features/services/service_flow.dart';
import 'package:kaj_app/features/services/services_screen.dart';
import 'package:kaj_app/features/storefront/item_page.dart';
import 'package:kaj_app/features/storefront/shop_style.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// The businesses (Ouagadougou only; brand-like names, no first names)
// ---------------------------------------------------------------------------
const _shop = OrgSummary(id: 'o-shop', name: 'Maison Élégance', profile: 'retail', roles: ['owner']);
const _shopPro =
    OrgSummary(id: 'o-shop', name: 'Maison Élégance', profile: 'retail', roles: ['owner'], plan: 'pro');
const _farm = OrgSummary(id: 'o-farm', name: 'Ferme Horizon Vert', profile: 'farm', roles: ['owner']);
const _association =
    OrgSummary(id: 'o-asso', name: 'Cercle des Bâtisseurs', profile: 'association', roles: ['owner']);
const _salon = OrgSummary(id: 'o-salon', name: 'Salon Prestige', profile: 'retail', roles: ['owner']);

/// A 1×1 PNG.
final _pixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x50,
  0x0F, 0x00, 0x04, 0x85, 0x01, 0x80, 0x84, 0xA9, 0x8C, 0x21, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// The photographs the screenshots show: drawn here (cloth, a bird, a hall),
/// a pixel for the plain tests.
final _art = <String, Uint8List>{};
Uint8List _bytes(String key) => _art[key] ?? _pixel;

Future<Uint8List> _draw(int seed) async {
  const w = 800.0, h = 640.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const palettes = [
    [Color(0xFF6B3E26), Color(0xFFC9A27E), Color(0xFFF2E6D8)],
    [Color(0xFF2F4A3A), Color(0xFF8DB38B), Color(0xFFEFE9D6)],
    [Color(0xFF7A2E2E), Color(0xFFE0A458), Color(0xFFF7EBDD)],
    [Color(0xFF29323C), Color(0xFF6E8CA0), Color(0xFFE9EEF2)],
    [Color(0xFF5A4632), Color(0xFFD9B88F), Color(0xFFFFF8EE)],
  ];
  final p = palettes[seed % palettes.length];
  c.drawRect(const Rect.fromLTWH(0, 0, w, h),
      Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(w, h), [p[2], p[1]]));
  final r = math.Random(seed);
  if (seed % 3 == 0) {
    // Folded cloth.
    for (var i = 0; i < 9; i++) {
      final y = 80.0 + i * 55;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(120, y, 560, 40), const Radius.circular(18)),
          Paint()..color = (i.isEven ? p[0] : p[1]).withValues(alpha: 0.85));
    }
  } else if (seed % 3 == 1) {
    // A bird, plump.
    c.drawOval(const Rect.fromLTWH(220, 200, 360, 260), Paint()..color = p[0]);
    c.drawCircle(const Offset(560, 220), 70, Paint()..color = p[0]);
    c.drawCircle(const Offset(585, 205), 10, Paint()..color = p[2]);
    c.drawPath(
        Path()
          ..moveTo(625, 215)
          ..lineTo(690, 235)
          ..lineTo(625, 250),
        Paint()..color = const Color(0xFFE0A030));
  } else {
    // A hall: rows of chairs.
    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 8; col++) {
        c.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(110.0 + col * 75, 230.0 + row * 70, 50, 45),
                const Radius.circular(8)),
            Paint()..color = p[0].withValues(alpha: 0.6 + r.nextDouble() * 0.4));
      }
    }
    c.drawRect(const Rect.fromLTWH(160, 80, 480, 100), Paint()..color = p[0]);
  }
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------
class _Retail extends RetailRepository {
  _Retail({this.shelf = const [], bool missing = false, this.limit = 5, List<GalleryPhoto>? photos})
      : held = photos ?? [],
        super(null) {
    itemPhotosMissing = missing;
  }

  final List<Product> shelf;
  final int limit;
  final List<GalleryPhoto> held;
  final log = <String>[];
  final updates = <Map<String, Object?>>[];

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => shelf;

  @override
  Future<Map<String, String>> photoKeys(String orgId) async =>
      {for (final p in shelf) if (held.isNotEmpty) p.id: held.first.photoKey};

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
    log.add('ensure $name');
    return 'p-new';
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
      log.add('receive $productId $quantity');

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
    bool? stockTracked,
  }) async =>
      updates.add({'id': productId, 'description': description});

  @override
  Future<void> setServiceDuration(String productId, int? minutes, {String? description}) async =>
      log.add('duration $productId $minutes');

  ItemGallery get _now => ItemGallery(photos: [...held], limit: limit);

  @override
  Future<ItemGallery?> gallery(String productId) async => _now;

  @override
  Future<ItemGallery?> addPhoto(String productId, String documentId) async {
    log.add('add $documentId');
    held.add(GalleryPhoto(documentId: documentId, photoKey: 'org/o/$documentId.jpg'));
    return _now;
  }

  @override
  Future<ItemGallery?> orderPhotos(String productId, List<String> documentIds) async {
    log.add('order ${documentIds.join(',')}');
    final by = {for (final p in held) p.documentId: p};
    held
      ..clear()
      ..addAll([for (final id in documentIds) by[id]!]);
    return _now;
  }

  @override
  Future<ItemGallery?> removePhoto(String productId, String documentId) async {
    log.add('remove $documentId');
    held.removeWhere((p) => p.documentId == documentId);
    return _now;
  }
}

/// A refused reorder (no network, the server says no).
class _FailingOrder extends _Retail {
  _FailingOrder({super.photos}) : super(limit: 5);
  @override
  Future<ItemGallery?> orderPhotos(String productId, List<String> documentIds) async {
    log.add('order refused');
    throw Exception('network down');
  }
}

/// 136 there, but the gallery cannot be read (no network).
class _NoGallery extends _Retail {
  _NoGallery({super.shelf});
  @override
  Future<ItemGallery?> gallery(String productId) async => throw Exception('network down');
}

class _Capture extends CaptureRepository {
  _Capture({required super.db, this.library = const []}) : super(null);

  final List<CapturedDocument> library;

  @override
  bool get isConfigured => true;

  @override
  Future<Uint8List> objectBytes(String key) async => _bytes(key);

  @override
  Future<Uint8List> publicObjectBytes(String key, {int? width}) async => _bytes(key);

  @override
  Future<List<CapturedDocument>> documents(String orgId,
          {String? kind, int limit = 60, int offset = 0}) async =>
      library;
}

// ---------------------------------------------------------------------------
// Hosts
// ---------------------------------------------------------------------------
Future<void> _size(WidgetTester tester, double w, double h, {double text = 1}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget home, {String lang = 'fr'}) => MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      debugShowCheckedModeBanner: false,
      // Around the navigator: the sheets and full screen are in the shot.
      builder: (context, child) => RepaintBoundary(key: const Key('shot'), child: child!),
      home: home,
    );

/// An edit sheet as the screens open it: « Enregistrer » closes it.
Future<void> _sheet(WidgetTester tester, Widget sheet) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_app(Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          key: const Key('open-sheet'),
          onPressed: () => showModalBottomSheet<bool>(
              context: context, isScrollControlled: true, builder: (_) => sheet),
          child: const Text('open'),
        ),
      ),
    ),
  )));
  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('flow-next')));
  await tester.pumpAndSettle();
}

String _question(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('flow-question'))).data!;

/// Opens the vitrine's item page for [item], as the vitrine does.
Future<void> _openItem(WidgetTester tester, PublicItem item, _Capture capture,
    {String lang = 'fr', double quantity = 0}) async {
  // A fresh navigator: the previous page closed.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_app(
      Builder(
        builder: (outer) => Theme(
          data: ShopStyle.theme(outer),
          child: Builder(builder: (context) => Scaffold(
            backgroundColor: ShopStyle.paper,
            body: Center(
              child: TextButton(
                key: const Key('open-item'),
                onPressed: () => showShopSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (sheet) => Theme(
                    data: ShopStyle.theme(sheet),
                    child: ArticleSheet(
                      item: item,
                      shopName: 'Maison Élégance',
                      currency: 'XOF',
                      phone: '+22670000000',
                      capture: capture,
                      quantity: quantity,
                      onAdd: () {},
                      onRemove: () {},
                      onOpen: (_) async {},
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          )),
        ),
      ),
      lang: lang));
  await tester.tap(find.byKey(const Key('open-item')));
  await tester.pumpAndSettle();
}

const _long = 'Pagne wax cousu à la main dans notre atelier de Ouagadougou.\n'
    'Coton 100 %, couleurs qui tiennent au lavage.\n'
    'Tailles : M, L, XL — dites-nous la vôtre en commandant.\n'
    'Lavable en machine à 30 °C, séchage à l\'ombre.\n'
    'Livré plié, dans son sac en tissu.\n'
    'Chaque pièce est unique : le motif peut varier légèrement.\n'
    'Retouche offerte sous 7 jours si la taille ne convient pas.\n'
    'Disponible aussi en ensemble avec le foulard assorti.';

PublicItem _pagne({int photos = 3, String? description = _long}) => PublicItem(
      id: 'i-pagne',
      name: 'Pagne wax Prestige',
      price: 15000,
      inStock: true,
      stockLeft: 6,
      photoKey: photos == 0 ? null : 'p/pagne-0',
      photoKeys: [for (var i = 0; i < photos; i++) 'p/pagne-$i'],
      description: description,
    );

const _poulets = PublicItem(
  id: 'i-poulets',
  name: 'Poulets fermiers',
  price: 4500,
  inStock: true,
  unit: 'tête',
  photoKey: 'p/poulet-0',
  photoKeys: ['p/poulet-0', 'p/poulet-1'],
  description: 'Poulets élevés en plein air, 45 jours, environ 1,8 kg.\nPlumés sur demande.',
);

const _coupe = PublicItem(
  id: 'i-coupe',
  name: 'Coupe et coiffage',
  price: 5000,
  inStock: true,
  isService: true,
  priceFrom: true,
  photoKey: 'p/salle-0',
  durationMinutes: 45,
  description: 'Coupe, shampoing et coiffage.\nSur rendez-vous, du mardi au samedi.',
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  late LocalDb db;
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() => db.close());

  // -------------------------------------------------------------------------
  group('the duration (136)', () {
    test('minutes read the way the flow wrote them, and written back', () {
      expect(durationMinutesOf('Durée : 1 h'), 60);
      expect(durationMinutesOf('une demi-journée'), 240);
      expect(durationMinutesOf('une journée'), 480);
      expect(durationMinutesOf('1 h 30'), 90);
      expect(durationMinutesOf('1h30'), 90);
      expect(durationMinutesOf('2 heures'), 120);
      expect(durationMinutesOf('45 min'), 45);
      expect(durationMinutesOf('90 minutes'), 90);
      expect(durationMinutesOf('3 séances'), isNull);
      expect(formatDuration(45), '45\u00a0min', reason: 'never parted on screen');
      expect(formatDuration(60), '1\u00a0h');
      expect(formatDuration(60, plain: true), '1 h');
      expect(formatDuration(90), '1\u00a0h\u00a030');
      expect(RetailRepository.legacyDurationDescription(60, 'Shampoing compris'),
          'Durée : 1 h\nShampoing compris');
    });

    test('the vitrine says the column, or the old first line, never twice', () {
      var w = serviceWords(isService: true, minutes: 60, description: 'Durée : 1 h\nShampoing compris');
      expect(w.duration, '1\u00a0h');
      expect(w.description, 'Shampoing compris');
      // Before the backfill: the old line read.
      w = serviceWords(isService: true, description: 'Durée : 2 h');
      expect(w.duration, '2\u00a0h');
      expect(w.description, isNull);
      w = serviceWords(isService: true, description: 'Durée : 3 séances\nEn groupe');
      expect(w.duration, '3 séances');
      expect(w.description, 'En groupe');
      // An article's words are its own.
      w = serviceWords(isService: false, description: 'Durée : 1 h');
      expect(w.duration, isNull);
      expect(w.description, 'Durée : 1 h');
    });
  });

  // -------------------------------------------------------------------------
  group('« Décrivez-le en quelques mots » in every add flow', () {
    Future<_Retail> walk(WidgetTester tester, OrgSummary org,
        {String? words, bool forSale = false, bool missing = false, String lang = 'fr'}) async {
      await _size(tester, 390, 1000);
      final retail = _Retail(missing: missing);
      await tester.pumpWidget(_app(
          ArticleFlow(org: org, retail: retail, forSale: true, store: MemoryFlowStore()),
          lang: lang));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('article-name')), 'Un article');
      await tester.pump();
      await _next(tester);
      await tester.enterText(find.byKey(const Key('article-price')), '2500');
      await tester.pump();
      await _next(tester);
      return retail;
    }

    Future<void> finish(WidgetTester tester) async {
      for (var i = 0; i < 12 && find.byKey(const Key('flow-save')).evaluate().isEmpty; i++) {
        await _next(tester);
      }
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
    }

    for (final (org, example) in [
      (_shop, 'Coton, taille M à XL, lavable en machine'),
      (_farm, 'Poulets élevés en plein air, 45 jours, environ 1,8 kg'),
      (_association, 'Salle de 80 places, chaises et sono comprises'),
    ]) {
      testWidgets('${org.profile}: after the price, its example; « Passer » empty; written, saved',
          (tester) async {
        final retail = await walk(tester, org);
        expect(_question(tester), 'Décrivez-le en quelques mots');
        expect(find.text('(facultatif)'), findsOneWidget);
        expect(find.text('Par exemple : $example'), findsOneWidget);
        expect(find.text('Passer'), findsOneWidget);
        final field = tester.widget<TextField>(
            find.descendant(of: find.byKey(const Key('article-description')), matching: find.byType(TextField)));
        expect(field.maxLength, 1000);
        await tester.enterText(find.byKey(const Key('article-description')), 'Ligne une\nLigne deux');
        await tester.pump();
        expect(find.text('Suivant'), findsOneWidget);
        expect(find.text('20/1000'), findsOneWidget, reason: 'the counter');
        await finish(tester);
        // Its own write, after the unit, the count and the vitrine (one
        // refusal never takes them with it).
        expect(retail.updates, hasLength(2));
        expect(retail.updates.first['description'], isNull);
        expect(retail.updates.last['description'], 'Ligne une\nLigne deux', reason: 'line breaks kept');
      });
    }

    testWidgets('« Passer »: nothing written', (tester) async {
      final retail = await walk(tester, _farm);
      await _next(tester);
      expect(_question(tester), isNot('Décrivez-le en quelques mots'));
      await finish(tester);
      expect(retail.updates.single['description'], isNull);
    });

    testWidgets('a database before 136: the step still asks, 300 characters (064)', (tester) async {
      await walk(tester, _shop, missing: true);
      expect(_question(tester), 'Décrivez-le en quelques mots');
      final field = tester.widget<TextField>(
          find.descendant(of: find.byKey(const Key('article-description')), matching: find.byType(TextField)));
      expect(field.maxLength, 300);
    });

    testWidgets('a service: its duration, then its words', (tester) async {
      await _size(tester, 390, 1000);
      final retail = _Retail();
      await tester.pumpWidget(_app(ServiceFlow(org: _salon, retail: retail, store: MemoryFlowStore())));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('service-flow-name')), 'Coupe et coiffage');
      await tester.pump();
      await _next(tester);
      await tester.enterText(find.byKey(const Key('service-flow-price')), '5000');
      await tester.pump();
      await _next(tester);
      expect(_question(tester), 'Combien de temps ?');
      expect(find.text('Passer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('duration-other')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('duration-minutes')), '50');
      await tester.pump();
      await _next(tester);
      expect(_question(tester), 'Décrivez-le en quelques mots');
      expect(find.text('Par exemple : Coupe, shampoing et coiffage, environ 45 min'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('service-flow-description')), 'Shampoing compris');
      await tester.pump();
      await _next(tester);
      await _next(tester);
      expect(find.text('50\u00a0min'), findsOneWidget, reason: 'the summary');
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(retail.updates.map((u) => u['description']), [null, 'Shampoing compris'],
          reason: 'the words their own write, after the name and the price');
      expect(retail.log, contains('duration p-new 50'));
    });

    testWidgets('in English', (tester) async {
      await walk(tester, _shop, lang: 'en');
      expect(_question(tester), 'Describe it in a few words');
      expect(find.text('For example: Cotton, sizes M to XL, machine washable'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('the edit sheets', () {
    testWidgets('a farm item and an association article: 1,000 characters, the kind\'s example',
        (tester) async {
      await _size(tester, 390, 1400);
      for (final (org, example) in [
        (_farm, 'Poulets élevés en plein air, 45 jours, environ 1,8 kg'),
        (_association, 'Salle de 80 places, chaises et sono comprises'),
      ]) {
        final retail = _Retail();
        await _sheet(
            tester,
            ForSaleSheet(
                org: org,
                retail: retail,
                product: const Product(id: 'p1', name: 'Poulets fermiers', salePrice: 4500, quantity: 8)));
        final field = tester.widget<TextField>(find.descendant(
            of: find.byKey(const Key('for-sale-description')), matching: find.byType(TextField)));
        expect(field.maxLength, 1000);
        expect(find.text('Par exemple : $example'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('for-sale-description')), 'Nouvelle description');
        await tester.tap(find.byKey(const Key('for-sale-save')));
        await tester.pumpAndSettle();
        expect(retail.updates.single['description'], 'Nouvelle description');
      }
    });

    testWidgets('a service: the duration\'s own field, the old « Durée : » line moved into it',
        (tester) async {
      await _size(tester, 390, 1600);
      final retail = _Retail();
      await _sheet(tester, (
          ServiceSheet(
              org: _salon,
              retail: retail,
              service: const Product(
                  id: 's1',
                  name: 'Coupe et coiffage',
                  salePrice: 5000,
                  isService: true,
                  description: 'Durée : 1 h\nShampoing compris'))));
      expect(find.byKey(const Key('service-duration')), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('duration-60')));
      expect(chip.selected, isTrue, reason: 'read off the old line');
      expect(tester.widget<TextField>(find.descendant(
              of: find.byKey(const Key('service-description')), matching: find.byType(TextField)))
          .controller!
          .text, 'Shampoing compris');
      await tester.tap(find.byKey(const Key('service-save')));
      await tester.pumpAndSettle();
      expect(retail.updates.single['description'], 'Shampoing compris');
      expect(retail.log, ['duration s1 60'], reason: 'moved into its column');
    });

    testWidgets('a service before 136: no duration field, the words as they are', (tester) async {
      await _size(tester, 390, 1600);
      final retail = _Retail(missing: true);
      await _sheet(tester, (
          ServiceSheet(
              org: _salon,
              retail: retail,
              service: const Product(
                  id: 's1', name: 'Coupe', salePrice: 5000, isService: true, description: 'Durée : 1 h'))));
      expect(find.byKey(const Key('service-duration')), findsNothing);
      expect(tester.widget<TextField>(find.descendant(
              of: find.byKey(const Key('service-description')), matching: find.byType(TextField)))
          .maxLength, 300);
    });

    testWidgets('the shop\'s article: 1,000 characters and its photos', (tester) async {
      await _size(tester, 800, 1600);
      final retail = _Retail(
        shelf: const [Product(id: 'p1', name: 'Pagne wax Prestige', salePrice: 15000, quantity: 6, isPublished: true)],
        photos: [
          const GalleryPhoto(documentId: 'd0', photoKey: 'p/pagne-0'),
          const GalleryPhoto(documentId: 'd1', photoKey: 'p/pagne-1'),
        ],
      );
      final capture = _Capture(db: db, library: const [
        CapturedDocument(id: 'd0', key: 'p/pagne-0', contentType: 'image/jpeg', productId: 'p1'),
      ]);
      await tester.pumpWidget(_app(ProductsScreen(org: _shopPro, retail: retail, capture: capture)));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Sur la vitrine — modifier'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
          find.descendant(of: find.byKey(const Key('product-description')), matching: find.byType(TextField)));
      expect(field.maxLength, 1000);
      expect(find.byKey(const Key('item-photo-strip')), findsOneWidget);
      expect(find.text('Photos de l\'article · 2 / 5'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('the photos in the edit sheet: Basic and Pro', () {
    Future<_Retail> strip(WidgetTester tester, {required int limit, required int count, String lang = 'fr'}) async {
      await _size(tester, 390, 700);
      final retail = _Retail(limit: limit, photos: [
        for (var i = 0; i < count; i++) GalleryPhoto(documentId: 'd$i', photoKey: 'p/pagne-$i'),
      ]);
      await tester.pumpWidget(_app(
          Scaffold(
              body: Padding(
            padding: const EdgeInsets.all(16),
            child: ItemPhotoStrip(
                org: limit > 1 ? _shopPro : _shop,
                retail: retail,
                capture: _Capture(db: db, library: const [
                  CapturedDocument(id: 'lib1', key: 'p/lib1', contentType: 'image/jpeg'),
                ]),
                productId: 'p1',
                name: 'Pagne wax Prestige'),
          )),
          lang: lang));
      await tester.pumpAndSettle();
      return retail;
    }

    testWidgets('Basic: the cover alone; « + » is the Pro door, nothing added', (tester) async {
      final retail = await strip(tester, limit: 1, count: 1);
      expect(find.text('Plusieurs photos par article avec Mara Pro.'), findsOneWidget);
      expect(find.text('Pro'), findsOneWidget);
      await tester.tap(find.byKey(const Key('item-photo-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('more-photos-pro')), findsOneWidget);
      expect(find.text('Plusieurs photos par article'), findsOneWidget);
      expect(retail.log, isEmpty);
    });

    testWidgets('Pro: « + » takes a photo from « Photos », last', (tester) async {
      final retail = await strip(tester, limit: 5, count: 2);
      expect(find.text('Photos de l\'article · 2 / 5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('item-photo-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-from-photos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo-library-lib1')));
      await tester.pumpAndSettle();
      expect(retail.log, ['add lib1']);
      expect(find.text('Photos de l\'article · 3 / 5'), findsOneWidget);
    });

    testWidgets('Pro at its limit: no « + »', (tester) async {
      await strip(tester, limit: 5, count: 5);
      expect(find.byKey(const Key('item-photo-add')), findsNothing);
      expect(find.text('Photos de l\'article · 5 / 5'), findsOneWidget);
    });

    testWidgets('« Mettre en premier » and « Retirer la photo »', (tester) async {
      final retail = await strip(tester, limit: 5, count: 3);
      expect(find.text('Couverture'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('item-photo-d2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-photo-first')));
      await tester.pumpAndSettle();
      expect(retail.log, ['order d2,d0,d1']);
      await tester.tap(find.byKey(const ValueKey('item-photo-d1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-photo-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-photo-remove-yes')));
      await tester.pumpAndSettle();
      expect(retail.log.last, 'remove d1');
      expect(find.text('Photos de l\'article · 2 / 5'), findsOneWidget);
    });

    testWidgets('a long press drags a photo into place', (tester) async {
      final retail = await strip(tester, limit: 5, count: 3);
      final from = tester.getCenter(find.byKey(const ValueKey('item-photo-d2')));
      final to = tester.getCenter(find.byKey(const ValueKey('item-photo-d0')));
      final g = await tester.startGesture(from);
      await tester.pump(const Duration(seconds: 1));
      // In small steps, as a finger does, to before the first photo.
      for (var i = 1; i <= 20; i++) {
        await g.moveTo(Offset.lerp(from, to - const Offset(45, 0), i / 20)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      await tester.pumpAndSettle();
      expect(retail.log.single, 'order d2,d0,d1');
    });

    testWidgets('in English', (tester) async {
      await strip(tester, limit: 1, count: 1, lang: 'en');
      expect(find.text('Several photos per item with Mara Pro.'), findsOneWidget);
      expect(find.text('Item photos'), findsOneWidget);
    });

    test('the setting is on « Pro et prix », 1 to 20', () {
      expect(settingCardOf('max_item_photos_pro')?.key, 'pro');
      expect(rangedSettings['max_item_photos_pro'], (1, 20));
      expect(platformSettingDefs.map((d) => d.key), contains('max_item_photos_pro'));
    });

    test('a gallery read: its room', () {
      final g = ItemGallery.fromJson({
        'limit': 5,
        'photos': [
          {'document_id': 'd0', 'photo_key': 'k0'},
          {'document_id': 'd1', 'photo_key': 'k1'},
        ],
      });
      expect(g.photos.map((p) => p.photoKey), ['k0', 'k1']);
      expect(g.hasRoom, isTrue);
      expect(g.coverOnly, isFalse);
      expect(ItemGallery.fromJson({'limit': 1, 'photos': []}).coverOnly, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('the vitrine\'s item page', () {
    test('the shelf reads photo_keys and the duration; an older row its one photo', () {
      final item = PublicItem.fromRow({
        'id': 'i1', 'name': 'Pagne', 'sale_price': 15000, 'in_stock': true,
        'photo_key': 'k0', 'photo_keys': ['k0', 'k1', 'k2'], 'duration_minutes': null,
      });
      expect(item.photos, ['k0', 'k1', 'k2']);
      final old = PublicItem.fromRow({'id': 'i1', 'name': 'Pagne', 'sale_price': 1, 'in_stock': true, 'photo_key': 'k0'});
      expect(old.photos, ['k0']);
      final none = PublicItem.fromRow({'id': 'i1', 'name': 'Pagne', 'sale_price': 1, 'in_stock': true});
      expect(none.photos, isEmpty);
      final svc = PublicItem.fromRow({'id': 's', 'name': 'Coupe', 'sale_price': 1, 'is_service': true, 'duration_minutes': 45});
      expect(svc.durationMinutes, 45);
    });

    testWidgets('one photo: drawn as before — no dots, no count; a tap opens it full screen',
        (tester) async {
      await _size(tester, 390, 844);
      await _openItem(tester, _pagne(photos: 1, description: 'Court.'), _Capture(db: db));
      expect(find.byKey(const Key('item-carousel-single')), findsOneWidget);
      expect(find.byKey(const Key('item-carousel-dots')), findsNothing);
      expect(find.byKey(const Key('item-carousel-count')), findsNothing);
      await tester.tap(find.byKey(const Key('item-carousel-single')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('item-fullscreen')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byKey(const Key('item-fullscreen-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('item-fullscreen')), findsNothing);
    });

    testWidgets('three photos: dots and « 1 / 3 », a swipe to the next, full screen zooms', (tester) async {
      await _size(tester, 390, 844);
      await _openItem(tester, _pagne(), _Capture(db: db));
      expect(find.byKey(const Key('item-carousel')), findsOneWidget);
      expect(find.byKey(const Key('item-carousel-dots')), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.drag(find.byKey(const Key('item-carousel-pages')), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('item-carousel-pages')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('item-fullscreen')), findsOneWidget);
      final viewer = find.byKey(const ValueKey('item-zoom-1'));
      expect(viewer, findsOneWidget, reason: 'opened on the photo shown');
      expect(tester.widget<InteractiveViewer>(viewer).maxScale, 4);
      // A pinch zooms in.
      final c = tester.getCenter(viewer);
      final a = await tester.startGesture(c - const Offset(40, 0));
      final b = await tester.startGesture(c + const Offset(40, 0));
      await tester.pump();
      await a.moveTo(c - const Offset(140, 0));
      await b.moveTo(c + const Offset(140, 0));
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      final scale = tester.widget<InteractiveViewer>(viewer).transformationController!.value.getMaxScaleOnAxis();
      expect(scale, greaterThan(1.5));
    });

    testWidgets('« Lire la suite » past six lines, « Réduire » after; a short one has none', (tester) async {
      await _size(tester, 390, 844);
      await _openItem(tester, _pagne(), _Capture(db: db));
      expect(find.text('Description'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('item-description'))).maxLines, 6);
      await tester.ensureVisible(find.byKey(const Key('item-read-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-read-more')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('item-description'))).maxLines, isNull);
      expect(find.text('Réduire'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('item-description'))).data, contains('\n'),
          reason: 'line breaks kept');

      await _openItem(tester, _pagne(description: 'Coton, taille M.'), _Capture(db: db));
      expect(find.byKey(const Key('item-read-more')), findsNothing);
    });

    testWidgets('the basket\'s button stays at the foot while the page scrolls', (tester) async {
      await _size(tester, 390, 844);
      await _openItem(tester, _pagne(), _Capture(db: db));
      final pinned = find.byKey(const Key('item-page-pinned'));
      expect(find.descendant(of: pinned, matching: find.text('Ajouter au panier')), findsOneWidget);
      final before = tester.getRect(pinned);
      await tester.tap(find.byKey(const Key('item-read-more')).hitTestable().evaluate().isEmpty
          ? find.text('Description')
          : find.byKey(const Key('item-read-more')));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const Key('item-page-scroll')), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(pinned.hitTestable(), findsOneWidget);
      expect(tester.getRect(pinned), before, reason: 'it does not move with the words');
      expect(tester.getRect(pinned).bottom, lessThanOrEqualTo(844));
    });

    testWidgets('a farm item by the head, a service with its duration', (tester) async {
      await _size(tester, 390, 844);
      await _openItem(tester, _poulets, _Capture(db: db));
      expect(find.textContaining('tête'), findsWidgets);
      expect(find.text('En stock'), findsOneWidget);
      expect(find.text('2 / 2'), findsNothing);
      expect(find.text('1 / 2'), findsOneWidget);

      expect(find.byKey(const Key('item-read-more')), findsNothing, reason: 'three lines: whole');

      await _openItem(tester, _coupe, _Capture(db: db));
      expect(find.text('Sur rendez-vous · Durée : 45\u00a0min'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('item-page-pinned')), matching: find.text('Réserver')),
          findsOneWidget);
      // Before 136: the old line, said once.
      await _openItem(
          tester,
          const PublicItem(
              id: 's', name: 'Coupe', price: 5000, inStock: true, isService: true, description: 'Durée : 1 h'),
          _Capture(db: db));
      expect(find.text('Sur rendez-vous · Durée : 1\u00a0h'), findsOneWidget);
      expect(find.text('Durée : 1 h'), findsNothing);
      expect(find.text('Description'), findsNothing);
    });

    testWidgets('in English', (tester) async {
      await _size(tester, 390, 844);
      await _openItem(tester, _coupe, _Capture(db: db), lang: 'en');
      expect(find.text('By appointment · Duration: 45\u00a0min'), findsOneWidget);
      await _openItem(tester, _pagne(), _Capture(db: db), lang: 'en');
      expect(find.text('Read more'), findsOneWidget);
      expect(find.text('Add to basket'), findsWidgets);
    });

    for (final item in [_pagne(), _poulets, _coupe]) {
      testWidgets('320 px at text × 1.3: ${item.name} fits (no overflow)', (tester) async {
        await _size(tester, 320, 640, text: 1.3);
        await _openItem(tester, item, _Capture(db: db));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('item-page-pinned')).hitTestable(), findsOneWidget);
      });
    }

    testWidgets('320 px at text × 1.3: the describe step and the photo strip fit', (tester) async {
      await _size(tester, 320, 640, text: 1.3);
      await tester.pumpWidget(_app(ArticleFlow(org: _farm, retail: _Retail(), forSale: true, store: MemoryFlowStore())));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('article-name')), 'Poulets fermiers');
      await tester.pump();
      await _next(tester);
      await tester.enterText(find.byKey(const Key('article-price')), '4500');
      await tester.pump();
      await _next(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(_app(Scaffold(
          body: ItemPhotoStrip(
              org: _shopPro,
              retail: _Retail(photos: [
                for (var i = 0; i < 4; i++) GalleryPhoto(documentId: 'd$i', photoKey: 'k$i'),
              ]),
              capture: _Capture(db: db),
              productId: 'p1',
              name: 'Pagne'))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Screenshots (B141_SHOTS=<dir>)
  // -------------------------------------------------------------------------
  final shots = Platform.environment['B141_SHOTS'];
  group('screenshots', () {
    Future<void> realFonts() async {
      var dir = File(Platform.resolvedExecutable).parent;
      for (var i = 0; i < 6 && !Directory('${dir.path}/material_fonts').existsSync(); i++) {
        dir = dir.parent;
      }
      final fonts = Directory('${dir.path}/material_fonts');
      if (!fonts.existsSync()) return;
      final loader = FontLoader('Roboto');
      for (final f in const ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
        final file = File('${fonts.path}/$f');
        if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
      }
      await loader.load();
      final icons = File('${fonts.path}/MaterialIcons-Regular.otf');
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer))))
            .load();
      }
    }

    Future<void> art(WidgetTester tester) async {
      if (_art.isNotEmpty) return;
      await tester.runAsync(() async {
        await realFonts();
        for (var i = 0; i < 3; i++) {
          _art['p/pagne-$i'] = await _draw(i * 3);
          _art['p/poulet-$i'] = await _draw(1 + i * 3);
          _art['p/salle-$i'] = await _draw(2 + i * 3);
        }
      });
    }

    Future<void> shoot(WidgetTester tester, String name) async {
      await tester.runAsync(() async {
        for (final e in find.byType(Image).evaluate()) {
          await precacheImage((e.widget as Image).image, e);
        }
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
        final img = await ro.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    final sizes = [('390', 390.0, 844.0, 1.0), ('320x1.3', 320.0, 640.0, 1.3)];
    for (final lang in ['fr', 'en']) {
      for (final (tag, w, h, text) in sizes) {
        testWidgets('$lang $tag', (tester) async {
          Directory(shots!).createSync(recursive: true);
          await art(tester);
          await _size(tester, w, h, text: text);
          // The describe step, each kind.
          for (final (kind, org) in [('shop', _shop), ('farm', _farm), ('association', _association)]) {
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(_app(ArticleFlow(org: org, retail: _Retail(), forSale: true, store: MemoryFlowStore()),
                lang: lang));
            await tester.pumpAndSettle();
            await tester.enterText(find.byKey(const Key('article-name')), 'Article');
            await tester.pump();
            await _next(tester);
            await tester.enterText(find.byKey(const Key('article-price')), '4500');
            await tester.pump();
            await _next(tester);
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            await shoot(tester, '${lang}_${tag}_describe_$kind');
          }
          await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(_app(ServiceFlow(org: _salon, retail: _Retail(), store: MemoryFlowStore()), lang: lang));
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const Key('service-flow-name')), 'Coupe et coiffage');
          await tester.pump();
          await _next(tester);
          await tester.enterText(find.byKey(const Key('service-flow-price')), '5000');
          await tester.pump();
          await _next(tester);
          await tester.tap(find.byKey(const ValueKey('duration-45')));
          await tester.pump();
          await _next(tester);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await shoot(tester, '${lang}_${tag}_describe_service');

          // The photo editor: Pro with three, Basic with its door.
          for (final (label, org, n, limit) in [('pro', _shopPro, 3, 5), ('basic', _shop, 1, 1)]) {
            final retail = _Retail(
              limit: limit,
              shelf: const [Product(id: 'p1', name: 'Pagne wax Prestige', salePrice: 15000, quantity: 6, isPublished: true)],
              photos: [for (var i = 0; i < n; i++) GalleryPhoto(documentId: 'd$i', photoKey: 'p/pagne-$i')],
            );
            final capture = _Capture(db: db, library: const [
              CapturedDocument(id: 'd0', key: 'p/pagne-0', contentType: 'image/jpeg', productId: 'p1'),
            ]);
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(_app(ProductsScreen(org: org, retail: retail, capture: capture), lang: lang));
            await tester.pump();
            await tester.pump();
            await tester.tap(find.byTooltip(lang == 'en' ? 'On the vitrine — edit' : 'Sur la vitrine — modifier'));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byKey(const Key('item-photo-strip')));
            await tester.pumpAndSettle();
            await shoot(tester, '${lang}_${tag}_photo_editor_$label');
            if (label == 'basic') {
              await tester.tap(find.byKey(const Key('item-photo-add')));
              await tester.pumpAndSettle();
              await shoot(tester, '${lang}_${tag}_photo_editor_basic_door');
            }
          }

          // The vitrine's page: a shop's article (3 photos, long words), a
          // farm's item, a service; full screen.
          await _openItem(tester, _pagne(), _Capture(db: db), lang: lang);
          await shoot(tester, '${lang}_${tag}_page_shop');
          await tester.ensureVisible(find.byKey(const Key('item-read-more')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('item-read-more')));
          await tester.pumpAndSettle();
          await tester.drag(find.byKey(const Key('item-page-scroll')), const Offset(0, -500));
          await tester.pumpAndSettle();
          await shoot(tester, '${lang}_${tag}_page_shop_scrolled');
          await _openItem(tester, _poulets, _Capture(db: db), lang: lang);
          await shoot(tester, '${lang}_${tag}_page_farm');
          await _openItem(tester, _coupe, _Capture(db: db), lang: lang);
          await shoot(tester, '${lang}_${tag}_page_service');
          await _openItem(tester, _pagne(), _Capture(db: db), lang: lang);
          await tester.tap(find.byKey(const Key('item-carousel-pages')));
          await tester.pumpAndSettle();
          final viewer = find.byKey(const ValueKey('item-zoom-0'));
          tester.widget<InteractiveViewer>(viewer).transformationController!.value = Matrix4.identity()
            ..translateByDouble(-w * 0.5, -h * 0.4, 0, 1)
            ..scaleByDouble(2, 2, 1, 1);
          await tester.pumpAndSettle();
          await shoot(tester, '${lang}_${tag}_fullscreen_zoom');
        });
      }
    }
  }, skip: shots == null ? 'B141_SHOTS=<dir> writes the screenshots' : null);

  // -------------------------------------------------------------------------
  // The supervisor's and the bug hunt's cases (batch 141 review).
  group('one photo control in every edit sheet', () {
    const pagne = Product(id: 'p1', name: 'Pagne wax Prestige', salePrice: 15000, quantity: 6, isPublished: true);
    final photos = [
      const GalleryPhoto(documentId: 'd0', photoKey: 'p/pagne-0'),
      const GalleryPhoto(documentId: 'd1', photoKey: 'p/pagne-1'),
    ];
    _Capture capture(LocalDb db) => _Capture(db: db, library: const [
          CapturedDocument(id: 'd0', key: 'p/pagne-0', contentType: 'image/jpeg', productId: 'p1'),
        ]);

    Future<void> shopSheet(WidgetTester tester, _Retail retail) async {
      await _size(tester, 800, 1600);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(ProductsScreen(org: _shopPro, retail: retail, capture: capture(db))));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Sur la vitrine — modifier'));
      await tester.pumpAndSettle();
    }

    testWidgets('the shop\'s article: the row alone with 136; « Changer la photo » without it', (tester) async {
      await shopSheet(tester, _Retail(shelf: const [pagne], photos: photos));
      expect(find.byKey(const Key('item-photo-strip')), findsOneWidget);
      expect(find.text('Changer la photo'), findsNothing);
      expect(find.text('Ajouter une photo'), findsNothing);

      await shopSheet(tester, _Retail(shelf: const [pagne], photos: photos, missing: true));
      expect(find.byKey(const Key('item-photo-strip')), findsNothing);
      expect(find.text('Changer la photo'), findsOneWidget);

      await shopSheet(tester, _NoGallery(shelf: const [pagne]));
      expect(find.byKey(const Key('item-photo-strip')), findsNothing);
      expect(find.text('Changer la photo'), findsOneWidget, reason: 'the row unreadable: the button again');
    });

    testWidgets('the farm\'s and the association\'s sheet, the service sheet: the row alone with 136',
        (tester) async {
      await _size(tester, 390, 1600);
      for (final org in [_farm, _association]) {
        await _sheet(tester, ForSaleSheet(
            org: org, retail: _Retail(photos: photos), capture: capture(db), product: pagne, hasPhoto: true));
        expect(find.byKey(const Key('item-photo-strip')), findsOneWidget);
        expect(find.byKey(const Key('for-sale-photo')), findsNothing);
        await _sheet(tester, ForSaleSheet(
            org: org, retail: _Retail(missing: true), capture: capture(db), product: pagne, hasPhoto: true));
        expect(find.byKey(const Key('item-photo-strip')), findsNothing);
        expect(find.byKey(const Key('for-sale-photo')), findsOneWidget);
      }
      const coupe = Product(id: 's1', name: 'Coupe et coiffage', salePrice: 5000, isService: true);
      await _sheet(tester, ServiceSheet(
          org: _salon, retail: _Retail(photos: photos), capture: capture(db), service: coupe, photoKey: 'p/pagne-0'));
      expect(find.byKey(const Key('item-photo-strip')), findsOneWidget);
      expect(find.byKey(const Key('service-photo')), findsNothing);
      await _sheet(tester, ServiceSheet(
          org: _salon, retail: _NoGallery(), capture: capture(db), service: coupe, photoKey: 'p/pagne-0'));
      expect(find.byKey(const Key('item-photo-strip')), findsNothing);
      expect(find.byKey(const Key('service-photo')), findsOneWidget);
    });

    for (final (label, org, limit) in [('Basic', _shop, 1), ('Pro', _shopPro, 5)]) {
      testWidgets('$label, an item with no photo yet: « + » adds its first, no Pro door', (tester) async {
        await _size(tester, 390, 700);
        final retail = _Retail(limit: limit);
        await tester.pumpWidget(_app(Scaffold(
            body: ItemPhotoStrip(
                org: org,
                retail: retail,
                capture: _Capture(db: db, library: const [
                  CapturedDocument(id: 'lib1', key: 'p/lib1', contentType: 'image/jpeg'),
                ]),
                productId: 'p1',
                name: 'Pagne wax Prestige'))));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('item-photo-strip')), findsOneWidget);
        await tester.tap(find.byKey(const Key('item-photo-add')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('more-photos-pro')), findsNothing);
        await tester.tap(find.byKey(const Key('pick-from-photos')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('photo-library-lib1')));
        await tester.pumpAndSettle();
        expect(retail.log, ['add lib1']);
      });
    }

    testWidgets('the cover tile offers « Remplacer la photo », the others « Mettre en premier »', (tester) async {
      await _size(tester, 390, 700);
      await tester.pumpWidget(_app(Scaffold(
          body: ItemPhotoStrip(
              org: _shopPro, retail: _Retail(photos: photos), capture: _Capture(db: db),
              productId: 'p1', name: 'Pagne wax Prestige'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('item-photo-d0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('item-photo-replace')), findsOneWidget);
      expect(find.byKey(const Key('item-photo-first')), findsNothing);
    });

    testWidgets('a drag the server refuses: the order it keeps is drawn again', (tester) async {
      await _size(tester, 390, 700);
      final retail = _FailingOrder(photos: [
        for (var i = 0; i < 3; i++) GalleryPhoto(documentId: 'd$i', photoKey: 'p/pagne-$i'),
      ]);
      await tester.pumpWidget(_app(Scaffold(
          body: Padding(
              padding: const EdgeInsets.all(16),
              child: ItemPhotoStrip(
                  org: _shopPro, retail: retail, capture: _Capture(db: db),
                  productId: 'p1', name: 'Pagne wax Prestige')))));
      await tester.pumpAndSettle();
      final from = tester.getCenter(find.byKey(const ValueKey('item-photo-d2')));
      final to = tester.getCenter(find.byKey(const ValueKey('item-photo-d0')));
      final g = await tester.startGesture(from);
      await tester.pump(const Duration(seconds: 1));
      for (var i = 1; i <= 20; i++) {
        await g.moveTo(Offset.lerp(from, to - const Offset(45, 0), i / 20)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      await tester.pumpAndSettle();
      expect(retail.log, ['order refused']);
      final xs = [for (final d in ['d0', 'd1', 'd2']) tester.getCenter(find.byKey(ValueKey('item-photo-$d'))).dx];
      expect(xs[0] < xs[1] && xs[1] < xs[2], isTrue, reason: 'd0, d1, d2 as the server keeps them');
    });
  });

  group('words, durations and counts', () {
    testWidgets('a service sheet keeps « Durée : 3 séances » (and 0 or 99999 min) in its words', (tester) async {
      await _size(tester, 390, 1600);
      for (final line in ['Durée : 3 séances', 'Durée : 0 min', 'Durée : 99999 min']) {
        final retail = _Retail();
        await _sheet(tester, ServiceSheet(
            org: _salon,
            retail: retail,
            service: Product(
                id: 's1', name: 'Cours', salePrice: 5000, isService: true,
                description: '$line\nMatériel fourni')));
        await tester.tap(find.byKey(const Key('service-save')));
        await tester.pumpAndSettle();
        expect(retail.updates.single['description'], '$line\nMatériel fourni', reason: line);
        expect(retail.log, isEmpty, reason: 'no duration read, none written');
      }
    });

    testWidgets('a typed duration past 7 days is said, not dropped', (tester) async {
      await _size(tester, 390, 800);
      int? minutes;
      await tester.pumpWidget(_app(Scaffold(
          body: StatefulBuilder(
              builder: (context, set) => DurationPicker(
                  minutes: minutes, onChanged: (m) => set(() => minutes = m))))));
      await tester.tap(find.byKey(const ValueKey('duration-other')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('duration-minutes')), '20000');
      await tester.pump();
      expect(minutes, isNull);
      expect(find.text('De 1 à 10 080 minutes (7 jours).'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('duration-minutes')), '10080');
      await tester.pump();
      expect(minutes, 10080);
      expect(find.text('De 1 à 10 080 minutes (7 jours).'), findsNothing);
    });

    test('nothing read yet: 300 characters, as an older database holds', () {
      final retail = RetailRepository(null);
      expect(retail.descriptionMax, 300);
      retail.itemPhotosMissing = false;
      expect(retail.descriptionMax, 1000);
      retail.itemPhotosMissing = true;
      expect(retail.descriptionMax, 300);
      expect(RetailRepository.legacyDurationPrefix(60), 'Durée : 1 h\n'.runes.length);
      expect(RetailRepository.legacyDurationPrefix(null), 0);
    });

    testWidgets('before 136 a service\'s words leave room for « Durée : 1 h »', (tester) async {
      await _size(tester, 390, 1000);
      await tester.pumpWidget(_app(
          ServiceFlow(org: _salon, retail: _Retail(missing: true), store: MemoryFlowStore())));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('service-flow-name')), 'Coupe et coiffage');
      await tester.pump();
      await _next(tester);
      await tester.enterText(find.byKey(const Key('service-flow-price')), '5000');
      await tester.pump();
      await _next(tester);
      await tester.tap(find.byKey(const ValueKey('duration-60')));
      await tester.pump();
      await _next(tester);
      final field = tester.widget<TextField>(find.descendant(
          of: find.byKey(const Key('service-flow-description')), matching: find.byType(TextField)));
      expect(field.maxLength, 300 - 'Durée : 1 h\n'.runes.length);
      expect(RetailRepository.legacyDurationDescription(60, 'a' * field.maxLength!).runes.length, 300);
    });

    testWidgets('600 emoji are 600 characters, as Postgres counts: « Suivant » open', (tester) async {
      await _size(tester, 390, 1000);
      await tester.pumpWidget(_app(
          ArticleFlow(org: _shop, retail: _Retail(), forSale: true, store: MemoryFlowStore())));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('article-name')), 'Un article');
      await tester.pump();
      await _next(tester);
      await tester.enterText(find.byKey(const Key('article-price')), '2500');
      await tester.pump();
      await _next(tester);
      await tester.enterText(find.byKey(const Key('article-description')), '😀' * 600);
      await tester.pump();
      expect(find.text('600/1000'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('flow-next'))).onPressed, isNotNull);
    });

    testWidgets('1,000 flags are 2,000 code points: the field keeps 1,000', (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(_app(Scaffold(body: DescriptionField(controller: c, example: 'x', maxLength: 1000))));
      await tester.enterText(find.byType(TextField), '🇧🇫' * 1000);
      await tester.pump();
      expect(c.text.runes.length, 1000);
      expect(find.text('1000/1000'), findsOneWidget);
    });

    test('a card says a service\'s duration, then its words', () {
      expect(cardWords(_coupe), 'Durée : 45 min\nCoupe, shampoing et coiffage.\nSur rendez-vous, du mardi au samedi.');
      // Before 136: the old first line, read.
      expect(
          cardWords(const PublicItem(
              id: 'x', name: 'Coupe', price: 1, inStock: true, isService: true,
              description: 'Durée : 1 h\nShampoing compris')),
          'Durée : 1 h\nShampoing compris');
      expect(cardWords(_poulets), _poulets.description);
      expect(cardWords(const PublicItem(id: 'y', name: 'Savon', price: 1, inStock: true)), isNull);
    });
  });

  group('the carousel on the website', () {
    tearDown(() => ItemCarousel.debugArrows = false);

    testWidgets('a mouse drags it to the next photo', (tester) async {
      await _size(tester, 390, 844);
      await _openItem(tester, _pagne(), _Capture(db: db));
      final pages = find.byKey(const Key('item-carousel-pages'));
      final g = await tester.startGesture(tester.getCenter(pages), kind: PointerDeviceKind.mouse);
      // In steps, as a mouse reports them.
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(-30, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(
          tester.widget<Text>(find.descendant(
              of: find.byKey(const Key('item-carousel-count')), matching: find.byType(Text))).data,
          '2 / 3');
    });

    testWidgets('« ‹ » and « › » on the page and full screen', (tester) async {
      ItemCarousel.debugArrows = true;
      await _size(tester, 390, 844);
      await _openItem(tester, _pagne(), _Capture(db: db));
      String count() => tester.widget<Text>(find.descendant(
          of: find.byKey(const Key('item-carousel-count')), matching: find.byType(Text))).data!;
      expect(find.byKey(const Key('item-carousel-previous')), findsNothing, reason: 'at the first');
      await tester.tap(find.byKey(const Key('item-carousel-next')));
      await tester.pumpAndSettle();
      expect(count(), '2 / 3');
      await tester.tap(find.byKey(const Key('item-carousel-previous')));
      await tester.pumpAndSettle();
      expect(count(), '1 / 3');
      await tester.tap(find.byKey(const Key('item-carousel-pages')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('item-fullscreen-next')), findsOneWidget);
      await tester.tap(find.byKey(const Key('item-fullscreen-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('item-fullscreen-previous')), findsOneWidget);
    });

    testWidgets('a double tap zooms about the tapped spot', (tester) async {
      await _size(tester, 390, 844);
      await _openItem(tester, _pagne(), _Capture(db: db));
      await tester.tap(find.byKey(const Key('item-carousel-pages')));
      await tester.pumpAndSettle();
      const p = Offset(300, 600);
      await tester.tapAt(p);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(p);
      await tester.pumpAndSettle();
      final iv = tester.widget<InteractiveViewer>(find.byKey(const ValueKey('item-zoom-0')));
      expect(iv.transformationController!.value.getMaxScaleOnAxis(), closeTo(2.5, 0.01));
      expect((iv.transformationController!.toScene(p) - p).distance, lessThan(5));
    });
  });
}
