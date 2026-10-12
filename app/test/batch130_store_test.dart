// Batch 130 §1: Mara Pro sold in the store apps.
//
//   * the Pro page in store mode (iPhone and Android): the store's two
//     products at the store's own price, « S'abonner », « Restaurer mes
//     achats », « Gérer mon abonnement », the auto-renewal terms with the
//     two links — and no card, no Wave, no period of Mara's own;
//   * store_billing_on false: the iPhone page sells nothing, the Play page
//     sells by card as before (unchanged);
//   * a purchase: sent to the Worker, completed only after its yes, Pro
//     read again; pending, cancelled, refused and unreachable each say so,
//     an unreachable Worker leaves the purchase open;
//   * every kind's door to Pro opens in store mode: a shop, a farm and an
//     association reach the same page with the same panel.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/access/store_rules.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/pay/wave_pay.dart';
import 'package:kaj_app/features/pro/pro_plans_screen.dart';
import 'package:kaj_app/features/pro/pro_strip.dart';
import 'package:kaj_app/features/pro/store_billing.dart';
import 'package:kaj_app/features/pro/store_panel.dart';
import 'package:kaj_app/features/pro/store_watcher.dart';
import 'package:kaj_app/l10n/strings.dart';

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<bool> isPlatformAdmin() async => false;
  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;
}

/// A store that answers what the test says.
class FakeStore implements StoreBilling {
  FakeStore(this.platform, {this.availableNow = true, List<StoreProduct>? items})
      : items = items ??
            [
              StoreProduct(
                  id: platform == 'apple' ? 'bf.kaj.app.pro.monthly' : 'mara_pro:monthly',
                  period: 'month',
                  price: platform == 'apple' ? '4,99 \$' : '2 900 F CFA'),
              StoreProduct(
                  id: platform == 'apple' ? 'bf.kaj.app.pro.yearly' : 'mara_pro:yearly',
                  period: 'year',
                  price: platform == 'apple' ? '49,99 \$' : '29 900 F CFA'),
            ];

  @override
  final String platform;
  final bool availableNow;
  final List<StoreProduct> items;
  final controller = StreamController<List<StorePurchase>>.broadcast();
  final bought = <(String, String)>[];
  final completed = <StorePurchase>[];
  int restores = 0;

  @override
  Future<bool> available() async => availableNow;
  @override
  Future<List<StoreProduct>> products() async => items;
  @override
  Stream<List<StorePurchase>> get purchases => controller.stream;
  @override
  Future<void> buy(StoreProduct product, {required String orgId}) async =>
      bought.add((product.id, orgId));
  @override
  Future<void> restore() async => restores++;
  @override
  Future<void> complete(StorePurchase purchase) async => completed.add(purchase);
  /// What the store account holds (132).
  List<StoreOwned> held = [];
  @override
  Future<List<StoreOwned>> owned() async => held;
  @override
  Uri get manageUrl => platform == 'apple'
      ? Uri.parse('https://apps.apple.com/account/subscriptions')
      : Uri.parse('https://play.google.com/store/account/subscriptions?sku=mara_pro&package=bf.kaj.app');
}

const _shop = OrgSummary(id: '52000000-0000-0000-0000-0000000000a1', name: 'Elim Shop', profile: 'retail', roles: ['owner']);
const _farm = OrgSummary(id: '52000000-0000-0000-0000-0000000000a2', name: 'Ferme Wend', profile: 'farm', roles: ['owner']);
const _assoc = OrgSummary(id: '52000000-0000-0000-0000-0000000000a3', name: 'Entraide', profile: 'association', roles: ['owner']);

const _terms = PlanTerms(stripeOn: true, priceMonth: 2900, priceYear: 29900, storeBillingOn: true);

void main() {
  tearDown(() {
    debugSellsDigitalInApp = null;
    debugStoreBillingPlatform = null;
    storeBillingOn = false;
  });

  /// The iPhone app (STORE=appstore) or the Play build (STORE=play).
  void build(String store, {required bool on}) {
    debugStoreBillingPlatform = store == 'appstore' ? 'apple' : 'google';
    debugSellsDigitalInApp = store != 'appstore';
    storeBillingOn = on;
  }

  Future<List<StorePurchase>> page(
    WidgetTester tester, {
    required OrgSummary org,
    FakeStore? store,
    Future<StoreVerdict> Function(StorePurchase p)? verify,
    VoidCallback? onPro,
    Future<StoreStanding?> Function()? standing,
  }) async {
    tester.view.physicalSize = const Size(390, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final sent = <StorePurchase>[];
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => ProPlansScreen(
          org: org,
          terms: _terms,
          admin: _Admin(),
          cardButton: (period) => Container(key: const Key('card-button')),
          cardManage: Container(key: const Key('card-manage')),
          storeBilling: store,
          storeVerify: store == null
              ? null
              : (p) async {
                  sent.add(p);
                  return verify == null
                      ? const StoreVerdict(pro: true, state: 'active')
                      : verify(p);
                },
          storeStanding: standing,
          onPaid: onPro,
        ),
      ),
      GoRoute(path: '/conditions', builder: (_, _) => const Text('CONDITIONS')),
      GoRoute(path: '/confidentialite', builder: (_, _) => const Text('CONFIDENTIALITE')),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return sent;
  }

  group('the Pro page in store mode', () {
    for (final (store, platform, month, year, name) in [
      ('appstore', 'apple', '4,99 \$', '49,99 \$', 'App Store'),
      ('play', 'google', '2 900 F CFA', '29 900 F CFA', 'Google Play'),
    ]) {
      testWidgets('$name: the store\'s products and prices, restore, manage, the terms — no card, no Wave',
          (tester) async {
        build(store, on: true);
        expect(sellsProThroughStore, isTrue);
        final fake = FakeStore(platform);
        await page(tester, org: _shop, store: fake);
        expect(find.byKey(const Key('store-panel')), findsOneWidget);
        expect(find.byKey(const Key('store-product-month')), findsOneWidget);
        expect(find.byKey(const Key('store-product-year')), findsOneWidget);
        expect(find.text('$month par mois'), findsOneWidget);
        expect(find.text('$year par an'), findsOneWidget);
        expect(find.byKey(const Key('store-buy-month')), findsOneWidget);
        expect(find.byKey(const Key('store-restore')), findsOneWidget);
        expect(find.byKey(const Key('store-manage')), findsOneWidget);
        final legal = tester.widget<Text>(find.byKey(const Key('store-legal'))).data!;
        expect(legal, contains('renouvellement automatique : 1 mois à $month, ou 1 an à $year'));
        expect(legal, contains('compte $name'));
        expect(legal, contains('au moins 24 heures avant la fin de la période'));
        expect(legal, contains('annulez-le à tout moment dans les réglages'));
        expect(find.byKey(const Key('store-terms')), findsOneWidget);
        expect(find.byKey(const Key('store-privacy')), findsOneWidget);
        // Nothing of Mara's own way to pay beside the store's.
        expect(find.byKey(const Key('card-button')), findsNothing);
        expect(find.byKey(const Key('card-manage')), findsNothing);
        expect(find.byKey(const Key('pro-period')), findsNothing);
        expect(find.byKey(const Key('pro-price')), findsNothing);
        expect(find.byKey(const Key('pro-soon')), findsNothing);
        expect(find.textContaining('par carte'), findsNothing);

        // « Gérer » opens the store's page; the links open the app's pages.
        await tester.tap(find.byKey(const Key('store-terms')));
        await tester.pumpAndSettle();
        expect(find.text('CONDITIONS'), findsOneWidget);
      });
    }

    testWidgets('« S\'abonner » passes the business to the store; « Gérer » opens the store\'s page', (tester) async {
      build('appstore', on: true);
      final fake = FakeStore('apple');
      await page(tester, org: _shop, store: fake);
      await tester.tap(find.byKey(const Key('store-buy-year')));
      await tester.pump();
      expect(fake.bought, [('bf.kaj.app.pro.yearly', _shop.id)]);

      final opened = <Uri>[];
      for (final f in [FakeStore('apple'), FakeStore('google')]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StorePanel(
                org: _shop,
                billing: f,
                verify: (_) async => const StoreVerdict(pro: true, state: 'active'),
                launch: (uri) async {
                  opened.add(uri);
                  return true;
                },
              ),
            ),
          ),
        ));
        await tester.pump();
        await tester.tap(find.byKey(const Key('store-manage')));
        await tester.pump();
      }
      expect(opened.map((u) => u.toString()), [
        'https://apps.apple.com/account/subscriptions',
        'https://play.google.com/store/account/subscriptions?sku=mara_pro&package=bf.kaj.app',
      ]);
    });

    testWidgets('a purchase: sent to the Worker, completed after its yes, Pro read again', (tester) async {
      build('appstore', on: true);
      final fake = FakeStore('apple');
      var pro = 0;
      final sent = await page(tester, org: _shop, store: fake, onPro: () => pro++);
      fake.controller.add(const [
        StorePurchase(status: StorePurchaseStatus.pending, productId: 'bf.kaj.app.pro.monthly'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Achat en attente : App Store doit encore le confirmer'), findsOneWidget);
      expect(sent, isEmpty, reason: 'nothing is verified while pending');

      fake.controller.add(const [
        StorePurchase(
            status: StorePurchaseStatus.purchased,
            productId: 'bf.kaj.app.pro.monthly',
            transactionId: '2000000111',
            needsCompletion: true),
      ]);
      await tester.pump();
      await tester.pump();
      expect(sent.single.transactionId, '2000000111');
      expect(fake.completed, hasLength(1), reason: 'completed once the Worker said yes');
      expect(pro, 1);
      expect(find.text('Merci ! Mara Pro est actif.'), findsOneWidget);
    });

    testWidgets('the Worker unreachable: the purchase stays open; refused: closed, its reason said',
        (tester) async {
      build('play', on: true);
      final fake = FakeStore('google');
      var answer = 0;
      await page(tester, org: _farm, store: fake, verify: (p) async {
        answer++;
        if (answer == 1) throw StateError('Pas de connexion au serveur de Mara.');
        throw const StoreVerifyRefused('Cet achat a été fait pour une autre entreprise.', 'wrong_org');
      });
      const bought = StorePurchase(
          status: StorePurchaseStatus.purchased, productId: 'mara_pro', token: 'tok-0123456789', needsCompletion: true);
      fake.controller.add(const [bought]);
      await tester.pump();
      await tester.pump();
      expect(fake.completed, isEmpty, reason: 'not completed: the store hands it back');
      expect(find.textContaining('Mara n\'a pas encore pu le vérifier'), findsOneWidget);
      fake.controller.add(const [bought]);
      await tester.pump();
      await tester.pump();
      expect(fake.completed, hasLength(1));
      expect(find.text('Cet achat a été fait pour une autre entreprise.'), findsOneWidget);
    });

    testWidgets('cancelled and failed purchases say so in French; Play\'s « already owned » is explained',
        (tester) async {
      build('play', on: true);
      final fake = FakeStore('google');
      await page(tester, org: _assoc, store: fake);
      fake.controller.add(const [StorePurchase(status: StorePurchaseStatus.canceled, productId: 'mara_pro')]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Achat annulé : rien n\'a été prélevé.'), findsOneWidget);
      fake.controller.add(const [
        StorePurchase(status: StorePurchaseStatus.error, productId: 'mara_pro',
            errorCode: 'purchase_error', errorMessage: 'BillingResponse.itemAlreadyOwned'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Ce compte Google Play paie déjà Mara Pro'), findsOneWidget);
      fake.controller.add(const [
        StorePurchase(status: StorePurchaseStatus.error, productId: 'mara_pro', errorCode: 'network'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('L\'achat n\'a pas pu se faire : Google Play n\'a rien prélevé'), findsOneWidget);
    });

    testWidgets('« Restaurer mes achats » asks the store, and says when it found nothing', (tester) async {
      build('appstore', on: true);
      final fake = FakeStore('apple');
      await page(tester, org: _shop, store: fake);
      await tester.tap(find.byKey(const Key('store-restore')));
      await tester.pump();
      expect(fake.restores, 1);
      expect(find.textContaining('Recherche de vos achats sur App Store'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Aucun abonnement Mara Pro à restaurer sur ce compte App Store.'), findsOneWidget);
    });

    testWidgets('S4 a second business: nothing to buy, the business paid named, « Gérer » offered',
        (tester) async {
      for (final (store, platform) in [('appstore', 'apple'), ('play', 'google')]) {
        build(store, on: true);
        final fake = FakeStore(platform);
        await page(tester, org: _farm, store: fake,
            standing: () async => StoreStanding(elsewhereName: 'Elim Shop', elsewherePlatform: platform));
        expect(find.byKey(const Key('store-elsewhere')), findsOneWidget);
        expect(find.textContaining('paie déjà Mara Pro pour « Elim Shop »'), findsOneWidget);
        // On Apple the other period would only crossgrade Elim Shop's:
        // neither period is offered.
        expect(find.byKey(const Key('store-buy-month')), findsNothing, reason: platform);
        expect(find.byKey(const Key('store-buy-year')), findsNothing, reason: platform);
        expect(find.byKey(const Key('store-manage')), findsOneWidget);
        expect(fake.bought, isEmpty);
      }
      // Paid in the other store (another account): this one may sell.
      build('appstore', on: true);
      await page(tester, org: _farm, store: FakeStore('apple'),
          standing: () async => const StoreStanding(elsewhereName: 'Elim Shop', elsewherePlatform: 'google'));
      expect(find.byKey(const Key('store-elsewhere')), findsNothing);
      expect(find.byKey(const Key('store-buy-month')), findsOneWidget);
    });

    testWidgets('an employee is not offered to buy; a Pro business has restore and manage, nothing to buy',
        (tester) async {
      build('appstore', on: true);
      await page(tester,
          org: const OrgSummary(id: 'o9', name: 'Elim Shop', profile: 'retail', roles: ['employee']),
          store: FakeStore('apple'));
      expect(find.byKey(const Key('store-buy-month')), findsNothing);
      expect(find.text('Seul un administrateur de l\'entreprise peut l\'abonner à Mara Pro.'), findsOneWidget);
      await page(tester,
          org: const OrgSummary(id: 'o8', name: 'Elim Shop', profile: 'retail', roles: ['owner'], plan: 'pro'),
          store: FakeStore('apple'),
          standing: () async => const StoreStanding(platform: 'apple', state: 'active'));
      expect(find.text('Vous êtes sur Mara Pro'), findsOneWidget);
      expect(find.byKey(const Key('store-buy-month')), findsNothing);
      expect(find.byKey(const Key('store-restore')), findsOneWidget);
      expect(find.byKey(const Key('store-manage')), findsOneWidget);
      // Pro paid by card (or in the other store): the App Store's page
      // holds nothing of it — no « Gérer ».
      await page(tester,
          org: const OrgSummary(id: 'o7', name: 'Elim Shop', profile: 'retail', roles: ['owner'], plan: 'pro'),
          store: FakeStore('apple'),
          standing: () async => const StoreStanding());
      expect(find.byKey(const Key('store-restore')), findsOneWidget);
      expect(find.byKey(const Key('store-manage')), findsNothing);
    });

    testWidgets('a store that sells nothing here says so', (tester) async {
      build('play', on: true);
      await page(tester, org: _shop, store: FakeStore('google', availableNow: false));
      expect(find.byKey(const Key('store-unavailable')), findsOneWidget);
    });
  });

  group('store_billing_on false: today\'s behaviour, unchanged', () {
    testWidgets('the iPhone app sells nothing and draws no store panel', (tester) async {
      build('appstore', on: false);
      expect(sellsProThroughStore, isFalse);
      expect(sellsProInApp, isFalse);
      await page(tester, org: _shop, store: FakeStore('apple'));
      expect(find.byKey(const Key('store-panel')), findsNothing);
      expect(find.byKey(const Key('pro-price')), findsNothing);
      expect(find.byKey(const Key('pro-period')), findsNothing);
      expect(find.byKey(const Key('card-button')), findsNothing);
      expect(ProStrip.shownFor(_shop), isFalse);
    });

    testWidgets('the Play app sells by card as before', (tester) async {
      build('play', on: false);
      await page(tester, org: _shop, store: FakeStore('google'));
      expect(find.byKey(const Key('store-panel')), findsNothing);
      expect(find.byKey(const Key('pro-price')), findsOneWidget);
      expect(find.byKey(const Key('pro-period')), findsOneWidget);
      expect(find.byKey(const Key('card-button')), findsOneWidget);
    });

    testWidgets('the web and the GitHub APK never sell through a store', (tester) async {
      debugSellsDigitalInApp = true;
      storeBillingOn = true;
      debugStoreBillingPlatform = null;
      expect(storeBillingPlatform, isNull, reason: 'no STORE in a test build');
      expect(sellsProThroughStore, isFalse);
      await page(tester, org: _shop);
      expect(find.byKey(const Key('store-panel')), findsNothing);
      expect(find.byKey(const Key('card-button')), findsOneWidget);
    });
  });

  group('shop, farm and association reach the same page', () {
    for (final org in [_shop, _farm, _assoc]) {
      testWidgets('${org.profile}: the Pro strip invites, the page sells through the store', (tester) async {
        build('appstore', on: true);
        expect(ProStrip.shownFor(org), isTrue);
        expect(sellsProInApp, isTrue);
        await page(tester, org: org, store: FakeStore('apple'));
        expect(find.byKey(const Key('store-panel')), findsOneWidget);
        expect(find.byKey(const Key('store-buy-month')), findsOneWidget);
      });
    }
  });

  group('S3: the app\'s own listener, from its start', () {
    const forA = StorePurchase(
        status: StorePurchaseStatus.purchased,
        productId: 'bf.kaj.app.pro.monthly',
        transactionId: '2000000111',
        needsCompletion: true,
        orgId: '52000000-0000-0000-0000-0000000000a1');

    test('with no page open: a purchase is verified for the business it names, completed, said outside', () async {
      final fake = FakeStore('apple');
      final sent = <StorePurchase>[];
      final outside = <StoreNotice>[];
      var pro = 0;
      final w = StoreWatcher(
        billing: fake,
        verify: (p) async {
          sent.add(p);
          return const StoreVerdict(pro: true, state: 'active');
        },
        onPro: () => pro++,
        outside: outside.add,
      )..start();
      addTearDown(w.dispose);
      fake.controller.add(const [forA]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(sent.single.orgId, '52000000-0000-0000-0000-0000000000a1');
      expect(fake.completed, hasLength(1));
      expect(pro, 1);
      expect(outside, isNotEmpty, reason: 'no page: a snackbar says it');
    });

    testWidgets('on another business\'s page: verified for ITS business, never the page\'s', (tester) async {
      build('appstore', on: true);
      final fake = FakeStore('apple');
      final sent = <StorePurchase>[];
      final outside = <StoreNotice>[];
      final w = StoreWatcher(billing: fake, outside: outside.add, verify: (p) async {
        sent.add(p);
        return const StoreVerdict(pro: true, state: 'active');
      })..start();
      addTearDown(w.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StorePanel(
              org: _farm, billing: fake, watcher: w,
              verify: (_) async => throw StateError('the page never verifies when the app listens'),
            ),
          ),
        ),
      ));
      await tester.pump();
      fake.controller.add(const [forA]);
      await tester.pump();
      await tester.pump();
      expect(sent.single.orgId, _shop.id, reason: 'the shop it was bought for, not the farm on screen');
      expect(fake.completed, hasLength(1));
      // 132: the farm's page draws only the farm's notices — the shop's
      // is said outside (a snackbar in the app), never on another's page.
      expect(find.text('Merci ! Mara Pro est actif.'), findsNothing, reason: 'the shop\'s notice, not the farm\'s');
      expect(outside.last.orgId, _shop.id);
    });

    test('a refusal that may pass — session, not an admin (yet), the server, no network — leaves it open', () async {
      for (final error in <Object>[
        const StoreVerifyRefused('Votre session a expiré', 'session', status: 401),
        const StoreVerifyRefused('Seul un administrateur…', 'not_admin', status: 403),
        const StoreVerifyRefused('', '', status: 409),
        StateError('Pas de connexion au serveur de Mara.'),
      ]) {
        final fake = FakeStore('google');
        final logged = <String>[];
        final w = StoreWatcher(billing: fake, verify: (_) async => throw error, log: logged.add)..start();
        fake.controller.add(const [
          StorePurchase(status: StorePurchaseStatus.purchased, productId: 'mara_pro', token: 'tok-0123456789',
              needsCompletion: true, orgId: '52000000-0000-0000-0000-0000000000a2'),
        ]);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(fake.completed, isEmpty, reason: '$error: not completed, the store hands it back');
        if (error is StoreVerifyRefused) {
          expect(logged.single, contains('left open'));
          expect(logged.single, isNot(contains('tok-0123456789')), reason: 'never a token in the log');
        }
        w.dispose();
      }
    });

    test('a refusal for good — another business, a test purchase, not Mara Pro — finished, said, logged', () async {
      for (final code in ['wrong_org', 'replayed', 'sandbox', 'product', 'bundle', 'no_org']) {
        final fake = FakeStore('apple');
        final logged = <String>[];
        final w = StoreWatcher(billing: fake, verify: (_) async => throw StoreVerifyRefused('…', code), log: logged.add)
          ..start();
        fake.controller.add(const [forA]);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(fake.completed, hasLength(1), reason: code);
        expect(logged.single, contains('($code, finished)'));
        expect(w.notice.value, isNotNull);
        w.dispose();
      }
    });

    testWidgets('the refusal is said by its code, in the reader\'s language', (tester) async {
      String? fr;
      String? en;
      for (final locale in [null, const Locale('en')]) {
        await tester.pumpWidget(MaterialApp(
          locale: locale,
          localizationsDelegates: locale == null ? null : Strings.localizationsDelegates,
          supportedLocales: locale == null ? const [Locale('en', 'US')] : Strings.supportedLocales,
          home: Builder(builder: (context) {
            final t = storeRefusalText(context, const StoreVerifyRefused('Achat de test refusé : …', 'sandbox'), 'App Store');
            if (locale == null) {
              fr = t;
            } else {
              en = t;
            }
            return Text(t);
          }),
        ));
      }
      expect(fr, startsWith('Achat de test refusé : un achat fait avec un compte de test'));
      expect(en, startsWith('Test purchase refused: a purchase made with a test account'));
    });
  });

  test('PlanTerms reads store_billing_on, off when absent', () {
    expect(PlanTerms.fromJson(const {'store_billing_on': true}).storeBillingOn, isTrue);
    expect(PlanTerms.fromJson(const {}).storeBillingOn, isFalse);
    expect(const PlanTerms(storeBillingOn: true).forProfile('farm').storeBillingOn, isTrue);
  });
}
