// Batch 148 (migration 144): « Mettre en avant » by area, and a business
// fixing its own spot.
//
//   1. the sheet says the places free around the business this week —
//      « 3 places libres sur 8 autour de vous cette semaine » — for an
//      article and for the whole vitrine, and how far it is seen;
//   2. full, the day the next place frees, as the server's queue says;
//   3. a business with no pin: the sheet says so before any payment, with
//      « La position de ma boutique » (ferme, association), and offers no
//      button to pay — on the website and in the stores, asking or paying;
//   4. before 144 is live: the sheet as before (one cap for the street);
//   5. the spots card: « Changer l'article ou le service », « Annuler »
//      and « Arrêter » only where allowed (asked; paid and waiting;
//      running, the change in its first 24 h), each with its line; the
//      dialogs — the stop says there is no refund — and what is sent;
//      one change only; none before 144;
//   6. the console: « Changer l'article » and « Arrêter » on any spot;
//   (7. the street asking À la une and the spotlights with no position
//      before « près de moi » is spots_test's, beside its directory;)
//   8. French and English; 320 px with text ×1.3: nothing overflows.
//
// B148_SHOTS=<dir> also writes the screenshots (390 px and 320 px at text
// ×1.3, French and English).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/store_rules.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/pay/wave_pay.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/admin/featured_screen.dart';
import 'package:kaj_app/features/admin/spots_card.dart';
import 'package:kaj_app/features/pro/store_billing.dart';
import 'package:kaj_app/features/pro/store_watcher.dart';
import 'package:kaj_app/l10n/strings.dart';

// The owner's naming rule: brand-like names, no first names; Ouagadougou
// the only Burkina town (Dakar, Abidjan elsewhere).
const _shop = OrgSummary(
    id: '14800000-0000-0000-0000-000000000001', name: 'Maison Élégance', profile: 'retail',
    currency: 'XOF', roles: ['owner']);
const _farm = OrgSummary(
    id: '14800000-0000-0000-0000-000000000002', name: 'Ferme Horizon Vert', profile: 'farm',
    currency: 'XOF', roles: ['owner']);
const _assoc = OrgSummary(
    id: '14800000-0000-0000-0000-000000000003', name: 'Fondation Espoir', profile: 'association',
    currency: 'XOF', roles: ['owner']);

const _terms = SpotTerms(
  maxLive: 8,
  zones: {
    'XOF': (article: 5000, shop: 15000),
    'EUR': (article: 14.99, shop: 39.99),
    'USD': (article: 14.99, shop: 39.99),
  },
  stripeOn: true,
  version: 139,
);

final _nextFree = DateTime(2026, 10, 21, 9, 30);

const _free = SpotArea(positioned: true, areaKm: 30, places: 8, taken: 5, free: 3);
const _freeShop = SpotArea(positioned: true, areaKm: 30, places: 8, taken: 0, free: 8);
const _one = SpotArea(positioned: true, areaKm: 30, places: 8, taken: 7, free: 1);
final _full = SpotArea(positioned: true, areaKm: 30, places: 8, taken: 9, free: 0, nextAt: _nextFree);
const _nowhere = SpotArea(positioned: false, areaKm: 30, places: 8);

class _Admin extends AdminRepository {
  _Admin({this.article, this.shop, this.mine = const [], this.options}) : super(null);

  /// Null: a database before 144.
  final SpotArea? article;
  final SpotArea? shop;
  List<Promotion> mine;
  PromotionOptions? options;
  final asked = <String>[];
  final sent = <String>[];
  List<PlatformPromotion> platform = const [];

  @override
  Future<SpotTerms> spotTerms() async => _terms;

  @override
  Future<SpotArea?> spotArea(String orgId, String kind) async => kind == 'shop' ? shop : article;

  @override
  Future<String> requestPromotion(String orgId, {String? productId, required int days}) async {
    asked.add(productId ?? 'shop');
    return 'pm-new';
  }

  @override
  Future<List<Promotion>> myPromotions(String orgId) async => mine;

  @override
  Future<PromotionOptions> promotionOptions(String promotionId) async => options ?? const PromotionOptions();

  @override
  Future<void> cancelPromotion(String promotionId) async => sent.add('cancel:$promotionId');

  @override
  Future<void> stopPromotion(String promotionId) async => sent.add('stop:$promotionId');

  @override
  Future<void> changePromotionProduct(String promotionId, String productId) async =>
      sent.add('change:$promotionId:$productId');

  @override
  Future<void> platformChangePromotionProduct(String promotionId, String productId) async =>
      sent.add('platform-change:$promotionId:$productId');

  @override
  Future<void> platformStopPromotion(String promotionId) async => sent.add('platform-stop:$promotionId');

  @override
  Future<List<PlatformPromotion>> platformPromotions() async => platform;

  @override
  Future<List<FeaturedCandidate>> featuredCandidates() async => const [];
}

class _Retail extends RetailRepository {
  _Retail(this.items) : super(null);

  final List<Product> items;

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => items;

  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {};
}

final _items = _Retail(const [
  Product(id: 'p-robe', name: 'Robe de soirée', salePrice: 25000, quantity: 3, isPublished: true),
  Product(id: 'p-sac', name: 'Sac en cuir', salePrice: 18000, quantity: 2, isPublished: true),
]);

class _Pay extends WavePay {
  _Pay() : super(null, url: 'https://pay.example');

  @override
  bool get compiledIn => true;

  @override
  Future<WaveTerms> terms({String? orgId}) async => const WaveTerms();
}

class _Store implements SpotStoreBilling {
  _Store();

  @override
  String get platform => 'google';

  @override
  Future<List<SpotStoreProduct>> spotProducts() async => const [
        SpotStoreProduct(id: 'mara_spot_article_7', kind: 'article', price: 'CFA 5,000', rawPrice: 5000, currencyCode: 'XOF'),
        SpotStoreProduct(id: 'mara_spot_shop_7', kind: 'shop', price: 'CFA 15,000', rawPrice: 15000, currencyCode: 'XOF'),
      ];

  @override
  Future<void> buySpot(SpotStoreProduct product, {required String orgId, required String promotionId}) async {}

  @override
  Future<void> restore() async {}

  @override
  Future<List<StorePurchase>> unfinishedSpots() async => const [];
}

Promotion _spot(String id, String status,
        {String kind = 'article', Duration? started, Duration? startsIn}) {
  final now = DateTime.now();
  final start = started != null ? now.subtract(started) : (startsIn != null ? now.add(startsIn) : null);
  return Promotion(
    id: id,
    kind: kind,
    productId: kind == 'article' ? 'p-robe' : null,
    productName: kind == 'article' ? 'Robe de soirée' : null,
    days: 7,
    price: 5000,
    status: status,
    startsAt: start,
    endsAt: start?.add(const Duration(days: 7)),
  );
}

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

Widget _opener(OrgSummary org, _Admin admin,
        {String lang = 'fr', bool vitrineOnly = false, Promotion? asked, SpotStoreSide? store}) =>
    _app(
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => asked != null
                  ? SpotSheet.pay(context, orgId: org.id, spot: asked, admin: admin, org: org, pay: _Pay(), store: store)
                  : SpotSheet.open(context,
                      orgId: org.id,
                      admin: admin,
                      retail: vitrineOnly ? null : _items,
                      vitrineOnly: vitrineOnly,
                      org: org,
                      pay: _Pay(),
                      store: store,
                      photo: (_) async => Uint8List(0)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      lang: lang,
    );

Widget _card(OrgSummary org, _Admin admin, {String lang = 'fr'}) => _app(
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SpotsCard(orgId: org.id, admin: admin, retail: _items, org: org),
        ),
      ),
      lang: lang,
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.tap(find.text('open'));
  await _settle(tester);
}

Finder _has(String s) => find.textContaining(s, findRichText: true);

void _platform(String? store) {
  debugStoreBillingPlatform = store == 'play' ? 'google' : null;
  debugSellsDigitalInApp = store != null ? true : null;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await initializeDateFormatting('en');
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDown(() {
    debugStoreBillingPlatform = null;
    debugSellsDigitalInApp = null;
  });

  // -------------------------------------------------------------------------
  group('1. the places free around the business this week', () {
    testWidgets('an article: « 3 places libres sur 8 », the radius; the vitrine its own', (tester) async {
      await _size(tester, 390, 1400);
      await _open(tester, _opener(_shop, _Admin(article: _free, shop: _freeShop)));
      expect(find.text('3 places libres sur 8 autour de vous cette semaine'), findsOneWidget);
      expect(find.text('Montrée aux clients à moins de 30 km de chez vous.'), findsOneWidget);
      expect(find.byKey(const Key('spot-go')), findsOneWidget);
      // The street-wide line is gone.
      expect(_has('Au plus 8 articles à la une'), findsNothing);
      await tester.tap(find.descendant(of: find.byKey(const Key('spot-what')), matching: find.byIcon(Icons.storefront_outlined)));
      await tester.pumpAndSettle();
      expect(find.text('8 places libres sur 8 autour de vous cette semaine'), findsOneWidget);
    });

    testWidgets('one place: said as one', (tester) async {
      await _size(tester, 390, 1400);
      await _open(tester, _opener(_shop, _Admin(article: _one, shop: _freeShop)));
      expect(find.text('1 place libre sur 8 autour de vous cette semaine'), findsOneWidget);
    });

    testWidgets('in English', (tester) async {
      await _size(tester, 390, 1400);
      await _open(tester, _opener(_shop, _Admin(article: _free, shop: _freeShop), lang: 'en'));
      expect(find.text('3 places free out of 8 around you this week'), findsOneWidget);
      expect(find.text('Shown to customers within 30 km of you.'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('2. full: the day the next place frees', () {
    testWidgets('French and English, the queue\'s date', (tester) async {
      await _size(tester, 390, 1400);
      await _open(tester, _opener(_shop, _Admin(article: _full, shop: _freeShop)));
      expect(find.text('Complet autour de vous cette semaine : votre mise en avant commencera le 21/10.'),
          findsOneWidget);
      expect(find.byKey(const Key('spot-area-full')), findsOneWidget);
      // Full is no refusal: the spot may still be bought, it waits its turn.
      expect(find.byKey(const Key('spot-go')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _open(tester, _opener(_shop, _Admin(article: _full, shop: _freeShop), lang: 'en'));
      expect(find.text('Full around you this week: your promotion will start on 21/10.'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('3. no position: refused before any payment', () {
    testWidgets('a shop, a farm, an association: their own words, no button to pay', (tester) async {
      await _size(tester, 390, 1400);
      for (final (org, where, vitrineOnly) in [
        (_shop, '« La position de ma boutique »', false),
        (_farm, '« La position de ma ferme »', false),
        (_assoc, '« La position de mon association »', true),
      ]) {
        await tester.pumpWidget(const SizedBox());
        final admin = _Admin(article: _nowhere, shop: _nowhere);
        await _open(tester, _opener(org, admin, vitrineOnly: vitrineOnly));
        expect(find.byKey(const Key('spot-no-position')), findsOneWidget, reason: org.name);
        expect(_has(where), findsOneWidget, reason: org.name);
        expect(find.byKey(const Key('spot-go')), findsNothing, reason: org.name);
        expect(find.byKey(const Key('spot-price')), findsNothing, reason: org.name);
        expect(admin.asked, isEmpty);
      }
    });

    testWidgets('a spot asked before: its payment step refuses too (website and Google Play)', (tester) async {
      await _size(tester, 390, 1400);
      await _open(tester, _opener(_shop, _Admin(article: _nowhere, shop: _nowhere), asked: _spot('pm-1', 'requested')));
      expect(find.byKey(const Key('spot-no-position')), findsOneWidget);
      expect(find.byKey(const Key('spot-card')), findsNothing);
      expect(find.text('J\'ai payé'), findsNothing);
      _platform('play');
      await tester.pumpWidget(const SizedBox());
      final notices = ValueNotifier<SpotNotice?>(null);
      await _open(tester, _opener(_shop, _Admin(article: _nowhere, shop: _nowhere),
          asked: _spot('pm-1', 'requested'), store: SpotStoreSide(billing: _Store(), notices: notices)));
      expect(find.byKey(const Key('spot-no-position')), findsOneWidget);
      expect(find.byKey(const Key('spot-go')), findsNothing);
      notices.dispose();
    });

    testWidgets('in English', (tester) async {
      await _size(tester, 390, 1400);
      await _open(tester, _opener(_farm, _Admin(article: _nowhere, shop: _nowhere), lang: 'en'));
      expect(find.text('Your business is not on the map'), findsOneWidget);
      expect(find.text('First place your farm on the map: a promotion is shown to customers around it.'), findsOneWidget);
      expect(_has('« My farm\'s location »'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('4. before 144 is live', () {
    testWidgets('the sheet as before: one cap for the street, no area line, no fix button', (tester) async {
      await _size(tester, 390, 1400);
      await _open(tester, _opener(_shop, _Admin()));
      expect(_has('Au plus 8 articles à la une en même temps'), findsOneWidget);
      expect(find.byKey(const Key('spot-area-free')), findsNothing);
      expect(find.byKey(const Key('spot-no-position')), findsNothing);
      await tester.pumpWidget(_card(_shop, _Admin(mine: [_spot('pm-r', 'requested')])));
      await _settle(tester);
      expect(find.byKey(const Key('spot-cancel-pm-r')), findsNothing);
      expect(find.byKey(const Key('spot-change-pm-r')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('5. the spots card: fixing a spot', () {
    List<Promotion> all() => [
          _spot('pm-ask', 'requested'),
          _spot('pm-wait', 'approved', startsIn: const Duration(days: 2)),
          _spot('pm-fresh', 'approved', started: const Duration(hours: 2)),
          _spot('pm-old', 'approved', started: const Duration(hours: 30)),
          _spot('pm-shop', 'approved', kind: 'shop', started: const Duration(hours: 1)),
        ];

    testWidgets('each button only where allowed, with its line', (tester) async {
      await _size(tester, 390, 2400);
      await tester.pumpWidget(_card(_shop, _Admin(article: _free, mine: all())));
      await _settle(tester);
      // Asked: change and cancel.
      expect(find.byKey(const Key('spot-change-pm-ask')), findsOneWidget);
      expect(find.byKey(const Key('spot-cancel-pm-ask')), findsOneWidget);
      expect(find.byKey(const Key('spot-stop-pm-ask')), findsNothing);
      // Paid, waiting: change only.
      expect(find.byKey(const Key('spot-change-pm-wait')), findsOneWidget);
      expect(find.byKey(const Key('spot-cancel-pm-wait')), findsNothing);
      expect(find.byKey(const Key('spot-stop-pm-wait')), findsNothing);
      // Running 2 h: change and stop. Running 30 h: stop only.
      expect(find.byKey(const Key('spot-change-pm-fresh')), findsOneWidget);
      expect(find.byKey(const Key('spot-stop-pm-fresh')), findsOneWidget);
      expect(find.byKey(const Key('spot-change-pm-old')), findsNothing);
      expect(find.byKey(const Key('spot-stop-pm-old')), findsOneWidget);
      // The vitrine's spot: nothing to change.
      expect(find.byKey(const Key('spot-change-pm-shop')), findsNothing);
      expect(find.byKey(const Key('spot-stop-pm-shop')), findsOneWidget);
      expect(find.text('Annuler : la demande est retirée, rien n\'est payé.'), findsOneWidget);
      expect(find.text('Changer : un autre article ou service, une fois, sans frais ; le paiement reste le même.'),
          findsOneWidget);
      expect(find.text('Arrêter : la mise en avant s\'arrête tout de suite, sans remboursement.'), findsNWidgets(3));
    });

    testWidgets('Annuler: a dialog, then the cancel sent', (tester) async {
      await _size(tester, 390, 1600);
      final admin = _Admin(article: _free, mine: [_spot('pm-ask', 'requested')]);
      await tester.pumpWidget(_card(_shop, admin));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('spot-cancel-pm-ask')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spot-cancel-dialog')), findsOneWidget);
      expect(find.text('Rien n\'a été payé : la demande est retirée. Vous pourrez en faire une autre.'), findsOneWidget);
      await tester.tap(find.text('Garder la demande'));
      await tester.pumpAndSettle();
      expect(admin.sent, isEmpty);
      await tester.tap(find.byKey(const Key('spot-cancel-pm-ask')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('spot-fix-confirm')));
      await _settle(tester);
      expect(admin.sent, ['cancel:pm-ask']);
      expect(find.text('Demande annulée.'), findsOneWidget);
    });

    testWidgets('Arrêter: the dialog says no refund, then the stop sent', (tester) async {
      await _size(tester, 390, 1600);
      final admin = _Admin(article: _free, mine: [_spot('pm-fresh', 'approved', started: const Duration(hours: 2))]);
      await tester.pumpWidget(_card(_shop, admin));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('spot-stop-pm-fresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spot-stop-dialog')), findsOneWidget);
      expect(_has('Aucun remboursement'), findsOneWidget);
      expect(find.text('Arrêter sans remboursement'), findsOneWidget);
      await tester.tap(find.byKey(const Key('spot-fix-confirm')));
      await _settle(tester);
      expect(admin.sent, ['stop:pm-fresh']);
    });

    testWidgets('Changer: the items the server offers, one picked, sent; the 24 h said', (tester) async {
      await _size(tester, 390, 1600);
      final admin = _Admin(
        article: _free,
        mine: [_spot('pm-fresh', 'approved', started: const Duration(hours: 2))],
        options: PromotionOptions(
          canChange: true,
          canStop: true,
          changeUntil: DateTime.now().add(const Duration(hours: 22)),
          items: const [
            (id: 'p-sac', name: 'Sac en cuir', service: false),
            (id: 'p-retouche', name: 'Retouche sur mesure', service: true),
          ],
        ),
      );
      await tester.pumpWidget(_card(_shop, admin));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('spot-change-pm-fresh')));
      await _settle(tester);
      expect(find.byKey(const Key('spot-change-dialog')), findsOneWidget);
      expect(_has('Les jours qui restent passent au nouvel article ou service ; pas de remboursement.'), findsOneWidget);
      expect(find.text('Retouche sur mesure'), findsOneWidget);
      expect(find.text('Service'), findsOneWidget);
      // Nothing picked: nothing to send.
      expect(tester.widget<FilledButton>(find.byKey(const Key('spot-change-go'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('spot-change-item-p-sac')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('spot-change-go')));
      await _settle(tester);
      expect(admin.sent, ['change:pm-fresh:p-sac']);
      expect(find.text('Article ou service changé.'), findsOneWidget);
    });

    testWidgets('one change only: said, no dialog', (tester) async {
      await _size(tester, 390, 1600);
      final admin = _Admin(
          article: _free,
          mine: [_spot('pm-ask', 'requested')],
          options: const PromotionOptions(canCancel: true, changed: true));
      await tester.pumpWidget(_card(_shop, admin, lang: 'en'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('spot-change-pm-ask')));
      await _settle(tester);
      expect(find.byKey(const Key('spot-change-dialog')), findsNothing);
      expect(find.text('The item or service can be changed only once'), findsOneWidget);
      expect(admin.sent, isEmpty);
    });

    testWidgets('in English: the buttons and the stop dialog', (tester) async {
      await _size(tester, 390, 1600);
      await tester.pumpWidget(_card(_farm,
          _Admin(article: _free, mine: [_spot('pm-fresh', 'approved', started: const Duration(hours: 2))]),
          lang: 'en'));
      await _settle(tester);
      expect(_has('Change the item or service'), findsOneWidget);
      await tester.tap(find.byKey(const Key('spot-stop-pm-fresh')));
      await tester.pumpAndSettle();
      expect(find.text('Stop the promotion?'), findsOneWidget);
      expect(_has('No refund'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('6. the console', () {
    testWidgets('« Changer l\'article » and « Arrêter » on any spot, each sent', (tester) async {
      await _size(tester, 390, 1600);
      final admin = _Admin(
        options: const PromotionOptions(items: [(id: 'p-sac', name: 'Sac en cuir', service: false)]),
      )..platform = [
          PlatformPromotion(
              id: 'pp-1', orgId: _shop.id, orgName: 'Maison Élégance', kind: 'article', days: 7,
              status: 'approved', productName: 'Robe de soirée',
              startsAt: DateTime.now().subtract(const Duration(days: 2)),
              endsAt: DateTime.now().add(const Duration(days: 5))),
        ];
      await tester.pumpWidget(_app(FeaturedScreen(admin: admin)));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('console-spot-change-pp-1')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('spot-change-item-p-sac')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('spot-change-go')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('console-spot-stop-pp-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('console-spot-stop-dialog')), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byKey(const Key('console-spot-stop-dialog')), matching: find.widgetWithText(FilledButton, 'Arrêter')));
      await _settle(tester);
      expect(admin.sent, ['platform-change:pp-1:p-sac', 'platform-stop:pp-1']);
    });
  });

  // -------------------------------------------------------------------------
  group('8. 320 px, text ×1.3: nothing overflows', () {
    for (final lang in ['fr', 'en']) {
      for (final (name, article) in [('free', _free), ('full', _full), ('nowhere', _nowhere)]) {
        testWidgets('$lang · the sheet, $name', (tester) async {
          await _size(tester, 320, 1600, text: 1.3);
          await _open(tester, _opener(_shop, _Admin(article: article, shop: article), lang: lang));
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('spot-sheet')), findsOneWidget);
        });
      }
      testWidgets('$lang · the card with every fix, and its dialogs', (tester) async {
        await _size(tester, 320, 2600, text: 1.3);
        final admin = _Admin(
          article: _free,
          mine: [
            _spot('pm-ask', 'requested'),
            _spot('pm-fresh', 'approved', started: const Duration(hours: 2)),
          ],
          options: PromotionOptions(
              canChange: true,
              changeUntil: DateTime.now().add(const Duration(hours: 22)),
              items: const [(id: 'p-sac', name: 'Sac en cuir de très belle qualité, fait main', service: false)]),
        );
        await tester.pumpWidget(_card(_assoc, admin, lang: lang));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('spot-stop-pm-fresh')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('spot-fix-confirm')));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('spot-change-pm-fresh')));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('spot-change-dialog')), findsOneWidget);
      });
    }
  });

  // -------------------------------------------------------------------------
  // Screenshots (B148_SHOTS=<dir>)
  // -------------------------------------------------------------------------
  final shots = Platform.environment['B148_SHOTS'];
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
      await _settle(tester);
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')).first);
        final img = await ro.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    final sizes = [('390', 390.0, 1.0), ('320x1.3', 320.0, 1.3)];
    for (final lang in ['fr', 'en']) {
      for (final (tag, w, text) in sizes) {
        testWidgets('$lang $tag', (tester) async {
          Directory(shots!).createSync(recursive: true);
          await tester.runAsync(realFonts);
          final p = '${lang}_${tag}_';
          await _size(tester, w, 1100, text: text);

          await _open(tester, _opener(_shop, _Admin(article: _free, shop: _freeShop), lang: lang));
          await shoot(tester, '${p}1_free');
          await tester.pumpWidget(const SizedBox());
          await _open(tester, _opener(_farm, _Admin(article: _full, shop: _freeShop), lang: lang));
          await shoot(tester, '${p}2_full');
          await tester.pumpWidget(const SizedBox());
          await _open(tester, _opener(_assoc, _Admin(article: _nowhere, shop: _nowhere), lang: lang, vitrineOnly: true));
          await shoot(tester, '${p}3_no_position');

          // The card with its fixes, then the stop and the change dialogs.
          await tester.pumpWidget(const SizedBox());
          final admin = _Admin(
            article: _free,
            mine: [
              _spot('pm-ask', 'requested'),
              _spot('pm-fresh', 'approved', started: const Duration(hours: 2)),
              _spot('pm-shop', 'approved', kind: 'shop', started: const Duration(hours: 30)),
            ],
            options: PromotionOptions(
                canChange: true,
                changeUntil: DateTime.now().add(const Duration(hours: 22)),
                items: const [
                  (id: 'p-sac', name: 'Sac en cuir', service: false),
                  (id: 'p-retouche', name: 'Retouche sur mesure', service: true),
                ]),
          );
          await tester.pumpWidget(_card(_shop, admin, lang: lang));
          await shoot(tester, '${p}4_card_fixes');
          await tester.tap(find.byKey(const Key('spot-stop-pm-fresh')));
          await shoot(tester, '${p}5_stop_dialog');
          await tester.tap(find.text(lang == 'fr' ? 'Continuer' : 'Continue'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('spot-change-pm-fresh')));
          await _settle(tester);
          await tester.tap(find.byKey(const Key('spot-change-item-p-sac')));
          await shoot(tester, '${p}6_change_dialog');
        });
      }
    }
  }, skip: shots == null ? 'B148_SHOTS=<dir> writes the screenshots' : null);
}
