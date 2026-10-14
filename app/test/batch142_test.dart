// Batch 142 (migration 139): « Mettre en avant » for 7 days, sold through
// the store in the Android and iPhone apps and by card on the website, at
// a price per zone; « Voir à quoi ça ressemble »; Mara Pro by card at the
// zone's own price; Réglages' zone prices.
//
//   1. the sheet sells 7 days only — two products, no 30-day choice, the
//      server asked 7; Pro is promised nothing free;
//   2. the zone prices on the website: XOF, EUR, USD (a business in
//      cedis), an XAF business the FCFA number; French and English;
//   3. the website: Stripe by card; Wave and « J'ai payé » in francs only;
//   4. Android (Google Play) and iPhone (App Store): the store's product
//      and its own price, and nothing else — no card, no Wave, no « J'ai
//      payé », no WhatsApp; the purchase names the spot; the listener's
//      word closes the sheet; nothing offered before 139 or without the
//      store's product; « Vérifier un achat déjà payé »;
//   5. the purchase listener: a spot's purchase verified as a spot, never
//      as Mara Pro; Apple's finished, Google's left to the Worker;
//   6. the preview — a shop's article, a farm's vitrine, an association's
//      vitrine — its own name, photo and price, « Sponsorisé », French
//      and English;
//   7. Mara Pro by card at the zone price; before 139 the francs;
//   8. Réglages: the zone prices, to the cent, the stores' line;
//   9. 320 px with text ×1.3, French and English: nothing overflows.
//
// B142_SHOTS=<dir> also writes the screenshots (390 × 844 and 320 px at
// text ×1.3, French and English).

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/access/store_rules.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/pay/price_zone.dart';
import 'package:kaj_app/core/pay/wave_pay.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/admin/spot_preview.dart';
import 'package:kaj_app/features/admin/spots_card.dart';
import 'package:kaj_app/features/pay/stripe_button.dart';
import 'package:kaj_app/features/pro/store_billing.dart';
import 'package:kaj_app/features/pro/store_watcher.dart';
import 'package:kaj_app/l10n/strings.dart';

// ---------------------------------------------------------------------------
// The businesses (the owner's naming rule: brand-like names, no first names;
// Ouagadougou the only Burkina town)
// ---------------------------------------------------------------------------

const _shop = OrgSummary(
    id: '14200000-0000-0000-0000-000000000001', name: 'Maison Élégance', profile: 'retail',
    currency: 'XOF', roles: ['owner'], plan: 'pro');
const _farm = OrgSummary(
    id: '14200000-0000-0000-0000-000000000002', name: 'Ferme Horizon Vert', profile: 'farm',
    currency: 'XOF', roles: ['owner']);
const _assoc = OrgSummary(
    id: '14200000-0000-0000-0000-000000000003', name: 'Fondation Espoir', profile: 'association',
    currency: 'XOF', roles: ['owner']);
const _euro = OrgSummary(
    id: '14200000-0000-0000-0000-000000000004', name: 'Le Comptoir Doré', profile: 'retail',
    currency: 'EUR', roles: ['owner']);
const _dollar = OrgSummary(
    id: '14200000-0000-0000-0000-000000000005', name: 'Domaine des Acacias', profile: 'farm',
    currency: 'GHS', roles: ['owner']);
const _cfa = OrgSummary(
    id: '14200000-0000-0000-0000-000000000006', name: 'Atelier Lumière', profile: 'retail',
    currency: 'XAF', roles: ['owner']);

const _terms = SpotTerms(
  wave: '+226 70 00 00 00',
  waveName: 'Mara',
  maxLive: 8,
  zones: {
    'XOF': (article: 1000, shop: 2500),
    'EUR': (article: 1.99, shop: 4.99),
    'USD': (article: 2.49, shop: 5.99),
  },
  stripeOn: true,
  version: 139,
);

late Uint8List _picture;

Future<Uint8List> _drawPicture() async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  c.drawRect(const Rect.fromLTWH(0, 0, 96, 96), Paint()..color = const Color(0xFF3B3A38));
  c.drawCircle(const Offset(48, 40), 24, Paint()..color = const Color(0xFFC49A6C));
  c.drawRect(const Rect.fromLTWH(18, 66, 60, 20), Paint()..color = const Color(0xFF8B5A3C));
  final image = await recorder.endRecording().toImage(96, 96);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class _Admin extends AdminRepository {
  _Admin({this.terms = _terms}) : super(null);

  final SpotTerms terms;
  final asked = <String>[];
  final claimed = <String>[];
  List<Promotion> mine = const [];

  @override
  Future<SpotTerms> spotTerms() async => terms;

  @override
  Future<String> requestPromotion(String orgId, {String? productId, required int days}) async {
    asked.add('${productId ?? 'shop'}:$days');
    mine = [
      Promotion(
          id: 'pm-142',
          kind: productId == null ? 'shop' : 'article',
          productId: productId,
          productName: productId == null ? null : 'Robe de soirée',
          days: days,
          price: 1.99,
          currency: 'EUR',
          status: 'requested'),
    ];
    return 'pm-142';
  }

  @override
  Future<void> claimPromotionPaid(String promotionId, {String? note}) async => claimed.add(promotionId);

  @override
  Future<List<Promotion>> myPromotions(String orgId) async => mine;
}

class _Retail extends RetailRepository {
  _Retail(this.items) : super(null);

  final List<Product> items;

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => items;

  @override
  Future<Map<String, String>> photoKeys(String orgId) async =>
      {for (final p in items) p.id: 'org/$orgId/${p.id}.jpg'};
}

final _shopItems = _Retail(const [
  Product(id: 'p-robe', name: 'Robe de soirée', salePrice: 25000, quantity: 3, isPublished: true),
  Product(id: 'p-sac', name: 'Sac en cuir', salePrice: 18000, quantity: 2, isPublished: true),
]);
final _farmItems = _Retail(const [
  Product(id: 'p-oeufs', name: 'Plateau d\'œufs', salePrice: 2500, quantity: 40, isPublished: true),
]);
final _euroItems = _Retail(const [
  Product(id: 'p-the', name: 'Coffret de thé', salePrice: 18, quantity: 9, isPublished: true),
]);

class _Store implements SpotStoreBilling {
  _Store(this.platform, {this.products = const []});

  @override
  final String platform;
  final List<SpotStoreProduct> products;
  final bought = <String>[];
  int restored = 0;

  @override
  Future<List<SpotStoreProduct>> spotProducts() async => products;

  @override
  Future<void> buySpot(SpotStoreProduct product, {required String orgId, required String promotionId}) async {
    bought.add('${product.id}|$orgId|$promotionId');
  }

  @override
  Future<void> restore() async => restored++;

  @override
  Future<List<StorePurchase>> unfinishedSpots() async => const [];
}

const _googleProducts = [
  SpotStoreProduct(id: 'mara_spot_article_7', kind: 'article', price: 'CFA 1,200', rawPrice: 1200, currencyCode: 'XOF'),
  SpotStoreProduct(id: 'mara_spot_shop_7', kind: 'shop', price: 'CFA 2,900', rawPrice: 2900, currencyCode: 'XOF'),
];
const _appleProducts = [
  SpotStoreProduct(id: 'bf.kaj.app.spot.article7', kind: 'article', price: '1,99 €', rawPrice: 1.99, currencyCode: 'EUR'),
  SpotStoreProduct(id: 'bf.kaj.app.spot.shop7', kind: 'shop', price: '4,99 €', rawPrice: 4.99, currencyCode: 'EUR'),
];

class _Pay extends WavePay {
  _Pay() : super(null, url: 'https://pay.example');

  final cards = <String>[];

  @override
  bool get compiledIn => true;

  @override
  Future<String> spotByCard(String promotionId) async {
    cards.add(promotionId);
    throw StateError('no browser in a test');
  }

  @override
  Future<WaveTerms> terms({String? orgId}) async => const WaveTerms();
}

class _Center extends CommandCenterRepository {
  _Center() : super(null);

  Map<String, SettingValue> values = const {};
  final calls = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<Map<String, SettingValue>> settings() async => values;

  @override
  Future<String?> setSetting(String key, Object? value) async {
    calls.add('set:$key=$value');
    return null;
  }
}

/// A minimal store for the purchase listener: what it completes, and the
/// spots it still holds unconsumed.
class _ProStore implements StoreBilling, SpotStoreBilling {
  _ProStore(this.platform, {this.unfinished = const []});

  @override
  final String platform;
  final List<StorePurchase> unfinished;
  int asked = 0;
  @override
  Future<List<StorePurchase>> unfinishedSpots() async {
    asked++;
    return unfinished;
  }

  @override
  Future<List<SpotStoreProduct>> spotProducts() async => const [];
  @override
  Future<void> buySpot(SpotStoreProduct product, {required String orgId, required String promotionId}) async {}
  final completed = <String>[];
  final _stream = StreamController<List<StorePurchase>>.broadcast();

  @override
  Future<bool> available() async => true;
  @override
  Future<List<StoreProduct>> products() async => const [];
  @override
  Stream<List<StorePurchase>> get purchases => _stream.stream;
  @override
  Future<void> buy(StoreProduct product, {required String orgId}) async {}
  @override
  Future<void> restore() async {}
  @override
  Future<void> complete(StorePurchase purchase) async => completed.add(purchase.productId);
  @override
  Uri get manageUrl => Uri.parse('https://example.org');
  @override
  Future<List<StoreOwned>> owned() async => const [];
}

// ---------------------------------------------------------------------------
// The harness
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
      theme: kajTheme(kajPalette),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => RepaintBoundary(key: const Key('shot'), child: child!),
      home: home,
    );

/// A page with one button that opens the sheet, as the settings do.
Widget _opener(
  OrgSummary org, {
  required _Admin admin,
  RetailRepository? retail,
  SpotStoreSide? store,
  WavePay? pay,
  bool vitrineOnly = false,
  Promotion? asked,
  String lang = 'fr',
}) =>
    _app(
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => asked != null
                  ? SpotSheet.pay(context, orgId: org.id, spot: asked, admin: admin, org: org, store: store, pay: pay)
                  : SpotSheet.open(context,
                      orgId: org.id,
                      admin: admin,
                      retail: retail,
                      vitrineOnly: vitrineOnly,
                      org: org,
                      store: store,
                      pay: pay,
                      photo: (_) async => _picture),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      lang: lang,
    );

Future<void> _open(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.tap(find.text('open'));
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 120,
      scrollable: find.ancestor(of: find.byKey(const Key('spot-sheet')).first, matching: find.byType(Scrollable)).first,
      maxScrolls: 60);
}

/// A finder for an exact text that may sit in a RichText (a button label).
Finder _has(String s) => find.textContaining(s, findRichText: true);

void _platform(String? store) {
  debugStoreBillingPlatform = store == 'appstore' ? 'apple' : (store == 'play' ? 'google' : null);
  debugSellsDigitalInApp = store != 'appstore';
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    _picture = await _drawPicture();
    // A tap that would miss is a failure here, never a warning.
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDown(() {
    debugStoreBillingPlatform = null;
    debugSellsDigitalInApp = null;
    storeBillingOn = false;
  });

  // -------------------------------------------------------------------------
  group('1. 7 days only', () {
    testWidgets('two products, no 30-day choice, the server is asked 7 days; nothing free for Pro', (tester) async {
      await _size(tester, 390, 1000);
      final admin = _Admin();
      await _open(tester, _opener(_shop, admin: admin, retail: _shopItems));
      expect(find.text('Un article à la une, 7 jours'), findsOneWidget);
      expect(find.text('30 jours'), findsNothing);
      expect(find.text('Combien de temps ?'), findsNothing);
      expect(find.textContaining('Offert'), findsNothing, reason: 'Pro pays too');
      expect(find.textContaining('pendant 7 jours'), findsOneWidget);

      await tester.tap(find.text('La boutique'));
      await tester.pumpAndSettle();
      expect(find.text('La boutique à la une, 7 jours'), findsOneWidget);
      await _scrollTo(tester, find.byKey(const Key('spot-go')));
      await tester.tap(find.byKey(const Key('spot-go')));
      await tester.pumpAndSettle();
      expect(admin.asked, ['shop:7']);
    });

    testWidgets('a farm and an association name their own vitrine product', (tester) async {
      await _size(tester, 390, 1000);
      await _open(tester, _opener(_farm, admin: _Admin(), retail: _farmItems));
      await tester.tap(find.text('La ferme'));
      await tester.pumpAndSettle();
      expect(find.text('La ferme à la une, 7 jours'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _open(tester, _opener(_assoc, admin: _Admin(), retail: null, vitrineOnly: true));
      expect(find.text('L\'association à la une, 7 jours'), findsOneWidget);
      expect(find.byKey(const Key('spot-what')), findsNothing, reason: 'an association buys its vitrine only');
    });
  });

  // -------------------------------------------------------------------------
  group('2. the zone prices on the website', () {
    for (final (org, retail, article, shop, currency) in [
      (_shop, _shopItems, 1000.0, 2500.0, 'XOF'),
      (_euro, _euroItems, 1.99, 4.99, 'EUR'),
      (_dollar, _farmItems, 2.49, 5.99, 'USD'),
      (_cfa, _shopItems, 1000.0, 2500.0, 'XAF'),
    ]) {
      testWidgets('${org.name} (${org.currency}) is priced in its zone', (tester) async {
        await _size(tester, 390, 1000);
        await _open(tester, _opener(org, admin: _Admin(), retail: retail));
        expect(find.text('Prix : ${zonePriceText(article, currency, language: 'fr')}'), findsOneWidget);
        await tester.tap(find.byKey(const Key('spot-what')).evaluate().isEmpty
            ? find.text('La boutique')
            : find.descendant(of: find.byKey(const Key('spot-what')), matching: find.byIcon(Icons.storefront_outlined)));
        await tester.pumpAndSettle();
        expect(find.text('Prix : ${zonePriceText(shop, currency, language: 'fr')}'), findsOneWidget);
      });
    }

    test('the zones and how they read, in French and in English', () {
      expect(priceZoneOf('XOF'), PriceZone.xof);
      expect(priceZoneOf('XAF'), PriceZone.xof);
      expect(priceZoneOf('EUR'), PriceZone.eur);
      expect(priceZoneOf('GHS'), PriceZone.usd);
      expect(priceZoneOf('USD'), PriceZone.usd);
      expect(zoneCurrencyOf('XAF'), 'XAF');
      expect(zoneCurrencyOf('NGN'), 'USD');
      // An XAF business reads the same FCFA number.
      expect(zonePriceText(1000, 'XAF'), zonePriceText(1000, 'XOF'));
      expect(zonePriceText(1000, 'XOF'), endsWith('FCFA'));
      expect(zonePriceText(1.99, 'EUR', language: 'fr'), matches(RegExp(r'^1,99\s€$')));
      expect(zonePriceText(1.99, 'EUR', language: 'en'), '€1.99');
      expect(zonePriceText(2.49, 'USD', language: 'en'), r'$2.49');
      expect(zonePriceText(2.49, 'USD', language: 'fr'), matches(RegExp(r'^2,49\s\$ US$')));
      expect(zonePriceText(5, 'EUR', language: 'en'), '€5', reason: 'a whole euro has no ,00');
      expect(_terms.zonePrice('EUR', shop: true), 4.99);
      expect(_terms.zoneCurrency('XAF'), 'XAF');
      // Before 139: the francs, for everyone, as the server asks then.
      const old = SpotTerms();
      expect(old.zonePrice('EUR', shop: false), 1000);
      expect(old.zoneCurrency('EUR'), 'XOF');
      expect(old.paidOnline, isFalse);
      expect(SpotTerms.fromJson({
        'article_7': 1000, 'shop_7': 2500, 'version': 139, 'stripe_on': true,
        'zones': {'EUR': {'article': 1.99, 'shop': 4.99}},
      }).zonePrice('EUR', shop: false), 1.99);
    });

    testWidgets('in English', (tester) async {
      await _size(tester, 390, 1000);
      await _open(tester, _opener(_euro, admin: _Admin(), retail: _euroItems, lang: 'en'));
      expect(find.text('One item featured, 7 days'), findsOneWidget);
      expect(find.text('Price: €1.99'), findsOneWidget);
      expect(find.text('See what it looks like'), findsOneWidget);
      await tester.tap(find.text('The shop'));
      await tester.pumpAndSettle();
      expect(find.text('The shop featured, 7 days'), findsOneWidget);
      expect(find.text('Price: €4.99'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('3. the website: Stripe by card', () {
    testWidgets('a business in euros pays by card only; the card door names the spot', (tester) async {
      await _size(tester, 390, 1000);
      final pay = _Pay();
      final admin = _Admin();
      await _open(tester, _opener(_euro, admin: admin, retail: _euroItems, pay: pay));
      await _scrollTo(tester, find.byKey(const Key('spot-go')));
      expect(find.text('Continuer vers le paiement'), findsOneWidget);
      await tester.tap(find.byKey(const Key('spot-go')));
      await tester.pumpAndSettle();
      expect(admin.asked, ['p-the:7']);
      expect(find.byKey(const Key('spot-card')), findsOneWidget);
      expect(find.text('J\'ai payé'), findsNothing, reason: 'by hand and Wave are the francs\' only');
      expect(find.byKey(const Key('spot-pay-whatsapp')), findsNothing);
      await tester.tap(find.byKey(const Key('spot-card')));
      await tester.pumpAndSettle();
      expect(pay.cards, ['pm-142']);
    });

    testWidgets('a business in francs: the card, and Wave and « J\'ai payé » as today', (tester) async {
      await _size(tester, 390, 1400);
      final admin = _Admin();
      await _open(tester, _opener(_shop, admin: admin, retail: _shopItems, pay: _Pay()));
      await _scrollTo(tester, find.byKey(const Key('spot-go')));
      await tester.tap(find.byKey(const Key('spot-go')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spot-card')), findsOneWidget);
      await _scrollTo(tester, find.text('J\'ai payé'));
      expect(find.text('+226 70 00 00 00'), findsOneWidget);
      await tester.tap(find.text('J\'ai payé'));
      await tester.pumpAndSettle();
      expect(admin.claimed, ['pm-142']);
    });

    testWidgets('a business in XAF: the card only — Wave takes no XAF, nor « J\'ai payé »', (tester) async {
      await _size(tester, 390, 1400);
      final admin = _Admin();
      await _open(tester, _opener(_cfa, admin: admin, retail: _shopItems, pay: _Pay()));
      await _scrollTo(tester, find.byKey(const Key('spot-go')));
      await tester.tap(find.byKey(const Key('spot-go')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spot-card')), findsOneWidget);
      expect(find.text('J\'ai payé'), findsNothing);
      expect(find.text('+226 70 00 00 00'), findsNothing);
    });

    testWidgets('the card off: a business in euros is told it opens soon, nothing else', (tester) async {
      await _size(tester, 390, 1000);
      final admin = _Admin(terms: const SpotTerms(zones: {'EUR': (article: 1.99, shop: 4.99)}, version: 139));
      await _open(tester, _opener(_euro, admin: admin, retail: _euroItems, pay: _Pay()));
      await _scrollTo(tester, find.byKey(const Key('spot-go')));
      await tester.tap(find.byKey(const Key('spot-go')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spot-card')), findsNothing);
      expect(find.byKey(const Key('spot-card-soon')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('4. the store apps: the store alone', () {
    for (final (store, products, name) in [
      ('play', _googleProducts, 'Google Play'),
      ('appstore', _appleProducts, 'l\'App Store'),
    ]) {
      testWidgets('$store: the store\'s product and price, nothing else; the purchase names the spot', (tester) async {
        _platform(store);
        await _size(tester, 390, 1000);
        final billing = _Store(store == 'play' ? 'google' : 'apple', products: products);
        final notices = ValueNotifier<SpotNotice?>(null);
        final admin = _Admin();
        await _open(
            tester,
            _opener(_shop,
                admin: admin,
                retail: _shopItems,
                store: SpotStoreSide(billing: billing, notices: notices),
                pay: _Pay()));
        expect(find.text('Prix : ${products.first.price}'), findsOneWidget, reason: 'the store\'s own price');
        expect(find.text('Prix : ${zonePriceText(1000, 'XOF')}'), findsNothing, reason: 'never Mara\'s');
        expect(find.textContaining(name), findsOneWidget);
        expect(find.text('Continuer vers le paiement'), findsNothing);
        await _scrollTo(tester, find.byKey(const Key('spot-go')));
        expect(_has('Acheter · ${products.first.price}'), findsOneWidget);
        // Two taps in one frame: asked once, bought once.
        await tester.tap(find.byKey(const Key('spot-go')));
        await tester.tap(find.byKey(const Key('spot-go')), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(admin.asked, ['p-robe:7']);
        expect(billing.bought, ['${products.first.id}|${_shop.id}|pm-142']);
        // In the apps: no card, no Wave, no « J'ai payé », no WhatsApp.
        expect(find.byKey(const Key('spot-card')), findsNothing);
        expect(find.text('J\'ai payé'), findsNothing);
        expect(find.text('Payer avec Wave'), findsNothing);
        expect(find.byKey(const Key('spot-pay-whatsapp')), findsNothing);
        // The listener's word: paid and programmed.
        notices.value = SpotNotice('pm-142', SpotNoticeState.done, (c) => 'ok');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('spot-done')), findsOneWidget);
        expect(find.text('C\'est payé.'), findsOneWidget);
        notices.dispose();
      });
    }

    testWidgets('a refusal says why and leaves the sheet; another spot\'s word is not this one\'s', (tester) async {
      _platform('play');
      await _size(tester, 390, 1000);
      final notices = ValueNotifier<SpotNotice?>(null);
      await _open(
          tester,
          _opener(_shop,
              admin: _Admin(),
              retail: _shopItems,
              store: SpotStoreSide(billing: _Store('google', products: _googleProducts), notices: notices)));
      await _scrollTo(tester, find.byKey(const Key('spot-go')));
      await tester.tap(find.byKey(const Key('spot-go')));
      await tester.pumpAndSettle();
      notices.value = SpotNotice('another', SpotNoticeState.done, (c) => 'ok');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spot-done')), findsNothing);
      notices.value = SpotNotice('pm-142', SpotNoticeState.refused, (c) => 'Achat de test refusé');
      await tester.pumpAndSettle();
      expect(find.text('Achat de test refusé'), findsOneWidget);
      expect(find.byKey(const Key('spot-done')), findsNothing);
      notices.dispose();
    });

    testWidgets('nothing offered without the store\'s product, nor before 139', (tester) async {
      _platform('appstore');
      await _size(tester, 390, 1000);
      final notices = ValueNotifier<SpotNotice?>(null);
      await _open(
          tester,
          _opener(_shop,
              admin: _Admin(),
              retail: _shopItems,
              store: SpotStoreSide(billing: _Store('apple'), notices: notices)));
      expect(find.byKey(const Key('spot-store-missing')), findsOneWidget);
      expect(find.byKey(const Key('spot-go')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _open(
          tester,
          _opener(_shop,
              admin: _Admin(terms: const SpotTerms()),
              retail: _shopItems,
              store: SpotStoreSide(billing: _Store('apple', products: _appleProducts), notices: notices)));
      expect(find.byKey(const Key('spot-store-missing')), findsOneWidget, reason: 'the server cannot check a store payment yet');
      notices.dispose();
    });

    testWidgets('a spot asked earlier: bought in the store, or checked again', (tester) async {
      _platform('play');
      await _size(tester, 390, 1000);
      final billing = _Store('google', products: _googleProducts);
      final notices = ValueNotifier<SpotNotice?>(null);
      await _open(
          tester,
          _opener(_farm,
              admin: _Admin(),
              asked: const Promotion(id: 'pm-old', kind: 'shop', days: 30, price: 8000, status: 'requested'),
              store: SpotStoreSide(billing: billing, notices: notices)));
      expect(find.text('Prix : CFA 2,900'), findsOneWidget);
      expect(find.text('La ferme à la une, 7 jours'), findsOneWidget);
      await tester.tap(find.byKey(const Key('spot-check-again')));
      await tester.pumpAndSettle();
      expect(billing.restored, 1);
      await tester.tap(find.byKey(const Key('spot-go')));
      await tester.pumpAndSettle();
      expect(billing.bought, ['mara_spot_shop_7|${_farm.id}|pm-old']);
      notices.dispose();
    });

    testWidgets('before 139 is live, a spot asked earlier is not sold in the store', (tester) async {
      _platform('play');
      await _size(tester, 390, 1000);
      final billing = _Store('google', products: _googleProducts);
      final notices = ValueNotifier<SpotNotice?>(null);
      await _open(
          tester,
          _opener(_farm,
              admin: _Admin(terms: const SpotTerms()),
              asked: const Promotion(id: 'pm-old', kind: 'shop', days: 7, price: 2500, status: 'requested'),
              store: SpotStoreSide(billing: billing, notices: notices)));
      expect(find.byKey(const Key('spot-store-missing')), findsOneWidget);
      expect(find.byKey(const Key('spot-go')), findsNothing);
      expect(billing.bought, isEmpty);
      notices.dispose();
    });

    testWidgets('the iPhone app draws « Mettre en avant » again (Apple\'s in-app purchase)', (tester) async {
      _platform('appstore');
      expect(sellsSpotsInApp, isTrue);
      expect(spotChannel, 'apple');
      _platform('play');
      expect(spotChannel, 'google');
      _platform(null);
      expect(spotChannel, 'web');
      _platform('appstore');
      await _size(tester, 390, 900);
      await tester.pumpWidget(_app(Scaffold(
          body: SpotsCard(orgId: _shop.id, admin: _Admin(), retail: _shopItems, org: _shop))));
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Mettre en avant'), findsOneWidget);
      expect(find.textContaining('30 jours'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('5. the purchase listener', () {
    StorePurchase spot(String platform, {StorePurchaseStatus status = StorePurchaseStatus.purchased}) => StorePurchase(
          status: status,
          productId: platform == 'apple' ? 'bf.kaj.app.spot.article7' : 'mara_spot_article_7',
          transactionId: platform == 'apple' ? '3000000142' : null,
          token: platform == 'google' ? 'gp-token-142' : null,
          orgId: platform == 'apple' ? 'pm-142' : _shop.id,
          profileId: platform == 'google' ? 'pm-142' : null,
          needsCompletion: true,
        );

    for (final platform in ['apple', 'google']) {
      test('$platform: a spot is verified as a spot, never as Mara Pro', () async {
        final store = _ProStore(platform);
        var pro = 0;
        final spots = <String?>[];
        final w = StoreWatcher(
          billing: store,
          verify: (p) async {
            pro++;
            return const StoreVerdict(pro: true, state: 'active');
          },
          verifySpot: (p) async {
            spots.add(p.spotId);
            return SpotVerdict(promotionId: p.spotId);
          },
        );
        await w.handle([spot(platform)]);
        expect(pro, 0);
        expect(spots, ['pm-142']);
        expect(w.spotNotice.value?.state, SpotNoticeState.done);
        expect(w.spotNotice.value?.promotionId, 'pm-142');
        // Apple's transaction is finished by the app; Google's consumed by the Worker.
        expect(store.completed, platform == 'apple' ? ['bf.kaj.app.spot.article7'] : isEmpty);
        w.dispose();
      });
    }

    test('a refusal for good: Apple\'s finished, Google\'s left unacknowledged (refunded by Google); a passing one left open', () async {
      for (final platform in ['apple', 'google']) {
        final store = _ProStore(platform);
        final w = StoreWatcher(
          billing: store,
          verify: (p) async => const StoreVerdict(pro: false, state: ''),
          verifySpot: (p) async => throw const StoreVerifyRefused('x', 'wrong_spot', status: 409),
        );
        await w.handle([spot(platform)]);
        expect(w.spotNotice.value?.state, SpotNoticeState.refused);
        expect(store.completed, platform == 'apple' ? hasLength(1) : isEmpty, reason: platform);
        final w2 = StoreWatcher(
          billing: store,
          verify: (p) async => const StoreVerdict(pro: false, state: ''),
          verifySpot: (p) async => throw StateError('offline'),
        );
        store.completed.clear();
        await w2.handle([spot(platform)]);
        expect(store.completed, isEmpty, reason: 'left open for the store to hand back');
        w.dispose();
        w2.dispose();
      }
      expect(spotRefusalsForGood, containsAll(['wrong_spot', 'replayed', 'sandbox', 'no_spot']));
      expect(spotRefusalsForGood.contains('session'), isFalse);
      expect(spotRefusalsForGood.contains('not_admin'), isFalse);
    });

    test('a spot paid while the connection died is verified at the next start, once', () async {
      final left = StorePurchase(
        status: StorePurchaseStatus.restored,
        productId: 'mara_spot_shop_7',
        token: 'gp-token-left-142',
        orgId: _shop.id,
        profileId: 'pm-142',
      );
      final store = _ProStore('google', unfinished: [left]);
      final verified = <String?>[];
      final w = StoreWatcher(
        billing: store,
        verify: (p) async => const StoreVerdict(pro: false, state: ''),
        verifySpot: (p) async {
          verified.add(p.token);
          return SpotVerdict(promotionId: p.spotId, granted: true);
        },
      );
      await w.recoverSpots();
      await w.recoverSpots();
      expect(verified, ['gp-token-left-142']);
      expect(store.asked, 1, reason: 'once per run');
      expect(w.spotNotice.value?.state, SpotNoticeState.done);
      // « Vérifier un achat déjà payé »: asked again, whatever the store
      // (Apple's unfinished consumables, which restore never hands back).
      await w.recoverSpots(again: true);
      expect(store.asked, 2);
      w.dispose();
    });

    test('the platform\'s « À faire » counts the store payments to refund, only where 139 is', () {
      expect(const PlatformTodo({}).has('spot_refunds'), isFalse);
      expect(const PlatformTodo({}).zeroKeys, isNot(contains('spot_refunds')));
      const t = PlatformTodo({'spot_refunds': 2});
      expect(t.has('spot_refunds'), isTrue);
      expect(t.waiting, 2);
      expect(t.waitingOrder, ['spot_refunds']);
      expect(t.urgent, 2);
      final row = SpotRefundRow.fromJson(const {'id': 'r1', 'channel': 'apple', 'external_id': '3000000203',
        'org_name': 'Maison Élégance', 'kind': 'article', 'amount': 14.99, 'currency': 'EUR', 'reason': 'no spot'});
      expect((row.channel, row.amount, row.reason), ('apple', 14.99, 'no spot'));
    });

    test('a refusal the money must come back for is final, said so', () {
      expect(spotRefusalsForGood, containsAll(['refused', 'ineligible', 'revoked']));
    });

    test('the products and the spot a purchase names', () {
      expect(isSpotProduct('mara_spot_article_7'), isTrue);
      expect(isSpotProduct('bf.kaj.app.spot.shop7'), isTrue);
      expect(isSpotProduct('mara_pro'), isFalse);
      expect(spotProductId('google', 'shop'), 'mara_spot_shop_7');
      expect(spotProductId('apple', 'article'), 'bf.kaj.app.spot.article7');
      expect(spot('google').spotId, 'pm-142');
      expect(spot('apple').spotId, 'pm-142');
      expect(const StorePurchase(status: StorePurchaseStatus.purchased, productId: 'mara_pro', orgId: 'o').spotId, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('6. « Voir à quoi ça ressemble »', () {
    testWidgets('a shop\'s article: its own name, photo and price first in « À la une », Sponsorisé', (tester) async {
      await _size(tester, 390, 1300);
      await _open(tester, _opener(_shop, admin: _Admin(), retail: _shopItems));
      await tester.tap(find.byKey(const Key('spot-preview-toggle')));
      await tester.pumpAndSettle();
      final preview = find.byKey(const Key('spot-preview'));
      expect(preview, findsOneWidget);
      Finder inside(Finder f) => find.descendant(of: preview, matching: f);
      expect(inside(find.text('À LA UNE')), findsOneWidget);
      expect(inside(find.text('Sponsorisé')), findsNWidgets(2), reason: 'the strip\'s note and the tag');
      final first = find.byKey(const Key('spot-preview-first'));
      expect(find.descendant(of: first, matching: find.text('Robe de soirée')), findsOneWidget);
      expect(find.descendant(of: first, matching: find.text('Maison Élégance')), findsOneWidget);
      expect(find.descendant(of: first, matching: find.textContaining('25')), findsOneWidget);
      expect(find.descendant(of: first, matching: find.byKey(const Key('spot-preview-photo'))), findsOneWidget);
      expect(find.textContaining('Votre article apparaît en premier dans « À la une »'), findsOneWidget);
      expect(find.textContaining('Pendant 7 jours'), findsOneWidget);
      // Another article: the preview follows.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sac en cuir').last);
      await tester.pumpAndSettle();
      expect(find.descendant(of: first, matching: find.text('Sac en cuir')), findsOneWidget);
    });

    testWidgets('a farm\'s vitrine: its card first in the list, its kind', (tester) async {
      await _size(tester, 390, 1300);
      await _open(tester, _opener(_farm, admin: _Admin(), retail: _farmItems));
      await tester.tap(find.text('La ferme'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('spot-preview-toggle')));
      await tester.pumpAndSettle();
      final first = find.byKey(const Key('spot-preview-first'));
      expect(find.descendant(of: first, matching: find.text('Ferme Horizon Vert')), findsOneWidget);
      expect(find.descendant(of: first, matching: find.text('Ferme')), findsOneWidget);
      expect(find.descendant(of: first, matching: find.text('Sponsorisé')), findsOneWidget);
      expect(find.textContaining('Votre ferme apparaît en premier'), findsOneWidget);
    });

    testWidgets('an association\'s vitrine, with its badge; no photo: its kind\'s icon', (tester) async {
      await _size(tester, 390, 1300);
      await _open(tester, _opener(_assoc, admin: _Admin(), retail: null, vitrineOnly: true));
      await tester.tap(find.byKey(const Key('spot-preview-toggle')));
      await tester.pumpAndSettle();
      final first = find.byKey(const Key('spot-preview-first'));
      expect(find.descendant(of: first, matching: find.text('Fondation Espoir')), findsOneWidget);
      expect(find.descendant(of: first, matching: find.text('Association')), findsNWidgets(2), reason: 'the badge and the kind');
      expect(find.descendant(of: first, matching: find.byIcon(Icons.groups_outlined)), findsOneWidget);
      expect(find.textContaining('Votre association apparaît en premier'), findsOneWidget);
      await tester.tap(find.byKey(const Key('spot-preview-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spot-preview')), findsNothing, reason: 'closed again');
    });

    testWidgets('in English', (tester) async {
      await _size(tester, 390, 1300);
      await tester.pumpWidget(_app(
          const SingleChildScrollView(
            child: SpotPreview(shop: false, businessName: 'Le Comptoir Doré', profile: 'retail',
                articleName: 'Coffret de thé', articlePrice: '18 EUR'),
          ),
          lang: 'en'));
      await tester.pumpAndSettle();
      expect(find.text('FEATURED'), findsOneWidget);
      expect(find.text('Sponsored'), findsNWidgets(2));
      expect(find.textContaining('Your item comes first in “Featured”'), findsOneWidget);
      expect(find.textContaining('For 7 days'), findsOneWidget);
      expect(find.textContaining('mise en avant'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('7. Mara Pro by card at the zone price', () {
    const zoned = PlanTerms(
      stripeOn: true,
      priceMonth: 2900,
      priceYear: 29900,
      proZones: {'XOF': (month: 2900, year: 29900), 'EUR': (month: 4.99, year: 49.99), 'USD': (month: 5.99, year: 59.99)},
    );
    test('the zone price for each business; the francs before 139', () {
      expect(zoned.proPriceFor('EUR', year: false), (amount: 4.99, currency: 'EUR'));
      expect(zoned.proPriceFor('GHS', year: true), (amount: 59.99, currency: 'USD'));
      expect(zoned.proPriceFor('XAF', year: false), (amount: 2900.0, currency: 'XAF'));
      const old = PlanTerms(priceMonth: 2900);
      expect(old.proPriceFor('EUR', year: false), (amount: 2900.0, currency: 'XOF'));
      final parsed = PlanTerms.fromJson({
        'pro_price_month': 2900,
        'pro_zones': {'EUR': {'month': 4.99, 'year': 49.99}},
      });
      expect(parsed.proZones['EUR']?.year, 49.99);
      expect(parsed.forProfile('farm').proZones['EUR']?.month, 4.99);
    });

    testWidgets('the website\'s card button says the zone price, no dollars converted', (tester) async {
      await _size(tester, 390, 700);
      await tester.pumpWidget(_app(Scaffold(
          body: StripeCardButton(orgId: _euro.id, terms: zoned, period: 'month', pay: _Pay(), currency: 'EUR'))));
      await tester.pump();
      expect(_has('S\'abonner par carte · ${zonePriceText(4.99, 'EUR', language: 'fr')} / mois'), findsOneWidget);
      expect(find.byKey(const Key('stripe-usd')), findsNothing);
      await tester.pumpWidget(_app(Scaffold(
          body: StripeCardButton(key: const Key('b'), orgId: _shop.id, terms: zoned, period: 'year', pay: _Pay(), currency: 'XOF')),
          lang: 'en'));
      await tester.pump();
      expect(_has('Subscribe by card · ${zonePriceText(29900, 'XOF')} / year'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('8. Réglages', () {
    const zoneKeys = [
      'spot_price_article_7_eur', 'spot_price_shop_7_eur', 'spot_price_article_7_usd', 'spot_price_shop_7_usd',
      'pro_price_month_eur', 'pro_price_year_eur', 'pro_price_month_usd', 'pro_price_year_usd',
    ];
    test('the zone prices are there, to the cent; the inert ones gone', () {
      final keys = [for (final d in platformSettingDefs) d.key];
      for (final k in zoneKeys) {
        expect(keys, contains(k));
        expect(decimalSettings, contains(k), reason: k);
        expect(settingCardOf(k), isNotNull, reason: k);
      }
      for (final k in ['spot_price_article_30', 'spot_price_shop_30', 'pro_free_spots_month', 'stripe_xof_per_usd']) {
        expect(keys, isNot(contains(k)), reason: '$k is inert since 139');
      }
      expect(settingCardOf('spot_price_shop_7_usd')?.key, 'vitrines');
      expect(settingCardOf('pro_price_year_eur')?.key, 'pro');
      expect(decimalSettings.contains('spot_price_article_7'), isFalse, reason: 'francs are whole');
    });

    for (final lang in ['fr', 'en']) {
      testWidgets('the spots\' card: each zone named, the stores\' line ($lang)', (tester) async {
        await _size(tester, 390, 1600);
        final center = _Center()
          ..values = {
            for (final d in platformSettingDefs)
              d.key: SettingValue(value: zoneKeys.contains(d.key) ? 1.99 : 1000),
          };
        await tester.pumpWidget(_app(SettingsSection(center: center, card: 'vitrines'), lang: lang));
        await tester.pumpAndSettle();
        expect(find.text(lang == 'fr'
            ? 'Un article à la une, 7 jours — euros (zone euro)'
            : 'An item featured, 7 days — euros (euro area)'), findsOneWidget);
        expect(find.text(lang == 'fr'
            ? 'La boutique à la une, 7 jours — dollars (reste du monde)'
            : 'The shop featured, 7 days — dollars (rest of the world)'), findsOneWidget);
        expect(find.text(lang == 'fr'
            ? 'Un article à la une, 7 jours — FCFA (zone franc CFA)'
            : 'An item featured, 7 days — FCFA (CFA franc zone)'), findsOneWidget);
        await tester.scrollUntilVisible(find.byKey(const Key('settings-note-vitrines-spots')), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.byKey(const Key('settings-note-vitrines-spots')), findsOneWidget);
        expect(find.textContaining(lang == 'fr'
            ? 'Sur Android et iPhone, le prix payé est celui de Google Play et de l\'App Store'
            : 'On Android and iPhone, the price paid is Google Play\'s and the App Store\'s'), findsOneWidget);
        expect(find.text('1,99'), findsWidgets, reason: 'the euro and dollar prices show their cents');
        // Typed to the cent.
        await tester.scrollUntilVisible(find.byKey(const Key('setting-spot_price_article_7_eur')), -200,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.byKey(const Key('setting-spot_price_article_7_eur')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('setting-field')), '2,49');
        await tester.tap(find.byKey(const Key('setting-save')));
        await tester.pumpAndSettle();
        expect(center.calls, ['set:spot_price_article_7_eur=2.49']);
      });
    }

    testWidgets('Mara Pro\'s card: its zone prices and the same line', (tester) async {
      await _size(tester, 390, 1600);
      final center = _Center()
        ..values = {for (final d in platformSettingDefs) d.key: const SettingValue(value: 1)};
      await tester.pumpWidget(_app(SettingsSection(center: center, card: 'pro')));
      await tester.pumpAndSettle();
      expect(find.text('Prix de Mara Pro, par mois — euros (zone euro)'), findsOneWidget);
      expect(find.text('Prix de Mara Pro, par an — dollars (reste du monde)'), findsOneWidget);
      expect(find.byKey(const Key('settings-note-pro-prices')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('9. 320 px, text ×1.3', () {
    for (final lang in ['fr', 'en']) {
      for (final (label, org, retail, store, vitrine) in [
        ('shop article, web', _shop, _shopItems, null, false),
        ('farm vitrine, Play', _farm, _farmItems, 'play', true),
        ('association, App Store', _assoc, null, 'appstore', true),
        ('euros, web', _euro, _euroItems, null, false),
      ]) {
        testWidgets('$lang · $label: the sheet, the preview and the payment fit', (tester) async {
          _platform(store);
          await _size(tester, 320, 640, text: 1.3);
          final notices = ValueNotifier<SpotNotice?>(null);
          final side = store == null
              ? null
              : SpotStoreSide(
                  billing: _Store(store == 'play' ? 'google' : 'apple',
                      products: store == 'play' ? _googleProducts : _appleProducts),
                  notices: notices);
          await _open(tester,
              _opener(org, admin: _Admin(), retail: retail, store: side, pay: _Pay(),
                  vitrineOnly: org.isAssociation, lang: lang));
          if (vitrine && !org.isAssociation) {
            await tester.tap(find.descendant(of: find.byKey(const Key('spot-what')), matching: find.byIcon(Icons.storefront_outlined)));
            await tester.pumpAndSettle();
          }
          await _scrollTo(tester, find.byKey(const Key('spot-preview-toggle')));
          await tester.tap(find.byKey(const Key('spot-preview-toggle')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('spot-preview')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _scrollTo(tester, find.byKey(const Key('spot-go')));
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('spot-go')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          notices.dispose();
        });
      }
    }
  });

  // -------------------------------------------------------------------------
  // Screenshots (B142_SHOTS=<dir>)
  // -------------------------------------------------------------------------
  final shots = Platform.environment['B142_SHOTS'];
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
        await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
      }
    }

    Future<void> shoot(WidgetTester tester, String name) async {
      await tester.pumpAndSettle();
      // The photographs decoded for real before the picture is taken.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')).first);
        final img = await ro.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    Future<void> tall(WidgetTester tester, double w, double text) async {
      // The whole sheet in one picture: as tall as it is.
      await _size(tester, w, 1700, text: text);
    }

    final sizes = [('390', 390.0, 1.0), ('320x1.3', 320.0, 1.3)];
    for (final lang in ['fr', 'en']) {
      for (final (tag, w, text) in sizes) {
        testWidgets('$lang $tag', (tester) async {
          Directory(shots!).createSync(recursive: true);
          await tester.runAsync(realFonts);
          final p = '${lang}_${tag}_';

          // 1. The website: a shop's article, the preview open.
          await tall(tester, w, text);
          await _open(tester, _opener(_shop, admin: _Admin(), retail: _shopItems, pay: _Pay(), lang: lang));
          await tester.tap(find.byKey(const Key('spot-preview-toggle')));
          await shoot(tester, '${p}1_web_article_preview');

          // 2. The website, a business in euros: the payment by card.
          await tester.pumpWidget(const SizedBox());
          await _open(tester, _opener(_euro, admin: _Admin(), retail: _euroItems, pay: _Pay(), lang: lang));
          await tester.tap(find.byKey(const Key('spot-go')));
          await shoot(tester, '${p}2_web_euro_card');

          // 3. Google Play: a farm's vitrine, the preview open.
          _platform('play');
          final notices = ValueNotifier<SpotNotice?>(null);
          await tester.pumpWidget(const SizedBox());
          await _open(tester, _opener(_farm, admin: _Admin(), retail: _farmItems, lang: lang,
              store: SpotStoreSide(billing: _Store('google', products: _googleProducts), notices: notices)));
          await tester.tap(find.descendant(of: find.byKey(const Key('spot-what')), matching: find.byIcon(Icons.storefront_outlined)));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('spot-preview-toggle')));
          await shoot(tester, '${p}3_play_farm_preview');

          // 4. The App Store: an association's vitrine, the preview open.
          _platform('appstore');
          await tester.pumpWidget(const SizedBox());
          await _open(tester, _opener(_assoc, admin: _Admin(), retail: null, vitrineOnly: true, lang: lang,
              store: SpotStoreSide(billing: _Store('apple', products: _appleProducts), notices: notices)));
          await tester.tap(find.byKey(const Key('spot-preview-toggle')));
          await shoot(tester, '${p}4_appstore_assoc_preview');

          // 5. The App Store: paid.
          await tester.tap(find.byKey(const Key('spot-go')));
          await tester.pumpAndSettle();
          notices.value = SpotNotice('pm-142', SpotNoticeState.done, (c) => 'ok');
          await shoot(tester, '${p}5_appstore_paid');
          _platform(null);

          // 6. Réglages › Vitrines: the zone prices.
          await tester.pumpWidget(const SizedBox());
          final center = _Center()
            ..values = {
              for (final d in platformSettingDefs)
                d.key: SettingValue(
                    value: switch (d.key) {
                      'spot_price_article_7' => 1000,
                      'spot_price_shop_7' => 2500,
                      'spot_price_article_7_eur' || 'spot_price_article_7_usd' => 1.99,
                      'spot_price_shop_7_eur' || 'spot_price_shop_7_usd' => 4.99,
                      'spots_max_live' => 8,
                      _ => 1,
                    }),
            };
          await tester.pumpWidget(_app(SettingsSection(center: center, card: 'vitrines'), lang: lang));
          await shoot(tester, '${p}6_reglages_spots');
          notices.dispose();
        });
      }
    }
  }, skip: shots == null ? 'B142_SHOTS=<dir> writes the screenshots' : null);
}
