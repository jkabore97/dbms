import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/format/money.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/invoicing/models.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/invoicing/invoice_flow.dart';
import 'package:kaj_app/l10n/strings.dart';

/// « Facture », one entry at a time (115) — a new invoice through
/// create_invoice, and the correction (040) through the same flow opened
/// pre-filled from the document, saved through revise — never create — so
/// the server can withdraw the old invoice and issue the replacement
/// atomically.
class _FakeInvoicing extends InvoicingRepository {
  _FakeInvoicing() : super(null);

  String? revisedInvoiceId;
  String? revisedCustomer;
  List<InvoiceLine>? revisedLines;
  bool createCalled = false;
  String? createdCustomer;
  List<InvoiceLine>? createdLines;
  int? createdDueDays;
  String? createdUuid;
  String? createdPhone;

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
    createdCustomer = customerName;
    createdLines = lines;
    createdDueDays = dueDays;
    createdUuid = clientUuid;
    createdPhone = customerPhone;
    return 'inv-new';
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

OrgSummary _org(String profile) => OrgSummary(
      id: 'o1',
      name: 'Boutique',
      slug: 'boutique',
      profile: profile,
      currency: 'XOF',
      roles: const ['owner'],
      visibility: 'full',
    );

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  Future<void> pump(WidgetTester tester, Widget flow) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: flow,
    ));
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();
  }

  for (final profile in ['retail', 'farm', 'association']) {
    testWidgets('a $profile raises an invoice one question at a time', (tester) async {
      final invoicing = _FakeInvoicing();
      String? opened;
      await pump(
          tester,
          InvoiceFlow(
            org: _org(profile),
            invoicing: invoicing,
            store: MemoryFlowStore(),
            onOpen: (id) => opened = id,
          ));

      expect(find.text('Pour qui ?'), findsOneWidget);
      final nextButton = find.byKey(const Key('flow-next'));
      expect(tester.widget<FilledButton>(nextButton).onPressed, isNull,
          reason: 'no customer yet');
      await tester.enterText(find.byKey(const Key('customer-name')), 'Hôtel Indépendance');
      await tester.pump();
      await next(tester);

      // How to reach them: optional, a wrong length holds « Suivant ».
      expect(find.byKey(const Key('flow-step-contact')), findsOneWidget);
      await next(tester);

      // What: a line typed (no catalogue in this build).
      expect(tester.widget<FilledButton>(nextButton).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('invoice-typed-name')), 'Plateaux d\'œufs');
      await tester.enterText(find.byKey(const Key('invoice-typed-price')), '2500');
      await tester.pump();
      await tester.tap(find.byKey(const Key('invoice-typed-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invoice-basket')), findsOneWidget);
      await next(tester);

      // How many.
      await tester.enterText(find.byKey(const Key('invoice-qty-0')), '4');
      await tester.pump();
      expect(find.text(moneyFormat('XOF').format(10000)), findsWidgets);
      await next(tester);

      // Due: 15 days.
      await tester.tap(find.byKey(const Key('flow-option-days:15')));
      await tester.pump();
      await next(tester);
      // The note: optional.
      await next(tester);

      expect(find.byKey(const Key('flow-summary')), findsOneWidget);
      expect(find.text('4 × Plateaux d\'œufs'), findsOneWidget);
      expect(find.text('Créer la facture'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();

      expect(invoicing.createCalled, isTrue);
      expect(invoicing.revisedInvoiceId, isNull);
      expect(invoicing.createdCustomer, 'Hôtel Indépendance');
      expect(invoicing.createdLines!.single.quantity, 4);
      expect(invoicing.createdLines!.single.unitPrice, 2500);
      expect(invoicing.createdDueDays, 15);
      expect(invoicing.createdUuid, isNotNull, reason: 'one uuid per invoice: a retry cannot raise it twice');
      expect(invoicing.createdPhone, isNull);

      // The document opened at once, as before (batch 115); « C'est fait »
      // behind it.
      expect(opened, 'inv-new');
      expect(find.byKey(const Key('flow-done')), findsOneWidget);
      opened = null;
      await tester.tap(find.byKey(const Key('invoice-open')));
      await tester.pumpAndSettle();
      expect(opened, 'inv-new');
    });
  }

  testWidgets('a correction opens pre-filled and saves through revise, never create',
      (tester) async {
    final invoicing = _FakeInvoicing();
    String? saved;
    await pump(
        tester,
        InvoiceFlow(
          org: _org('retail'),
          invoicing: invoicing,
          revisionOf: _doc(),
          store: MemoryFlowStore(),
          onSaved: (id) => saved = id,
        ));

    expect(find.text('Corriger la facture 2026-0007'), findsOneWidget);
    expect(find.text('Hôtel Liberté'), findsOneWidget);
    await next(tester); // customer
    await next(tester); // contact
    expect(find.textContaining('20 × Savon 500g'), findsOneWidget);
    await next(tester); // items
    expect(find.text('750'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('invoice-qty-0')), '12');
    await tester.pump();
    await next(tester); // quantities
    await next(tester); // due
    await next(tester); // memo

    await tester.tap(find.text('Corriger la facture'));
    await tester.pumpAndSettle();

    expect(invoicing.createCalled, isFalse);
    expect(invoicing.revisedInvoiceId, 'inv-1');
    expect(invoicing.revisedCustomer, 'Hôtel Liberté');
    expect(invoicing.revisedLines, hasLength(1));
    expect(invoicing.revisedLines!.single.quantity, 12);
    expect(saved, 'new-invoice-1');
    expect(find.byKey(const Key('invoice-another')), findsNothing,
        reason: 'a correction is one document, not a series');
  });
}
