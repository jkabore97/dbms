// Batch 133: the UI audit's fixes, kept (UI_AUDIT B-1, O-1, AU-1, AU-2,
// C-1 / A-2, and S-1, V-1, K-1 where they can be pumped alone).
//
//   * B-1: the business's bar keeps its full height on a phone with a notch
//     or a Dynamic Island (top safe area 59) — for a shop, a farm and an
//     association — and on Android (24); its labels stay above the home
//     indicator;
//   * O-1: the « Utiliser Mara sans connexion ? » sheet scrolls, and « Oui »
//     and « Plus tard » are on screen on an iPhone SE at 1.3 and at 2.0;
//   * AU-1: « Continuer avec Apple » on one line, as tall as Google, above
//     it; Google's words whole — iPhone SE at 1.3, French and English;
//   * AU-2: on the PIN screen every key and « Se reconnecter » are on
//     screen without scrolling, iPhone SE at 1.3 and 375 × 667 at 2.0;
//   * C-1 / A-2: an amount says its currency once (« 7 000 FCFA », never
//     « 7 000 FCFA XOF ») — the carnet, and no screen appends it again.

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/pin_codec.dart';
import 'package:kaj_app/core/credit/credit_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/nav/business_cover.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/offline/offline_prep.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/auth/login_screen.dart';
import 'package:kaj_app/features/auth/pin_screen.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/credit/credit_book_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/home/business_frame.dart';
import 'package:kaj_app/features/home/home_nav.dart' show BusinessNav;
import 'package:kaj_app/features/offline/offline_sheet.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// Real letters for the widths that matter (AU-1): flutter_test draws text
/// in a font a full em wide per letter, which would wrap any label. The
/// SDK's own Roboto (bin/cache/artifacts/material_fonts, next to the
/// flutter_tester running this) stands in for Roboto and for Apple's
/// system face, whose widths are close. False when it cannot be found.
Future<bool> _realFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6 && !Directory('${dir.path}/material_fonts').existsSync(); i++) {
    dir = dir.parent;
  }
  final fonts = Directory('${dir.path}/material_fonts');
  if (!fonts.existsSync()) return false;
  ByteData bytes(String name) =>
      ByteData.view(File('${fonts.path}/$name').readAsBytesSync().buffer);
  for (final family in const ['Roboto', '.SF Pro Text', 'CupertinoSystemText', 'CupertinoSystemDisplay', '.AppleSystemUIFont']) {
    final loader = FontLoader(family);
    for (final f in const ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
      if (File('${fonts.path}/$f').existsSync()) loader.addFont(Future.value(bytes(f)));
    }
    await loader.load();
  }
  return true;
}

var _fonts = false;

const _shop = OrgSummary(id: '13300000-0000-0000-0000-0000000000a1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);
const _farm = OrgSummary(id: '13300000-0000-0000-0000-0000000000a2', name: 'Ferme Wend', profile: 'farm', roles: ['owner']);
const _assoc = OrgSummary(id: '13300000-0000-0000-0000-0000000000a3', name: 'Entraide', profile: 'association', roles: ['owner']);

/// A phone: its size, its safe areas, its text size, its platform.
Future<void> _phone(WidgetTester tester,
    {Size size = const Size(390, 844),
    EdgeInsets pad = const EdgeInsets.only(top: 59, bottom: 34),
    double scale = 1.0,
    TargetPlatform platform = TargetPlatform.iOS}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = FakeViewPadding(top: pad.top, bottom: pad.bottom);
  tester.view.viewPadding = FakeViewPadding(top: pad.top, bottom: pad.bottom);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Widget _app({GoRouter? router, Widget? home, Locale locale = const Locale('fr')}) => router != null
    ? MaterialApp.router(
        locale: locale,
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        routerConfig: router,
      )
    : MaterialApp(
        locale: locale,
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: home,
      );

/// Fully inside the screen's safe area.
void _onScreen(WidgetTester tester, Finder f, Size size, EdgeInsets pad, String what) {
  final r = tester.getRect(f);
  expect(r.top, greaterThanOrEqualTo(pad.top - 0.5), reason: '$what under the top: $r');
  expect(r.bottom, lessThanOrEqualTo(size.height - pad.bottom + 0.5), reason: '$what below the fold: $r');
}

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

class _Server extends AuthRepository {
  _Server() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<bool> googleAvailable() async => true;
  @override
  Future<bool> appleAvailable() async => true;
}

class _Credit extends CreditRepository {
  _Credit() : super(null);
  @override
  Future<List<DebtorRow>> debtors(String orgId) async => const [
        DebtorRow(customerId: 'c1', name: 'Awa', totalOwed: 5000),
        DebtorRow(customerId: 'c2', name: 'Issa', totalOwed: 2000),
      ];
  @override
  Future<List<DebtDate>> dueDates(String orgId) async => const [];
}

class _Retail extends RetailRepository {
  _Retail() : super(null);
  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [];
  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {};
}

void main() {
  // A failed expectation leaves the platform set: put back for the next.
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
    _fonts = await _realFonts();
  });

  group('B-1: the business\'s bar is whole under a notch', () {
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

    GoRouter business(Widget Function() home, OrgSummary org) {
      final cover = BusinessCover();
      return GoRouter(initialLocation: '/o/${org.id}', routes: [
        ShellRoute(
          observers: [cover],
          builder: (context, state, child) => BusinessFrame(
              org: org, location: state.uri.path, cover: cover, session: session, child: child),
          routes: [
            GoRoute(path: '/o/:orgId', builder: (_, _) => BusinessPage(child: home())),
          ],
        ),
      ]);
    }

    for (final (platform, pad) in [
      (TargetPlatform.iOS, const EdgeInsets.only(top: 59, bottom: 34)),
      (TargetPlatform.android, const EdgeInsets.only(top: 24, bottom: 16)),
    ]) {
      for (final org in [_shop, _farm, _assoc]) {
        testWidgets('${platform.name}, ${org.profile}: every destination as tall as the bar, labels above the home band',
            (tester) async {
          const size = Size(390, 844);
          await _phone(tester, size: size, pad: pad, platform: platform);
          Widget home() => switch (org.profile) {
                'retail' => StoreHomeScreen(org: org, retail: _Shop(client), invoicing: InvoicingRepository(client)),
                'farm' => FarmHomeScreen(db: db, org: org, invoicing: InvoicingRepository(client)),
                _ => ChurchHomeScreen(
                    db: db, orgId: org.id, orgName: org.name, org: org, invoicing: InvoicingRepository(client)),
              };
          await tester.pumpWidget(_app(router: business(home, org)));
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
            await tester.pump();
          }
          final bar = find.byKey(const Key('business-bar'));
          expect(bar, findsOneWidget);
          final barRect = tester.getRect(bar);
          expect(barRect.height, 80 + pad.bottom, reason: 'the bar: 80 and the home band');
          final destinations = find.byType(NavigationDestination);
          expect(destinations, findsWidgets);
          for (final d in destinations.evaluate()) {
            final r = tester.getRect(find.byWidget(d.widget));
            // Before: 21 px on an iPhone (the top's 59 taken off the bar too).
            expect(r.height, closeTo(80, 0.5), reason: 'a destination is ${r.height} px tall');
            expect(r.width * r.height, greaterThan(48 * 48), reason: 'a full tap target');
            expect(r.bottom, lessThanOrEqualTo(size.height - pad.bottom + 0.5),
                reason: 'inside the home indicator band');
          }
          for (final label in tester.widgetList<NavigationDestination>(destinations).map((d) => d.label)) {
            final text = find.descendant(of: bar, matching: find.text(label));
            if (text.evaluate().isEmpty) continue;
            expect(tester.getRect(text.first).bottom, lessThanOrEqualTo(size.height - pad.bottom + 0.5),
                reason: '« $label » under the home indicator');
          }
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }
  });

  group('O-1: the offline sheet scrolls, its buttons always in reach', () {
    for (final (size, scale) in [(const Size(320, 568), 1.3), (const Size(375, 667), 2.0), (const Size(320, 568), 2.0)]) {
      testWidgets('iPhone ${size.width.toInt()}×${size.height.toInt()} at $scale', (tester) async {
        const pad = EdgeInsets.only(top: 59, bottom: 34);
        await _phone(tester, size: size, pad: pad, scale: scale);
        late LocalDb db;
        await tester.runAsync(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
        addTearDown(db.close);
        final prep = OfflinePrep(db: db);
        await tester.pumpWidget(_app(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => OfflineSheet.open(context, org: _shop, prep: prep),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'no overflow');
        expect(find.byKey(const Key('offline-scroll')), findsOneWidget);
        for (final k in ['offline-yes', 'offline-later']) {
          final f = find.byKey(Key(k));
          expect(f.hitTestable(), findsOneWidget, reason: '$k reachable');
          _onScreen(tester, f, size, pad, k);
        }
        // « Oui » works from there: the download button, also on screen.
        await tester.tap(find.byKey(const Key('offline-yes')));
        await tester.pumpAndSettle();
        _onScreen(tester, find.byKey(const Key('offline-download')), size, pad, 'offline-download');
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  group('AU-1: Apple and Google whole on an iPhone SE at 1.3', () {
    for (final locale in const [Locale('fr'), Locale('en')]) {
      testWidgets('${locale.languageCode}: Apple on one line, above Google, as tall; Google\'s words whole',
          (tester) async {
        const size = Size(320, 568);
        await _phone(tester, size: size, scale: 1.3);
        await tester.pumpWidget(_app(
          locale: locale,
          home: LoginScreen(
            auth: _Server(),
            onSignedIn: (_) async {},
            onGoogle: () async {},
            onApple: () async {},
          ),
        ));
        await tester.pumpAndSettle();
        final apple = find.byKey(const Key('apple-sign-in'));
        final google = find.byKey(const Key('google-sign-in'));
        // The screen scrolls: both buttons brought into view.
        await tester.ensureVisible(find.byKey(const Key('google-sign-in'), skipOffstage: false));
        await tester.pumpAndSettle();
        expect(apple, findsOneWidget);
        expect(google, findsOneWidget);
        final a = tester.getRect(apple), g = tester.getRect(google);
        expect(a.top, lessThan(g.top), reason: 'Apple above Google (App Review 4.8)');
        expect(a.height, g.height, reason: 'as tall');
        expect(a.width, closeTo(g.width, 0.5), reason: 'as wide');
        // The label is drawn unscaled (Apple's 43 % of the height).
        final appleScaler = MediaQuery.textScalerOf(tester.element(find.descendant(of: apple, matching: find.byType(Text))));
        expect(appleScaler.scale(10), 10, reason: 'Apple\'s label follows its height, not the text size');
        if (!_fonts) {
          markTestSkipped('the SDK\'s Roboto was not found: widths not measured');
          return;
        }
        final appleWords = locale.languageCode == 'fr' ? 'Continuer avec Apple' : 'Continue with Apple';
        final appleText = tester.renderObject<RenderParagraph>(
            find.descendant(of: apple, matching: find.text(appleWords)));
        expect(appleText.didExceedMaxLines, isFalse);
        final lineHeight = appleText.getFullHeightForCaret(const TextPosition(offset: 0));
        expect(appleText.size.height, lessThan(lineHeight * 1.5), reason: 'one line, not two');
        expect(appleText.size.height, lessThanOrEqualTo(a.height), reason: 'inside its button');
        final googleText = tester.renderObject<RenderParagraph>(find.byKey(const Key('google-sign-in-label')));
        expect(googleText.didExceedMaxLines, isFalse, reason: 'never « Continuer avec … »');
        expect(googleText.text.toPlainText(), isNot(contains('…')));
        // Apple at least as prominent: its words drawn at least as large.
        double drawn(RenderParagraph p) =>
            MatrixUtils.transformRect(p.getTransformTo(null), Offset.zero & p.size).height;
        expect(drawn(appleText), greaterThanOrEqualTo(drawn(googleText) - 0.5));
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  group('AU-2: the whole keypad on screen, no scroll', () {
    for (final (size, scale) in [(const Size(320, 568), 1.3), (const Size(375, 667), 2.0), (const Size(320, 568), 1.0)]) {
      testWidgets('iPhone ${size.width.toInt()}×${size.height.toInt()} at $scale: 0–9, erase and « Se reconnecter »',
          (tester) async {
        const pad = EdgeInsets.only(top: 59, bottom: 34);
        await _phone(tester, size: size, pad: pad, scale: scale);
        final salt = PinCodec.newSalt();
        var out = 0;
        await tester.pumpWidget(_app(
          home: PinScreen(
            purpose: PinPurpose.unlock,
            identity: LocalIdentity(
                userId: 'u1', displayName: 'Awa Ouédraogo', pinSalt: salt, pinHash: PinCodec.hash('2580', salt)),
            onPinAccepted: (_) async {},
            onSignOut: () async => out++,
          ),
        ));
        await tester.pumpAndSettle();
        final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
        expect(scroll.position.pixels, 0);
        for (final d in '0123456789'.split('')) {
          _onScreen(tester, find.widgetWithText(TextButton, d), size, pad, 'key $d');
        }
        _onScreen(tester, find.byTooltip('Effacer'), size, pad, 'erase');
        final signOut = find.byKey(const Key('pin-sign-out'));
        _onScreen(tester, signOut, size, pad, '« Se reconnecter »');
        expect(find.text('Se reconnecter'), findsOneWidget);
        await tester.tap(signOut);
        await tester.pump();
        expect(out, 1);
        // Keys are still real targets.
        expect(tester.getSize(find.widgetWithText(TextButton, '5')).height, greaterThanOrEqualTo(44));
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  group('C-1 / A-2: the currency once', () {
    testWidgets('the carnet: « Total dû : 7 000 FCFA », never « FCFA XOF »', (tester) async {
      await _phone(tester, size: const Size(390, 1200), pad: EdgeInsets.zero);
      await tester.pumpWidget(_app(home: CreditBookScreen(org: _shop, credit: _Credit(), retail: _Retail())));
      await tester.pumpAndSettle();
      final total = find.textContaining('Total dû');
      expect(total, findsOneWidget);
      final text = tester.widget<Text>(total).data!;
      expect(text, contains('FCFA'));
      expect('FCFA'.allMatches(text).length, 1, reason: text);
      expect(text, isNot(contains('XOF')));
      expect(find.textContaining('FCFA XOF'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    test('no screen writes the currency again after a formatted amount', () {
      // moneyFormat(...).format(x) already ends in « FCFA » (or the code):
      // « ${money.format(x)} ${org.currency} » said it twice.
      final twice = RegExp(r"format\([^)]*\)\}\s*'?\s*\n?\s*'?\s*\$\{[\w.!?]*[cC]urrency\}");
      final found = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        for (final m in twice.allMatches(src)) {
          found.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(found, isEmpty);
    });
  });
}
