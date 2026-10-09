import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/credit/credit_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/credit/credit_flows.dart';
import 'package:kaj_app/features/money/expense_flow.dart';
import 'package:kaj_app/features/retail/sale_flow.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Batch 115, W2: the carnet's « Nouveau crédit » and « Remboursement »,
/// and « Dépense » for a shop and a farm — one question a screen.
class _Credit extends CreditRepository {
  _Credit() : super(null);

  final sums = <Map<String, Object?>>[];
  final dues = <Map<String, Object?>>[];
  final repaid = <Map<String, Object?>>[];

  /// What set_debt_due answers for a sale: null while it is not there.
  String? saleDebt;

  @override
  Future<String> recordCreditSale({
    required String orgId,
    required String customerName,
    required double amount,
    required String label,
    String? customerPhone,
    String? category,
    String? clientUuid,
  }) async {
    sums.add({'customer': customerName, 'amount': amount, 'label': label,
        'phone': customerPhone, 'uuid': clientUuid});
    return 'debt-1';
  }

  @override
  Future<String?> setDue({
    required String orgId,
    required DateTime? dueOn,
    String? debtId,
    String? saleClientUuid,
  }) async {
    dues.add({'due': dueOn, 'debt': debtId, 'sale': saleClientUuid});
    return debtId ?? saleDebt;
  }

  @override
  Future<double> repay({
    required String orgId,
    required String customerId,
    required double amount,
    String method = 'cash',
    String? clientUuid,
  }) async {
    repaid.add({'customer': customerId, 'amount': amount, 'uuid': clientUuid});
    return 2500 - amount;
  }
}

OrgSummary _org(String profile) => OrgSummary(
      id: 'o-$profile',
      name: 'Chez $profile',
      slug: 'chez-$profile',
      profile: profile,
      currency: 'XOF',
      roles: const ['owner'],
      visibility: 'full',
    );

const _debtors = [
  DebtorRow(customerId: 'c-awa', name: 'Awa', totalOwed: 2500, phone: '+22670112233'),
  DebtorRow(customerId: 'c-ali', name: 'Ali', totalOwed: 900),
];

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  Future<void> pump(WidgetTester tester, Widget flow) async {
    tester.view.physicalSize = const Size(390, 1400);
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

  bool nextEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('flow-next'))).onPressed != null;

  DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  testWidgets('an association lends a sum: no « articles » question, the date set on its debt',
      (tester) async {
    final credit = _Credit();
    await pump(tester, NewCreditFlow(
        org: _org('association'), credit: credit,
        retail: RetailRepository(null), debtors: _debtors, store: MemoryFlowStore()));

    expect(nextEnabled(tester), isFalse);
    // A known customer: the chip fills the name, the number comes with it.
    await tester.tap(find.byKey(const Key('customer-known-Awa')));
    await tester.pumpAndSettle();
    await next(tester);
    expect(find.byKey(const Key('flow-step-phone')), findsOneWidget);
    expect(find.text('70112233'), findsOneWidget);
    await next(tester);
    // Straight to the sum: an association keeps no stock.
    expect(find.byKey(const Key('flow-step-amount')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('credit-amount')), '1500');
    await tester.pump();
    await next(tester);
    expect(nextEnabled(tester), isFalse, reason: 'what it is for is asked');
    await tester.enterText(find.byKey(const Key('credit-label')), 'Cotisation de mars');
    await tester.pump();
    await next(tester);
    await tester.tap(find.byKey(const Key('flow-option-days:7')));
    await tester.pump();
    await next(tester);

    expect(find.byKey(const Key('flow-summary')), findsOneWidget);
    await tester.tap(find.byKey(const Key('flow-save')));
    await tester.pumpAndSettle();

    expect(credit.sums.single['customer'], 'Awa');
    expect(credit.sums.single['amount'], 1500);
    expect(credit.sums.single['label'], 'Cotisation de mars');
    expect(credit.sums.single['phone'], '+22670112233');
    expect(credit.sums.single['uuid'], isNotNull);
    expect(credit.dues.single['debt'], 'debt-1');
    expect(credit.dues.single['due'], today().add(const Duration(days: 7)));
    expect(find.byKey(const Key('credit-remind')), findsOneWidget);
  });

  for (final profile in ['retail', 'farm']) {
    testWidgets('a $profile gives articles on credit: the Vente flow on Crédit, the date queued behind the sale',
        (tester) async {
      final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
      addTearDown(() => tester.runAsync(() => db!.close()));
      final credit = _Credit();
      await pump(tester, NewCreditFlow(
          org: _org(profile), credit: credit, retail: RetailRepository(null),
          db: db, debtors: _debtors, store: MemoryFlowStore()));

      await tester.enterText(find.byKey(const Key('customer-name')), 'Mariam');
      await tester.pump();
      await next(tester);
      await next(tester); // no number
      await tester.tap(find.byKey(const Key('flow-option-articles')));
      await tester.pump();
      await next(tester);
      // No sum, no label: the articles say what is owed.
      expect(find.byKey(const Key('flow-step-due')), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-option-days:30')));
      await tester.pump();
      await next(tester);
      expect(find.text('Choisir les articles'), findsOneWidget);

      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final sale = tester.widget<SaleFlow>(find.byType(SaleFlow));
      expect(sale.initialMethod, 'credit');
      expect(sale.customerName, 'Mariam');
      expect(sale.farm, profile == 'farm');

      // The sale is kept on the phone (no signal): its uuid comes back.
      sale.onSaved!('sale-uuid-1');
      Navigator.of(tester.element(find.byType(SaleFlow))).pop(true);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      expect(credit.sums, isEmpty, reason: 'no free-text debt beside the sale');
      expect(credit.dues.single['sale'], 'sale-uuid-1');
      final pending = await tester.runAsync(() => db!.pendingActions());
      expect(pending!.single['action'], 'set_debt_due');
      final payload = jsonDecode(pending.single['payload'] as String) as Map<String, dynamic>;
      expect(payload, {
        'p_org_id': 'o-$profile',
        'p_due_on': CreditRepository.day(today().add(const Duration(days: 30))),
        'p_sale_client_uuid': 'sale-uuid-1',
      });
      expect(find.byKey(const Key('flow-done')), findsOneWidget);
      expect(find.text('La date partira avec la vente, dès le retour du réseau.'), findsOneWidget);
    });
  }

  testWidgets('a repayment: who, how much (never past what is owed), Enregistrer', (tester) async {
    final credit = _Credit();
    await pump(tester, RepayFlow(
        org: _org('retail'), credit: credit, debtors: _debtors, store: MemoryFlowStore()));

    expect(nextEnabled(tester), isFalse);
    await tester.tap(find.byKey(const Key('repay-customer-c-awa')));
    await tester.pump();
    await next(tester);
    await tester.enterText(find.byKey(const Key('repay-amount')), '3000');
    await tester.pump();
    expect(nextEnabled(tester), isFalse, reason: 'more than Awa owes');
    expect(find.text('C\'est plus que ce qu\'il doit.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('repay-all')));
    await tester.pump();
    expect(nextEnabled(tester), isTrue);
    await next(tester);
    await tester.tap(find.byKey(const Key('flow-save')));
    await tester.pumpAndSettle();

    expect(credit.repaid.single['customer'], 'c-awa');
    expect(credit.repaid.single['amount'], 2500);
    expect(credit.repaid.single['uuid'], isNotNull);
    expect(find.text('Il ne doit plus rien.'), findsOneWidget);
  });

  testWidgets('opened from a customer\'s page, that customer is already chosen', (tester) async {
    final credit = _Credit();
    await pump(tester, RepayFlow(
        org: _org('association'), credit: credit, debtors: _debtors,
        customerId: 'c-ali', store: MemoryFlowStore()));
    expect(nextEnabled(tester), isTrue);
    await next(tester);
    expect(find.textContaining('Ali doit'), findsOneWidget);
  });

  for (final (profile, heading) in [('retail', 'Transport'), ('farm', 'Vétérinaire')]) {
    testWidgets('« Dépense » for a $profile: its own headings, written to the phone first',
        (tester) async {
      final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
      addTearDown(() => tester.runAsync(() => db!.close()));
      await pump(tester, ExpenseFlow(
          db: db!, orgId: 'o-$profile', profile: profile, store: MemoryFlowStore()));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('heading-$heading')), findsOneWidget);
      await tester.tap(find.byKey(Key('heading-$heading')));
      await tester.pump();
      await next(tester);
      await tester.enterText(find.byKey(const Key('expense-amount')), '7 500');
      await tester.pump();
      await next(tester);
      await tester.tap(find.byKey(const Key('flow-option-mobile_money')));
      await tester.pump();
      await next(tester);
      await next(tester); // no word
      expect(find.byKey(const Key('flow-summary')), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      final pending = await tester.runAsync(() => db.pendingActions());
      expect(pending!.single['action'], 'record_entry');
      final payload = jsonDecode(pending.single['payload'] as String) as Map<String, dynamic>;
      expect(payload['p_org_id'], 'o-$profile');
      expect(payload['p_direction'], 'out');
      expect(payload['p_amount'], 7500);
      expect(payload['p_label'], heading);
      expect(payload['p_category'], heading);
      expect(payload['p_method'], 'mobile_money');
      expect(find.byKey(const Key('flow-done')), findsOneWidget);
    });
  }
}
