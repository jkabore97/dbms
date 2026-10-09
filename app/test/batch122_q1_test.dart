import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/features/home/activity_switch.dart';
import 'package:kaj_app/features/home/business_shell.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Batch 122, Q1: « Changer d'activité » for everybody who owns or runs a
/// business — several: the picker; one on Pro: a sheet to create the next;
/// one on Basic: why a second needs Mara Pro, with « Passer à Pro ».
void main() {
  OrgSummary org(String profile, {String plan = 'free', String role = 'owner'}) =>
      OrgSummary(
        id: 'o-$profile',
        name: 'Chez $profile',
        profile: profile,
        plan: plan,
        roles: [role],
      );

  const kinds = ['retail', 'farm', 'association'];

  group('the rule', () {
    for (final k in kinds) {
      test('$k: several → the picker, owner or staff', () {
        expect(ActivitySwitch.modeFor(activities: 2, org: org(k)), ActivitySwitchMode.picker);
        expect(ActivitySwitch.modeFor(activities: 3, org: org(k, role: 'employee')),
            ActivitySwitchMode.picker);
      });
      test('$k: one, a second open → create', () {
        expect(ActivitySwitch.modeFor(activities: 1, org: org(k, plan: 'pro'), secondLocked: false),
            ActivitySwitchMode.create);
        // The server's own answer wins over the plan read here.
        expect(ActivitySwitch.modeFor(activities: 1, org: org(k), secondLocked: false),
            ActivitySwitchMode.create);
      });
      test('$k: one, a second locked → Pro', () {
        expect(ActivitySwitch.modeFor(activities: 1, org: org(k), secondLocked: true),
            ActivitySwitchMode.pro);
        expect(ActivitySwitch.modeFor(activities: 1, org: org(k, plan: 'pro'), secondLocked: true),
            ActivitySwitchMode.pro);
        expect(ActivitySwitch.modeFor(activities: 1, org: org(k, role: 'admin'), secondLocked: true),
            ActivitySwitchMode.pro);
      });
      test('$k: one, the server\'s lock not known yet → nothing, never « needs Pro »', () {
        expect(ActivitySwitch.modeFor(activities: 1, org: org(k)), ActivitySwitchMode.none);
        expect(ActivitySwitch.modeFor(activities: 1, org: org(k, plan: 'pro')), ActivitySwitchMode.none);
        expect(ActivitySwitch.modeFor(activities: 2, org: org(k)), ActivitySwitchMode.picker,
            reason: 'several: the picker needs no lock');
      });
      test('$k: one, only working in it → nothing', () {
        expect(ActivitySwitch.modeFor(activities: 1, org: org(k, role: 'employee')),
            ActivitySwitchMode.none);
        expect(ActivitySwitch.modeFor(activities: 1, org: org(k), platformAdmin: true),
            ActivitySwitchMode.none);
      });
    }
  });

  group('the button and its sheet', () {
    Future<void> pump(WidgetTester tester, OrgSummary o, ActivitySwitchMode mode,
        {int activities = 1}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            appBar: AppBar(actions: [
              SwitchActivityButton(activities: activities, mode: mode, org: o),
            ]),
          ),
        ),
        GoRoute(path: '/entreprises', builder: (_, _) => const Text('le sélecteur')),
        GoRoute(path: '/creer-mon-activite', builder: (_, _) => const Text('la création')),
        GoRoute(
            path: '/o/:id/kaj-pro',
            builder: (_, s) => Text('pro de ${s.pathParameters['id']}')),
      ]);
      await tester.pumpWidget(MaterialApp.router(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        routerConfig: router,
      ));
      await tester.pumpAndSettle();
    }

    for (final k in kinds) {
      testWidgets('$k, several: the picker as before', (tester) async {
        await pump(tester, org(k), ActivitySwitchMode.picker, activities: 2);
        await tester.tap(find.byKey(const Key('switch-activity')));
        await tester.pumpAndSettle();
        expect(find.text('le sélecteur'), findsOneWidget);
      });

      testWidgets('$k, one on Pro: the sheet, then the creation', (tester) async {
        final o = org(k, plan: 'pro');
        await pump(tester, o, ActivitySwitchMode.create);
        await tester.tap(find.byKey(const Key('switch-activity')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('activity-sheet')), findsOneWidget);
        expect(find.byKey(Key('activity-current-${o.id}')), findsOneWidget);
        expect(find.text(o.name), findsOneWidget);
        expect(find.byKey(const Key('activity-needs-pro')), findsNothing);
        expect(find.text('Créer une nouvelle activité'), findsOneWidget);
        await tester.tap(find.byKey(const Key('activity-create')));
        await tester.pumpAndSettle();
        expect(find.text('la création'), findsOneWidget);
      });

      testWidgets('$k, one on Basic: why, and « Passer à Pro » opens Pro', (tester) async {
        final o = org(k);
        await pump(tester, o, ActivitySwitchMode.pro);
        await tester.tap(find.byKey(const Key('switch-activity')));
        await tester.pumpAndSettle();
        expect(find.text('Une deuxième activité demande Mara Pro'), findsOneWidget);
        expect(find.byKey(const Key('activity-create')), findsNothing);
        final go = find.byKey(const Key('activity-go-pro'));
        expect(tester.widget<FilledButton>(go).onPressed, isNotNull, reason: 'never a dead button');
        await tester.tap(go);
        await tester.pumpAndSettle();
        expect(find.text('pro de ${o.id}'), findsOneWidget);
      });

      testWidgets('$k, staff of one: no button', (tester) async {
        await pump(tester, org(k, role: 'employee'), ActivitySwitchMode.none);
        expect(find.byKey(const Key('switch-activity')), findsNothing);
      });
    }
  });
}
