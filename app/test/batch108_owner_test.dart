import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/invoice_reading.dart' as reading;
import 'package:kaj_app/core/cauris/cauris_repository.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/invoicing/models.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/admin/cauris_console_card.dart';
import 'package:kaj_app/features/admin/org_settings_screen.dart';
import 'package:kaj_app/features/capture/confirm_products_screen.dart';
import 'package:kaj_app/features/cauris/path_card.dart';
import 'package:kaj_app/features/cauris/unlock_sheet.dart';
import 'package:kaj_app/features/home/home_nav.dart';
import 'package:kaj_app/features/invoicing/invoice_flow.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/retail/sale_flow.dart';
import 'package:kaj_app/l10n/strings.dart';

/// The owner's list (108), on the screens: « Nouvelle vente » says what to
/// do (E4); the business's place is « La position de ma boutique », de ma
/// ferme, de mon association (E3); a tool cauris cannot open yet says why
/// and when, on its button, and the wallet is the server's of now (E5).
class _Till extends RetailRepository {
  _Till() : super(null);

  @override
  Future<Map<String, double>> pendingSaleQuantities(String orgId) async => const {};
}

class _Settings extends AdminRepository {
  _Settings(this.profile) : super(null);

  final String profile;

  @override
  Future<Map<String, dynamic>> fetchOrg(String orgId) async => {
        'id': orgId,
        'name': 'Ici',
        'slug': 'ici',
        'profile': profile,
        'default_currency': 'XOF',
      };

  @override
  Future<String?> waveMerchant(String orgId) async => null;

  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) async => const [];

  @override
  Future<
      ({
        bool enabled,
        String? blurb,
        double? lat,
        double? lng,
        double? deliveryBase,
        double? deliveryPerKm,
      })> storefront(String orgId) async => (
        enabled: true,
        blurb: null as String?,
        lat: null as double?,
        lng: null as double?,
        deliveryBase: null as double?,
        deliveryPerKm: null as double?,
      );

  @override
  Future<double?> deliveryReach(String orgId) async => null;

  @override
  Future<double?> deliveryIncludedKm(String orgId) async => null;

  @override
  Future<({String? phone, String? address})> orgContact(String orgId) async =>
      (phone: null, address: null);

  @override
  Future<VitrineChecklist?> vitrineChecklist(String orgId) async =>
      const VitrineChecklist(published: 1, minItems: 1);
}

class _Prices extends CaurisRepository {
  _Prices() : super(null);

  final saved = <String>[];

  @override
  Future<List<CaurisRule>> rules() async => const [];

  @override
  Future<List<CaurisWatchRow>> watch() async => const [];

  @override
  Future<List<({String feature, int cost, int minDays})>> costs() async => const [
        (feature: 'accounting', cost: 500, minDays: 60),
        (feature: 'photo_slot', cost: 50, minDays: 0),
      ];

  @override
  Future<String?> setCost(String feature, int cost, {required int minDays}) async {
    saved.add('$feature $cost $minDays');
    return null;
  }
}

const _shop = OrgSummary(id: 'o1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Scaffold(body: child),
    );

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async => initializeDateFormatting('fr_FR', null));

  group('E4 — « Nouvelle vente » says what to do', () {
    // Since 115 the sale is the « Vente » flow: the line is its first
    // question's, right under it.
    testWidgets('the shop: the articles the customer asks for', (tester) async {
      await _tall(tester);
      await tester.pumpWidget(_app(SaleFlow(orgId: 'o1', retail: _Till(), store: MemoryFlowStore())));
      await tester.pump();
      final line = find.text('Choisissez les articles demandés par le client ici');
      expect(line, findsOneWidget);
      expect(tester.getTopLeft(line).dy,
          greaterThan(tester.getTopLeft(find.byKey(const Key('flow-question'))).dy));
    });

    testWidgets('the farm (its carnet de crédit): the products', (tester) async {
      await _tall(tester);
      await tester.pumpWidget(_app(SaleFlow(orgId: 'f1', retail: _Till(), farm: true, initialMethod: 'credit', store: MemoryFlowStore())));
      await tester.pump();
      expect(find.text('Choisissez les produits demandés par le client ici'), findsOneWidget);
    });
  });

  group('E3 — the business\'s own place', () {
    testWidgets('Le Chemin\'s step, whatever an older server still calls it', (tester) async {
      late String shop, farm;
      await tester.pumpWidget(_app(Builder(builder: (context) {
        const old = PathStep(key: 'pin', stage: 2, title: 'Ma position sur la carte');
        shop = pathStepTitle(context, old);
        farm = pathStepTitle(context, old, farm: true);
        return const SizedBox();
      })));
      expect(shop, 'La position de ma boutique');
      expect(farm, 'La position de ma ferme');
    });

    testWidgets('Le Chemin\'s article goal: one is « 1 article en vente », never « 1 articles »', (tester) async {
      late String one, farmOne, three;
      await tester.pumpWidget(_app(Builder(builder: (context) {
        one = pathStepTitle(context, const PathStep(key: 'articles', stage: 1, title: 'x', goal: 1));
        farmOne = pathStepTitle(context, const PathStep(key: 'articles', stage: 1, title: 'x', goal: 1), farm: true);
        three = pathStepTitle(context, const PathStep(key: 'articles', stage: 1, title: 'x', goal: 3));
        return const SizedBox();
      })));
      expect(one, '1 article en vente');
      expect(farmOne, '1 produit en vente');
      expect(three, '3 articles en vente');
    });

    for (final (profile, words) in [
      ('retail', 'La position de ma boutique'),
      ('farm', 'La position de ma ferme'),
      ('association', 'La position de mon association'),
    ]) {
      testWidgets('the settings of a $profile: « $words »', (tester) async {
        await _tall(tester);
        await tester.pumpWidget(_app(OrgSettingsScreen(admin: _Settings(profile), orgId: 'o1')));
        await tester.pump();
        await tester.pump();
        expect(find.text(words), findsWidgets);
        expect(find.text('Position'), findsNothing);
      });
    }
  });

  group('E5 — cauris: why, when, and the wallet of now', () {
    FeatureStates states({int balance = 600, int? waits}) => FeatureStates(
          balance: balance,
          tools: {'accounting': ToolState(cost: 500, waitsDays: waits)},
        );

    Future<void> sheet(WidgetTester tester, FeatureStates s, {FeatureStates? fresh}) async {
      await _tall(tester);
      await tester.pumpWidget(_app(UnlockSheet(
        org: _shop,
        feature: 'accounting',
        states: s,
        admin: AdminRepository(null),
        fresh: fresh == null ? null : () async => fresh,
      )));
      await tester.pump();
      await tester.pump();
    }

    String buy(WidgetTester tester) {
      final label = find.descendant(
          of: find.byKey(const Key('unlock-buy')), matching: find.byType(Text));
      return tester.widgetList<Text>(label).map((t) => t.data).join();
    }

    bool enabled(WidgetTester tester) =>
        tester.widget<ButtonStyleButton>(find.byKey(const Key('unlock-buy'))).onPressed != null;

    testWidgets('a wait is said on the button, with its day — never a silent grey button',
        (tester) async {
      await sheet(tester, states(waits: 23));
      expect(buy(tester), 'Disponible dans 23 jours');
      expect(enabled(tester), isFalse);
      final wait = tester.widget<Text>(find.descendant(
          of: find.byKey(const Key('unlock-wait')), matching: find.byType(Text)));
      expect(wait.data, startsWith('Disponible avec vos cauris dans 23 jours. Le '));
      expect(wait.data, contains('${DateTime.now().add(const Duration(days: 23)).year}'));
    });

    testWidgets('too few cauris: how many are missing, on the button', (tester) async {
      await sheet(tester, states(balance: 400));
      expect(buy(tester), 'Il vous manque 100 cauris');
      expect(enabled(tester), isFalse);
    });

    testWidgets('the wallet as the server says it now: a stale « missing » gives way', (tester) async {
      // The session's copy is from before a step paid 200 cauris.
      await sheet(tester, states(balance: 400), fresh: states(balance: 600));
      expect(buy(tester), 'Débloquer avec mes cauris');
      expect(enabled(tester), isTrue);
    });

    testWidgets('Mara sets a tool\'s wait with its price; a photo slot has no wait', (tester) async {
      await _tall(tester);
      final prices = _Prices();
      await tester.pumpWidget(_app(SingleChildScrollView(child: CaurisConsoleCard(cauris: prices))));
      await tester.pump();
      await tester.pump();
      expect(find.text('après 60 jours sur Mara'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cost-accounting')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cost-wait')), '30');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(prices.saved, ['accounting 500 30']);
      await tester.tap(find.byKey(const Key('cost-photo_slot')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cost-wait')), findsNothing);
      await tester.enterText(find.byKey(const Key('cost-value')), '60');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(prices.saved.last, 'photo_slot 60 0');
    });

    testWidgets('a tool on the path offers Mara Pro complet in cauris, when there is a price',
        (tester) async {
      Future<PathState?> none() async => null;
      await _tall(tester);
      await tester.pumpWidget(_app(PathGateSheet(
          org: _shop, feature: 'invoices', load: none, onPath: () {},
          proAllCost: 1500, onProAll: () {})));
      await tester.pump();
      expect(find.text('Ou tout ouvrir maintenant : Mara Pro complet, 1500 cauris'), findsOneWidget);
      await tester.pumpWidget(_app(PathGateSheet(
          org: _shop, feature: 'invoices', load: none, onPath: () {})));
      await tester.pump();
      expect(find.byKey(const Key('path-pro-all')), findsNothing);
    });
  });

  // A4: the pages that hold input tell the business's bar, which asks
  // « Quitter sans enregistrer ? » before leaving them (batch108_frame_test
  // proves the asking).
  group('A4 — input not saved, told to the bar', () {
    Widget framed(BusinessNav nav, Widget page) => _app(
        BusinessNavHost(nav: nav, insets: EdgeInsets.zero, child: page));

    for (final profile in ['retail', 'farm', 'association']) {
      testWidgets('the settings of a $profile: a rubrique edited is unsaved, saved is not', (tester) async {
        await _tall(tester);
        final nav = BusinessNav();
        addTearDown(nav.dispose);
        await tester.pumpWidget(framed(nav, OrgSettingsScreen(admin: _Settings(profile), orgId: 'o1')));
        await tester.pump();
        await tester.pump();
        expect(nav.hasUnsaved, isFalse, reason: 'as read: nothing to lose');
        await tester.tap(find.text('Identité'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Ici et là');
        await tester.pump();
        expect(nav.hasUnsaved, isTrue);
        await tester.enterText(find.byType(TextField).first, 'Ici');
        await tester.pump();
        expect(nav.hasUnsaved, isFalse, reason: 'back as it was');
      });
    }

    testWidgets('a new invoice once typed, its correction once changed', (tester) async {
      await _tall(tester);
      final nav = BusinessNav();
      addTearDown(nav.dispose);
      await tester.pumpWidget(framed(nav, InvoiceFlow(org: _shop, invoicing: InvoicingRepository(null), store: MemoryFlowStore())));
      await tester.pump();
      expect(nav.hasUnsaved, isFalse);
      await tester.enterText(find.byType(TextField).first, 'Hôtel Liberté');
      await tester.pump();
      expect(nav.hasUnsaved, isTrue);

      final doc = InvoiceDocument(
        id: 'inv-1', number: '2026-0007', issuedOn: DateTime(2026, 8, 1), total: 15000, paid: 0,
        outstanding: 15000, customerName: 'Hôtel Liberté', orgName: 'Boutique', currency: 'XOF',
        lines: const [InvoiceLine(description: 'Savon', quantity: 20, unitPrice: 750)]);
      final fix = BusinessNav();
      addTearDown(fix.dispose);
      await tester.pumpWidget(framed(fix, InvoiceFlow(
          key: const Key('fix'), org: _shop, invoicing: InvoicingRepository(null), revisionOf: doc,
          store: MemoryFlowStore())));
      await tester.pump();
      expect(fix.hasUnsaved, isFalse, reason: 'opened with the document: nothing changed yet');
      await tester.enterText(find.byType(TextField).first, 'Hôtel Indépendance');
      await tester.pump();
      expect(fix.hasUnsaved, isTrue);
    });

    testWidgets('a photo\'s articles to confirm: unsaved until « Enregistrer »', (tester) async {
      await _tall(tester);
      final nav = BusinessNav();
      addTearDown(nav.dispose);
      await tester.pumpWidget(framed(nav, ConfirmProductsScreen(
          org: _shop, retail: _Till(),
          lines: const [reading.InvoiceLine(name: 'Riz 25 kg', quantity: 2, unitCost: 15000)])));
      await tester.pump();
      expect(nav.hasUnsaved, isTrue);
      await tester.pumpWidget(_app(const SizedBox()));
      expect(nav.hasUnsaved, isFalse, reason: 'gone: nothing holds the bar');
    });
  });
}
