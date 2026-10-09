import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/features/admin/org_settings_screen.dart';

/// Multi-currency at the till (039): the arithmetic and the owner's rate
/// dialog. The till's chips, the amount to collect and the stamped tender
/// are checked on the « Vente » flow (batch115_sale_flow_test).
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
