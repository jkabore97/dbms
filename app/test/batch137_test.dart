// Batch 137: share pictures people are proud of, and that don't all look
// the same. The owner: « the images that are being generated has only one
// type of image and one type of color. The user should have at least 3 to
// 5 choices of design, and multiple colors to choose. »
//
//   1. five designs × every colour, for a shop (no photo, one, four), long
//      names, services, a farm's units, an association, an English phone:
//      no overflow, the link, the QR code and Mara's mark on each, prices
//      written once (« FCFA », never « FCFA XOF »);
//   2. every palette's text reads on what it sits on (WCAG AA, the ratio
//      computed here, not borrowed from the app), « Ma couleur » too;
//   3. two businesses that touch nothing still post different pictures;
//   4. the choice is remembered per business, « Surprise » changes both;
//   5. the panel fits a phone, in French and in English.
//
// B137_SHOTS=<dir> also writes every design in three colours for a shop, a
// farm and an association, and the panel at 390 × 844, as PNG
// (B137_PHOTOS=<dir> gives them real photographs).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/theme/mara_mark.dart';
import 'package:kaj_app/features/storefront/share_vitrine.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A 1 × 1 PNG: a photograph's bytes, for layout.
final _pixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x50,
  0x0F, 0x00, 0x04, 0x85, 0x01, 0x80, 0x84, 0xA9, 0x8C, 0x21, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// The photographs: real ones for the screenshots when B137_PHOTOS names
/// them, a pixel otherwise.
Uint8List _photo(String name) {
  final dir = Platform.environment['B137_PHOTOS'];
  if (dir != null) {
    final f = File('$dir/$name.jpg');
    if (f.existsSync()) return f.readAsBytesSync();
  }
  return _pixel;
}

/// One case: a business, its articles, its photographs.
class _Case {
  _Case(this.label, this.shop, this.items, {Map<String, String> photos = const {}, String? cover})
      : photos = {for (final e in photos.entries) e.key: _photo(e.value)},
        cover = cover == null ? null : _photo(cover);

  final String label;
  final PublicShop shop;
  final List<PublicItem> items;
  final Map<String, Uint8List> photos;
  final Uint8List? cover;

  StatusCard card({StatusDesign? design, StatusPalette? palette}) => StatusCard(
        shop: shop,
        items: StatusCard.pick(items),
        photos: photos,
        cover: cover,
        design: design,
        palette: palette,
      );
}

PublicItem _i(String id, String name, double price,
        {bool photo = false, String? unit, bool service = false, bool from = false, DateTime? on}) =>
    PublicItem(
      id: id,
      name: name,
      price: price,
      inStock: true,
      photoKey: photo ? 'k-$id' : null,
      unit: unit,
      isService: service,
      priceFrom: from,
      availableFrom: on,
    );

final _shop4 = _Case(
  'shop-4-photos',
  const PublicShop(
    orgId: '13700000-0000-0000-0000-000000000001',
    name: 'Tony Pizza',
    slug: 'tony-pizza',
    profile: 'retail',
    blurb: 'Pizzas, burgers et fritures.',
    style: StorefrontStyle(tagline: 'La pizza du quartier, au feu de bois'),
  ),
  [
    _i('a', 'Margherita', 5000, photo: true),
    _i('b', 'Salade César', 3500, photo: true),
    _i('c', 'Jus de bissap', 1000, photo: true),
    _i('d', 'Pizza Reine', 6500, photo: true),
    _i('e', 'Frites', 1000),
  ],
  photos: {'a': 'pizza', 'b': 'salad', 'c': 'juice', 'd': 'pizza'},
  cover: 'cover',
);

final _shop1 = _Case(
  'shop-1-photo',
  const PublicShop(
    orgId: '13700000-0000-0000-0000-000000000002',
    name: 'Pagnes Awa',
    slug: 'pagnes-awa',
    profile: 'retail',
    style: StorefrontStyle(tagline: 'Wax et Faso Dan Fani'),
  ),
  [
    _i('a', 'Faso Dan Fani', 12500, photo: true),
    _i('b', 'Wax hollandais', 9000),
    _i('c', 'Bazin riche', 15000),
  ],
  photos: {'a': 'fabric'},
);

final _shop0 = _Case(
  'shop-no-photo',
  const PublicShop(
    orgId: '13700000-0000-0000-0000-000000000003',
    name: 'Boutique Awa',
    slug: 'boutique-awa',
    profile: 'retail',
  ),
  [
    _i('a', 'Savon', 250),
    _i('b', 'Riz parfumé 25 kg', 17500),
  ],
);

final _empty = _Case(
  'shop-empty',
  const PublicShop(
    orgId: '13700000-0000-0000-0000-000000000004',
    name: 'Chez Mariam',
    slug: 'chez-mariam',
    profile: 'generic',
    blurb: 'Bientôt nos articles.',
  ),
  const [],
);

final _long = _Case(
  'long-names',
  const PublicShop(
    orgId: '13700000-0000-0000-0000-000000000005',
    name: 'Quincaillerie Générale du Grand Marché de Bobo-Dioulasso',
    slug: 'quincaillerie-generale-du-grand-marche-de-bobo-dioulasso',
    profile: 'retail',
    style: StorefrontStyle(
        tagline: 'Tout pour bâtir : ciment, fer à béton, tôles, peinture et outillage — livraison en ville'),
  ),
  [
    _i('a', 'Ciment CPJ 45 sac de 50 kg qualité supérieure', 6750, photo: true),
    _i('b', 'Fer à béton de 12 mm, barre de 12 mètres', 1250000),
    _i('c', 'Tôle ondulée galvanisée 3 mètres', 4500),
    _i('d', 'Peinture à eau blanche seau de 20 litres', 27500),
  ],
  photos: {'a': 'eggs'},
);

final _services = _Case(
  'services',
  const PublicShop(
    orgId: '13700000-0000-0000-0000-000000000006',
    name: 'Salon Belle Tresse',
    slug: 'salon-belle-tresse',
    profile: 'retail',
    style: StorefrontStyle(tagline: 'Tresses, tissages, soins'),
  ),
  [
    _i('a', 'Tresses africaines', 5000, service: true, from: true),
    _i('b', 'Tissage', 7500, service: true, from: true),
    _i('c', 'Soin du cuir chevelu', 2500, service: true, unit: 'heure'),
  ],
);

final _farm = _Case(
  'farm',
  const PublicShop(
    orgId: '13700000-0000-0000-0000-000000000007',
    name: 'Ferme Wend-Panga',
    slug: 'ferme-wend-panga',
    profile: 'farm',
    blurb: 'Œufs, poulets et pintades élevés à Koubri.',
  ),
  [
    _i('a', 'Œufs frais', 2500, photo: true, unit: 'plateau'),
    _i('b', 'Poulets bicyclette', 3500, unit: 'tête'),
    _i('c', 'Pintades', 4000, unit: 'tête', on: DateTime(2026, 11, 15)),
    _i('d', 'Maïs blanc', 15000, unit: 'sac'),
  ],
  photos: {'a': 'eggs'},
);

final _association = _Case(
  'association',
  const PublicShop(
    orgId: '13700000-0000-0000-0000-000000000008',
    name: 'Association Entraide des Femmes de Tanghin',
    slug: 'entraide-tanghin',
    profile: 'association',
    style: StorefrontStyle(tagline: 'Ensemble, on va plus loin'),
  ),
  [
    _i('a', 'Cotisation mensuelle', 1000, service: true),
    _i('b', 'Formation couture', 5000, service: true, from: true, unit: 'mois'),
    _i('c', 'Location de bâches', 2500, service: true, unit: 'jour'),
  ],
);

final _own = _Case(
  'own-colour',
  const PublicShop(
    orgId: '13700000-0000-0000-0000-000000000009',
    name: 'Mode Lagune',
    slug: 'mode-lagune',
    profile: 'retail',
    style: StorefrontStyle(accent: Color(0xFFF2C94C), tagline: 'La mode, en jaune soleil'),
  ),
  [_i('a', 'Robe', 15000, photo: true), _i('b', 'Sac', 9000)],
  photos: {'a': 'fabric'},
);

final _cases = [_shop4, _shop1, _shop0, _empty, _long, _services, _farm, _association, _own];

Widget _app(Widget home, {Locale locale = const Locale('fr')}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

/// Real letters (as batch 133): the SDK's own Roboto, so a width that
/// overflows on a phone overflows here.
Future<bool> _realFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6 && !Directory('${dir.path}/material_fonts').existsSync(); i++) {
    dir = dir.parent;
  }
  final fonts = Directory('${dir.path}/material_fonts');
  if (!fonts.existsSync()) return false;
  final loader = FontLoader('Roboto');
  for (final f in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    final file = File('${fonts.path}/$f');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
  final icons = File('${fonts.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer))))
        .load();
  }
  return true;
}

List<String> _texts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (t.data != null) t.data!,
    ];

/// The WCAG ratio, computed here from the sRGB formula.
double _ratio(Color a, Color b) {
  double ch(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double lum(Color c) => 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  final x = lum(a), y = lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

class _Memory implements StatusMemory {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Future<void> _size(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    await _realFonts();
  });

  group('1. five designs, every colour, real-world data', () {
    for (final c in [..._cases]) {
      for (final locale in [const Locale('fr'), if (c == _shop4 || c == _farm || c == _association) const Locale('en')]) {
        testWidgets('${c.label} (${locale.languageCode}): every design × every colour, no overflow',
            (tester) async {
          await _size(tester, StatusCard.size);
          final palettes = c.card().palettes;
          expect(palettes.length, inInclusiveRange(7, 8), reason: '6–8 colours a design');
          for (final d in StatusDesign.values) {
            for (final p in palettes) {
              await tester.pumpWidget(_app(c.card(design: d, palette: p), locale: locale));
              final what = '${c.label} ${d.name} ${p.id}';
              expect(tester.takeException(), isNull, reason: what);
              final texts = _texts(tester);
              expect(texts.any((t) => t.contains('marakaj.com/s/${c.shop.slug}')), isTrue,
                  reason: '$what: the link');
              expect(find.byType(QrImageView), findsOneWidget, reason: '$what: the QR code');
              expect(find.byType(MaraWordmark), findsOneWidget, reason: '$what: Marakaj\'s mark');
              expect(texts.where((t) => t.contains('XOF')), isEmpty, reason: '$what: « FCFA XOF »');
              if (c.items.isNotEmpty) {
                expect(texts.any((t) => t.contains('FCFA')), isTrue, reason: '$what: a price');
              }
            }
          }
        });
      }
    }

    testWidgets('each kind in its own words, its units, its services', (tester) async {
      await _size(tester, StatusCard.size);
      Future<List<String>> words(_Case c, StatusDesign d, [Locale l = const Locale('fr')]) async {
        await tester.pumpWidget(_app(c.card(design: d, palette: StatusPalette.curated.first), locale: l));
        return _texts(tester);
      }

      var t = await words(_farm, StatusDesign.affiche);
      expect(t, contains('FERME'));
      expect(t.any((s) => s.endsWith('/ plateau')), isTrue);
      expect(t.any((s) => s.endsWith('/ tête')), isTrue);
      t = await words(_farm, StatusDesign.bandeau);
      expect(t.any((s) => s.contains('EN PRÉCOMMANDE')), isTrue, reason: 'a batch to come');
      t = await words(_farm, StatusDesign.grille);
      expect(t, contains('FERME · À VENDRE'));

      t = await words(_association, StatusDesign.grille);
      expect(t, contains('ASSOCIATION · NOS SERVICES'));
      expect(t, contains('Réservez ici'));
      expect(t.any((s) => s.startsWith('à partir de') && s.endsWith('/ mois')), isTrue);
      t = await words(_association, StatusDesign.vedette, const Locale('en'));
      expect(t, contains('Book on Marakaj'));

      t = await words(_shop4, StatusDesign.vitrine);
      expect(t, contains('BOUTIQUE'));
      expect(t, contains('Commandez ici'));
      t = await words(_shop4, StatusDesign.bandeau, const Locale('en'));
      expect(t.any((s) => s.contains('NEW IN')), isTrue);
      expect(t, contains('Order here'));
      t = await words(_shop4, StatusDesign.vedette);
      expect(t, contains('Commandez sur Marakaj'));
      expect(t, contains('Margherita'), reason: 'the star: the first photographed article');

      // Initials from the words that carry the name: « Fer à béton » is FB.
      t = await words(_long, StatusDesign.bandeau);
      expect(t, containsAll(['FB', 'TO']));
      expect(t, isNot(contains('FÀ')));

      t = await words(_empty, StatusDesign.grille);
      expect(t, contains('Découvrez notre vitrine'));
    });

    test('the articles: four, in stock and photographed first', () {
      final picked = StatusCard.pick([
        const PublicItem(id: 'out', name: 'Épuisé', price: 1, inStock: false, photoKey: 'k'),
        ..._shop4.items,
      ]);
      expect(picked.map((i) => i.id), ['a', 'b', 'c', 'd']);
    });
  });

  group('2. every colour reads', () {
    void legible(StatusPalette p, String what) {
      expect(_ratio(p.ink, p.ground), greaterThanOrEqualTo(4.5), reason: '$what: the name');
      expect(_ratio(p.soft, p.ground), greaterThanOrEqualTo(4.5), reason: '$what: the line');
      expect(_ratio(p.onSurface, p.surface), greaterThanOrEqualTo(4.5), reason: '$what: a card');
      expect(_ratio(p.onAccent, p.accent), greaterThanOrEqualTo(4.5), reason: '$what: the ribbon, the button');
      expect(_ratio(p.accentOnGround, p.ground), greaterThanOrEqualTo(3), reason: '$what: a big price');
      expect(_ratio(p.priceOnSurface, p.surface), greaterThanOrEqualTo(3), reason: '$what: a card\'s price');
    }

    test('the curated palettes: WCAG AA for the text, 3:1 for the big prices', () {
      for (final p in StatusPalette.curated) {
        legible(p, p.id);
      }
      // The paper plate under the QR code.
      expect(_ratio(maraBlack, maraPaper), greaterThanOrEqualTo(4.5));
      expect(_ratio(maraBrown, maraPaper), greaterThanOrEqualTo(4.5));
      expect(_ratio(maraBrown, Colors.white), greaterThanOrEqualTo(4.5));
    });

    test('« Ma couleur » stays legible whatever the colour', () {
      const colours = [
        Color(0xFFF2C94C), // a yellow
        Color(0xFFFFC0CB), // a pale pink
        Color(0xFF2F80ED), // a mid blue
        Color(0xFFFF0000), // a pure red
        Color(0xFF00FF00), // a pure green
        Color(0xFF000000),
        Color(0xFFFFFFFF),
        Color(0xFF808080),
        Color(0xFF3F7A52), // Mara's green
        Color(0xFFC49A6C), // caramel
        Color(0x80123456), // half transparent
      ];
      for (final c in colours) {
        final p = StatusPalette.own(c);
        expect(p.id, StatusPalette.ownId);
        legible(p, 'own ${c.toARGB32().toRadixString(16)}');
      }
      // Near its colour: the hue is kept.
      final blue = StatusPalette.own(const Color(0xFF2F80ED));
      expect(HSLColor.fromColor(blue.ground).hue, closeTo(HSLColor.fromColor(const Color(0xFF2F80ED)).hue, 2));
    });

    test('« Ma couleur » is offered only with a colour, first', () {
      expect(StatusPalette.forShop(null).map((p) => p.id), isNot(contains(StatusPalette.ownId)));
      expect(StatusPalette.forShop(const Color(0xFF2F80ED)).first.id, StatusPalette.ownId);
      expect(StatusPalette.curated.map((p) => p.id).toSet(), hasLength(StatusPalette.curated.length));
    });
  });

  group('3. two businesses, two pictures', () {
    test('the default comes from the id: the same for one, different across many', () {
      final ids = [for (var k = 0; k < 40; k++) '13700000-0000-0000-0000-${k.toString().padLeft(12, '0')}'];
      final choices = [for (final id in ids) StatusChoice.defaultFor(id)];
      expect(choices.map((c) => c.design).toSet(), hasLength(StatusDesign.values.length),
          reason: 'every design is someone\'s default');
      expect(choices.map((c) => c.paletteId).toSet().length, greaterThanOrEqualTo(6));
      expect(choices.toSet().length, greaterThanOrEqualTo(20));
      expect(StatusChoice.defaultFor(ids.first), StatusChoice.defaultFor(ids.first));
      expect(stableHash('o1'), stableHash('o1'));
      // FNV-1a's published values (review): the same on a phone and on the
      // web, where a product past 2^53 would have lost its low bits.
      expect(stableHash(''), 0x811c9dc5);
      expect(stableHash('a'), 0xe40c292c);
      expect(stableHash('foobar'), 0xbf9cf968);
      // A business with its own colour starts in it.
      expect(StatusChoice.defaultFor(ids.first, hasOwn: true).paletteId, StatusPalette.ownId);
    });

    testWidgets('untouched, two shops\' cards differ', (tester) async {
      await _size(tester, StatusCard.size);
      final a = _shop4.card().choice;
      final b = _shop1.card().choice;
      expect(a == b, isFalse);
    });
  });

  group('4. the choice: remembered, « Surprise »', () {
    Future<void> phone(WidgetTester tester) => _size(tester, const Size(390, 844));

    testWidgets('a tap changes the preview at once, and is remembered for this business', (tester) async {
      await phone(tester);
      final memory = _Memory();
      Widget preview() => _app(StatusPreview(
            card: _farm.card(),
            name: 'ferme.png',
            text: 'Ferme',
            memory: memory,
          ));
      await tester.pumpWidget(preview());
      await tester.pump();
      StatusCard shown() => tester.widget<StatusCard>(
          find.descendant(of: find.byKey(const Key('status-card')), matching: find.byType(StatusCard)));
      expect(shown().design, _farm.card().defaultChoice.design, reason: 'the business\'s default first');

      final other = StatusDesign.values.firstWhere((d) => d != shown().design);
      await tester.tap(find.byKey(Key('status-design-${other.name}')));
      await tester.pump();
      expect(shown().design, other);
      await tester.tap(find.byKey(const Key('status-colour-savane')));
      await tester.pump();
      expect(shown().palette?.id, 'savane');
      expect(memory.values[StatusMemory.keyFor(_farm.shop.orgId)], '${other.name}:savane');

      // Opened again: the same picture.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(preview());
      await tester.pump();
      await tester.pump();
      expect(shown().design, other);
      expect(shown().palette?.id, 'savane');
      // Another business keeps its own.
      expect(memory.values.keys, [StatusMemory.keyFor(_farm.shop.orgId)]);
    });

    testWidgets('« Surprise » changes the design and the colour', (tester) async {
      await phone(tester);
      final memory = _Memory();
      await tester.pumpWidget(_app(StatusPreview(
        card: _shop4.card(),
        name: 'tony.png',
        text: 'Tony',
        memory: memory,
        random: math.Random(137),
      )));
      await tester.pump();
      var before = _shop4.card().defaultChoice;
      for (var k = 0; k < 6; k++) {
        await tester.tap(find.byKey(const Key('status-surprise')));
        await tester.pump();
        final now = StatusChoice.decode(memory.values[StatusMemory.keyFor(_shop4.shop.orgId)])!;
        expect(now.design, isNot(before.design));
        expect(now.paletteId, isNot(before.paletteId));
        before = now;
      }
      expect(tester.takeException(), isNull);
    });

    test('surprise never repeats what shows, decode refuses nonsense', () {
      const c = StatusChoice(StatusDesign.affiche, 'nuit');
      final r = math.Random(1);
      for (var k = 0; k < 50; k++) {
        final s = c.surprise(StatusPalette.curated, r);
        expect(s.design, isNot(StatusDesign.affiche));
        expect(s.paletteId, isNot('nuit'));
      }
      expect(StatusChoice.decode('affiche:nuit'), c);
      expect(StatusChoice.decode('nothing'), isNull);
      expect(StatusChoice.decode('cube:nuit'), isNull);
      // « Ma couleur » chosen, then the colour taken off: the first one.
      expect(const StatusChoice(StatusDesign.grille, 'own').paletteIn(StatusPalette.curated).id,
          StatusPalette.curated.first.id);
    });
  });

  group('5. the panel fits a phone', () {
    for (final size in const [Size(390, 844), Size(375, 667), Size(360, 640)]) {
      for (final locale in const [Locale('fr'), Locale('en')]) {
        testWidgets('${size.width.toInt()}×${size.height.toInt()} ${locale.languageCode}', (tester) async {
          await _size(tester, size);
          await tester.pumpWidget(_app(
              StatusPreview(card: _own.card(), name: 'a.png', text: 'A', memory: _Memory()),
              locale: locale));
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);
          // 140: four ways out at the foot instead of the one share.
          for (final t in StatusTarget.values) {
            expect(find.byKey(Key('status-out-${t.name}')).hitTestable(), findsOneWidget, reason: t.name);
          }
          expect(find.byKey(const Key('status-surprise')).hitTestable(), findsOneWidget);
          for (final d in StatusDesign.values) {
            expect(find.byKey(Key('status-design-${d.name}')).hitTestable(), findsOneWidget, reason: d.name);
          }
          final card = tester.getRect(find.byKey(const Key('status-card')));
          expect(card.height, greaterThan(size.height * 0.36), reason: 'the preview stays the star: $card');
          expect(find.text(locale.languageCode == 'en' ? 'Surprise' : 'Surprise'), findsOneWidget);
        });
      }
    }
  });

  // -------------------------------------------------------------------------
  // Screenshots (B137_SHOTS=<dir>)
  // -------------------------------------------------------------------------
  final shots = Platform.environment['B137_SHOTS'];
  group('screenshots', () {
    Future<void> capture(WidgetTester tester, Finder boundary, String path, double ratio) async {
      final element = tester.element(boundary);
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(image.image, element);
        }
      });
      await tester.pump();
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(boundary);
        final img = await ro.toImage(pixelRatio: ratio);
        final data = await img.toByteData(format: ImageByteFormat.png);
        File(path).writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    testWidgets('every design in three colours, shop, farm, association', (tester) async {
      Directory(shots!).createSync(recursive: true);
      await _size(tester, StatusCard.size);
      final picks = {
        _shop4: ['graphite', 'papier', 'terre'],
        _shop0: ['caramel', 'nuit'],
        _farm: ['savane', 'caramel', 'espresso'],
        _association: ['nuit', 'papier', 'terre'],
        _long: ['espresso', 'papier'],
        _own: ['own'],
        _empty: ['graphite'],
      };
      for (final e in picks.entries) {
        for (final d in StatusDesign.values) {
          for (final id in e.value) {
            final card = e.key.card(design: d);
            final p = card.palettes.firstWhere((p) => p.id == id);
            const k = Key('shot');
            await tester.pumpWidget(_app(Center(
                child: RepaintBoundary(key: k, child: e.key.card(design: d, palette: p)))));
            expect(tester.takeException(), isNull);
            await capture(tester, find.byKey(k), '$shots/${e.key.label}_${d.name}_$id.png', 0.5);
          }
        }
      }
    }, skip: shots == null);

    testWidgets('the panel at 390 × 844, FR and EN', (tester) async {
      Directory(shots!).createSync(recursive: true);
      await _size(tester, const Size(390, 844));
      for (final locale in const [Locale('fr'), Locale('en')]) {
        const k = Key('screen');
        await tester.pumpWidget(RepaintBoundary(
            key: k,
            child: _app(
                StatusPreview(
                    card: _shop4.card(),
                    name: 'a.png',
                    text: 'A',
                    memory: _Memory(),
                    initial: const StatusChoice(StatusDesign.grille, 'papier')),
                locale: locale)));
        await tester.pump();
        await capture(tester, find.byKey(k), '$shots/panel_390x844_${locale.languageCode}.png', 2);
      }
    }, skip: shots == null);
  });
}
