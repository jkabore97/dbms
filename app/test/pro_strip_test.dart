import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/features/pro/pro_plans_screen.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/features/pro/pro_strip.dart';

/// The small « Pro » at the top of every page of a business not on Kaj Pro,
/// for whoever can change that, and the page it opens.
const _owner = OrgSummary(
  id: 'o1',
  name: 'Elim Shop',
  profile: 'retail',
  roles: ['owner'],
);
const _clerk = OrgSummary(
  id: 'o1',
  name: 'Elim Shop',
  profile: 'retail',
  roles: ['employee'],
);
const _pro = OrgSummary(
  id: 'o1',
  name: 'Elim Shop',
  profile: 'retail',
  roles: ['owner'],
  plan: 'pro',
);

void main() {
  Future<void> pump(WidgetTester tester, OrgSummary org) async {
    final router = GoRouter(
      initialLocation: '/o/o1/produits',
      routes: [
        GoRoute(
          path: '/o/:id/produits',
          builder: (_, _) => ProStrip(
            org: org,
            child: Scaffold(appBar: AppBar(title: const Text('Articles'))),
          ),
        ),
        GoRoute(
          path: '/o/:id/kaj-pro',
          builder: (_, _) => const Scaffold(body: Text('page Mara Pro')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('the owner of a Free business sees it over every page, and it '
      'opens Mara and Mara Pro side by side', (tester) async {
    await pump(tester, _owner);
    expect(find.byKey(const Key('pro-pill')), findsOneWidget);
    expect(find.text('PRO'), findsOneWidget);
    expect(
      find.text('Articles'),
      findsOneWidget,
      reason: 'the page is still all there, under the strip',
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('pro-pill'))).dy,
      lessThan(tester.getTopLeft(find.text('Articles')).dy),
    );
    await tester.tap(find.byKey(const Key('pro-pill')));
    await tester.pumpAndSettle();
    expect(find.text('page Mara Pro'), findsOneWidget);
  });

  testWidgets('an employee, or a Pro business, sees no strip', (tester) async {
    await pump(tester, _clerk);
    expect(find.byKey(const Key('pro-pill')), findsNothing);
    await pump(tester, _pro);
    expect(find.byKey(const Key('pro-pill')), findsNothing);
  });

  test('the comparison reads the platform\'s terms', () {
    const terms = PlanTerms(
      freeMaxStaff: 2,
      proFeatures: ['delivery', 'analytics'],
    );
    final rows = {
      for (final (title, list) in ProPlansScreenRows.of(terms)) title: list,
    };
    expect(rows['Avec Mara Pro']!.map((r) => r.label), [
      PlanTerms.labelOf('delivery'),
      PlanTerms.labelOf('analytics'),
    ]);
    final staff = rows['Sans limite']!.first;
    expect(staff.free, '2');
    expect(staff.pro, 'Illimité');
    expect(
      rows['Pour tous']!.every((r) => r.free == true && r.pro == true),
      isTrue,
    );
  });
}
