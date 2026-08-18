import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/invoicing/models.dart';
import 'package:kaj_app/features/invoicing/new_invoice_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Correcting an invoice (040): the same form as a new one, opened pre-filled
/// from the document, and saving goes through revise — never create — so the
/// server can withdraw the old invoice and issue the replacement atomically.
class _FakeInvoicing extends InvoicingRepository {
  _FakeInvoicing() : super(null);

  String? revisedInvoiceId;
  String? revisedCustomer;
  List<InvoiceLine>? revisedLines;
  bool createCalled = false;

  @override
  Future<String> revise({
    required String invoiceId,
    required String customerName,
    required List<InvoiceLine> lines,
    String? customerPhone,
    String? customerAddress,
    int? dueDays,
    DateTime? dueOn,
    DateTime? issuedOn,
    String? memo,
  }) async {
    revisedInvoiceId = invoiceId;
    revisedCustomer = customerName;
    revisedLines = lines;
    return 'new-invoice-1';
  }

  @override
  Future<String> create({
    required String orgId,
    required String customerName,
    required List<InvoiceLine> lines,
    String? customerPhone,
    String? customerAddress,
    String? category,
    int? dueDays,
    DateTime? dueOn,
    DateTime? issuedOn,
    String? memo,
    String? clientUuid,
  }) async {
    createCalled = true;
    return 'should-not-happen';
  }
}

InvoiceDocument _doc() => InvoiceDocument(
      id: 'inv-1',
      number: '2026-0007',
      issuedOn: DateTime(2026, 8, 1),
      total: 15000,
      paid: 0,
      outstanding: 15000,
      customerName: 'Hôtel Liberté',
      customerAddress: 'Ouaga 2000',
      orgName: 'Boutique',
      currency: 'XOF',
      lines: const [
        InvoiceLine(description: 'Savon 500g', quantity: 20, unitPrice: 750),
      ],
    );

const _org = OrgSummary(
  id: 'o1',
  name: 'Boutique',
  slug: 'boutique',
  profile: 'retail',
  currency: 'XOF',
  roles: ['owner'],
  visibility: 'full',
);

void main() {
  Future<void> pump(WidgetTester tester, _FakeInvoicing invoicing) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: NewInvoiceScreen(
        org: _org,
        invoicing: invoicing,
        revisionOf: _doc(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('opens pre-filled with the document it corrects',
      (tester) async {
    await pump(tester, _FakeInvoicing());

    expect(find.text('Corriger la facture 2026-0007'), findsOneWidget);
    expect(find.text('Hôtel Liberté'), findsOneWidget);
    expect(find.text('Savon 500g'), findsOneWidget);
    expect(find.text('750'), findsOneWidget);
  });

  testWidgets('saving goes through revise, never create', (tester) async {
    final invoicing = _FakeInvoicing();
    await pump(tester, invoicing);

    // Correct the quantity: 20 becomes 12.
    await tester.enterText(find.text('20'), '12');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Corriger la facture'));
    await tester.pumpAndSettle();

    expect(invoicing.createCalled, isFalse);
    expect(invoicing.revisedInvoiceId, 'inv-1');
    expect(invoicing.revisedCustomer, 'Hôtel Liberté');
    expect(invoicing.revisedLines, hasLength(1));
    expect(invoicing.revisedLines!.single.quantity, 12);
  });
}
