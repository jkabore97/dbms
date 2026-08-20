import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/retail/corrections_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// The corrections screen: an owner sees recent sales and deliveries, an
/// already-undone one reads "Corrigé" rather than offering to undo it twice,
/// and pressing Corriger on a live delivery reverses that exact receipt.
class _FakeRetail extends RetailRepository {
  _FakeRetail() : super(null);

  List<SaleSummary> sales = const [];
  List<Delivery> deliveries = const [];
  String? reversedReceiptId;
  String? returnedSaleId;

  @override
  Future<List<SaleSummary>> recentSales(String orgId, {int limit = 50}) async =>
      sales;

  @override
  Future<List<Delivery>> recentDeliveries(String orgId,
          {int limit = 50}) async =>
      deliveries;

  @override
  Future<void> reverseReceipt(String receiptId, {String? reason}) async {
    reversedReceiptId = receiptId;
  }

  @override
  Future<String> recordReturn(String saleId, {String? note}) async {
    returnedSaleId = saleId;
    return 'return-id';
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: child,
      );

  const org = OrgSummary(
      id: 'o1', name: 'ELIM Shop', profile: 'retail', roles: ['owner']);

  testWidgets('a reversed delivery reads Corrigé; a live one can be reversed',
      (tester) async {
    final retail = _FakeRetail()
      ..sales = [
        SaleSummary(
          id: 's1',
          method: 'cash',
          total: 1000,
          occurredAt: DateTime(2026, 8, 1),
          reversed: true, // already returned -> chip, no button
        ),
      ]
      ..deliveries = [
        Delivery(
          id: 'd1',
          productName: 'Savon',
          quantity: 10,
          unitCost: 300,
          lineTotal: 3000,
          receivedAt: DateTime(2026, 8, 2),
        ),
      ];

    await tester.pumpWidget(wrap(CorrectionsScreen(org: org, retail: retail)));
    await tester.pumpAndSettle();

    // Both transactions listed.
    expect(find.text('Savon'), findsOneWidget);
    // The reversed sale shows the chip, and offers no second undo.
    expect(find.text('Corrigé'), findsOneWidget);

    // Exactly one live transaction (the delivery) offers a Corriger button.
    expect(find.widgetWithText(OutlinedButton, 'Corriger'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Corriger'));
    await tester.pumpAndSettle();

    // The confirm dialog explains it is a reversal, not a deletion.
    expect(find.textContaining('écriture inverse'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Corriger'));
    await tester.pumpAndSettle();

    expect(retail.reversedReceiptId, 'd1',
        reason: 'the delivery that was pressed is the one reversed');
    expect(retail.returnedSaleId, isNull,
        reason: 'the reversed sale must not have been touched');
  });
}
