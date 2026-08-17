import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/retail/sale_sheet.dart';
import 'package:kaj_app/l10n/strings.dart';

/// The carnet opens the sale sheet on Crédit so a credit sale picks real
/// products instead of a free-text line. initialMethod is what makes that
/// happen: the customer field (shown only for credit) is present from the
/// start when it is 'credit', and absent on the default 'cash'.
void main() {
  Widget host(String initialMethod) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: Scaffold(
          body: SaleSheet(
            orgId: 'o1',
            retail: RetailRepository(null),
            canCredit: true,
            initialMethod: initialMethod,
          ),
        ),
      );

  testWidgets('opening on credit shows the customer field immediately',
      (tester) async {
    tester.view.physicalSize = const Size(600, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host('credit'));
    await tester.pump();
    expect(find.text('Nom du client'), findsOneWidget);
    expect(find.textContaining('ira dans le carnet'), findsOneWidget);
  });

  testWidgets('the default cash sheet has no customer field', (tester) async {
    tester.view.physicalSize = const Size(600, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host('cash'));
    await tester.pump();
    expect(find.text('Nom du client'), findsNothing);
  });
}
