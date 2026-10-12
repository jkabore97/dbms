// Batch 132: the owner's TestFlight 4 (iPhone) and internal Android build.
//
//   1. a way back on every screen — an iPhone has no system back: the
//      WhatsApp status preview and its share sheet, every bottom sheet (its
//      « X »), the sign-in page reached with `go`, and a sample of the
//      app's routes, pushed and opened cold ([expectWayBack]);
//   2. « S'abonner »: only the tapped button is busy, the other keeps its
//      look and does not answer — App Store and Google Play;
//   3. a store failure says why: the friendly line and the store's code,
//      reported; a cancel says nothing alarming and is not reported;
//   4. a store account that already holds Mara Pro — for another business,
//      or one the Worker refused — is not offered a purchase the store
//      would refuse; another business's refusal never shows here;
//   5. the business's bar is on the very first frame, for a shop, a farm
//      and an association, and the page does not move when the home's own
//      places arrive.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/nav/business_cover.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/pay/wave_pay.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/core/theme/mara_mark.dart' show maraPaper;
import 'package:kaj_app/core/theme/mara_sheet.dart';
import 'package:kaj_app/features/account/legal_screens.dart';
import 'package:kaj_app/features/auth/login_screen.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/home/business_frame.dart';
import 'package:kaj_app/features/home/home_nav.dart' show BusinessNav;
import 'package:kaj_app/features/pro/pro_plans_screen.dart';
import 'package:kaj_app/features/pro/store_billing.dart';
import 'package:kaj_app/features/pro/store_panel.dart';
import 'package:kaj_app/features/pro/store_watcher.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/features/storefront/share_vitrine.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

// ---------------------------------------------------------------------------
// The way back
// ---------------------------------------------------------------------------

/// Every control that leaves a screen: Flutter's own arrow or cross (an
/// AppBar's implied one among them), or an IconButton drawing one.
Finder wayBack() => find.byWidgetPredicate((w) {
      if (w is BackButton || w is CloseButton) return true;
      if (w is IconButton && w.icon is Icon) {
        final icon = (w.icon as Icon).icon;
        return icon == Icons.arrow_back || icon == Icons.close || icon == Icons.arrow_back_ios_new;
      }
      return false;
    });

/// The generic check (132): the screen on top offers a visible way back.
void expectWayBack(WidgetTester tester, {required String reason}) {
  expect(wayBack().hitTestable(), findsAtLeastNWidgets(1), reason: '$reason: no visible back or close');
}

Widget _app({GoRouter? router, Widget? home, Locale? locale}) {
  final theme = ThemeData(platform: TargetPlatform.iOS);
  final shown = locale ?? const Locale('fr');
  return router != null
      ? MaterialApp.router(
          theme: theme,
          locale: shown,
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          routerConfig: router,
        )
      : MaterialApp(
          theme: theme,
          locale: shown,
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          home: home,
        );
}

Future<void> _phone(WidgetTester tester, [double height = 844]) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

const _vitrine = PublicShop(orgId: 'o-awa', name: 'Boutique Awa', slug: 'boutique-awa', profile: 'retail');

// ---------------------------------------------------------------------------
// The store
// ---------------------------------------------------------------------------

class _Store implements StoreBilling {
  _Store(this.platform);

  @override
  final String platform;
  final controller = StreamController<List<StorePurchase>>.broadcast();
  final bought = <String>[];
  List<StoreOwned> held = [];

  /// What « S'abonner » does: waits on [running] (a purchase on screen),
  /// or throws [failure] (StoreKit 2 says its refusals here).
  Completer<void>? running;
  Object? failure;

  @override
  Future<bool> available() async => true;
  @override
  Future<List<StoreProduct>> products() async => [
        StoreProduct(id: platform == 'apple' ? 'bf.kaj.app.pro.monthly' : 'mara_pro:monthly', period: 'month', price: '4,99 \$'),
        StoreProduct(id: platform == 'apple' ? 'bf.kaj.app.pro.yearly' : 'mara_pro:yearly', period: 'year', price: '49,99 \$'),
      ];
  @override
  Stream<List<StorePurchase>> get purchases => controller.stream;
  @override
  Future<void> buy(StoreProduct product, {required String orgId}) async {
    bought.add(product.id);
    final f = failure;
    if (f != null) throw f;
    await running?.future;
  }

  @override
  Future<void> restore() async {}
  @override
  Future<void> complete(StorePurchase purchase) async {}
  @override
  Future<List<StoreOwned>> owned() async => held;
  @override
  Uri get manageUrl => Uri.parse('https://example.test/manage');
}

const _shop = OrgSummary(id: '52000000-0000-0000-0000-0000000000a1', name: 'Elim Shop', profile: 'retail', roles: ['owner']);
const _farm = OrgSummary(id: '52000000-0000-0000-0000-0000000000a2', name: 'Ferme Wend', profile: 'farm', roles: ['owner']);
const _assoc = OrgSummary(id: '52000000-0000-0000-0000-0000000000a3', name: 'Entraide', profile: 'association', roles: ['owner']);

Future<void> _panel(WidgetTester tester, _Store store,
    {OrgSummary org = _shop, StoreWatcher? watcher, Locale? locale}) async {
  await _phone(tester, 1400);
  await tester.pumpWidget(_app(
    locale: locale,
    home: Scaffold(
      body: SingleChildScrollView(
        child: StorePanel(
          org: org,
          billing: store,
          watcher: watcher,
          verify: (_) async => const StoreVerdict(pro: true, state: 'active'),
          launch: (_) async => true,
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

FilledButton _buy(WidgetTester tester, String period) =>
    tester.widget<FilledButton>(find.byKey(Key('store-buy-$period')));

// ---------------------------------------------------------------------------
// The business's bar
// ---------------------------------------------------------------------------

class _Shop extends RetailRepository {
  _Shop(super.client);
  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();
  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) async => const [];
  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [];
  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) async => 0;
  @override
  Future<int> pendingOrders(String orgId) async => 0;
}

GoRouter _business(Widget Function() home, OrgSummary org, SessionController session) {
  final cover = BusinessCover();
  return GoRouter(initialLocation: '/o/${org.id}', routes: [
    ShellRoute(
      observers: [cover],
      builder: (context, state, child) => BusinessFrame(
          org: org, location: state.uri.path, cover: cover, session: session, child: child),
      routes: [
        GoRoute(
          path: '/o/:orgId',
          builder: (_, _) => BusinessPage(child: home()),
          routes: [
            for (final r in const ['produits', 'commandes', 'factures', 'stock', 'bandes', 'rapports', 'journal', 'compte', 'administration', 'equipe'])
              GoRoute(path: r, builder: (_, _) => BusinessPage(child: Scaffold(appBar: AppBar(title: Text('Page $r'))))),
          ],
        ),
      ],
    ),
  ]);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('1. a way back on every screen', () {
    testWidgets('the WhatsApp status: its sheet has an « X », its preview a close that goes back', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Vitrine')),
            body: TextButton(
              key: const Key('open-share'),
              onPressed: () => ShareVitrine.open(context, shop: _vitrine, items: const []),
              child: const Text('Partager'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open-share')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('share-vitrine')), findsOneWidget);
      expect(find.byKey(const Key('sheet-close')).hitTestable(), findsOneWidget);

      await tester.tap(find.byKey(const Key('share-status')));
      await tester.pumpAndSettle();
      expect(find.text('Votre statut'), findsOneWidget);
      expect(find.byKey(const Key('status-close')).hitTestable(), findsOneWidget);
      expectWayBack(tester, reason: 'status preview');

      await tester.tap(find.byKey(const Key('status-close')));
      await tester.pumpAndSettle();
      expect(find.text('Votre statut'), findsNothing);
      expect(find.byKey(const Key('share-vitrine')), findsNothing, reason: 'the sheet under it closes too');
      expect(find.text('Vitrine'), findsOneWidget);

      // The sheet's own « X » closes it.
      await tester.tap(find.byKey(const Key('open-share')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('share-vitrine')), findsNothing);
    });

    testWidgets('the status preview opened alone (nothing under it) still has its close', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(
        home: const StatusPreview(
          card: StatusCard(shop: _vitrine, items: []),
          name: 'awa.png',
          text: 'Boutique Awa',
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('status-close')).hitTestable(), findsOneWidget);
    });

    testWidgets('the dark bars draw their way back in paper, not in the theme\'s ink (it was invisible)',
        (tester) async {
      await _phone(tester);
      await tester.pumpWidget(MaterialApp(
        theme: kajTheme(kajPalette).copyWith(platform: TargetPlatform.iOS),
        home: const StatusPreview(
          card: StatusCard(shop: _vitrine, items: []),
          name: 'awa.png',
          text: 'Boutique Awa',
        ),
      ));
      await tester.pump();
      Color? ink(Finder of) => tester
          .widget<RichText>(find.descendant(of: of, matching: find.byType(RichText)).first)
          .text
          .style
          ?.color;
      expect(ink(find.byKey(const Key('status-close'))), maraPaper, reason: 'the X on maraBlack');
      expect(ink(find.text('Votre statut')), maraPaper, reason: 'the title on maraBlack');
    });

    testWidgets('every sheet: the « X » beside the handle, above the content, never over it', (tester) async {
      await _phone(tester);
      for (final handle in [true, false]) {
        await tester.pumpWidget(_app(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open'),
                onPressed: () => showMaraSheet<void>(
                  context: context,
                  showDragHandle: handle,
                  builder: (_) => const SizedBox(height: 120, child: Text('Contenu', key: Key('content'))),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ));
        await tester.tap(find.byKey(const Key('open')));
        await tester.pumpAndSettle();
        final close = tester.getRect(find.byKey(const Key('sheet-close')));
        final content = tester.getRect(find.byKey(const Key('content')));
        expect(close.bottom, lessThanOrEqualTo(content.top), reason: 'handle $handle: the X stands above the content');
        await tester.tap(find.byKey(const Key('sheet-close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('content')), findsNothing);
      }
    });

    testWidgets('a sample of the app\'s routes, pushed and opened cold, each with its way back', (tester) async {
      await _phone(tester);
      final router = GoRouter(initialLocation: Routes.directory, routes: [
        GoRoute(
          path: Routes.directory,
          builder: (_, _) => const Scaffold(body: Center(child: Text('La rue'))),
        ),
        GoRoute(path: Routes.privacy, builder: (_, _) => const PrivacyScreen()),
        GoRoute(path: Routes.terms, builder: (_, _) => const TermsScreen()),
        GoRoute(path: Routes.faq, builder: (_, _) => const FaqScreen()),
        GoRoute(
          path: Routes.signIn,
          builder: (_, _) => LoginScreen(auth: AuthRepository(null), onSignedIn: (_) async {}),
        ),
        // As the router nests it: the business's home under its Pro page.
        GoRoute(
          path: '/o/:orgId',
          builder: (_, _) => const Scaffold(body: Text('Accueil')),
          routes: [
            GoRoute(
              path: 'kaj-pro',
              builder: (_, _) => ProPlansScreen(org: _shop, terms: PlanTerms.defaults, admin: AdminRepository(null)),
            ),
          ],
        ),
        GoRoute(
          path: '/statut',
          builder: (_, _) => const StatusPreview(
              card: StatusCard(shop: _vitrine, items: []), name: 'awa.png', text: 'Boutique Awa'),
        ),
      ]);
      await tester.pumpWidget(_app(router: router));
      await tester.pumpAndSettle();
      for (final path in [Routes.privacy, Routes.terms, Routes.faq, Routes.signIn, '/o/${_shop.id}/kaj-pro', '/statut']) {
        // Pushed over the street.
        unawaited(router.push(path));
        await tester.pumpAndSettle();
        expectWayBack(tester, reason: 'pushed $path');
        router.pop();
        await tester.pumpAndSettle();
        // Opened cold, with `go` (a link, a redirect): nothing under it.
        router.go(path);
        await tester.pumpAndSettle();
        expectWayBack(tester, reason: 'opened with go $path');
        router.go(Routes.directory);
        await tester.pumpAndSettle();
      }
      // The sign-in's back, opened cold, goes to the street.
      router.go(Routes.signIn);
      await tester.pumpAndSettle();
      await tester.tap(wayBack().hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.text('La rue'), findsOneWidget);
    });
  });

  group('2. « S\'abonner »: only the tapped button is busy', () {
    for (final platform in ['apple', 'google']) {
      testWidgets('$platform: the tapped one spins, the other keeps its look and does not answer', (tester) async {
        final store = _Store(platform)..running = Completer<void>();
        await _panel(tester, store);
        final styleBefore = _buy(tester, 'year').style;
        await tester.tap(find.byKey(const Key('store-buy-month')));
        await tester.pump();
        expect(find.descendant(of: find.byKey(const Key('store-buy-month')), matching: find.byKey(const Key('store-buy-busy'))),
            findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('store-buy-year')), matching: find.byKey(const Key('store-buy-busy'))),
            findsNothing);
        expect(find.descendant(of: find.byKey(const Key('store-buy-year')), matching: find.text('S\'abonner')), findsOneWidget);
        // The other: not tappable, drawn as before.
        final year = _buy(tester, 'year');
        expect(year.onPressed, isNull);
        final ink = year.style!.backgroundColor!.resolve({WidgetState.disabled});
        expect(ink, styleBefore!.backgroundColor!.resolve(const {}), reason: 'disabled, it keeps its colour');
        await tester.tap(find.byKey(const Key('store-buy-year')));
        await tester.pump();
        expect(store.bought, hasLength(1), reason: 'one purchase at a time');
        // The store answers: both are back.
        store.controller.add([StorePurchase(status: StorePurchaseStatus.canceled, productId: store.bought.single)]);
        store.running!.complete();
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('store-buy-busy')), findsNothing);
        expect(_buy(tester, 'month').onPressed, isNotNull);
        expect(_buy(tester, 'year').onPressed, isNotNull);
      });
    }
  });

  group('3. a store failure says why', () {
    test('the store\'s code, short: Google\'s BillingResponse, StoreKit\'s code', () {
      expect(storeErrorCode('purchase_error', 'BillingResponse.itemAlreadyOwned'), 'itemAlreadyOwned');
      expect(storeErrorCode('storekit2_failed_to_fetch_product', 'Storekit has failed to fetch this product.'),
          'storekit2_failed_to_fetch_product');
      expect(storeErrorCode(null, null), isNull);
      expect(storeErrorCode('x' * 90, null)!.length, 58);
      expect(storeCancelled('purchase_error', 'BillingResponse.userCanceled'), isTrue);
      expect(storeCancelled('storekit2_failed_to_fetch_product', ''), isFalse);
      final line = storeErrorLine('apple', 'bf.kaj.app.pro.monthly', 'storekit2_failed_to_fetch_product', 'Storekit has failed', 'Product ID : x');
      expect(line, contains('code=storekit2_failed_to_fetch_product'));
      expect(line, contains('details=Product ID : x'));
    });

    testWidgets('App Store: StoreKit\'s refusal at « S\'abonner » — the friendly line, its code, reported', (tester) async {
      final store = _Store('apple')
        ..failure = PlatformException(
            code: 'storekit2_failed_to_fetch_product',
            message: 'Storekit has failed to fetch this product.',
            details: 'Product ID : bf.kaj.app.pro.monthly');
      final logged = <String>[];
      final w = StoreWatcher(billing: store, verify: (_) async => const StoreVerdict(pro: true, state: 'active'), log: logged.add)
        ..start();
      addTearDown(w.dispose);
      await _panel(tester, store, watcher: w);
      await tester.tap(find.byKey(const Key('store-buy-month')));
      await tester.pump();
      await tester.pump();
      final said = tester.widget<Text>(find.descendant(of: find.byKey(const Key('store-message')), matching: find.byType(Text))).data!;
      expect(said, startsWith('L\'achat n\'a pas pu se faire : App Store n\'a rien prélevé.'));
      expect(said, endsWith('\n(App Store : storekit2_failed_to_fetch_product)'));
      expect(logged.single, contains('apple bf.kaj.app.pro.monthly: code=storekit2_failed_to_fetch_product'));
      expect(logged.single, contains('details=Product ID'));
      expect(find.byKey(const Key('store-buy-busy')), findsNothing, reason: 'the button is back');
    });

    testWidgets('Google Play: the purchase stream\'s error — its BillingResponse said, in English too', (tester) async {
      for (final (locale, line) in [
        (null, '(Google Play : developerError)'),
        (const Locale('en'), '(Google Play: developerError)'),
      ]) {
        final store = _Store('google');
        final logged = <String>[];
        final w = StoreWatcher(billing: store, verify: (_) async => const StoreVerdict(pro: true, state: 'active'), log: logged.add)
          ..start();
        await _panel(tester, store, watcher: w, locale: locale);
        store.controller.add(const [
          StorePurchase(status: StorePurchaseStatus.error, productId: 'mara_pro', errorCode: 'purchase_error',
              errorMessage: 'BillingResponse.developerError', errorDetails: 'Invalid offer token'),
        ]);
        await tester.pump();
        await tester.pump();
        expect(find.textContaining(line), findsOneWidget, reason: '$locale');
        expect(logged.single, contains('details=Invalid offer token'));
        w.dispose();
      }
    });

    testWidgets('a cancel says nothing alarming, no code, and is not reported', (tester) async {
      for (final (store, cancel) in [
        (_Store('apple'), PlatformException(code: 'userCancelled', message: 'The user cancelled')),
        (_Store('google'), null),
      ]) {
        store.failure = cancel;
        final logged = <String>[];
        final w = StoreWatcher(billing: store, verify: (_) async => const StoreVerdict(pro: true, state: 'active'), log: logged.add)
          ..start();
        await _panel(tester, store, watcher: w);
        if (cancel != null) {
          await tester.tap(find.byKey(const Key('store-buy-month')));
        } else {
          store.controller.add(const [
            StorePurchase(status: StorePurchaseStatus.error, productId: 'mara_pro', errorCode: 'purchase_error',
                errorMessage: 'BillingResponse.userCanceled'),
          ]);
        }
        await tester.pump();
        await tester.pump();
        expect(find.text('Achat annulé : rien n\'a été prélevé.'), findsOneWidget, reason: store.platform);
        expect(find.textContaining('('), findsNothing, reason: 'no code line');
        expect(logged, isEmpty, reason: '${store.platform}: a cancel is not reported');
        w.dispose();
      }
    });
  });

  group('4. a store account that already holds Mara Pro', () {
    for (final (platform, account, where) in [
      ('google', 'Google Play', 'Google Play'),
      ('apple', 'Apple', 'l\'App Store'),
    ]) {
      testWidgets('$platform: for another business — nothing to buy, said, « Gérer mon abonnement »', (tester) async {
        final store = _Store(platform)
          ..held = [StoreOwned(productId: platform == 'apple' ? 'bf.kaj.app.pro.monthly' : 'mara_pro', orgId: _shop.id, token: 't-elim')];
        await _panel(tester, store, org: _farm);
        expect(find.byKey(const Key('store-buy-month')), findsNothing);
        expect(find.byKey(const Key('store-buy-year')), findsNothing);
        expect(
            find.text('Ce compte $account a déjà un abonnement Mara Pro, pour une autre entreprise ou refusé. '
                'Gérez-le ou annulez-le dans $where, puis réessayez.'),
            findsOneWidget);
        expect(find.byKey(const Key('store-manage')), findsOneWidget);
        expect(find.text('Gérer mon abonnement'), findsOneWidget);
      });
    }

    testWidgets('for this business but refused by Mara (a test purchase): the same — the store would refuse a second',
        (tester) async {
      final store = _Store('google')
        ..held = const [StoreOwned(productId: 'mara_pro', orgId: '52000000-0000-0000-0000-0000000000a1', token: 'tok-elim')];
      final w = StoreWatcher(
        billing: store,
        verify: (_) async => throw const StoreVerifyRefused('Achat de test refusé', 'sandbox'),
      )..start();
      addTearDown(w.dispose);
      await _panel(tester, store, watcher: w);
      // For this business and not yet read: restore it.
      expect(find.byKey(const Key('store-owned-here')), findsOneWidget);
      expect(find.byKey(const Key('store-buy-month')), findsNothing);
      store.controller.add(const [
        StorePurchase(status: StorePurchaseStatus.restored, productId: 'mara_pro', token: 'tok-elim',
            orgId: '52000000-0000-0000-0000-0000000000a1', needsCompletion: true),
      ]);
      await tester.pump();
      await tester.pump();
      expect(w.refused, contains('tok-elim'));
      expect(find.byKey(const Key('store-owned-elsewhere')), findsOneWidget);
      expect(find.byKey(const Key('store-owned-here')), findsNothing);
      expect(find.textContaining('Achat de test refusé'), findsOneWidget, reason: 'its own refusal, on its own page');
    });

    testWidgets('another business\'s refusal never shows on this business\'s page; it does on its own', (tester) async {
      final store = _Store('google');
      final w = StoreWatcher(
        billing: store,
        verify: (_) async => throw const StoreVerifyRefused('Achat de test refusé', 'sandbox'),
      )..start();
      addTearDown(w.dispose);
      // The watcher re-verified ELIM SHOP's purchase before any page opened.
      store.controller.add(const [
        StorePurchase(status: StorePurchaseStatus.purchased, productId: 'mara_pro', token: 'tok-elim',
            orgId: '52000000-0000-0000-0000-0000000000a1', needsCompletion: true),
      ]);
      await tester.pump();
      expect(w.notice.value?.orgId, _shop.id);
      await _panel(tester, store, org: _farm, watcher: w);
      expect(find.byKey(const Key('store-message')), findsNothing, reason: 'the farm\'s page: not the shop\'s refusal');
      expect(find.textContaining('Achat de test refusé'), findsNothing);
      await _panel(tester, store, org: _shop, watcher: w);
      expect(find.textContaining('Achat de test refusé'), findsOneWidget, reason: 'the shop\'s own page says it');
    });

    testWidgets('nothing held: the two products, as before', (tester) async {
      await _panel(tester, _Store('google'));
      expect(find.byKey(const Key('store-buy-month')), findsOneWidget);
      expect(find.byKey(const Key('store-owned-elsewhere')), findsNothing);
    });
  });

  group('5. the business\'s bar on the first frame', () {
    late LocalDb db;
    late SupabaseClient client;
    late SessionController session;

    setUp(() async {
      BusinessNav.forgetKnown();
      db = await LocalDb.open(path: inMemoryDatabasePath);
      client = SupabaseClient('https://example.supabase.co', 'sb_publishable_test');
      session = SessionController(
        db: db,
        auth: AuthRepository(null),
        admin: AdminRepository(null),
        accounting: AccountingRepository(null),
      );
    });

    tearDown(() async {
      session.dispose();
      await client.dispose();
      await db.close();
    });

    List<String> labels(WidgetTester tester) => tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => d.label)
        .toList();

    for (final (org, first, settled) in [
      (_shop, ['Vente', 'Articles', 'Commandes', 'Factures', 'Plus'], ['Vente', 'Articles', 'Commandes', 'Factures', 'Plus']),
      (_farm, ['Accueil', 'Stock', 'Bandes', 'Factures', 'Plus'], ['Accueil', 'Stock', 'Bandes', 'Factures', 'Plus']),
      (_assoc, ['Accueil', 'Historique', 'Rapports', 'Factures', 'Plus'], ['Accueil', 'Factures', 'Plus']),
    ]) {
      testWidgets('${org.profile}: there on the first frame, and the page does not move', (tester) async {
        await _phone(tester);
        Widget home() => switch (org.profile) {
              'retail' => StoreHomeScreen(org: org, retail: _Shop(client), invoicing: InvoicingRepository(client)),
              'farm' => FarmHomeScreen(db: db, org: org, invoicing: InvoicingRepository(client)),
              _ => ChurchHomeScreen(
                  db: db, orgId: org.id, orgName: org.name, org: org, invoicing: InvoicingRepository(client)),
            };
        await tester.pumpWidget(_app(router: _business(home, org, session)));
        // The very first frame.
        expect(find.byKey(const Key('business-bar')), findsOneWidget);
        expect(labels(tester), first);
        final page = tester.getRect(find.byType(Scaffold).first);
        expect(page.bottom, lessThan(844), reason: 'the page already stands above the bar');

        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('business-bar')), findsOneWidget);
        expect(labels(tester), settled, reason: 'the home\'s own places');
        expect(tester.getRect(find.byType(Scaffold).first).bottom, page.bottom, reason: 'no layout jump');
      });
    }

    testWidgets('a place of the first frame opens its page', (tester) async {
      await _phone(tester);
      // The bar the home has not said yet: a home that never says it.
      final router = _business(() => const Scaffold(body: Text('Accueil lent')), _shop, session);
      await tester.pumpWidget(_app(router: router));
      expect(labels(tester), ['Vente', 'Articles', 'Commandes', 'Factures', 'Plus']);
      await tester.tap(find.text('Articles'));
      await tester.pumpAndSettle();
      expect(find.text('Page produits'), findsOneWidget);
    });

    testWidgets('the second time, the places the home said last', (tester) async {
      await _phone(tester);
      final router = _business(
          () => StoreHomeScreen(org: _shop, retail: _Shop(client), invoicing: InvoicingRepository(client)), _shop, session);
      await tester.pumpWidget(_app(router: router));
      await tester.pumpAndSettle();
      expect(BusinessNav.lastKnown(_shop.id, 'fr'), isNotNull);
      expect(BusinessNav.lastKnown(_shop.id, 'en'), isNull, reason: 'never drawn in another language');
      // Open again, with a home that has not said them yet.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(router: _business(() => const Scaffold(body: Text('…')), _shop, session)));
      expect(labels(tester), ['Vente', 'Articles', 'Commandes', 'Factures', 'Plus']);
    });

    testWidgets('no session (a frame alone): the bar waits for the home, as before', (tester) async {
      await _phone(tester);
      final cover = BusinessCover();
      final router = GoRouter(initialLocation: '/o/x', routes: [
        ShellRoute(
          observers: [cover],
          builder: (context, state, child) =>
              BusinessFrame(org: _shop, location: state.uri.path, cover: cover, child: child),
          routes: [GoRoute(path: '/o/:orgId', builder: (_, _) => const BusinessPage(child: Scaffold(body: Text('Mise en route'))))],
        ),
      ]);
      await tester.pumpWidget(_app(router: router));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
    });
  });
}
