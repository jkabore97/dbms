import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/retail/sale_sheet.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Wave at the counter (037): the sheet offers Wave only when the shop has a
/// handle, and choosing it leads to the QR, the sender field, and a receipt —
/// with nothing recorded until a name is given.
class _FakeRetail extends RetailRepository {
  _FakeRetail({this.merchant}) : super(null);

  final String? merchant;
  String? confirmedSender;
  String? recordedMethod;

  @override
  Future<String?> waveMerchant(String orgId) async => merchant;

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
    recordedMethod = method;
    return 'sale-1';
  }

  @override
  Future<void> confirmWavePayment({
    required String saleId,
    required String sender,
    String? reference,
  }) async {
    confirmedSender = sender;
  }
}

void main() {
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
    tester.view.physicalSize = const Size(700, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    await tester.pumpAndSettle();
  }

  testWidgets('Wave is offered only when the shop has a handle',
      (tester) async {
    await sized(tester, host(_FakeRetail(merchant: '+22670000000')));
    expect(find.text('Wave'), findsOneWidget);
  });

  testWidgets('no handle, no Wave button', (tester) async {
    await sized(tester, host(_FakeRetail(merchant: null)));
    expect(find.text('Wave'), findsNothing);
  });

  testWidgets('paying by Wave shows the QR, takes the sender, and confirms',
      (tester) async {
    final retail = _FakeRetail(merchant: '+22670000000');
    await sized(tester, host(retail));

    // Add a line so a sale can be recorded.
    await tester.enterText(find.byType(TextField).first, 'Savon');
    await tester.pumpAndSettle();
    // Price field is the third TextField (name, quantity, price).
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(2), '500');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter au panier'));
    await tester.pumpAndSettle();

    // Choose Wave.
    await tester.tap(find.text('Wave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payer avec Wave'));
    await tester.pumpAndSettle();

    // The payment sheet: a QR and a sender field.
    expect(find.text('Paiement Wave'), findsOneWidget);
    expect(find.text('Paiement reçu'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Nom de l\'expéditeur Wave').first,
        'Awa Traoré');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paiement reçu'));
    // Not pumpAndSettle: the main sheet's progress spinner keeps animating while
    // the receipt dialog is open, so settle never returns. A few frames is
    // enough for the recordSale/confirm futures and the dialog to appear.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The sale was recorded as Wave and the sender confirmed; the receipt shows.
    expect(retail.recordedMethod, 'wave');
    expect(retail.confirmedSender, 'Awa Traoré');
    expect(find.text('Paiement Wave reçu'), findsOneWidget);
    expect(find.text('Awa Traoré'), findsWidgets);
  });
}
