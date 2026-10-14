// Batch 144: « Prices by area for everyone's own business » — a business's
// money follows where it is, by default, everywhere; for a shop, a farm and
// an association alike, in French and in English.
//
//   1. currency defaults at creation: Burkina XOF, Cameroun XAF, France
//      EUR, the United States USD, Brazil BRL, Nigeria NGN, Ghana GHS,
//      Morocco MAD, Canada CAD, the United Kingdom GBP, Japan JPY… — every
//      country of the phone list named, never XOF by accident (the São
//      Paulo association that read « XOF — Franc CFA (UEMOA) »);
//   2. formatting with each money's own decimals (XOF, XAF, JPY none; EUR,
//      USD, BRL two; the three-decimal dinars two, as the books keep), names in French and English;
//   3. « Créer mon activité »: Brazil → BRL, France → EUR, still changeable,
//      and what is sent;
//   4. the vitrine in EUR, the till in USD, an invoice in BRL, a farm's and
//      an association's money screens in BRL and USD — no « FCFA » and no
//      « F » anywhere;
//   5. the street: each card's menu board in its shop's money; the basket
//      is one vitrine's — in its money, never with another's articles;
//   6. the settings keep a business's money whatever it is (a list of six
//      read a business in reais as XOF, and saved it so), the delivery
//      prices in it;
//   7. 320 px with text × 1.3, French and English: nothing overflows;
//   8. the supervision's: XAF as « FCFA », amounts typed in each money's
//      decimals (no centimes of a franc), the platform admin's picker, the
//      app and the server writing an amount alike, totals per money.
//
// B144_SHOTS=<dir> also writes the screenshots (390 px and 320 px at text
// × 1.3, French and English).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/association/books_start.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/features/admin/create_business_screen.dart';
import 'package:kaj_app/features/admin/vitrine_plus_card.dart';
import 'package:kaj_app/features/courier/courier_screen.dart' show earningsByCurrency;
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/whatsapp_phone.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/format/currencies.dart';
import 'package:kaj_app/core/format/money.dart';
import 'package:kaj_app/core/invoicing/models.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/onboarding/business_creation.dart';
import 'package:kaj_app/core/phone/country_codes.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/admin/org_settings_screen.dart';
import 'package:kaj_app/features/church/entry_controls.dart';
import 'package:kaj_app/features/church/record_transfer_sheet.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/invoicing/invoice_paper.dart';
import 'package:kaj_app/features/money/expense_flow.dart';
import 'package:kaj_app/features/money/income_flow.dart';
import 'package:kaj_app/features/retail/sale_flow.dart';
import 'package:kaj_app/features/setup/create_my_business_screen.dart';
import 'package:kaj_app/features/storefront/directory_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------


/// The platform admin's « Nouvelle entreprise » server: what it creates.
class _CreateAdmin extends AdminRepository {
  _CreateAdmin() : super(null);
  String? currency;

  @override
  Future<String> createOrg({
    required String name,
    required String slug,
    required String profile,
    required String currency,
  }) async {
    this.currency = currency;
    return 'o-new';
  }
}

/// « Créer mon activité »'s server: what it is asked to create.
class _Api implements BusinessCreation {
  Map<String, Object?>? sent;

  @override
  Future<BusinessStart> start() async => const BusinessStart();

  @override
  Future<AddressCheck> checkAddress(String slug) async => AddressCheck(slug: slug);

  @override
  Future<String> create({
    required String profile,
    required String name,
    required String slug,
    required String activity,
    required String about,
    required String city,
    required String area,
    required String phone,
    required String currency,
    Map<String, Object?>? answers,
  }) async {
    sent = {'profile': profile, 'name': name, 'currency': currency, 'phone': phone};
    return 'org-144';
  }
}

class _Drafts implements DraftStore {
  _Drafts(this.kept);

  BusinessDraft? kept;

  @override
  Future<BusinessDraft?> read() async =>
      kept == null ? null : BusinessDraft.fromJson(Map<String, dynamic>.from(kept!.toJson()));

  @override
  Future<void> write(BusinessDraft? draft) async => kept = draft;
}

class _WhatsApp implements WhatsAppPhone {
  @override
  Future<OrderPhoneGate?> gate() async => null;
  @override
  Future<void> sendCode(String e164) async {}
  @override
  Future<void> confirm(String e164, String code) async {}
}

/// The street: a Paris shop in euros, a São Paulo farm in reais, a New York
/// association in dollars, an Ouagadougou shop in francs CFA.
class _Street extends StorefrontRepository {
  _Street() : super(null);

  static const shops = {
    'maison-elegance': PublicShop(
        orgId: 'o-paris', name: 'Maison Élégance', slug: 'maison-elegance',
        profile: 'retail', phone: '+33612345678', address: 'Paris', currency: 'EUR'),
    'ferme-soleil-levant': PublicShop(
        orgId: 'o-sp', name: 'Ferme Soleil Levant', slug: 'ferme-soleil-levant',
        profile: 'farm', phone: '+5511912345678', address: 'São Paulo', currency: 'BRL'),
    'fondation-espoir': PublicShop(
        orgId: 'o-ny', name: 'Fondation Espoir', slug: 'fondation-espoir',
        profile: 'association', phone: '+12125550100', address: 'New York', currency: 'USD'),
    'atelier-lumiere': PublicShop(
        orgId: 'o-ouaga', name: 'Atelier Lumière', slug: 'atelier-lumiere',
        profile: 'retail', phone: '+22670000000', address: 'Ouagadougou', currency: 'XOF'),
  };

  static const goods = {
    'maison-elegance': [
      PublicItem(id: 'p-foulard', name: 'Foulard en soie', price: 12.5, inStock: true),
      PublicItem(id: 'p-sac', name: 'Sac en cuir', price: 89.9, inStock: true),
    ],
    'ferme-soleil-levant': [
      PublicItem(id: 'p-oeufs', name: 'Œufs frais', price: 18.9, inStock: true, unit: 'plateau'),
    ],
    'fondation-espoir': [
      PublicItem(id: 'p-livre', name: 'Livre solidaire', price: 9.99, inStock: true),
    ],
    'atelier-lumiere': [
      PublicItem(id: 'p-savon', name: 'Savon karité', price: 500, inStock: true),
    ],
  };

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => shops[slug];

  @override
  Future<List<PublicItem>> items(String slug) async => goods[slug] ?? const [];

  @override
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) async => [
        for (final s in shops.values)
          DirectoryEntry(orgId: s.orgId, name: s.name, slug: s.slug, profile: s.profile),
      ];

  @override
  Future<List<FeaturedItem>> featured({double? lat, double? lng}) async => const [];

  @override
  Future<Map<String, List<ShopPreview>>> previews(List<String> slugs) async => {
        for (final s in shops.values)
          s.slug: [
            for (final i in goods[s.slug]!)
              ShopPreview(
                  slug: s.slug, productId: i.id, name: i.name, price: i.price, currency: s.currency),
          ],
      };
}

class _Books implements BooksStartApi {
  @override
  Future<BooksStart?> booksStart(String orgId) async => BooksStart.fromJson(const {
        'association': true,
        'opening_set': true,
        'movements': 3,
        'can_set': true,
        'dismissed': true,
        'contribution': {'amount': 25.5, 'period': 'month'},
      });
  @override
  Future<void> setOpeningBalance(String orgId, double amount, {String? clientUuid}) async {}
  @override
  Future<void> setContributionDefault(String orgId, double? amount, ContributionPeriod period) async {}
  @override
  Future<void> dismissBooksStart(String orgId) async {}
}

/// Réglages of a São Paulo farm in reais, its delivery priced in reais.
class _Settings extends AdminRepository {
  _Settings() : super(null);

  @override
  Future<Map<String, dynamic>> fetchOrg(String orgId) async => {
        'id': orgId,
        'name': 'Ferme Soleil Levant',
        'slug': 'ferme-soleil-levant',
        'profile': 'farm',
        'default_currency': 'BRL',
      };

  @override
  Future<String?> waveMerchant(String orgId) async => null;

  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) async => const [];

  @override
  Future<({bool enabled, String? blurb, double? lat, double? lng, double? deliveryBase, double? deliveryPerKm})>
      storefront(String orgId) async => (
            enabled: true,
            blurb: null as String?,
            lat: -23.55,
            lng: -46.63,
            deliveryBase: 5.0,
            deliveryPerKm: 1.5,
          );

  @override
  Future<double?> deliveryReach(String orgId) async => null;

  @override
  Future<double?> deliveryIncludedKm(String orgId) async => null;
}

class _Till extends RetailRepository {
  _Till() : super(null);

  final calls = <Map<String, Object?>>[];

  @override
  Future<String?> waveMerchant(String orgId) async => null;

  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) async => const [];

  @override
  Future<Map<String, double>> freshStock(String orgId, List<String> ids) async => const {};

  @override
  Future<String> recordSale({
    required String orgId,
    required List<SaleLineDraft> lines,
    String method = 'cash',
    String? note,
    String? clientUuid,
    String? deviceId,
    String? customerName,
    String? customerPhone,
  }) async {
    calls.add({'lines': [for (final l in lines) l.toJson()]});
    return 'sale-1';
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The amount as a person reads it: every kind of space one plain space.
String _plain(String s) => s.replaceAll(RegExp(r'[  \s]+'), ' ');

Widget _shot(Widget child) => RepaintBoundary(key: const Key('shot'), child: child);

Widget _app(Widget home, {String lang = 'fr'}) => MaterialApp(
      locale: Locale(lang),
      theme: kajTheme(kajPalette),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => _shot(child!),
      home: home,
    );

Future<void> _size(WidgetTester tester, double w, double h, {double text = 1}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 800));
}

/// Every string drawn on screen, plain-spaced.
List<String> _texts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        _plain(t.data ?? t.textSpan?.toPlainText() ?? ''),
      for (final t in tester.widgetList<RichText>(find.byType(RichText)))
        _plain(t.text.toPlainText()),
    ];

/// No franc CFA anywhere on a screen of a business in another money.
void _noFranc(WidgetTester tester, {String? where}) {
  final franc = RegExp(r'\bFCFA\b|\bXOF\b|\d F\b|\bF CFA\b');
  final hits = _texts(tester).where(franc.hasMatch).toList();
  expect(hits, isEmpty, reason: 'a franc CFA on ${where ?? 'the screen'}: $hits');
}

BusinessDraft _draftAtPhone(String iso, {String profile = 'association', String? currency}) => BusinessDraft(
      step: 4,
      profile: profile,
      name: 'Fondation Espoir',
      slug: 'fondation-espoir',
      activity: profile == 'association' ? 'culturelle' : 'alimentation',
      about: 'Entraide et soutien scolaire',
      city: iso == 'BR' ? 'São Paulo' : 'Paris',
      area: iso == 'BR' ? 'Vila Mariana' : 'Le Marais',
      phoneIso: iso,
      phone: iso == 'BR' ? '11912345678' : '612345678',
      currency: currency,
    );

InvoiceDocument _invoiceBrl() => InvoiceDocument(
      id: 'inv-1',
      number: 'F-2026-0042',
      issuedOn: DateTime(2026, 10, 14),
      dueOn: DateTime(2026, 10, 28),
      total: 1312.4,
      paid: 300,
      outstanding: 1012.4,
      customerName: 'Atelier Lumière',
      customerAddress: 'São Paulo',
      orgName: 'Ferme Soleil Levant',
      orgAddress: 'Estrada do Campo, São Paulo',
      orgPhone: '+55 11 91234 5678',
      currency: 'BRL',
      lines: const [
        InvoiceLine(description: 'Œufs frais (plateau)', quantity: 40, unitPrice: 18.9),
        InvoiceLine(description: 'Poulets fermiers', quantity: 12, unitPrice: 46.37),
      ],
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  SessionController session() => SessionController(
        db: db,
        auth: AuthRepository(null),
        admin: AdminRepository(null),
        accounting: AccountingRepository(null),
      );

  // -------------------------------------------------------------------------
  group('1. the currency a business starts with', () {
    test('the owner\'s list, and a few more', () {
      const want = {
        'BF': 'XOF', 'CI': 'XOF', 'SN': 'XOF', 'ML': 'XOF', 'NE': 'XOF', 'TG': 'XOF', 'BJ': 'XOF',
        'GW': 'XOF',
        'CM': 'XAF', 'GA': 'XAF', 'TD': 'XAF', 'CF': 'XAF', 'CG': 'XAF', 'GQ': 'XAF',
        'FR': 'EUR', 'BE': 'EUR', 'DE': 'EUR', 'ES': 'EUR', 'IT': 'EUR', 'PT': 'EUR', 'NL': 'EUR',
        'LU': 'EUR', 'IE': 'EUR', 'AT': 'EUR', 'FI': 'EUR', 'GR': 'EUR', 'CY': 'EUR',
        'US': 'USD', 'BR': 'BRL', 'NG': 'NGN', 'GH': 'GHS', 'MA': 'MAD', 'CA': 'CAD', 'GB': 'GBP',
        'GN': 'GNF', 'JP': 'JPY', 'CN': 'CNY', 'ZA': 'ZAR', 'KE': 'KES', 'CH': 'CHF', 'IN': 'INR',
        'MX': 'MXN', 'AE': 'AED', 'TN': 'TND', 'DZ': 'DZD', 'EG': 'EGP', 'CD': 'CDF', 'RW': 'RWF',
      };
      for (final e in want.entries) {
        expect(currencyOfCountry(e.key), e.value, reason: e.key);
      }
      expect(currencyOfCountry('br'), 'BRL', reason: 'any case');
    });

    test('every country of the phone list has its money, named in French and English', () {
      for (final c in allCountries) {
        final code = currencyOfCountryOrNull(c.iso);
        expect(code, isNotNull, reason: '${c.iso} ${c.name} has no currency');
        final info = worldCurrencies[code];
        expect(info, isNotNull, reason: '$code (${c.iso}) is not described');
        expect(info!.fr.trim(), isNotEmpty);
        expect(info.en.trim(), isNotEmpty);
        expect(RegExp(r'^[A-Z]{3}$').hasMatch(info.code), isTrue);
      }
    });

    test('never the franc CFA by accident: Brazil was XOF, an unknown country is the dollar', () {
      expect(currencyOfCountry('BR'), isNot('XOF'));
      expect(currencyOfCountry('ZZ'), 'USD');
      expect(currencyOfCountryOrNull('ZZ'), isNull);
      // Outside the two franc zones nothing starts in francs CFA.
      const franc = {'BF', 'CI', 'SN', 'ML', 'NE', 'TG', 'BJ', 'GW'};
      for (final c in allCountries) {
        if (!franc.contains(c.iso)) expect(currencyOfCountry(c.iso), isNot('XOF'), reason: c.iso);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('2. each money with its own decimals', () {
    test('XOF, XAF, JPY none; EUR, USD, BRL two; the three-decimal dinars two too', () {
      expect(_plain(moneyFormat('XOF').format(1500.7)), '1 501 FCFA');
      // XAF reads « FCFA » as XOF does (144's supervision): both are « le franc CFA ».
      expect(_plain(moneyFormat('XAF').format(25000)), '25 000 FCFA');
      expect(_plain(moneyFormat('JPY').format(1500)), '1 500 JPY');
      expect(_plain(moneyFormat('EUR').format(12.5)), '12,50 EUR');
      expect(_plain(moneyFormat('USD').format(1234.5)), '1 234,50 USD');
      expect(_plain(moneyFormat('BRL').format(18.9)), '18,90 BRL');
      expect(_plain(moneyFormat('NGN').format(2500)), '2 500,00 NGN');
      // ISO gives the dinar three, the books' columns keep two (144's
      // decision): never a third shown.
      expect(_plain(moneyFormat('TND').format(1.25)), '1,25 TND');
      for (final c in ['TND', 'LYD', 'KWD', 'BHD', 'OMR', 'JOD']) {
        expect(currencyDecimals(c), 2, reason: c);
      }
      expect(currencyDecimals('XOF'), 0);
      expect(currencyDecimals('xaf'), 0);
      expect(currencyDecimals('GNF'), 0);
      expect(currencyDecimals('EUR'), 2);
      expect(currencyDecimals('QQQ'), 2, reason: 'a code not known: two, ISO\'s usual');
    });

    test('a foreign tender keeps its own decimals too', () {
      expect(_plain(foreignMoneyFormat('USD').format(15.384)), '15,38 USD');
      expect(_plain(foreignMoneyFormat('XOF').format(9500)), '9 500 XOF');
    });

    test('names in French and in English', () {
      expect(currencyName('BRL', 'fr'), 'Réal brésilien');
      expect(currencyName('BRL', 'en'), 'Brazilian real');
      expect(currencyName('XOF', 'fr'), 'Franc CFA (UEMOA)');
      expect(currencyName('XOF', 'en'), 'CFA franc (WAEMU)');
      expect(currencyName('EUR', 'en'), 'Euro');
      expect(currencyName('QQQ', 'en'), 'QQQ');
    });

    test('the picker: the business\'s own first, the francs, the euro, the dollar, then by code', () {
      final c = currencyChoices('BRL');
      expect(c.take(5), ['BRL', 'XOF', 'XAF', 'EUR', 'USD']);
      expect(c.toSet().length, c.length, reason: 'no money twice');
      expect(currencyChoices('ZWG').first, 'ZWG', reason: 'a business\'s own, even unknown here');
      expect(knownCurrencies['BRL'], 'Réal brésilien');
    });
  });

  // -------------------------------------------------------------------------
  group('3. « Créer mon activité »: the country\'s money, still changeable', () {
    Future<_Api> pump(WidgetTester tester, BusinessDraft draft, {String lang = 'fr'}) async {
      final api = _Api();
      await tester.pumpWidget(_app(
          CreateMyBusinessScreen(
            key: UniqueKey(),
            api: api,
            drafts: _Drafts(draft),
            whatsApp: _WhatsApp(),
            onCreated: (_) async => true,
          ),
          lang: lang));
      await _settle(tester);
      return api;
    }

    testWidgets('a São Paulo association: BRL — Réal brésilien, never the franc CFA', (tester) async {
      await _size(tester, 390, 1000);
      await pump(tester, _draftAtPhone('BR'));
      expect(find.text('BRL — Réal brésilien'), findsOneWidget);
      expect(find.textContaining('XOF'), findsNothing);
    });

    testWidgets('a Paris shop: EUR — Euro; in English EUR — Euro and BRL — Brazilian real',
        (tester) async {
      await _size(tester, 390, 1000);
      await pump(tester, _draftAtPhone('FR', profile: 'retail'));
      expect(find.text('EUR — Euro'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await pump(tester, _draftAtPhone('BR'), lang: 'en');
      expect(find.text('BRL — Brazilian real'), findsOneWidget);
      expect(find.text('Currency'), findsOneWidget);
    });

    testWidgets('changed by hand, it stays; what is created is in BRL, then USD', (tester) async {
      await _size(tester, 390, 1000);
      // The summary, the country's money: BRL is sent.
      var api = await pump(tester, _draftAtPhone('BR')..step = 5);
      expect(find.textContaining('BRL — Réal brésilien'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-submit')));
      await _settle(tester);
      expect(api.sent?['currency'], 'BRL');
      expect(api.sent?['phone'], '+5511912345678');

      // On the phone screen, the dollar chosen instead.
      await tester.pumpWidget(const SizedBox());
      api = await pump(tester, _draftAtPhone('BR'));
      await tester.tap(find.byKey(const ValueKey('create-currency-BRL')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD — Dollar américain').last);
      await tester.pumpAndSettle();
      expect(find.text('USD — Dollar américain'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-next')));
      await _settle(tester);
      expect(find.textContaining('USD — Dollar américain'), findsOneWidget, reason: 'the summary');
      await tester.tap(find.byKey(const Key('create-submit')));
      await _settle(tester);
      expect(api.sent?['currency'], 'USD');
    });
  });

  // -------------------------------------------------------------------------
  group('4. every money screen in the business\'s money', () {
    Future<void> pumpShop(WidgetTester tester, String slug, {String lang = 'fr'}) async {
      await tester.pumpWidget(_app(
          StorefrontScreen(
            slug: slug,
            storefront: _Street(),
            capture: CaptureRepository(null, db: db),
            session: session(),
          ),
          lang: lang));
      await _settle(tester);
    }

    testWidgets('the vitrine in EUR: the prices, the article, the basket', (tester) async {
      await _size(tester, 390, 1400);
      await pumpShop(tester, 'maison-elegance');
      final texts = _texts(tester);
      expect(texts, contains('12,50 EUR'));
      expect(texts, contains('89,90 EUR'));
      _noFranc(tester, where: 'the Paris vitrine');

      await tester.tap(find.text('Foulard en soie').last);
      await tester.pumpAndSettle();
      expect(_plain(tester.widget<Text>(find.byKey(const Key('item-price'))).data!), '12,50 EUR');
      await tester.tap(find.text('Ajouter au panier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(_texts(tester).any((t) => t.contains('12,50 EUR')), isTrue, reason: 'the basket total');
      _noFranc(tester, where: 'the Paris basket');
    });

    testWidgets('the vitrine of a São Paulo farm in BRL and of a New York association in USD',
        (tester) async {
      await _size(tester, 390, 1400);
      await pumpShop(tester, 'ferme-soleil-levant');
      expect(_texts(tester).any((t) => t.contains('18,90 BRL')), isTrue);
      _noFranc(tester, where: 'the farm\'s vitrine');
      await tester.pumpWidget(const SizedBox());
      await pumpShop(tester, 'fondation-espoir', lang: 'en');
      expect(_texts(tester).any((t) => t.contains('9,99 USD')), isTrue);
      _noFranc(tester, where: 'the association\'s vitrine');
    });

    testWidgets('the till in USD: each price and the total with their cents', (tester) async {
      await _size(tester, 390, 1400);
      final till = _Till();
      await tester.pumpWidget(_app(SaleFlow(
        orgId: 'o-ny',
        orgName: 'Atelier Lumière',
        retail: till,
        store: MemoryFlowStore(),
        currency: 'USD',
        products: const [Product(id: 'p1', name: 'Bougie parfumée', salePrice: 9.99, quantity: 5)],
      )));
      await tester.pumpAndSettle();
      expect(_texts(tester).any((t) => t.contains('9,99 USD')), isTrue, reason: 'the article\'s price');
      await tester.tap(find.byKey(const ValueKey('sale-pick-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('sale-qty-p1')), '2');
      await tester.pumpAndSettle();
      expect(_plain(tester.widget<Text>(find.byKey(const Key('sale-total'))).data!), '19,98 USD');
      _noFranc(tester, where: 'the till');
    });

    testWidgets('a farm\'s sale in BRL: its produce by the tray', (tester) async {
      await _size(tester, 390, 1400);
      await tester.pumpWidget(_app(SaleFlow(
        orgId: 'o-sp',
        retail: _Till(),
        farm: true,
        store: MemoryFlowStore(),
        currency: 'BRL',
        products: const [Product(id: 'e', name: 'Œufs frais', salePrice: 18.9, quantity: 40, unit: 'plateau')],
      )));
      await tester.pumpAndSettle();
      expect(_texts(tester).any((t) => t.contains('18,90 BRL')), isTrue);
      _noFranc(tester, where: 'the farm\'s till');
    });

    testWidgets('a farm\'s expense in BRL: the amount field says BRL', (tester) async {
      await _size(tester, 390, 1400);
      await tester.pumpWidget(_app(ExpenseFlow(
        db: db,
        orgId: 'o-sp',
        profile: 'farm',
        currency: 'BRL',
        store: MemoryFlowStore(),
      )));
      await _settle(tester);
      // « Pour quoi ? »: the first heading, then the amount.
      final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == 'HeadingTiles');
      await tester.tap(find.descendant(of: tiles, matching: find.byType(InkWell)).first);
      await tester.pumpAndSettle();
      for (var i = 0; i < 3 && find.byKey(const Key('expense-amount')).evaluate().isEmpty; i++) {
        if (find.byKey(const Key('expense-other')).evaluate().isNotEmpty) {
          await tester.enterText(find.byKey(const Key('expense-other')), 'Semences');
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('flow-next')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('expense-amount')), findsOneWidget);
      expect(find.text('BRL'), findsWidgets, reason: 'the amount\'s suffix');
      _noFranc(tester, where: 'the farm\'s expense');
    });

    testWidgets('an association\'s cotisation in USD: the amount and the usual one', (tester) async {
      await _size(tester, 390, 1400);
      await tester.pumpWidget(_app(IncomeFlow(
        db: db,
        orgId: 'o-ny',
        currency: 'USD',
        store: MemoryFlowStore(),
        books: _Books(),
      )));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('flow-option-cotisation')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3 && find.byKey(const Key('income-amount')).evaluate().isEmpty; i++) {
        await tester.tap(find.byKey(const Key('flow-next')));
        await tester.pumpAndSettle();
        final who = find.byKey(const Key('income-who'));
        if (who.evaluate().isNotEmpty) {
          await tester.enterText(who, 'Membre fondateur');
          await tester.pumpAndSettle();
        }
      }
      expect(find.byKey(const Key('income-amount')), findsOneWidget);
      expect(find.text('USD'), findsWidgets, reason: 'the amount\'s suffix');
      expect(_plain(tester.widget<Text>(find.byKey(const Key('income-usual'))).data!),
          'Cotisation habituelle : 25,50 USD par mois');
      expect(find.widgetWithText(TextField, '25.5'), findsOneWidget,
          reason: 'the usual amount filled with its cents');
      _noFranc(tester, where: 'the cotisation');
    });

    testWidgets('an association\'s transfer in EUR: the keypad has the comma, the cents are kept',
        (tester) async {
      await _size(tester, 390, 1400);
      await tester.pumpWidget(_app(Scaffold(
          body: SingleChildScrollView(
              child: RecordTransferSheet(db: db, orgId: 'o-paris', currency: 'EUR')))));
      await _settle(tester);
      expect(find.widgetWithText(InkWell, '000'), findsNothing, reason: 'no 000 for a money with cents');
      for (final k in ['1', '2', ',', '5', '0', '7']) {
        await tester.tap(find.widgetWithText(InkWell, k).last);
        await tester.pump();
      }
      expect(_texts(tester), contains('12,50 EUR'), reason: 'two decimals at most');
      _noFranc(tester, where: 'the transfer');
    });

    testWidgets('the franc CFA keeps its 000 key', (tester) async {
      await _size(tester, 390, 1400);
      await tester.pumpWidget(_app(const Scaffold(
          body: AmountKeypad(onDigit: _ignore, onBackspace: _none))));
      expect(find.text('000'), findsOneWidget);
      expect(find.text(','), findsNothing);
    });

    testWidgets('an invoice in BRL: every line, the total and what is left', (tester) async {
      await _size(tester, 390, 1400);
      await tester.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: InvoicePaper(doc: _invoiceBrl())))));
      await _settle(tester);
      final texts = _texts(tester);
      expect(texts.any((t) => t.contains('18,90 BRL')), isTrue, reason: 'a unit price');
      expect(texts.any((t) => t.contains('756,00 BRL')), isTrue, reason: '40 × 18,90');
      expect(texts.any((t) => t.contains('1 312,40 BRL')), isTrue, reason: 'the total');
      expect(texts.any((t) => t.contains('1 012,40 BRL')), isTrue, reason: 'what is left');
      _noFranc(tester, where: 'the invoice');
    });
  });

  // -------------------------------------------------------------------------
  group('5. the street and the basket', () {
    testWidgets('each card\'s menu board in its own shop\'s money', (tester) async {
      await _size(tester, 390, 2400);
      await tester.pumpWidget(_app(DirectoryScreen(
        storefront: _Street(),
        capture: CaptureRepository(null, db: db),
        session: session(),
      )));
      await _settle(tester);
      String price(String id) =>
          _plain(tester.widget<Text>(find.byKey(Key('street-preview-price-$id'))).data!);
      expect(price('p-foulard'), '12,50 EUR');
      expect(price('p-oeufs'), '18,90 BRL');
      expect(price('p-livre'), '9,99 USD');
      expect(price('p-savon'), '500 FCFA');
      expect(tester.takeException(), isNull);
    });

    test('a database before 140 says no money: the card reads the franc CFA as it always did', () {
      final p = ShopPreview.fromRow(const {
        'slug': 'atelier-lumiere', 'product_id': 'p', 'name': 'Savon', 'sale_price': 500,
      });
      expect(p.currency, isNull);
      expect(ShopPreview.fromRow(const {
        'slug': 'maison-elegance', 'product_id': 'p', 'name': 'Foulard', 'sale_price': 12.5,
        'currency': 'EUR',
      }).currency, 'EUR');
    });

    testWidgets('one basket per vitrine: another shop\'s article never joins it', (tester) async {
      await _size(tester, 390, 1400);
      // A basket kept at the Paris shop, and one at the São Paulo farm with
      // a Paris article slipped into it (an older app, a hand-edited pref).
      await tester.runAsync(() async {
        await db.writePref('street_basket_maison-elegance', jsonEncode({'p-foulard': 2}));
        await db.writePref('street_basket_ferme-soleil-levant', jsonEncode({'p-oeufs': 1, 'p-foulard': 3}));
      });
      await tester.pumpWidget(_app(StorefrontScreen(
        slug: 'ferme-soleil-levant',
        storefront: _Street(),
        capture: CaptureRepository(null, db: db),
        session: session(),
      )));
      await _settle(tester);
      final texts = _texts(tester);
      expect(texts.any((t) => t.contains('1 article') || t.contains('1 ×') || t.contains('18,90 BRL')), isTrue);
      expect(texts.any((t) => t.contains('EUR')), isFalse, reason: 'no euro in the farm\'s basket');
      expect(texts.any((t) => t.contains('Foulard')), isFalse, reason: 'no Paris article at the farm');
      // The Paris basket is still Paris's.
      final paris = await tester.runAsync(() => db.readPref('street_basket_maison-elegance'));
      expect(jsonDecode(paris!), {'p-foulard': 2});
    });
  });

  // -------------------------------------------------------------------------
  group('5b. Réglages keep the business\'s money', () {
    testWidgets('a farm in reais reads BRL, not XOF (a list of six used to reset it)', (tester) async {
      await _size(tester, 800, 3200);
      await tester.pumpWidget(_app(OrgSettingsScreen(
          admin: _Settings(), orgId: 'o-sp', plan: 'pro', initialPart: 'identite')));
      await _settle(tester);
      expect(find.text('BRL — Réal brésilien'), findsOneWidget);
      expect(find.textContaining('XOF'), findsNothing);
    });

    testWidgets('its delivery in reais: the fields say BRL, no « 500 + 150 F/km »', (tester) async {
      await _size(tester, 800, 3200);
      await tester.pumpWidget(_app(OrgSettingsScreen(
          admin: _Settings(), orgId: 'o-sp', plan: 'pro', initialPart: 'livraison')));
      await _settle(tester);
      expect(find.text('BRL'), findsNWidgets(2), reason: 'Base and Par km');
      expect(find.textContaining('150 F/km'), findsNothing);
      expect(find.textContaining('le prix de la course est à convenir'), findsOneWidget);
      _noFranc(tester, where: 'the delivery settings');
    });
  });

  // -------------------------------------------------------------------------
  // -------------------------------------------------------------------------
  // The supervision's checks (144): the franc CFA of CEMAC written as the
  // one of UEMOA, amounts typed in each money's decimals, the platform
  // admin's picker, the bells written as the app writes, totals per money.
  group('7. supervision', () {
    test('XAF prints « FCFA » like XOF; the names still tell UEMOA from CEMAC', () {
      expect(currencySymbol('XAF'), 'FCFA');
      expect(currencySymbol('XOF'), 'FCFA');
      expect(currencySymbol('EUR'), 'EUR');
      expect(isFrancCfa('XAF') && isFrancCfa('XOF') && !isFrancCfa('EUR'), isTrue);
      expect(currencyName('XOF', 'fr'), 'Franc CFA (UEMOA)');
      expect(currencyName('XAF', 'fr'), 'Franc CFA (CEMAC)');
      expect(currencyName('XOF', 'en'), 'CFA franc (WAEMU)');
      expect(currencyName('XAF', 'en'), 'CFA franc (CEMAC)');
      expect(rateLabel('EUR', 655.957, 'XAF'), '1 EUR = 655,957 F');
      // A small rate keeps four significant digits.
      expect(_plain(rateLabel('EUR', 0.001524, 'XOF')), '1 EUR = 0,001524 F');
      expect(_plain(rateLabel('USD', 0.5, 'EUR')), '1 USD = 0,5 EUR');
    });

    test('the app and the server write an amount the same way, character for character', () {
      // 140's money_text: a narrow no-break space between thousands, a
      // no-break space before the money (test_batch140.sql pins the same).
      expect(moneyFormat('XOF').format(12000), '12 000 FCFA');
      expect(moneyFormat('XAF').format(12000), '12 000 FCFA');
      expect(moneyFormat('EUR').format(12.5), '12,50 EUR');
      expect(moneyFormat('TND').format(1234567.891), '1 234 567,89 TND');
      expect(moneyFormat('JPY').format(1500), '1 500 JPY');
    });

    test('typed in a money: « 12,50 » and « 12.50 » are 12,5 €; no centimes of a franc', () {
      expect(parseAmount('12,50', currency: 'EUR'), 12.5);
      expect(parseAmount('12.50', currency: 'EUR'), 12.5);
      expect(parseAmount('1 234,50', currency: 'EUR'), 1234.5);
      expect(parseAmount('12,5055', currency: 'EUR'), isNull, reason: 'four decimals in euros');
      expect(parseAmount('12,505', currency: 'EUR'), isNull, reason: 'the comma is the decimal mark in euros');
      expect(parseAmount('12,500', currency: 'EUR'), 12.5, reason: 'never 12 500 in euros');
      expect(parseAmount('12,500', currency: 'KWD'), 12.5);
      expect(parseAmount('1.000,50', currency: 'EUR'), 1000.5);
      expect(parseAmount('1,000.50', currency: 'EUR'), 1000.5);
      expect(parseAmount('1 000', currency: 'EUR'), 1000);
      expect(parseAmount('1.000.000', currency: 'EUR'), 1000000);
      expect(parseAmount('45.000', currency: 'EUR'), 45000, reason: 'thousands written with a dot');
      // 0 decimals: refused, not rounded.
      expect(parseAmount('12,50', currency: 'XOF'), isNull);
      expect(parseAmount('12.5', currency: 'XAF'), isNull);
      expect(parseAmount('12,5', currency: 'JPY'), isNull);
      expect(parseAmount('1 500', currency: 'XOF'), 1500);
      expect(parseAmount('1.500', currency: 'XOF'), 1500);
      expect(parseAmount('45,000', currency: 'XOF'), 45000);
      // The dinars: two decimals, as the books keep.
      expect(parseAmount('1,250', currency: 'TND'), 1.25);
      expect(parseAmount('1,255', currency: 'TND'), isNull);
      // A 0-decimal money: what is saved is rounded to it (18,9 yen → 19).
      expect(roundToCurrency(18.9, 'JPY'), 19);
      expect(roundToCurrency(12.345, 'EUR'), closeTo(12.35, 0.001));
      // Without a money (a quantity), and FlowNumberField.read alike:
      // the same text, the same number everywhere.
      for (final (text, want) in [
        ('45.000', 45000.0), ('1 000', 1000.0), ('1.000,50', 1000.5), ('12,50', 12.5),
        ('2,5', 2.5), ('0.500', 0.5), ('45,000', 45000.0), ('1.5', 1.5),
      ]) {
        expect(parseAmount(text), want, reason: text);
        expect(FlowNumberField.read(TextEditingController(text: text)), want, reason: 'read $text');
      }
      expect(parseAmount('1.2.3'), isNull);
      expect(parseAmount('abc'), isNull);
      expect(parseAmount('1,000,5'), isNull);
      // Why, in words.
      expect(amountProblem('12,50', 'XOF'), 'Pas de centimes en {money}');
      expect(amountProblem('12,5055', 'EUR'), 'Au plus {n} chiffres après la virgule');
      expect(amountProblem('12,50', 'EUR'), isNull);
      expect(amountProblem('', 'XOF'), isNull);
      // Put back in a field in the money's own decimals.
      expect(amountField(12.5, 'EUR'), '12,50');
      expect(amountField(12.6, 'XOF'), '13');
      expect(amountField(1.25, 'TND'), '1,25');
      expect(parseAmount(amountField(12.5, 'EUR'), currency: 'EUR'), 12.5);
    });

    testWidgets('an amount field says when the money has no centimes, in French and English',
        (tester) async {
      for (final lang in ['fr', 'en']) {
        final c = TextEditingController(text: '12,50');
        await tester.pumpWidget(_app(
            Scaffold(body: FlowNumberField(controller: c, currency: 'XOF', suffix: 'FCFA')),
            lang: lang));
        await tester.pump();
        expect(find.text(lang == 'fr' ? 'Pas de centimes en FCFA' : 'No cents in FCFA'), findsOneWidget);
        expect(FlowNumberField.readAmount(c, 'XOF'), isNull);
        await tester.pumpWidget(_app(
            Scaffold(body: FlowNumberField(controller: c, currency: 'EUR', suffix: 'EUR')),
            lang: lang));
        await tester.pump();
        expect(find.textContaining(lang == 'fr' ? 'centimes' : 'cents'), findsNothing);
        expect(FlowNumberField.readAmount(c, 'EUR'), 12.5);
        c.text = '12.50';
        expect(FlowNumberField.readAmount(c, 'EUR'), 12.5);
        c.text = '1,255';
        expect(FlowNumberField.readAmount(c, 'TND'), isNull, reason: 'two decimals, as the books keep');
      }
    });

    testWidgets('« Nouvelle entreprise »: the same picker, the country\'s money first, sent as chosen',
        (tester) async {
      await _size(tester, 390, 1400);
      final admin = _CreateAdmin();
      await tester.pumpWidget(_app(CreateBusinessScreen(admin: admin)));
      await _settle(tester);
      // No signed-in phone here: the device's region (the test's) decides.
      final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
      final want = currencyOfCountry(townCountry(null));
      expect(find.byKey(const Key('create-business-currency')), findsOneWidget);
      expect(find.text('$want — ${currencyName(want, 'fr')}'), findsOneWidget, reason: 'region $region');
      await tester.enterText(find.widgetWithText(TextField, 'Nom de l\'activité'), 'Le Comptoir Doré');
      await tester.pump();
      await tester.tap(find.byKey(const Key('create-business-currency')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('XAF — Franc CFA (CEMAC)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer l\'activité'));
      await tester.pumpAndSettle();
      expect(admin.currency, 'XAF');
    });

    testWidgets('the vitrine preview in the shop\'s money: « 12,50 EUR », not « 13 F »', (tester) async {
      await _size(tester, 420, 900);
      await tester.pumpWidget(_app(const Scaffold(
          body: VitrinePreview(
              name: 'Maison Élégance',
              style: StorefrontStyle(layout: VitrineLayout.list),
              items: [Product(id: 'f', name: 'Foulard', salePrice: 12.5)],
              currency: 'EUR'))));
      await tester.pump();
      expect(_texts(tester), contains('12,50 EUR'));
      _noFranc(tester, where: 'the vitrine preview');
    });

    test('the courier\'s tally: one strip per money, francs first; 062\'s rows in the courier\'s own', () {
      final by = earningsByCurrency(const [
        CourierEarnings(period: 'today', courses: 1, fees: 4.1, km: 2, currency: 'EUR'),
        CourierEarnings(period: 'today', courses: 2, fees: 1600, km: 4, currency: 'XOF'),
        CourierEarnings(period: 'week', courses: 1, fees: 4.1, km: 2, currency: 'EUR'),
        CourierEarnings(period: 'week', courses: 2, fees: 1600, km: 4, currency: 'XOF'),
      ], 'XOF');
      expect(by.keys.toList(), ['XOF', 'EUR']);
      expect(by['EUR']!.map((e) => e.fees), [4.1, 4.1]);
      expect(by['XOF']!.map((e) => e.fees), [1600, 1600]);
      final old = earningsByCurrency(const [
        CourierEarnings(period: 'today', courses: 0, fees: 0, km: 0),
      ], 'XAF');
      expect(old.keys.toList(), ['XAF']);
      expect(CourierEarnings.fromRow(const {'period': 'today', 'currency': 'EUR', 'fees': 4.1}).currency, 'EUR');
      expect(CourierSettlement.fromRow(const {'courier_id': 'c', 'currency': 'EUR', 'share': 0.41}).currency, 'EUR');
      expect(CourierSettlement.fromRow(const {'courier_id': 'c', 'share': 240}).currency, 'XOF');
    });

    testWidgets('a bell with an amount, French and English, written from its facts', (tester) async {
      NotificationRow row(String kind, String message, Map<String, dynamic> p) => NotificationRow(
          id: kind, kind: kind, message: message, createdAt: DateTime(2026, 10, 14), params: p);
      final rows = [
        // Written by the server before 140: its words in the server's grouping.
        row('new_order', 'Nouvelle commande de Awa : 12,000.00 XOF + livraison 1,500',
            {'to': 'shop', 'name': 'Awa', 'total': 12000, 'currency': 'XOF', 'fee': 1500}),
        row('new_order', 'Nouvelle commande de Léa : 12.50 EUR',
            {'to': 'shop', 'name': 'Léa', 'total': 12.5, 'currency': 'EUR'}),
        row('delivery_available', 'Nouvelle livraison près de vous : Maison Élégance (4 F)',
            {'to': 'courier', 'shop': 'Maison Élégance', 'fee': 4.1, 'currency': 'EUR'}),
        row('courier_cash_received', 'Le Comptoir confirme … : 10,000 F.',
            {'to': 'courier', 'shop': 'Le Comptoir', 'name': 'Awa', 'amount': 10000, 'currency': 'XAF'}),
        row('vitrine_news', 'Prix en baisse chez Maison Élégance : Foulard à 10 EUR',
            {'to': 'customer', 'shop': 'Maison Élégance', 'count': 1, 'names': ['Foulard'],
             'offer': true, 'price': 9.9, 'currency': 'EUR'}),
        // A bell with no amount keeps the server's own words in French.
        row('member_joined', 'Awa a rejoint Entraide', {'to': 'shop', 'who': 'Awa', 'org': 'Entraide'}),
      ];
      for (final lang in ['fr', 'en']) {
        late List<String> out;
        await tester.pumpWidget(_app(Builder(builder: (context) {
          out = [for (final r in rows) _plain(notificationLine(context, r))];
          return const SizedBox();
        }), lang: lang));
        if (lang == 'fr') {
          expect(out, [
            'Nouvelle commande de Awa : 12 000 FCFA + livraison 1 500 FCFA',
            'Nouvelle commande de Léa : 12,50 EUR',
            'Nouvelle livraison près de vous : Maison Élégance (4,10 EUR)',
            'Le Comptoir confirme avoir reçu l\'argent de la livraison pour Awa : 10 000 FCFA.',
            'Prix en baisse chez Maison Élégance : Foulard à 9,90 EUR',
            'Awa a rejoint Entraide',
          ]);
        } else {
          expect(out[0], 'New order from Awa: 12 000 FCFA + delivery 1 500 FCFA');
          expect(out[2], 'New delivery near you: Maison Élégance (4,10 EUR)');
        }
      }
    });

    test('« Revenus de Mara »: francs CFA, the other moneys beside, never added', () {
      final t = PlatformToday.fromJson(const {
        'money': {
          'currency': 'XOF', 'pro': 15000, 'spots': 0, 'delivery_cut': 240, 'shops_sold': 17500,
          'other': {'EUR': {'delivery_cut': 0.41, 'shops_sold': 25}},
        },
      });
      expect(t.earnedMonth, 15240, reason: 'francs only');
      String f(String c, num v) => _plain(moneyFormat(c).format(v));
      expect(t.withOthers('delivery_cut', (v) => f('XOF', v), f), '240 FCFA + 0,41 EUR');
      expect(t.withOthers('shops_sold', (v) => f('XOF', v), f), '17 500 FCFA + 25,00 EUR');
      // A database before 140: no other money, the old line.
      final old = PlatformToday.fromJson(const {'money': {'delivery_cut': 240}});
      expect(old.withOthers('delivery_cut', (v) => f('XOF', v), f), '240 FCFA');
    });
  });

  group('6. 320 px with text × 1.3, French and English: nothing overflows', () {
    for (final lang in ['fr', 'en']) {
      testWidgets('$lang: creation, vitrine, till, invoice', (tester) async {
        await _size(tester, 320, 640, text: 1.3);
        await tester.pumpWidget(_app(
            CreateMyBusinessScreen(
                key: UniqueKey(), api: _Api(), drafts: _Drafts(_draftAtPhone('BR')),
                whatsApp: _WhatsApp(), onCreated: (_) async => true),
            lang: lang));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.byKey(const ValueKey('create-currency-BRL')), 120,
            scrollable: find.byType(Scrollable).first);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('create-currency-BRL')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the open list');
        await tester.pumpWidget(const SizedBox());

        await tester.pumpWidget(_app(
            StorefrontScreen(
                slug: 'maison-elegance', storefront: _Street(),
                capture: CaptureRepository(null, db: db), session: session()),
            lang: lang));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());

        await tester.pumpWidget(_app(
            SaleFlow(
                orgId: 'o', retail: _Till(), store: MemoryFlowStore(), currency: 'USD',
                products: const [Product(id: 'p1', name: 'Bougie parfumée', salePrice: 1249.99, quantity: 5)]),
            lang: lang));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());

        await tester.pumpWidget(_app(
            Scaffold(body: SingleChildScrollView(child: InvoicePaper(doc: _invoiceBrl()))), lang: lang));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());

        await tester.pumpWidget(_app(
            DirectoryScreen(storefront: _Street(), capture: CaptureRepository(null, db: db), session: session()),
            lang: lang));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());

        // The platform admin's « Nouvelle entreprise », its picker open, and
        // a vitrine preview in euros (the supervision's).
        await tester.pumpWidget(_app(CreateBusinessScreen(key: UniqueKey(), admin: _CreateAdmin()), lang: lang));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.byKey(const Key('create-business-currency')), 120,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.byKey(const Key('create-business-currency')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the open list');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_app(
            const Scaffold(
                body: SingleChildScrollView(
                    child: VitrinePreview(
                        name: 'Maison Élégance',
                        style: StorefrontStyle(layout: VitrineLayout.menu),
                        items: [Product(id: 'f', name: 'Foulard', salePrice: 1249.99)],
                        currency: 'EUR'))),
            lang: lang));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // -------------------------------------------------------------------------
  // Screenshots (B144_SHOTS=<dir>)
  // -------------------------------------------------------------------------
  final shots = Platform.environment['B144_SHOTS'];
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
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer))))
            .load();
      }
    }

    Future<void> shoot(WidgetTester tester, String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')).first);
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
          await tester.runAsync(realFonts);
          await _size(tester, w, h, text: text);
          final p = '${lang}_${tag}_';

          // Creation: Brazil → BRL, France → EUR.
          for (final (iso, profile, n) in [('BR', 'association', '01_creation_bresil_brl'), ('FR', 'retail', '02_creation_france_eur')]) {
            await tester.pumpWidget(_app(
                CreateMyBusinessScreen(
                    key: UniqueKey(), api: _Api(), drafts: _Drafts(_draftAtPhone(iso, profile: profile)),
                    whatsApp: _WhatsApp(), onCreated: (_) async => true),
                lang: lang));
            await _settle(tester);
            await shoot(tester, '$p$n');
            await tester.pumpWidget(const SizedBox());
          }

          // The vitrine in EUR.
          await tester.pumpWidget(_app(
              StorefrontScreen(
                  slug: 'maison-elegance', storefront: _Street(),
                  capture: CaptureRepository(null, db: db), session: session()),
              lang: lang));
          await _settle(tester);
          await shoot(tester, '${p}03_vitrine_eur');
          await tester.pumpWidget(const SizedBox());

          // The till in USD, on « Combien ? ».
          await tester.pumpWidget(_app(
              SaleFlow(
                  orgId: 'o', orgName: 'Atelier Lumière', retail: _Till(), store: MemoryFlowStore(),
                  currency: 'USD',
                  products: const [
                    Product(id: 'p1', name: 'Bougie parfumée', salePrice: 9.99, quantity: 5),
                    Product(id: 'p2', name: 'Diffuseur', salePrice: 24.5, quantity: 3),
                  ]),
              lang: lang));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sale-pick-p1')));
          await tester.tap(find.byKey(const ValueKey('sale-pick-p2')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('flow-next')));
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const ValueKey('sale-qty-p1')), '2');
          await tester.pumpAndSettle();
          await shoot(tester, '${p}04_caisse_usd');
          await tester.pumpWidget(const SizedBox());

          // An invoice in BRL.
          await tester.pumpWidget(_app(
              Scaffold(body: SingleChildScrollView(child: InvoicePaper(doc: _invoiceBrl()))), lang: lang));
          await _settle(tester);
          await shoot(tester, '${p}05_facture_brl');
          await tester.pumpWidget(const SizedBox());

          // The street: each card in its shop's money.
          await tester.pumpWidget(_app(
              DirectoryScreen(storefront: _Street(), capture: CaptureRepository(null, db: db), session: session()),
              lang: lang));
          await _settle(tester);
          final card = find.text('Foulard en soie');
          if (card.evaluate().isNotEmpty) {
            await tester.ensureVisible(card.first);
            await tester.pumpAndSettle();
          }
          await shoot(tester, '${p}06_rue_monnaies');

          // The platform admin's « Nouvelle entreprise », its picker.
          await tester.pumpWidget(_app(CreateBusinessScreen(key: UniqueKey(), admin: _CreateAdmin()), lang: lang));
          await _settle(tester);
          await shoot(tester, '${p}07_nouvelle_entreprise');

          // A Paris shop's vitrine preview, in euros.
          await tester.pumpWidget(_app(
              const Scaffold(
                  body: SingleChildScrollView(
                      child: VitrinePreview(
                          name: 'Maison Élégance',
                          style: StorefrontStyle(layout: VitrineLayout.menu),
                          items: [
                            Product(id: 'f', name: 'Foulard en soie', salePrice: 1249.99),
                            Product(id: 'b', name: 'Bougie', salePrice: 7.2),
                          ],
                          currency: 'EUR'))),
              lang: lang));
          await _settle(tester);
          await shoot(tester, '${p}08_apercu_vitrine_eur');
        });
      }
    }
  }, skip: shots == null ? 'B144_SHOTS=<dir> writes the screenshots' : null);
}

void _ignore(String _) {}
void _none() {}
