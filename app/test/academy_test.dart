import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/academy/academy_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/features/academy/academy_screen.dart';
import 'package:kaj_app/features/academy/lessons.dart';

/// Académie Mara (087): the level and the lessons, a guide played to its
/// end and paid, a mission refused until it is lived.
class _Academy extends AcademyRepository {
  _Academy({this.lived = false}) : super(null);

  final bool lived;
  final done = <String>[];

  @override
  Future<Academy?> mine(String orgId) async => Academy.fromJson({
        'level': done.isEmpty ? 'Apprenti' : 'Commerçant',
        'done': done.length,
        'total': 3,
        'cauris_each': 10,
        'lessons': [
          {'key': 'welcome', 'title': 'Bienvenue sur Mara', 'kind': 'guide',
           'minutes': 1, 'done': done.contains('welcome'), 'ready': false},
          {'key': 'first_sale', 'title': 'Faire sa première vente', 'kind': 'mission',
           'minutes': 2, 'done': done.contains('first_sale'), 'ready': lived},
          {'key': 'cauris', 'title': 'Les cauris', 'kind': 'guide',
           'minutes': 1, 'done': false, 'ready': false},
        ],
      });

  @override
  Future<({bool done, int earned})> complete(String orgId, String lesson) async {
    if (lesson == 'first_sale' && !lived) return (done: false, earned: 0);
    done.add(lesson);
    return (done: true, earned: 10);
  }
}

const _org = OrgSummary(
    id: 'o1', name: 'Delta', profile: 'retail', roles: ['owner'], slug: 'delta');

void main() {
  Future<void> open(WidgetTester tester, _Academy a) async {
    tester.view.physicalSize = const Size(500, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AcademyScreen(org: _org, academy: a)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('the level and the lessons, a lived mission glowing', (tester) async {
    await open(tester, _Academy(lived: true));
    expect(find.byKey(const Key('academy-level')), findsOneWidget);
    expect(find.text('Apprenti'), findsOneWidget);
    expect(find.text('0 leçon sur 3 · Apprenti › Commerçant › Maître'), findsOneWidget);
    expect(find.byKey(const Key('lesson-welcome')), findsOneWidget);
    expect(find.text('Mission réussie : touchez pour la valider'), findsOneWidget);
    expect(find.text('Guide · 1 min'), findsNWidgets(2));
  });

  testWidgets('a guide played to its end pays, and the level climbs', (tester) async {
    final a = _Academy();
    await open(tester, a);
    await tester.tap(find.byKey(const Key('lesson-welcome')));
    await settle(tester);
    expect(find.byKey(const Key('lesson-pages')), findsOneWidget);
    final steps = lessonScripts['welcome']!.steps;
    expect(find.text(steps.first.text), findsOneWidget);
    for (var i = 1; i < steps.length; i++) {
      await tester.tap(find.byKey(const Key('lesson-next')));
      await settle(tester);
      expect(find.text(steps[i].text), findsOneWidget);
    }
    expect(find.byKey(const Key('lesson-hand')), findsNothing,
        reason: 'the last welcome step has nothing to tap');
    await tester.tap(find.byKey(const Key('lesson-finish')));
    await settle(tester);
    expect(find.text('Bravo ! +10 cauris pour votre entreprise.'), findsOneWidget);
    expect(a.done, ['welcome']);

    await tester.pageBack();
    await settle(tester);
    expect(find.text('Commerçant'), findsOneWidget);
  });

  testWidgets('a mission is refused until it is lived', (tester) async {
    final a = _Academy();
    await open(tester, a);
    await tester.tap(find.byKey(const Key('lesson-first_sale')));
    await settle(tester);
    expect(find.byKey(const Key('lesson-hand')), findsOneWidget,
        reason: 'the hand shows where to tap');
    for (var i = 1; i < lessonScripts['first_sale']!.steps.length; i++) {
      await tester.tap(find.byKey(const Key('lesson-next')));
      await settle(tester);
    }
    expect(find.byKey(const Key('lesson-try')), findsOneWidget);
    expect(find.text('Aller à la caisse'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lesson-finish')));
    await settle(tester);
    expect(
        find.text('Pas encore : faites-le d\'abord dans l\'application, puis revenez.'),
        findsOneWidget);
    expect(a.done, isEmpty);
  });

  test('every lesson the server seeds has its pictures here', () {
    final sql = File('../database/migrations/087_academy.sql').readAsStringSync();
    final keys = RegExp(r"^\s*\('([a-z_]+)',", multiLine: true)
        .allMatches(sql)
        .map((m) => m.group(1)!)
        .toSet();
    expect(keys, isNotEmpty);
    expect(keys.difference(lessonScripts.keys.toSet()), isEmpty);
  });
}
