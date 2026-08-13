import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/invoicing/models.dart';
import 'package:kaj_app/features/invoicing/invoice_paper.dart';

/// The document that leaves the app.
///
/// Everything else in this repository can be checked by asking the database
/// what it stored. This cannot: the invoice is a *picture* that ends up in
/// somebody else's WhatsApp, and if a line is missing from it there is no
/// error anywhere — the customer simply receives a bill that is wrong, and
/// the business finds out when it is not paid.
///
/// So the assertions here are about what is printed, not about what is saved.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  InvoiceDocument doc({
    double total = 24000,
    double paid = 0,
    DateTime? cancelledAt,
    String? taxId = '00012345A',
    String? taxLabel = 'IFU',
    String? footer = 'Merci de votre confiance.',
    List<InvoiceLine>? lines,
  }) =>
      InvoiceDocument(
        id: 'inv-1',
        number: '2026-0007',
        issuedOn: DateTime(2026, 8, 13),
        dueOn: DateTime(2026, 9, 12),
        cancelledAt: cancelledAt,
        total: total,
        paid: paid,
        outstanding: total - paid,
        customerName: 'Hôtel Indépendance',
        customerPhone: '+22676000000',
        customerAddress: 'Avenue Kwame Nkrumah',
        orgName: 'Boutique Esperance',
        orgAddress: 'Rue 14.28, Ouagadougou',
        orgPhone: '+22670000000',
        orgTaxId: taxId,
        orgTaxLabel: taxLabel,
        currency: 'XOF',
        footer: footer,
        lines: lines ??
            const [
              InvoiceLine(
                  description: 'Savon 500g', quantity: 20, unitPrice: 750),
              InvoiceLine(
                  description: 'Sucre 1kg', quantity: 10, unitPrice: 900),
            ],
      );

  Future<void> pump(WidgetTester tester, InvoiceDocument d) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: InvoicePaper(doc: d)),
      ),
    ));
    await tester.pump();
  }

  group('what the customer receives', () {
    testWidgets('says who is billing, and how to identify them', (t) async {
      await pump(t, doc());
      expect(find.text('Boutique Esperance'), findsOneWidget);
      expect(find.text('Rue 14.28, Ouagadougou'), findsOneWidget);
      // Without this line the customer's own accountant cannot file it, which
      // is the difference between an invoice and a note.
      expect(find.text('IFU : 00012345A'), findsOneWidget);
    });

    testWidgets('says who is being billed', (t) async {
      await pump(t, doc());
      expect(find.text('Hôtel Indépendance'), findsOneWidget);
      expect(find.text('Avenue Kwame Nkrumah'), findsOneWidget);
    });

    testWidgets('carries a number and a date', (t) async {
      await pump(t, doc());
      expect(find.text('N° 2026-0007'), findsOneWidget);
      expect(find.text('FACTURE'), findsOneWidget);
      expect(find.textContaining('13 août 2026'), findsWidgets);
      expect(find.textContaining('Échéance'), findsOneWidget);
    });

    testWidgets('prints every line, not only the first', (t) async {
      await pump(t, doc());
      expect(find.text('Savon 500g'), findsOneWidget);
      expect(find.text('Sucre 1kg'), findsOneWidget);
    });

    testWidgets('a whole quantity prints whole, a fractional one does not',
        (t) async {
      await pump(
        t,
        doc(lines: const [
          InvoiceLine(description: 'Ciment', quantity: 12, unitPrice: 5000),
          InvoiceLine(description: 'Sable', quantity: 2.5, unitPrice: 4000),
        ]),
      );
      // "12" and not "12.0" — a bill that reads 12.0 sacks looks like a
      // machine talking to itself.
      expect(find.text('12'), findsOneWidget);
      expect(find.text('2.5'), findsOneWidget);
    });

    testWidgets('the footer the business wrote is printed', (t) async {
      await pump(t, doc());
      expect(find.text('Merci de votre confiance.'), findsOneWidget);
    });
  });

  group('the state of the invoice is unmissable', () {
    testWidgets('a part payment shows what is still owed', (t) async {
      await pump(t, doc(paid: 10000));
      expect(find.text('Déjà payé'), findsOneWidget);
      expect(find.text('Reste à payer'), findsOneWidget);
      expect(find.text('PAYÉE'), findsNothing);
    });

    testWidgets('a settled invoice says so', (t) async {
      await pump(t, doc(paid: 24000));
      expect(find.text('PAYÉE'), findsOneWidget);
    });

    testWidgets('a cancelled invoice says so, loudly', (t) async {
      // It still exists and can still be re-opened, so the document has to
      // carry the fact — a cancelled invoice that looks payable is how
      // somebody pays one twice.
      await pump(t, doc(cancelledAt: DateTime(2026, 8, 14)));
      expect(find.text('FACTURE ANNULÉE'), findsOneWidget);
      expect(find.text('PAYÉE'), findsNothing);
    });
  });

  group('a business that has not finished filling in its header', () {
    testWidgets('still produces a document rather than refusing', (t) async {
      // Refusing to invoice until a form is complete is how an app stops
      // somebody trading. The line is omitted; the invoice still goes out.
      await pump(t, doc(taxId: null, taxLabel: null, footer: null));
      expect(find.textContaining('IFU'), findsNothing);
      expect(find.text('Boutique Esperance'), findsOneWidget);
      expect(find.text('Savon 500g'), findsOneWidget);
    });

    testWidgets('a tax number with no label still gets one', (t) async {
      await pump(t, doc(taxLabel: null));
      expect(find.text('N° fiscal : 00012345A'), findsOneWidget);
    });
  });
}
