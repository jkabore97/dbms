import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/l10n/en.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/features/academy/lessons.dart';
import 'package:kaj_app/features/setup/setup_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Every phrase the screens pass through context.tr() has its English, and
/// an English phone reads the screens in English.
class _A implements SetupActions {
  @override
  Future<void> rename(String o, String n, String c) async {}
  @override
  Future<void> addArticle(String o,
      {required String name, required double price, required double quantity}) async {}
  @override
  Future<void> saveVitrine(String o,
      {required bool open, required String blurb, required String phone, required String address}) async {}
  @override
  Future<void> savePosition(String o, double a, double b) async {}
  @override
  Future<void> finish(String o) async {}
}

void main() {
  test('every context.tr() phrase in lib/ has its English', () {
    final call = RegExp(r"context\.tr\(\s*'((?:[^'\\]|\\.)*)'");
    final entry = RegExp(r"^  '((?:[^'\\]|\\.)*)':", multiLine: true);
    final english = entry
        .allMatches(File('lib/core/l10n/en.dart').readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final m in call.allMatches(f.readAsStringSync())) {
        if (!english.contains(m.group(1))) missing.add('${f.path}: ${m.group(1)}');
      }
    }
    expect(missing, isEmpty, reason: 'add these to lib/core/l10n/en.dart');
  });

  test('every lesson, and every lesson the server seeds, has its English', () {
    final missing = <String>[];
    for (final script in lessonScripts.values) {
      for (final step in script.steps) {
        for (final s in [step.title, step.text, step.target]) {
          if (s != null && !enStrings.containsKey(s)) missing.add(s);
        }
      }
      final t = script.tryLabel;
      if (t != null && !enStrings.containsKey(t)) missing.add(t);
    }
    final sql = File('../database/migrations/087_academy.sql').readAsStringSync();
    for (final m in RegExp(r"\('\w+',\s*'((?:[^']|'')*)',\s*'(?:guide|mission)'").allMatches(sql)) {
      final title = m.group(1)!.replaceAll("''", "'");
      if (!enStrings.containsKey(title)) missing.add(title);
    }
    expect(missing, isEmpty);
  });

  test('placeholders are filled, an unknown phrase stays French', () {
    expect(translate('en', 'Votre vitrine : {score} %', {'score': 40}),
        'Your vitrine: 40 %');
    expect(translate('fr', 'Votre vitrine : {score} %', {'score': 40}),
        'Votre vitrine : 40 %');
    expect(translate('en', 'Une phrase pas encore traduite'),
        'Une phrase pas encore traduite');
  });

  testWidgets('an English phone reads the first setup in English', (tester) async {
    tester.view.physicalSize = const Size(480, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: SetupScreen(
          org: const OrgSummary(id: 'o', name: 'Awa', profile: 'retail', roles: ['owner']),
          actions: _A(),
          onDone: () {}),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Your shop'), findsOneWidget);
    expect(find.text('Getting started'), findsOneWidget);
    expect(find.text('Votre boutique'), findsNothing);
  });
}
