import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/admin/org_settings_screen.dart';
import 'package:kaj_app/features/retail/sale_sheet.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Multi-currency at the till (039): the chips appear only when the owner has
/// set rates, the converted amount is what the server is told was collected,
/// and the books' amount never moves.
class _FakeRetail extends RetailRepository {
  _FakeRetail({this.rates = const []}) : super(null);

  final List<CurrencyRate> rates;
  String? tenderCurrency;
  double? tenderAmount;
  double? tenderRate;

  @override
  Future<String?> waveMerchant(String orgId) async => null;

  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) async => rates;

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
  }) async =>
      'sale-1';

  @override
  Future<void> attachSaleTender({
    required String saleId,
    required String currency,
    required double amount,
    required double rate,
  }) async {
    tenderCurrency = currency;
    tenderAmount = amount;
    tenderRate = rate;
  }
}

void main() {
  group('the arithmetic', () {
    test('fromHome converts and keeps foreign cents', () {
      const usd = CurrencyRate(currency: 'USD', rate: 600);
      expect(usd.fromHome(9000), 15.0);
      // 10 000 / 600 = 16.666... → the cash precision a note actually has.
      expect(usd.fromHome(10000), 16.67);
      expect(usd.toHome(15), 9000);
    });

    test('a rate keeps its decimals where an amount would not', () {
      // The EUR peg must never print as 656 F while the maths uses 655,957.
      expect(rateLabel('EUR', eurXofPeg, 'XOF'), '1 EUR = 655,957 F');
      expect(rateLabel('USD', 600, 'XOF'), '1 USD = 600 F');
    });
  });

  group('the sale sheet', () {
    Widget host(RetailRepository retail) => MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          home: Scaffold(
            body: SaleSheet(
              orgId: 'o1',
              orgName: 'Boutique',
              retail: retail,
              products: const [],
            ),
          ),
        );

    Future<void> sized(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(700, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(w);
      await tester.pumpAndSettle();
    }

    Future<void> addLine(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).first, 'Tissu');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), '9000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter au panier'));
      await tester.pumpAndSettle();
    }

    testWidgets('no rates, no chips', (tester) async {
      await sized(tester, host(_FakeRetail()));
      await addLine(tester);
      expect(find.text('FCFA'), findsNothing);
      expect(find.text('USD'), findsNothing);
    });

    testWidgets('rates draw the chips, home currency selected by default',
        (tester) async {
      await sized(
          tester,
          host(_FakeRetail(
              rates: const [CurrencyRate(currency: 'USD', rate: 600)])));
      await addLine(tester);
      expect(find.text('FCFA'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);
      // Nothing to collect in a foreign currency until one is chosen.
      expect(find.text('À encaisser'), findsNothing);
    });

    testWidgets('a rate for the home currency itself never draws a chip',
        (tester) async {
      await sized(
          tester,
          host(_FakeRetail(
              rates: const [CurrencyRate(currency: 'XOF', rate: 1)])));
      await addLine(tester);
      expect(find.text('USD'), findsNothing);
      expect(find.text('FCFA'), findsNothing); // no foreign rates → no row
    });

    testWidgets(
        'paying in USD shows the amount to collect, stamps the tender, '
        'and hands back a two-currency receipt', (tester) async {
      final retail =
          _FakeRetail(rates: const [CurrencyRate(currency: 'USD', rate: 600)]);
      await sized(tester, host(retail));
      await addLine(tester);

      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      // 9 000 F at 600 → exactly 15 USD to collect, with the rate in writing.
      expect(find.text('À encaisser'), findsOneWidget);
      expect(find.textContaining('15,00'), findsOneWidget);
      expect(find.text('1 USD = 600 F'), findsOneWidget);

      await tester.tap(find.text('Enregistrer la vente'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(retail.tenderCurrency, 'USD');
      expect(retail.tenderAmount, 15.0);
      expect(retail.tenderRate, 600);
      expect(find.text('Vente enregistrée'), findsOneWidget);
      expect(find.text('Payé'), findsOneWidget);
    });

    testWidgets('a home-currency sale stamps nothing', (tester) async {
      final retail =
          _FakeRetail(rates: const [CurrencyRate(currency: 'USD', rate: 600)]);
      await sized(tester, host(retail));
      await addLine(tester);

      await tester.tap(find.text('Enregistrer la vente'));
      await tester.pumpAndSettle();
      expect(retail.tenderCurrency, isNull);
    });
  });

  group('the rate dialog', () {
    testWidgets('adding EUR to a XOF business pre-fills the peg',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: RateDialog(homeCurrency: 'XOF', taken: []),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('EUR — Euro').last);
      await tester.pumpAndSettle();

      expect(find.text('$eurXofPeg'), findsOneWidget);
      expect(find.textContaining('Taux fixe officiel'), findsOneWidget);
    });
  });
}
