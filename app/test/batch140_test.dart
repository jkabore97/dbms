// Batch 140: « Partager » — the owner chooses what the picture shows, one
// article alone as an ad; the picture leaves by WhatsApp, Facebook, any
// other app or the photos; « Ma vitrine » one tap from the home.
//
//   1. the choice of articles: 1, 2, 4, their order, the 5th refused,
//      « Un seul produit » (Vedette pre-selected, not remembered),
//      « Choix automatique » restoring today's rule, the search past 12,
//      « Articles | Services » with both, the « Épuisé » note;
//   2. every design × one article (shop, hairdresser services, a farm's
//      « / plateau », pre-order and « Labour d'un hectare », an association's
//      « Location de la salle »), with and without a photo, a long name, in
//      English: no overflow, the QR code and the link, no stock wording on
//      a service, « Réservez »;
//   3. the entry points: Catalogue › Articles, À vendre, Services (sheet and
//      row), the vitrine's own article sheet, the Product mapper;
//   4. the share sheet: its title per kind and per article, its two
//      choices, « Le lien »;
//   5. the four ways out per platform, through a fake platform: Android's
//      intents and their fallbacks, iOS's hint, the web's « Partager… » and
//      download, the save;
//   6. the memory: the design remembered, the articles never;
//   7. the panel and the foot fit 360 × 640 and 320 px at 1.3, FR and EN;
//   8. « Ma vitrine » on the three homes, its tap, the hidden banner, the
//      bar at 390 / 360 / 320 × 1.0 / 1.3.
//
// B140_SHOTS=<dir> also writes the screenshots (B140_PHOTOS=<dir> gives
// them real photographs).

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui show PictureRecorder;
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/help/help_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/invoicing/models.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/farm/for_sale_screen.dart';
import 'package:kaj_app/features/help/help_button.dart';
import 'package:kaj_app/features/retail/products_screen.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/features/services/services_screen.dart';
import 'package:kaj_app/features/storefront/share_vitrine.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// Photographs
// ---------------------------------------------------------------------------

/// A small photograph's bytes, drawn by the engine itself (setUpAll): a
/// real decode, as a phone's, must accept it.
late Uint8List _pixel;

Future<Uint8List> _drawPixel() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = const Color(0xFFC49A6C));
  final image = await recorder.endRecording().toImage(8, 8);
  final data = await image.toByteData(format: ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Uint8List _photo(String name) {
  final dir = Platform.environment['B140_PHOTOS'];
  if (dir != null) {
    final f = File('$dir/$name.jpg');
    if (f.existsSync()) return f.readAsBytesSync();
  }
  return _pixel;
}

// ---------------------------------------------------------------------------
// The businesses
// ---------------------------------------------------------------------------

PublicItem _i(String id, String name, double price,
        {String? photo,
        String? unit,
        bool service = false,
        bool from = false,
        DateTime? on,
        bool inStock = true,
        String? description}) =>
    PublicItem(
      id: id,
      name: name,
      price: price,
      inStock: service || inStock,
      photoKey: photo == null ? null : 'k-$photo',
      unit: unit,
      isService: service,
      priceFrom: from,
      availableFrom: on,
      description: description,
    );

/// One kind of business, its shelf, its photographs by key.
class _Kind {
  const _Kind(this.label, this.shop, this.items);
  final String label;
  final PublicShop shop;
  final List<PublicItem> items;

  Map<String, Uint8List> get photos => {
        for (final i in items)
          if (i.photoKey != null) i.id: _photo(i.photoKey!.substring(2)),
      };

  StatusCard card(List<PublicItem> chosen, {StatusDesign? design, StatusPalette? palette, bool photos = true}) =>
      StatusCard(
        shop: shop,
        items: chosen,
        photos: photos ? this.photos : const {},
        design: design,
        palette: palette,
      );

  PublicItem item(String id) => items.firstWhere((i) => i.id == id);
}

final _shop = _Kind(
  'shop',
  const PublicShop(
    orgId: '14000000-0000-0000-0000-000000000001',
    name: 'Le Comptoir Doré',
    slug: 'le-comptoir-dore',
    profile: 'retail',
    style: StorefrontStyle(tagline: 'La pizza du quartier, au feu de bois'),
  ),
  [
    _i('a', 'Margherita', 5000, photo: 'pizza', description: 'Tomate, mozzarella, basilic frais.'),
    _i('b', 'Salade César', 3500, photo: 'salad'),
    _i('c', 'Jus de bissap', 1000, photo: 'juice'),
    _i('d', 'Pizza Reine', 6500),
    _i('e', 'Frites', 1000),
    _i('f', 'Glace vanille', 1500, inStock: false),
    _i('long', 'Pizza quatre fromages, grande taille, pâte fine et croustillante', 12500),
  ],
);

/// A hairdresser: articles and services side by side.
final _salon = _Kind(
  'salon',
  const PublicShop(
    orgId: '14000000-0000-0000-0000-000000000002',
    name: 'Salon Prestige',
    slug: 'salon-prestige',
    profile: 'retail',
    style: StorefrontStyle(tagline: 'Tresses, tissages, soins'),
  ),
  [
    _i('s1', 'Tresses africaines', 5000, service: true, from: true, photo: 'fabric',
        description: 'Nattes collées, vanilles, box braids.'),
    _i('s2', 'Coupe homme', 1500, service: true),
    _i('s3', 'Soin du cuir chevelu', 2500, service: true, unit: 'heure'),
    _i('p1', 'Huile de karité', 2000, photo: 'juice'),
  ],
);

final _farm = _Kind(
  'farm',
  const PublicShop(
    orgId: '14000000-0000-0000-0000-000000000003',
    name: 'Ferme Horizon Vert',
    slug: 'ferme-horizon-vert',
    profile: 'farm',
    blurb: 'Œufs, poulets et pintades élevés près de Ouagadougou.',
  ),
  [
    _i('a', 'Œufs frais', 2500, photo: 'eggs', unit: 'plateau'),
    _i('b', 'Poulets bicyclette', 3500, unit: 'tête'),
    _i('c', 'Pintades', 4000, unit: 'tête', on: DateTime(2026, 11, 15)),
    _i('labour', 'Labour d\'un hectare', 25000, service: true, unit: 'hectare'),
  ],
);

/// An association: its articles (stock not followed: never « épuisé »)
/// and its services.
final _assoc = _Kind(
  'association',
  const PublicShop(
    orgId: '14000000-0000-0000-0000-000000000004',
    name: 'Cercle des Bâtisseurs Solidaires de Ouagadougou',
    slug: 'cercle-des-batisseurs',
    profile: 'association',
    style: StorefrontStyle(tagline: 'Ensemble, on va plus loin'),
  ),
  [
    _i('salle', 'Location de la salle', 15000, service: true, from: true, unit: 'soirée', photo: 'cover'),
    _i('tshirt', 'T-shirt de l\'association', 3000, photo: 'fabric'),
    _i('livre', 'Livre de recettes', 5000),
  ],
);


// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _Memory implements StatusMemory {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// The phone, as a test has it: what each way out was asked.
class _Platform implements StatusPlatform {
  _Platform(this.os, {this.whatsAppThere = true, this.facebookThere = true, this.saves = true, this.webShare = true});

  @override
  final StatusOs os;
  final bool whatsAppThere;
  final bool facebookThere;
  final bool saves;
  final bool webShare;
  final calls = <String>[];

  @override
  Future<bool> canShareFiles() async => os == StatusOs.web && webShare;

  @override
  Future<bool> whatsApp(Uint8List png, String name, String text) async {
    calls.add('whatsapp');
    return whatsAppThere;
  }

  @override
  Future<bool> facebookStory(Uint8List png, String appId) async {
    calls.add('facebook:$appId');
    return facebookThere;
  }

  @override
  Future<void> system(Uint8List png, String name, String text) async => calls.add('system:$name');

  @override
  Future<void> text(String text) async => calls.add('text:$text');

  @override
  Future<bool> save(Uint8List png, String name) async {
    calls.add('save:$name');
    return saves;
  }
}

Widget _app(Widget home, {Locale locale = const Locale('fr')}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

Future<bool> _realFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6 && !Directory('${dir.path}/material_fonts').existsSync(); i++) {
    dir = dir.parent;
  }
  final fonts = Directory('${dir.path}/material_fonts');
  if (!fonts.existsSync()) return false;
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
  return true;
}

List<String> _texts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (t.data != null) t.data!,
    ];

Future<void> _size(WidgetTester tester, Size size, {double scale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  if (scale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

Future<void> _settle(WidgetTester tester, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

StatusCard _shown(WidgetTester tester) => tester.widget<StatusCard>(
    find.descendant(of: find.byKey(const Key('status-card')), matching: find.byType(StatusCard)));

StatusPreview _preview(_Kind k,
        {_Memory? memory,
        StatusSelection selection = const StatusSelection(),
        StatusPlatform? platform,
        StatusChoice? initial}) =>
    StatusPreview(
      card: k.card(selection.itemsIn(k.items)),
      catalogue: k.items,
      selection: selection,
      photos: (key, {width}) async => _photo(key.substring(2)),
      name: '${k.shop.slug}.png',
      text: k.shop.name,
      memory: memory ?? _Memory(),
      platform: platform ?? _Platform(StatusOs.android),
      initial: initial,
    );

// Homes (as batch 136's harness).

class _Help extends HelpRepository {
  _Help() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<HelpState> state(String orgId) async => const HelpState(available: true, pro: false);
  @override
  Future<HelpInbox> inbox() async => HelpInbox.none;
}

class _Shelf extends RetailRepository {
  _Shelf([this.goods = const []]) : super(null);
  final List<Product> goods;
  @override
  bool get isConfigured => true;
  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();
  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) async => const [];
  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => goods;
  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {};
  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) async => 0;
  @override
  Future<int> pendingOrders(String orgId) async => 0;
  @override
  Future<int> pendingSales(String orgId) async => 0;
  @override
  Future<List<Map<String, Object?>>> refusedSales(String orgId) async => const [];
}

class _Bills extends InvoicingRepository {
  _Bills() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<List<InvoiceSummary>> list(String orgId, {bool includePaid = true, int limit = 200}) async => const [];
  @override
  Future<BillingDetails> billingDetails(String orgId) async => const BillingDetails();
}

const _shopOrg = OrgSummary(
    id: '14000000-0000-0000-0000-0000000000a1',
    name: 'Le Comptoir Général des Bâtisseurs',
    slug: 'comptoir-general',
    profile: 'retail',
    plan: 'pro',
    roles: ['owner']);
const _farmOrg = OrgSummary(
    id: '14000000-0000-0000-0000-0000000000a2',
    name: 'Domaine des Acacias',
    slug: 'domaine-des-acacias',
    profile: 'farm',
    plan: 'free',
    roles: ['owner']);
const _assocOrg = OrgSummary(
    id: '14000000-0000-0000-0000-0000000000a3',
    name: 'Cercle Atelier Lumière',
    slug: 'atelier-lumiere',
    profile: 'association',
    plan: 'pro',
    roles: ['owner']);

OrgSummary _as(OrgSummary o, {List<String>? roles, String? slug}) => OrgSummary(
    id: o.id, name: o.name, slug: slug ?? o.slug, profile: o.profile, plan: o.plan, roles: roles ?? o.roles);

Widget _home(OrgSummary org, LocalDb db) => switch (org.profile) {
      'retail' => StoreHomeScreen(org: org, retail: _Shelf(), invoicing: _Bills(), help: _Help()),
      'farm' => FarmHomeScreen(db: db, org: org, retail: _Shelf(), invoicing: _Bills(), help: _Help()),
      _ => ChurchHomeScreen(
          db: db,
          orgId: org.id,
          orgName: org.name,
          org: org,
          reports: ReportsRepository(null),
          invoicing: _Bills(),
          retail: _Shelf(),
          onHistory: () {},
          help: _Help(),
        ),
    };

// The vitrine, for its own people.

class _Street extends StorefrontRepository {
  _Street(this.answer, this.goods) : super(null);
  final PublicShop? answer;
  final List<PublicItem> goods;
  @override
  bool get isConfigured => true;
  @override
  Future<PublicShop?> shop(String slug) async => answer;
  @override
  Future<List<PublicItem>> items(String slug) async => goods;
  @override
  Future<Set<String>> showcaseSlugs() async => const {};
}

class _Admin extends AdminRepository {
  _Admin(this.checklist) : super(null);
  final VitrineChecklist? checklist;
  int asked = 0;
  @override
  Future<VitrineChecklist?> vitrineChecklist(String orgId) async {
    asked++;
    return checklist;
  }
}

/// A phone whose Facebook answers with an error.
class _Broken extends _Platform {
  _Broken(super.os);
  @override
  Future<bool> facebookStory(Uint8List png, String appId) async => throw StateError('Facebook said no');
}

class _Session extends SessionController {
  _Session(LocalDb db, this.mine, AdminRepository admin)
      : super(db: db, auth: AuthRepository(null), admin: admin, accounting: AccountingRepository(null));
  final List<OrgSummary> mine;
  @override
  List<OrgSummary> get orgs => mine;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
    await _realFonts();
    _pixel = await _drawPixel();
  });

  // -------------------------------------------------------------------------
  group('1. the choice of articles', () {
    test('1, 2 and 4 chosen in their order; the 5th refused; untick', () {
      var s = const StatusSelection();
      expect(s.automatic, isTrue);
      s = s.toggle('c')!;
      expect(s.itemsIn(_shop.items).map((i) => i.id), ['c']);
      s = s.toggle('a')!;
      expect(s.itemsIn(_shop.items).map((i) => i.id), ['c', 'a'], reason: 'the order ticked');
      s = s.toggle('e')!.toggle('b')!;
      expect(s.itemsIn(_shop.items).map((i) => i.id), ['c', 'a', 'e', 'b']);
      expect(s.toggle('d'), isNull, reason: 'a fifth is refused');
      s = s.toggle('a')!;
      expect(s.chosen, ['c', 'e', 'b']);
    });

    test('« Automatique » is today\'s rule; « Un seul produit » keeps one', () {
      expect(const StatusSelection().itemsIn(_shop.items).map((i) => i.id),
          StatusCard.pick(_shop.items).map((i) => i.id));
      var s = const StatusSelection(['e', 'a']);
      s = s.toggleSingle(_shop.items);
      expect(s.single, isTrue);
      expect(s.itemsIn(_shop.items).map((i) => i.id), ['e']);
      s = s.toggle('b')!;
      expect(s.chosen, ['b'], reason: 'one only: the tap moves it');
      // From automatic: the first the rule would show.
      final one = const StatusSelection().toggleSingle(_shop.items);
      expect(one.chosen, [StatusCard.pick(_shop.items).first.id]);
      expect(StatusSelection.only('labour').itemsIn(_farm.items).single.name, 'Labour d\'un hectare');
    });

    testWidgets('the sheet: ticks change the picture at once, the 5th refused, the order kept', (tester) async {
      await _size(tester, const Size(390, 844));
      await tester.pumpWidget(_app(_preview(_shop)));
      await _settle(tester, 3);
      expect(find.text('Automatique'), findsOneWidget);
      await tester.tap(find.byKey(const Key('status-articles-row')));
      await _settle(tester, 3);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('status-articles')), findsOneWidget);
      for (final id in ['d', 'a']) {
        await tester.tap(find.byKey(Key('status-article-$id')));
        await tester.pump();
      }
      expect(_shown(tester).items.map((i) => i.id), ['d', 'a'], reason: 'the preview follows at once');
      expect(find.text('2/4'), findsWidgets);
      await tester.tap(find.byKey(const Key('status-article-b')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('status-article-e')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('status-article-c')));
      await tester.tap(find.byKey(const Key('status-article-c')));
      await tester.pump();
      expect(_shown(tester).items.map((i) => i.id), ['d', 'a', 'b', 'e']);
      expect(find.text('4 articles au plus : retirez-en un d\'abord.'), findsOneWidget);
      // Out of stock: chosen, said.
      await tester.tap(find.byKey(const Key('status-article-e')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('status-article-f')));
      await tester.tap(find.byKey(const Key('status-article-f')));
      await tester.pump();
      expect(find.byKey(const Key('status-articles-soldout')), findsOneWidget);
      expect(_texts(tester).any((t) => t.contains('Épuisé')), isTrue);
      // « Choix automatique »: today's rule again.
      await tester.tap(find.byKey(const Key('status-articles-auto')));
      await tester.pump();
      expect(_shown(tester).items.map((i) => i.id), StatusCard.pick(_shop.items).map((i) => i.id));
      expect(tester.takeException(), isNull);
    });

    testWidgets('« Un seul produit »: Vedette pre-selected, not remembered; the owner can switch', (tester) async {
      await _size(tester, const Size(390, 844));
      final memory = _Memory();
      await tester.pumpWidget(_app(_preview(_shop,
          memory: memory, initial: const StatusChoice(StatusDesign.grille, 'papier'))));
      await _settle(tester, 3);
      await tester.tap(find.byKey(const Key('status-articles-row')));
      await _settle(tester, 3);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('status-articles-single')));
      await tester.pump();
      expect(_shown(tester).items, hasLength(1));
      expect(_shown(tester).design, StatusDesign.vedette);
      expect(memory.values, isEmpty, reason: 'Mara chose Vedette, not the owner');
      await tester.tap(find.byKey(const Key('status-article-c')));
      await tester.pump();
      expect(_shown(tester).items.single.id, 'c');
      await tester.tap(find.byKey(const Key('status-articles-done')));
      await _settle(tester, 3);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('Annonce : Jus de bissap'), findsOneWidget);
      await tester.tap(find.byKey(const Key('status-design-affiche')));
      await tester.pump();
      expect(_shown(tester).design, StatusDesign.affiche);
      expect(_shown(tester).items.single.id, 'c', reason: 'still the ad');
      expect(memory.values.values.single, startsWith('affiche:'));
    });

    testWidgets('the search past 12, « Articles | Services » with both', (tester) async {
      await _size(tester, const Size(390, 844));
      final many = _Kind('many', _salon.shop, [
        ..._salon.items,
        for (var k = 0; k < 12; k++) _i('x$k', 'Mèche $k', 1000.0 + k),
      ]);
      await tester.pumpWidget(_app(_preview(many)));
      await _settle(tester, 3);
      await tester.tap(find.byKey(const Key('status-articles-row')));
      await _settle(tester, 3);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('status-articles-search')), findsOneWidget);
      expect(find.byKey(const Key('status-articles-kind')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('status-articles-search')), 'meche 1');
      await tester.pump();
      expect(find.byKey(const Key('status-article-x1')), findsOneWidget);
      expect(find.byKey(const Key('status-article-x2')), findsNothing);
      await tester.enterText(find.byKey(const Key('status-articles-search')), '');
      await tester.tap(find.text('Services').last);
      await tester.pump();
      expect(find.byKey(const Key('status-article-s1')), findsOneWidget);
      expect(find.byKey(const Key('status-article-p1')), findsNothing);
      expect(_texts(tester).any((t) => t.contains('Sur rendez-vous')), isTrue);
      // A window of one kind: no filter.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(_preview(_shop)));
      await _settle(tester, 3);
      await tester.tap(find.byKey(const Key('status-articles-row')));
      await _settle(tester, 3);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('status-articles-kind')), findsNothing);
      expect(find.byKey(const Key('status-articles-search')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('2. every design × one article', () {
    final singles = <(String, _Kind, String, bool)>[
      ('shop with photo', _shop, 'a', true),
      ('shop no photo', _shop, 'd', false),
      ('shop long name', _shop, 'long', false),
      ('shop sold out', _shop, 'f', false),
      ('salon service from', _salon, 's1', true),
      ('salon service by the hour', _salon, 's3', false),
      ('farm per plateau', _farm, 'a', true),
      ('farm pre-order', _farm, 'c', false),
      ('farm labour', _farm, 'labour', false),
      ('association salle', _assoc, 'salle', true),
      ('association salle no photo', _assoc, 'salle', false),
      ('association t-shirt', _assoc, 'tshirt', true),
    ];
    for (final (label, kind, id, photos) in singles) {
      for (final locale in [const Locale('fr'), if (label.contains('photo') || label.contains('labour') || label.contains('salle')) const Locale('en')]) {
        testWidgets('$label (${locale.languageCode}): five designs, every colour', (tester) async {
          await _size(tester, StatusCard.size);
          final item = kind.item(id);
          final card = kind.card([item], photos: photos);
          for (final d in StatusDesign.values) {
            for (final p in card.palettes) {
              await tester.pumpWidget(_app(kind.card([item], design: d, palette: p, photos: photos), locale: locale));
              final what = '$label ${d.name} ${p.id}';
              expect(tester.takeException(), isNull, reason: what);
              final texts = _texts(tester);
              expect(texts.any((t) => t.contains('marakaj.com/s/${kind.shop.slug}')), isTrue, reason: '$what: link');
              expect(find.byType(QrImageView), findsOneWidget, reason: '$what: QR');
              expect(texts.any((t) => t.contains('FCFA')), isTrue, reason: '$what: price');
              expect(texts.where((t) => t.contains('XOF')), isEmpty);
              if (item.isService) {
                expect(texts.where((t) => t.contains('Épuisé') || t.contains('Sold out') || t.contains('stock')),
                    isEmpty, reason: '$what: no stock words on a service');
                expect(
                    texts.any((t) => t.contains(locale.languageCode == 'en' ? 'Book' : 'Réservez')), isTrue,
                    reason: '$what: booked');
              }
              if (!item.inStock) {
                expect(texts.any((t) => t.toUpperCase().contains('ÉPUISÉ')), isTrue, reason: '$what: épuisé');
              }
            }
          }
        });
      }
    }

    testWidgets('an ad shows the article, not the four: its words, its unit, its date', (tester) async {
      await _size(tester, StatusCard.size);
      Future<List<String>> words(_Kind k, String id, StatusDesign d, [Locale l = const Locale('fr')]) async {
        await tester.pumpWidget(_app(k.card([k.item(id)], design: d, palette: StatusPalette.curated.first), locale: l));
        return _texts(tester);
      }

      var t = await words(_shop, 'a', StatusDesign.vitrine);
      expect(t, contains('Margherita'));
      expect(t, contains('Tomate, mozzarella, basilic frais.'), reason: 'its description');
      expect(t.where((s) => s == 'Salade César'), isEmpty);
      expect(t, contains('À LA UNE'));
      t = await words(_farm, 'a', StatusDesign.affiche);
      expect(t.any((s) => s.endsWith('/ plateau')), isTrue);
      t = await words(_farm, 'c', StatusDesign.bandeau);
      expect(t.any((s) => s.contains('EN PRÉCOMMANDE')), isTrue);
      expect(t.any((s) => s.contains('15/11')), isTrue, reason: 'the day');
      t = await words(_farm, 'labour', StatusDesign.grille);
      expect(t.any((s) => s.contains(RegExp(r'25\D?000')) && s.endsWith('/ hectare')), isTrue);
      t = await words(_assoc, 'salle', StatusDesign.vedette, const Locale('en'));
      expect(t, contains('Book on Mara'));
      expect(t.any((s) => s.startsWith('from') && s.endsWith('/ soirée')), isTrue);
      t = await words(_salon, 's1', StatusDesign.bandeau);
      expect(t.any((s) => s.contains('SUR RENDEZ-VOUS')), isTrue);
      t = await words(_shop, 'f', StatusDesign.grille);
      expect(t.any((s) => s.toUpperCase().contains('ÉPUISÉ')), isTrue);
      // A mix of services and articles: the four, priced.
      await tester.pumpWidget(_app(_salon.card(_salon.items, design: StatusDesign.bandeau)));
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('3. the entry points', () {
    late LocalDb db;
    setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
    tearDown(() => db.close());

    test('a Catalogue article as the vitrine shows it', () {
      final today = DateTime(2026, 10, 13);
      var p = publicItemOf(
          const Product(id: 'p', name: 'Œufs', salePrice: 2500, quantity: 0, unit: 'plateau', isPublished: true),
          photoKey: 'k1',
          today: today);
      expect((p.inStock, p.unit, p.photoKey, p.isService), (false, 'plateau', 'k1', false));
      p = publicItemOf(const Product(id: 'p', name: 'Livre', salePrice: 5000, stockTracked: false), today: today);
      expect(p.inStock, isTrue, reason: 'not followed: never épuisé (134)');
      p = publicItemOf(Product(id: 'p', name: 'Pintades', availableFrom: DateTime(2026, 11, 15)), today: today);
      expect((p.inStock, p.isPreorder), (true, true));
      p = publicItemOf(Product(id: 'p', name: 'Pintades', availableFrom: DateTime(2026, 9, 1), quantity: 3),
          today: today);
      expect(p.isPreorder, isFalse, reason: 'a day gone is there now');
      p = publicItemOf(const Product(id: 's', name: 'Labour', isService: true, priceFrom: true, unit: ' '),
          today: today);
      expect((p.inStock, p.priceFrom, p.unit), (true, true, null));
    });

    Future<void> imageFromSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('share-image')));
      await _settle(tester, 12);
    }

    testWidgets('Catalogue › Services: on the row and in the sheet, « Partager ce service », an ad', (tester) async {
      await _size(tester, const Size(390, 844));
      const salle = Product(
          id: 'salle', name: 'Location de la salle', salePrice: 15000, isService: true, isPublished: true, unit: 'soirée');
      const hidden = Product(id: 'h', name: 'Cours privé', salePrice: 1000, isService: true);
      final platform = _Platform(StatusOs.android);
      await tester.pumpWidget(_app(Scaffold(
        body: ServicesScreen(org: _assocOrg, retail: _Shelf(const [salle, hidden])),
      )));
      await _settle(tester);
      expect(find.byKey(const Key('share-article-salle')), findsOneWidget, reason: 'on the row');
      expect(find.byKey(const Key('share-article-h')), findsNothing, reason: 'not on the vitrine: nothing to point at');
      // The sheet, opened from the row as the owner does.
      await tester.pumpWidget(_app(Scaffold(
          body: ShareArticleButton(org: _assocOrg, product: salle, platform: platform))));
      await tester.tap(find.byKey(const Key('share-article-salle')));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Partager ce service'), findsOneWidget);
      expect(find.byKey(const Key('share-image')), findsOneWidget);
      expect(find.byKey(const Key('share-link')), findsOneWidget);
      await imageFromSheet(tester);
      final preview = tester.widget<StatusPreview>(find.byType(StatusPreview));
      expect(preview.selection.single, isTrue);
      expect(_shown(tester).items.single.name, 'Location de la salle');
      expect(_shown(tester).design, StatusDesign.vedette);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Catalogue › Articles and À vendre: in the article\'s sheet', (tester) async {
      await _size(tester, const Size(390, 1400));
      const eggs = Product(id: 'eggs', name: 'Œufs frais', salePrice: 2500, quantity: 12, unit: 'plateau', isPublished: true);
      await tester.pumpWidget(_app(Scaffold(
          body: ForSaleSheet(org: _farmOrg, retail: _Shelf(), product: eggs))));
      await tester.pump();
      expect(find.byKey(const Key('share-article-eggs')), findsOneWidget);
      // Not on the vitrine: nothing to share yet.
      await tester.pumpWidget(_app(Scaffold(
          body: ForSaleSheet(org: _farmOrg, retail: _Shelf(), product: const Product(id: 'x', name: 'Maïs')))));
      await tester.pump();
      expect(find.byKey(const Key('share-article-x')), findsNothing);
      // The shop's Articles: the edit sheet, from the vitrine button.
      await tester.pumpWidget(_app(Scaffold(
          body: ProductsScreen(org: _shopOrg, retail: _Shelf(const [
        Product(id: 'ciment', name: 'Ciment CPJ 45', salePrice: 6750, quantity: 30, isPublished: true),
      ])))));
      await _settle(tester);
      await tester.tap(find.byTooltip('Sur la vitrine — modifier'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('share-article-ciment')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('share-article-ciment')));
      await tester.tap(find.byKey(const Key('share-article-ciment')));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Partager ce produit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the vitrine\'s article sheet: « Partager » for its own people only', (tester) async {
      await _size(tester, const Size(390, 1600));
      final goods = _farm.items;
      Future<void> open(List<OrgSummary> mine) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_app(StorefrontScreen(
          slug: _farm.shop.slug,
          storefront: _Street(_farm.shop, goods),
          capture: CaptureRepository(null, db: db),
          session: _Session(db, mine, _Admin(null)),
        )));
        await _settle(tester);
        await tester.tap(find.text('Œufs frais').first);
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 600));
      }

      await open(const []);
      expect(find.byKey(const Key('article-share')), findsNothing, reason: 'a shopper');
      await open([_as(_farmOrg, slug: _farm.shop.slug)].map((o) => OrgSummary(
          id: _farm.shop.orgId, name: o.name, slug: o.slug, profile: 'farm', roles: const ['owner'])).toList());
      expect(find.byKey(const Key('article-share')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('article-share')));
      await tester.tap(find.byKey(const Key('article-share')));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Partager ce produit'), findsOneWidget);
      await imageFromSheet(tester);
      expect(_shown(tester).items.single.name, 'Œufs frais');
      expect(_shown(tester).design, StatusDesign.vedette);
    });
  });

  // -------------------------------------------------------------------------
  group('4. the share sheet', () {
    for (final (kind, mine, article, fr, en) in [
      (_shop, true, null, 'Partager ma boutique', 'Share my shop'),
      (_farm, true, null, 'Partager ma ferme', 'Share my farm'),
      (_assoc, true, null, 'Partager mon association', 'Share my association'),
      (_shop, false, null, 'Partager cette boutique', 'Share this shop'),
      (_farm, false, null, 'Partager cette ferme', 'Share this farm'),
      (_assoc, false, null, 'Partager cette association', 'Share this association'),
      (_shop, true, 'a', 'Partager ce produit', 'Share this item'),
      (_farm, true, 'labour', 'Partager ce service', 'Share this service'),
    ]) {
      testWidgets('${kind.label}${mine ? ' (mine)' : ''}${article == null ? '' : ' $article'}: « $fr »',
          (tester) async {
        await _size(tester, const Size(390, 844));
        for (final (locale, title) in [(const Locale('fr'), fr), (const Locale('en'), en)]) {
          final platform = _Platform(StatusOs.android);
          await tester.pumpWidget(_app(
              Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => ShareVitrine.open(context,
                          shop: kind.shop,
                          items: kind.items,
                          mine: mine,
                          article: article == null ? null : kind.item(article),
                          platform: platform),
                      child: const Text('go'),
                    ),
                  ),
                ),
              ),
              locale: locale));
          await tester.tap(find.text('go'));
          await _settle(tester, 3);
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.text(title), findsOneWidget);
          expect(find.text(locale.languageCode == 'en' ? 'A picture' : 'Une image'), findsOneWidget);
          expect(find.text(locale.languageCode == 'en' ? 'The link' : 'Le lien'), findsOneWidget);
          expect(find.text('Mettre en statut WhatsApp'), findsNothing);
          expect(tester.takeException(), isNull);
          // « Le lien »: the message, the link, the article's name.
          await tester.tap(find.byKey(const Key('share-link')));
          await _settle(tester, 3);
          final sent = platform.calls.single;
          expect(sent, startsWith('text:'));
          expect(sent, contains(publicShopUrl(kind.shop.slug)));
          if (article != null) expect(sent, contains(kind.item(article).name));
        }
      });
    }
  });

  // -------------------------------------------------------------------------
  group('5. the four ways out', () {
    final png = Uint8List.fromList([1, 2, 3]);

    test('Android: WhatsApp and Facebook straight; their fallback is the sheet', () async {
      var p = _Platform(StatusOs.android);
      var s = StatusSharer(p);
      expect(await s.targets(), StatusTarget.values);
      expect(s.whatsAppHint, isFalse);
      expect(await s.send(StatusTarget.whatsapp, png, 'a.png', 't'), StatusOutcome.direct);
      expect(await s.send(StatusTarget.facebook, png, 'a.png', 't'), StatusOutcome.direct);
      expect(p.calls, ['whatsapp', 'facebook:$facebookAppId']);
      expect(facebookAppId, '1471844268381528');
      p = _Platform(StatusOs.android, whatsAppThere: false, facebookThere: false, saves: false);
      s = StatusSharer(p);
      expect(await s.send(StatusTarget.whatsapp, png, 'a.png', 't'), StatusOutcome.fallback);
      expect(await s.send(StatusTarget.facebook, png, 'a.png', 't'), StatusOutcome.fallback);
      expect(await s.send(StatusTarget.save, png, 'a.png', 't'), StatusOutcome.fallback);
      expect(p.calls, ['whatsapp', 'system:a.png', 'facebook:$facebookAppId', 'system:a.png', 'save:a.png', 'system:a.png']);
    });

    test('iOS: WhatsApp by the system sheet with its hint; Facebook\'s stories; the photos', () async {
      final p = _Platform(StatusOs.ios);
      final s = StatusSharer(p);
      expect(await s.targets(), StatusTarget.values);
      expect(s.whatsAppHint, isTrue);
      expect(await s.send(StatusTarget.whatsapp, png, 'a.png', 't'), StatusOutcome.direct);
      expect(await s.send(StatusTarget.facebook, png, 'a.png', 't'), StatusOutcome.direct);
      expect(await s.send(StatusTarget.others, png, 'a.png', 't'), StatusOutcome.direct);
      expect(await s.send(StatusTarget.save, png, 'a.png', 't'), StatusOutcome.saved);
      expect(p.calls, ['system:a.png', 'facebook:$facebookAppId', 'system:a.png', 'save:a.png']);
    });

    test('the web: « Partager… » where the browser shares files, the download always', () async {
      expect(await StatusSharer(_Platform(StatusOs.web)).targets(), [StatusTarget.others, StatusTarget.save]);
      expect(await StatusSharer(_Platform(StatusOs.web, webShare: false)).targets(), [StatusTarget.save]);
      final p = _Platform(StatusOs.web, saves: false);
      expect(await StatusSharer(p).send(StatusTarget.save, png, 'a.png', 't'), StatusOutcome.failed);
      expect(p.calls, ['save:a.png'], reason: 'no sheet to fall back to');
    });

    for (final (os, keys, hint) in [
      (StatusOs.android, ['whatsapp', 'facebook', 'others', 'save'], false),
      (StatusOs.ios, ['whatsapp', 'facebook', 'others', 'save'], true),
      (StatusOs.web, ['others', 'save'], false),
    ]) {
      testWidgets('the foot on ${os.name}', (tester) async {
        await _size(tester, const Size(390, 844));
        final p = _Platform(os);
        await tester.pumpWidget(_app(_preview(_farm, platform: p)));
        await _settle(tester, 3);
        for (final t in StatusTarget.values) {
          expect(find.byKey(Key('status-out-${t.name}')), keys.contains(t.name) ? findsOneWidget : findsNothing,
              reason: '${os.name} ${t.name}');
        }
        expect(find.byKey(const Key('status-ios-hint')), hint ? findsOneWidget : findsNothing);
        if (hint) expect(find.text('Choisissez WhatsApp'), findsOneWidget);
        if (os == StatusOs.web) {
          expect(find.text('Partager…'), findsOneWidget);
          expect(find.text('Autres…'), findsNothing);
        }
        expect(find.text('Choisissez WhatsApp, puis « Mon statut ».'), findsNothing);
      });
    }

    testWidgets('« Enregistrer » saves the picture, and says so', (tester) async {
      await _size(tester, const Size(390, 844));
      final p = _Platform(StatusOs.android);
      await tester.pumpWidget(_app(_preview(_assoc, platform: p)));
      await _settle(tester, 3);
      await tester.tap(find.byKey(const Key('status-out-save')));
      await _settle(tester, 10);
      expect(p.calls, ['save:${_assoc.shop.slug}.png']);
      expect(find.text('Image enregistrée dans vos photos.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('status-out-whatsapp')));
      await _settle(tester, 10);
      expect(p.calls.last, 'whatsapp');
    });
  });

  // -------------------------------------------------------------------------
  group('6. the memory', () {
    testWidgets('the design remembered, the articles never', (tester) async {
      await _size(tester, const Size(390, 844));
      final memory = _Memory();
      await tester.pumpWidget(_app(_preview(_farm, memory: memory)));
      await _settle(tester, 3);
      await tester.tap(find.byKey(const Key('status-design-bandeau')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('status-articles-row')));
      await _settle(tester, 3);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('status-article-labour')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('status-articles-done')));
      await _settle(tester, 3);
      await tester.pump(const Duration(milliseconds: 600));
      expect(memory.values.keys, [StatusMemory.keyFor(_farm.shop.orgId)]);
      expect(memory.values.values.single, startsWith('bandeau:'));
      // The next share: the design kept, « Automatique » again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(_preview(_farm, memory: memory)));
      await _settle(tester, 3);
      expect(_shown(tester).design, StatusDesign.bandeau);
      expect(find.text('Automatique'), findsOneWidget);
      expect(_shown(tester).items.map((i) => i.id), StatusCard.pick(_farm.items).map((i) => i.id));
    });

    testWidgets('opened from an article: Vedette, in the colour remembered', (tester) async {
      await _size(tester, const Size(390, 844));
      final memory = _Memory()..values[StatusMemory.keyFor(_assoc.shop.orgId)] = 'affiche:savane';
      await tester.pumpWidget(_app(_preview(_assoc, memory: memory, selection: StatusSelection.only('salle'))));
      await _settle(tester, 3);
      expect(_shown(tester).design, StatusDesign.vedette);
      expect(_shown(tester).palette?.id, 'savane');
      expect(_shown(tester).items.single.id, 'salle');
    });
  });

  // -------------------------------------------------------------------------
  group('7. the panel fits', () {
    for (final (size, scale) in const [(Size(390, 844), 1.0), (Size(360, 640), 1.0), (Size(320, 568), 1.3)]) {
      for (final locale in const [Locale('fr'), Locale('en')]) {
        testWidgets('${size.width.toInt()}×${size.height.toInt()} ×$scale ${locale.languageCode}', (tester) async {
          await _size(tester, size, scale: scale);
          await tester.pumpWidget(_app(_preview(_salon, selection: StatusSelection.only('s1')), locale: locale));
          await _settle(tester, 3);
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('status-articles-row')).hitTestable(), findsOneWidget);
          for (final d in StatusDesign.values) {
            expect(find.byKey(Key('status-design-${d.name}')).hitTestable(), findsOneWidget);
          }
          for (final t in StatusTarget.values) {
            expect(find.byKey(Key('status-out-${t.name}')).hitTestable(), findsOneWidget);
          }
          final card = tester.getRect(find.byKey(const Key('status-card')));
          expect(card.height, greaterThan(size.height * 0.28), reason: 'the preview stays the star: $card');
          // The article sheet too.
          await tester.tap(find.byKey(const Key('status-articles-row')));
          await _settle(tester, 3);
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('status-articles-done')).hitTestable(), findsOneWidget);
          expect(find.byKey(const Key('status-articles-single')).hitTestable(), findsOneWidget);
        });
      }
    }
  });

  // -------------------------------------------------------------------------
  group('8. « Ma vitrine » on the home', () {
    late LocalDb db;
    setUp(() async {
      HelpButton.reset();
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    for (final org in [_shopOrg, _farmOrg, _assocOrg]) {
      for (final (width, scale) in const [(390.0, 1.0), (360.0, 1.0), (320.0, 1.0), (390.0, 1.3), (360.0, 1.3), (320.0, 1.3)]) {
        for (final locale in const [Locale('fr'), Locale('en')]) {
          testWidgets('${org.profile} at $width px ×$scale ${locale.languageCode}: on the bar, the name whole',
              (tester) async {
            await _size(tester, Size(width, 800), scale: scale);
            await tester.pumpWidget(_app(_home(org, db), locale: locale));
            await _settle(tester);
            expect(tester.takeException(), isNull);
            final button = find.byKey(const Key('home-vitrine'));
            expect(button, findsOneWidget);
            final label = locale.languageCode == 'en' ? 'My vitrine' : 'Ma vitrine';
            final room = width / scale;
            final words = find.descendant(of: button, matching: find.text(label));
            expect(words, room < HelpButton.wordsWidth ? findsNothing : findsOneWidget, reason: 'room $room');
            expect(find.byTooltip(label), findsOneWidget);
            // Help: words, icon, or in Compte.
            final help = find.byKey(const Key('help-free-button'));
            expect(help, room < 300 ? findsNothing : findsOneWidget);
            // The name kept whole: no word cut inside.
            final title = find.text(org.name);
            expect(title, findsOneWidget);
            final text = tester.widget<Text>(title);
            final style = DefaultTextStyle.of(tester.element(title)).style.merge(text.style);
            final box = tester.getSize(title);
            for (final w in org.name.split(' ')) {
              final tp = TextPainter(
                text: TextSpan(text: w, style: style),
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(tester.element(title)),
              )..layout();
              expect(tp.width, lessThanOrEqualTo(box.width + 1), reason: '« $w » whole in ${box.width}');
              tp.dispose();
            }
            // Nor its end cut by an ellipsis (« Bâti… »).
            final all = TextPainter(
              text: TextSpan(text: org.name, style: style),
              textDirection: TextDirection.ltr,
              maxLines: text.maxLines,
              textScaler: MediaQuery.textScalerOf(tester.element(title)),
            )..layout(maxWidth: box.width + 0.5);
            expect(all.didExceedMaxLines, isFalse, reason: '${org.name} whole in ${box.width}');
            all.dispose();
          });
        }
      }
    }

    testWidgets('not for a trainer\'s look-only access, nor without an address', (tester) async {
      await _size(tester, const Size(390, 800));
      await tester.pumpWidget(_app(_home(_as(_shopOrg, roles: ['observer']), db)));
      await _settle(tester);
      expect(find.byKey(const Key('home-vitrine')), findsNothing);
      await tester.pumpWidget(_app(_home(_as(_farmOrg, slug: ''), db)));
      await _settle(tester);
      expect(find.byKey(const Key('home-vitrine')), findsNothing);
    });

    testWidgets('the tap opens the business\'s own vitrine', (tester) async {
      await _size(tester, const Size(390, 800));
      final went = <String>[];
      final router = GoRouter(initialLocation: '/o/${_assocOrg.id}', routes: [
        GoRoute(path: '/o/:orgId', builder: (_, _) => _home(_assocOrg, db)),
        GoRoute(
            path: '/s/:slug',
            builder: (_, state) {
              went.add(state.pathParameters['slug']!);
              return const Scaffold(body: Text('vitrine'));
            }),
      ]);
      await tester.pumpWidget(MaterialApp.router(
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        locale: const Locale('fr'),
        routerConfig: router,
      ));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('home-vitrine')));
      await _settle(tester);
      expect(went, ['atelier-lumiere']);
      expect(Routes.storefront('atelier-lumiere'), '/s/atelier-lumiere');
    });

    testWidgets('not yet visible to customers: the preview, with the banner and the way to open it', (tester) async {
      await _size(tester, const Size(390, 1200));
      final own = OrgSummary(
          id: _shop.shop.orgId, name: _shop.shop.name, slug: _shop.shop.slug, profile: 'retail', roles: const ['owner']);
      Future<void> open(PublicShop? answer, VitrineChecklist? c, List<OrgSummary> mine) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_app(StorefrontScreen(
          slug: _shop.shop.slug,
          storefront: _Street(answer, _shop.items),
          capture: CaptureRepository(null, db: db),
          session: _Session(db, mine, _Admin(c)),
        )));
        await _settle(tester);
      }

      // Short of the street's minimum: its own people see it, with the banner.
      await open(_shop.shop, const VitrineChecklist(published: 2, minItems: 5), [own]);
      expect(find.byKey(const Key('vitrine-hidden-banner')), findsOneWidget);
      expect(find.text('Votre vitrine n\'est pas encore visible des clients'), findsOneWidget);
      expect(find.text('Margherita'), findsWidgets, reason: 'the preview under it');
      // Visible: no banner.
      await open(_shop.shop, const VitrineChecklist(published: 7, minItems: 5), [own]);
      expect(find.byKey(const Key('vitrine-hidden-banner')), findsNothing);
      // Closed: the server shows nothing, its own people are told what to do.
      await open(null, const VitrineChecklist(open: false, published: 7), [own]);
      expect(find.text('Votre vitrine n\'est pas encore visible des clients'), findsOneWidget);
      expect(find.text('Ouvrir ou régler la vitrine'), findsOneWidget);
      // A stranger: as before.
      await open(null, null, const []);
      expect(find.text('Cette vitrine n\'existe pas, ou n\'est pas ouverte.'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 9. The review of 140: what an independent read found, kept fixed.
  // -------------------------------------------------------------------------
  group('9. review', () {
    const longShop = PublicShop(
      orgId: '14000000-0000-0000-0000-0000000000ff',
      name: 'Maison Élégance et Raffinement des Grands Boulevards Internationaux',
      slug: 'maison-elegance-et-raffinement-des-grands-boulevards',
      profile: 'retail',
      style: StorefrontStyle(
          tagline: 'Le meilleur du prêt-à-porter, des accessoires et des parfums, livrés chez vous en une heure'),
    );
    final longItems = [
      _i('L1', 'Robe de soirée longue en soie naturelle brodée à la main, collection prestige automne-hiver',
          1250000,
          photo: 'a', unit: 'pièce sur mesure'),
      _i('L2', 'Consultation personnalisée de style et de garde-robe complète', 750000,
          service: true, from: true, unit: 'séance de deux heures', photo: 'b'),
      _i('L3', 'Parfum Oud Royal édition limitée flacon cristal cent millilitres', 999999, inStock: false),
      _i('L4', 'Pagnes tissés Faso Dan Fani motifs traditionnels', 45000, on: DateTime(2027, 1, 15), unit: 'pagne'),
    ];

    for (final locale in const [Locale('fr'), Locale('en')]) {
      for (final n in [1, 4]) {
        testWidgets('long names ${locale.languageCode}, $n item(s): five designs, every palette, no overflow',
            (tester) async {
          await _size(tester, StatusCard.size);
          final chosen = n == 1 ? [longItems.first] : longItems;
          final photos = {
            for (final i in chosen)
              if (i.photoKey != null) i.id: _pixel
          };
          final base = StatusCard(shop: longShop, items: chosen, photos: photos);
          final errors = <String>[];
          for (final d in StatusDesign.values) {
            for (final p in base.palettes) {
              await tester.pumpWidget(_app(
                  StatusCard(shop: longShop, items: chosen, photos: photos, design: d, palette: p),
                  locale: locale));
              final e = tester.takeException();
              if (e != null) errors.add('${d.name} ${p.id}: $e');
            }
          }
          expect(errors, isEmpty);
        });
      }
    }

    testWidgets('only services: the picker says services, not articles', (tester) async {
      await _size(tester, const Size(390, 844));
      final services = _salon.items.where((i) => i.isService).toList();
      await tester.pumpWidget(_app(Scaffold(
          body: StatusArticlesSheet(
              catalogue: services, currency: 'XOF', selection: const StatusSelection(), onChanged: (_) {}))));
      await tester.pump();
      expect(find.text('SERVICES'), findsOneWidget);
      expect(find.text('ARTICLES'), findsNothing);
      expect(find.text('Services du statut'), findsOneWidget);
      expect(find.text('Un seul service (annonce)'), findsOneWidget);
      expect(find.text('Touchez jusqu\'à 4 services, dans l\'ordre où ils paraîtront.'), findsOneWidget);
      // And the preview's panel.
      await tester.pumpWidget(_app(StatusPreview(
        card: _salon.card(services.take(1).toList()),
        catalogue: services,
        name: 'a.png',
        text: 'A',
        memory: _Memory(),
        platform: _Platform(StatusOs.android),
      )));
      await _settle(tester, 2);
      expect(
          find.descendant(of: find.byKey(const Key('status-articles-row')), matching: find.text('SERVICES')),
          findsOneWidget);
    });

    test('search folds the ligatures: « oeufs » is « Œufs »', () {
      expect(foldSearchText('Œufs frais'), 'oeufs frais');
      expect(foldSearchText('Cæsar'), 'caesar');
      expect(foldSearchText('Café'), 'cafe');
    });

    testWidgets('search: « oeufs » finds « Œufs frais »', (tester) async {
      await _size(tester, const Size(390, 844));
      final many = [
        for (var k = 0; k < 13; k++) _i('x$k', 'Article $k', 1000),
        _i('eggs', 'Œufs frais', 2500),
      ];
      await tester.pumpWidget(_app(Scaffold(
          body: StatusArticlesSheet(
              catalogue: many, currency: 'XOF', selection: const StatusSelection(), onChanged: (_) {}))));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('status-articles-search')), 'oeufs');
      await tester.pump();
      expect(find.byKey(const Key('status-article-eggs')), findsOneWidget);
    });

    testWidgets('a chosen one gone from the catalogue: the count is the picture\'s', (tester) async {
      await _size(tester, const Size(390, 844));
      const stale = StatusSelection(['gone', 'a']);
      await tester.pumpWidget(_app(Scaffold(
          body: StatusArticlesSheet(catalogue: _shop.items, currency: 'XOF', selection: stale, onChanged: (_) {}))));
      await tester.pump();
      final label = tester.widget<Text>(find.byKey(const Key('status-articles-count'))).data;
      expect(label, '${stale.itemsIn(_shop.items).length}/4');
    });

    testWidgets('a double tap on a way out sends once', (tester) async {
      await _size(tester, const Size(390, 844));
      final p = _Platform(StatusOs.android);
      await tester.pumpWidget(_app(_preview(_assoc, platform: p)));
      await _settle(tester, 3);
      final f = find.byKey(const Key('status-out-whatsapp'));
      await tester.tap(f);
      await tester.tap(f);
      await _settle(tester, 10);
      expect(p.calls, ['whatsapp']);
    });

    test('Facebook: Mara\'s App ID; missing or failing, the system sheet', () async {
      expect(facebookAppId, '1471844268381528');
      final png = Uint8List(4);
      var p = _Platform(StatusOs.android, facebookThere: false);
      expect(await StatusSharer(p).send(StatusTarget.facebook, png, 'a.png', 'A'), StatusOutcome.fallback);
      expect(p.calls, ['facebook:1471844268381528', 'system:a.png']);
      final broken = _Broken(StatusOs.ios);
      expect(await StatusSharer(broken).send(StatusTarget.facebook, png, 'a.png', 'A'), StatusOutcome.fallback);
      expect(broken.calls, ['system:a.png']);
    });

    for (final role in ['observer', 'platform_admin']) {
      testWidgets('the vitrine for a $role: not its own — no banner, no article Partager, no checklist asked',
          (tester) async {
        await _size(tester, const Size(390, 1600));
        final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
        final org = OrgSummary(
            id: _farm.shop.orgId, name: _farm.shop.name, slug: _farm.shop.slug, profile: 'farm', roles: [role]);
        final admin = _Admin(const VitrineChecklist(published: 1, minItems: 5));
        await tester.pumpWidget(_app(StorefrontScreen(
          slug: _farm.shop.slug,
          storefront: _Street(_farm.shop, _farm.items),
          capture: CaptureRepository(null, db: db),
          session: _Session(db, [org], admin),
        )));
        await _settle(tester);
        expect(find.byKey(const Key('vitrine-hidden-banner')), findsNothing);
        expect(admin.asked, 0);
        await tester.tap(find.text('Œufs frais').first);
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byKey(const Key('article-share')), findsNothing);
      });
    }

    testWidgets('a platform admin on a closed vitrine: the street\'s notice, not the owner\'s', (tester) async {
      await _size(tester, const Size(390, 844));
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      final org = OrgSummary(
          id: _farm.shop.orgId, name: _farm.shop.name, slug: _farm.shop.slug, profile: 'farm', roles: const ['platform_admin']);
      await tester.pumpWidget(_app(StorefrontScreen(
        slug: _farm.shop.slug,
        storefront: _Street(null, const []),
        capture: CaptureRepository(null, db: db),
        session: _Session(db, [org], _Admin(null)),
      )));
      await _settle(tester);
      expect(find.text('Votre vitrine n\'est pas encore visible des clients'), findsNothing);
      expect(find.text('Cette vitrine n\'existe pas, ou n\'est pas ouverte.'), findsOneWidget);
    });

    Future<void> openSheet(WidgetTester tester, {required bool mine, required AdminRepository admin}) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => ShareVitrine.open(context,
                  shop: _farm.shop,
                  items: _farm.items,
                  article: _farm.item('a'),
                  mine: mine,
                  admin: admin,
                  platform: _Platform(StatusOs.android)),
              child: const Text('go'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('go'));
      await _settle(tester, 3);
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('an ad for a vitrine the street cannot see: the sheet says so, « Régler »', (tester) async {
      await _size(tester, const Size(390, 844));
      await openSheet(tester, mine: true, admin: _Admin(const VitrineChecklist(published: 1, minItems: 5)));
      expect(find.byKey(const Key('share-hidden')), findsOneWidget);
      expect(find.text('Votre vitrine n\'est pas encore visible : vos clients ne la verront pas.'), findsOneWidget);
      expect(find.byKey(const Key('share-hidden-open')), findsOneWidget);
      expect(find.byKey(const Key('share-image')), findsOneWidget, reason: 'still offered: a preview to prepare');
      expect(tester.takeException(), isNull);
      // Closed by its switch, enough articles or not.
      await openSheet(tester, mine: true, admin: _Admin(const VitrineChecklist(published: 9, open: false)));
      expect(find.byKey(const Key('share-hidden')), findsOneWidget);
    });

    testWidgets('a visible vitrine, or a passer-by: no line, nothing asked of a passer-by', (tester) async {
      await _size(tester, const Size(390, 844));
      await openSheet(tester, mine: true, admin: _Admin(const VitrineChecklist(published: 5, minItems: 5)));
      expect(find.byKey(const Key('share-hidden')), findsNothing);
      final admin = _Admin(const VitrineChecklist(published: 0, minItems: 5));
      await openSheet(tester, mine: false, admin: admin);
      expect(find.byKey(const Key('share-hidden')), findsNothing);
      expect(admin.asked, 0);
    });

    testWidgets('an ad: a colour changed keeps the design remembered (not Vedette); Surprise too', (tester) async {
      await _size(tester, const Size(390, 844));
      final memory = _Memory()..values[StatusMemory.keyFor(_assoc.shop.orgId)] = 'affiche:savane';
      await tester.pumpWidget(_app(_preview(_assoc,
          memory: memory,
          selection: StatusSelection.only('salle'),
          initial: const StatusChoice(StatusDesign.vedette, 'savane'))));
      await _settle(tester, 3);
      expect(_shown(tester).design, StatusDesign.vedette);
      final other = _shown(tester).palettes.firstWhere((p) => p.id != 'savane');
      await tester.ensureVisible(find.byKey(Key('status-colour-${other.id}')));
      await tester.tap(find.byKey(Key('status-colour-${other.id}')));
      await _settle(tester, 3);
      expect(memory.values.values.single, 'affiche:${other.id}');
      await tester.tap(find.byKey(const Key('status-surprise')));
      await _settle(tester, 3);
      expect(memory.values.values.single, startsWith('affiche:'));
      // A design picked on its thumbnail is the owner's: remembered.
      final pick = StatusDesign.values.firstWhere((d) => d != _shown(tester).design && d != StatusDesign.affiche);
      await tester.ensureVisible(find.byKey(Key('status-design-${pick.name}')));
      await tester.tap(find.byKey(Key('status-design-${pick.name}')));
      await _settle(tester, 3);
      expect(memory.values.values.single, startsWith('${pick.name}:'));
    });

    testWidgets('« Partager » on an article, tapped twice: one sheet', (tester) async {
      await _size(tester, const Size(390, 844));
      const salle = Product(
          id: 'salle', name: 'Location de la salle', salePrice: 15000, isService: true, isPublished: true);
      await tester.pumpWidget(_app(Scaffold(
          body: ShareArticleButton(
              org: _assocOrg,
              product: salle,
              storefront: _Street(null, const []),
              platform: _Platform(StatusOs.android)))));
      await tester.tap(find.byKey(const Key('share-article-salle')));
      await tester.tap(find.byKey(const Key('share-article-salle')), warnIfMissed: false);
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('share-vitrine')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Screenshots (B140_SHOTS=<dir>)
  // -------------------------------------------------------------------------
  final shots = Platform.environment['B140_SHOTS'];
  group('screenshots', () {
    Future<void> capture(WidgetTester tester, Finder boundary, String path, double ratio) async {
      final element = tester.element(boundary);
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          try {
            await precacheImage(image.image, element).timeout(const Duration(seconds: 2));
          } catch (_) {}
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

    Widget framed(Widget child, {Locale locale = const Locale('fr')}) =>
        RepaintBoundary(key: const Key('screen'), child: KeyedSubtree(key: UniqueKey(), child: _app(child, locale: locale)));

    testWidgets('the five designs with one article, each kind, at 540 × 960', (tester) async {
      Directory(shots!).createSync(recursive: true);
      await _size(tester, StatusCard.size);
      final picks = <(String, _Kind, String, String)>[
        ('shop', _shop, 'a', 'graphite'),
        ('shop-nophoto', _shop, 'd', 'papier'),
        ('salon-service', _salon, 's1', 'terre'),
        ('farm-plateau', _farm, 'a', 'savane'),
        ('farm-labour', _farm, 'labour', 'caramel'),
        ('assoc-salle', _assoc, 'salle', 'nuit'),
        ('assoc-tshirt', _assoc, 'tshirt', 'espresso'),
      ];
      for (final (label, kind, id, palette) in picks) {
        for (final d in StatusDesign.values) {
          final p = StatusPalette.curated.firstWhere((x) => x.id == palette);
          const k = Key('shot');
          await tester.pumpWidget(_app(Center(
              child: RepaintBoundary(key: k, child: kind.card([kind.item(id)], design: d, palette: p)))));
          expect(tester.takeException(), isNull);
          await capture(tester, find.byKey(k), '$shots/ad_${label}_${d.name}.png', 0.5);
        }
      }
    }, skip: shots == null);

    testWidgets('the panel, the article sheet, the share sheet, the foot — FR and EN', (tester) async {
      Directory(shots!).createSync(recursive: true);
      for (final (size, scale, tag) in const [(Size(390, 844), 1.0, '390x844'), (Size(320, 640), 1.3, '320x640_1.3')]) {
        await _size(tester, size, scale: scale);
        for (final locale in const [Locale('fr'), Locale('en')]) {
          final lang = locale.languageCode;
          await tester.pumpWidget(framed(_preview(_salon, initial: const StatusChoice(StatusDesign.grille, 'papier')),
              locale: locale));
          await _settle(tester, 3);
          await capture(tester, find.byKey(const Key('screen')), '$shots/panel_${tag}_$lang.png', 2);
          await tester.tap(find.byKey(const Key('status-articles-row')));
          await _settle(tester, 3);
          await tester.pump(const Duration(milliseconds: 600));
          await tester.tap(find.byKey(const Key('status-article-s2')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('status-article-s3')));
          await _settle(tester, 3);
          await capture(tester, find.byKey(const Key('screen')), '$shots/articles_${tag}_$lang.png', 2);
          // iOS foot, with its hint.
          await tester.pumpWidget(framed(
              _preview(_farm, selection: StatusSelection.only('a'), platform: _Platform(StatusOs.ios)),
              locale: locale));
          await _settle(tester, 3);
          await capture(tester, find.byKey(const Key('screen')), '$shots/foot_ios_${tag}_$lang.png', 2);
          await tester.pumpWidget(framed(
              _preview(_farm, selection: StatusSelection.only('a'), platform: _Platform(StatusOs.web)),
              locale: locale));
          await _settle(tester, 3);
          await capture(tester, find.byKey(const Key('screen')), '$shots/foot_web_${tag}_$lang.png', 2);
          // The share sheet, for a whole vitrine and for one service.
          for (final (name, article) in [('vitrine', null), ('service', 'salle')]) {
            await tester.pumpWidget(framed(
                Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => ShareVitrine.open(context,
                            shop: _assoc.shop,
                            items: _assoc.items,
                            mine: true,
                            article: article == null ? null : _assoc.item(article)),
                        child: const Text('go'),
                      ),
                    ),
                  ),
                ),
                locale: locale));
            await tester.tap(find.text('go'));
            await _settle(tester, 4);
            await tester.pump(const Duration(milliseconds: 600));
            expect(tester.takeException(), isNull);
            await capture(tester, find.byKey(const Key('screen')), '$shots/sheet_${name}_${tag}_$lang.png', 2);
          }
        }
      }
    }, skip: shots == null);

    testWidgets('the Catalogue entry point, the vitrine\'s article sheet', (tester) async {
      Directory(shots!).createSync(recursive: true);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(db.close);
      await _size(tester, const Size(390, 844));
      const salle = Product(
          id: 'salle', name: 'Location de la salle', salePrice: 15000, isService: true, isPublished: true, unit: 'soirée');
      const cours = Product(id: 'c', name: 'Cours de couture', salePrice: 5000, isService: true, isPublished: true, priceFrom: true);
      await tester.pumpWidget(framed(Scaffold(body: ServicesScreen(org: _assocOrg, retail: _Shelf(const [salle, cours])))));
      await _settle(tester);
      await capture(tester, find.byKey(const Key('screen')), '$shots/catalogue_services_row.png', 2);
      await tester.pumpWidget(framed(ProductsScreen(org: _shopOrg, retail: _Shelf(const [
        Product(id: 'ciment', name: 'Ciment CPJ 45', salePrice: 6750, quantity: 30, isPublished: true),
      ]))));
      await _settle(tester);
      await tester.tap(find.byTooltip('Sur la vitrine — modifier'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
      await _settle(tester, 3);
      await capture(tester, find.byKey(const Key('screen')), '$shots/catalogue_article_sheet.png', 2);
      final own = OrgSummary(
          id: _farm.shop.orgId, name: _farm.shop.name, slug: _farm.shop.slug, profile: 'farm', roles: const ['owner']);
      await tester.pumpWidget(framed(StorefrontScreen(
        slug: _farm.shop.slug,
        storefront: _Street(_farm.shop, _farm.items),
        capture: CaptureRepository(null, db: db),
        session: _Session(db, [own], _Admin(const VitrineChecklist(published: 1, minItems: 3))),
      )));
      await _settle(tester);
      await capture(tester, find.byKey(const Key('screen')), '$shots/vitrine_hidden_banner.png', 2);
      await tester.tap(find.text('Œufs frais').first);
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await capture(tester, find.byKey(const Key('screen')), '$shots/vitrine_article_share.png', 2);
    }, skip: shots == null);

    testWidgets('the three homes\' top bars at 390 and 320 × 1.3', (tester) async {
      Directory(shots!).createSync(recursive: true);
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(db.close);
      for (final (w, scale) in const [(390.0, 1.0), (360.0, 1.0), (320.0, 1.3)]) {
        await _size(tester, Size(w, 640), scale: scale);
        for (final org in [_shopOrg, _farmOrg, _assocOrg]) {
          HelpButton.reset();
          await tester.pumpWidget(framed(_home(org, db)));
          await _settle(tester);
          await capture(tester, find.byKey(const Key('screen')), '$shots/home_${org.profile}_${w.toInt()}_$scale.png', 2);
        }
      }
    }, skip: shots == null);
  });
}
