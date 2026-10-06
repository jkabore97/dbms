import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/features/cauris/path_card.dart';
import 'package:kaj_app/features/cauris/unlock_sheet.dart';
import 'package:kaj_app/features/pro/pro_plans_screen.dart';

/// Cauris buy Pro tools; Basic opens step by step (085).
class _Admin extends AdminRepository {
  _Admin() : super(null);
  final spent = <String>[];

  @override
  Future<DateTime?> spendCauris(String orgId, String feature) async {
    spent.add(feature);
    return DateTime(2026, 11, 5);
  }
}

const _owner = OrgSummary(id: 'o1', name: 'Elim Shop', profile: 'retail', roles: ['owner']);
const _clerk = OrgSummary(id: 'o1', name: 'Elim Shop', profile: 'retail', roles: ['employee']);

FeatureStates _states({int balance = 260}) => FeatureStates.fromJson({
      'plan': 'free',
      'balance': balance,
      'tools': [
        {'feature': 'analytics', 'cost': 400},
        {'feature': 'accounting', 'cost': 500, 'waits_days': 41},
        {'feature': 'pro_all', 'cost': 1500},
      ],
      'progress': {
        'gated': true, 'in_trial': false, 'score': 67, 'orders': 3,
        'street_pct': 60, 'tools_pct': 90, 'orders_needed': 10, 'on_street': true,
      },
    });

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Future<void> sheet(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    await tester.pump();
  }

  testWidgets('short of cauris: says how many more, and the button waits',
      (tester) async {
    final admin = _Admin();
    await sheet(tester, UnlockSheet(
        org: _owner, feature: 'analytics', states: _states(), admin: admin));
    expect(find.byKey(const Key('unlock-missing')), findsOneWidget);
    expect(find.text(' — encore 140 à gagner'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('unlock-buy'))).onPressed,
        isNull);
    expect(find.byKey(const Key('unlock-earn')), findsOneWidget);
    expect(find.byKey(const Key('unlock-pro')), findsOneWidget);
  });

  testWidgets('enough cauris: one tap opens it for 30 days, and the session '
      'is told', (tester) async {
    final admin = _Admin();
    var reloaded = 0;
    await sheet(tester, UnlockSheet(
        org: _owner, feature: 'analytics', states: _states(balance: 500),
        admin: admin, onUnlocked: () async => reloaded++));
    await tester.tap(find.byKey(const Key('unlock-buy')));
    await tester.pump();
    await tester.pump();
    expect(admin.spent, ['analytics']);
    expect(reloaded, 1);
    expect(find.byKey(const Key('unlocked')), findsOneWidget);
    expect(find.textContaining('Ouvert jusqu\'au 5 novembre'), findsOneWidget);
  });

  testWidgets('a tool that waits for days, or an employee: no purchase',
      (tester) async {
    await sheet(tester, UnlockSheet(
        org: _owner, feature: 'accounting', states: _states(balance: 900),
        admin: _Admin()));
    expect(find.textContaining('dans 41 jours'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('unlock-buy'))).onPressed,
        isNull);
    await sheet(tester, UnlockSheet(
        org: _clerk, feature: 'analytics', states: _states(balance: 900),
        admin: _Admin()));
    expect(find.textContaining('Le propriétaire ou un administrateur'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('unlock-buy'))).onPressed,
        isNull);
  });

  testWidgets('the grey badge says PRO and its price', (tester) async {
    await sheet(tester, const ProCostBadge(cost: 400));
    expect(find.text('PRO'), findsOneWidget);
    expect(find.text('400'), findsOneWidget);
  });

  test('the comparison prices each Pro tool in cauris in the Free column', () {
    final rows = ProPlansScreenRows.of(
        const PlanTerms(proFeatures: ['analytics', 'payroll']),
        costs: const {'analytics': 400});
    final pro = rows[1].$2;
    expect((pro[0].free as CaurisPrice).cost, 400);
    expect(pro[1].free, isNull, reason: 'no price, no lock');
  });

  test('the Basic path: 90 % opens the tools, 10 orders a second business, '
      'the trial opens everything, an old business is not gated', () {
    final p = _states().progress;
    expect(p.locks('invoices'), isTrue);
    expect(p.locks('production'), isTrue);
    expect(p.locks('credits'), isTrue);
    expect(p.locks('second_business'), isTrue);
    expect(p.locks('payroll'), isFalse, reason: 'not a Basic path tool');
    expect(p.needFor('second_business'), '3 commandes terminées sur 10');
    expect(const BasicProgress(gated: true, inTrial: true, score: 10).locks('invoices'),
        isFalse);
    expect(const BasicProgress(gated: false, score: 10).locks('invoices'), isFalse);
    expect(const BasicProgress(gated: true, score: 100, orders: 12).locks('credits'),
        isFalse);
  });

  testWidgets('the path card fills and says what each step opens',
      (tester) async {
    await sheet(tester, PathCard(org: _owner, progress: _states().progress));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('67 %'), findsOneWidget);
    expect(find.textContaining('60 % : votre vitrine sur le marché'), findsOneWidget);
    expect(find.textContaining('90 % : reçus et factures'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget, reason: 'the street');
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
    await sheet(tester, PathCard(
        org: _owner,
        progress: BasicProgress(gated: true, inTrial: true, score: 20,
            trialUntil: DateTime(2026, 10, 13))));
    expect(find.text('Essai : tout est ouvert jusqu\'au 13 octobre.'), findsOneWidget);
  });
}
