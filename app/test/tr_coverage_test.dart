import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/errors.dart';
import 'package:kaj_app/core/l10n/tr.dart';
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

  test('no raw French sentence is handed straight to a widget (122)', () {
    // A heuristic, not a parser: a literal right after Text(, a field's
    // label, hint, helper or error, a tooltip or a semantic label, that
    // reads as French (an accent, a guillemet, or one of French's small
    // words), and is not passed through context.tr(). What is French on
    // purpose (a language named in itself, a person's own quoted note)
    // is allowed by name below.
    final at = RegExp(r"(?:\bText\(|labelText:|hintText:|helperText:|errorText:|"
        r"tooltip:|semanticLabel:|\bhint:|barrierLabel:|ShopSectionLabel\(|helpText:)"
        r"\s*'((?:[^'\\\n]|\\.)*)'");
    final french = RegExp(
        r"[àâçéèêëîïôûùüœÀÂÇÉÈÊÔ«»]|\b(le|la|les|des|du|une|et|pour|avec|sur|dans|vos|votre|aucun|aucune|pas|est|sont)\b",
        caseSensitive: false);
    const allowed = {
      'Français', // the language's own name, on the language choice
      '« \${r.note} »', // a person's own words, quoted
    };
    final raw = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart') || f.path.contains('/l10n/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        for (final m in at.allMatches(lines[i])) {
          final text = m.group(1)!;
          if (french.hasMatch(text) && !allowed.contains(text)) {
            raw.add('${f.path}:${i + 1}: $text');
          }
        }
      }
    }
    expect(raw, isEmpty, reason: 'wrap these in context.tr() and add their English');
  });

  test('every word Le Chemin (097) sends has its English', () {
    // The steps' titles and lines, the stage names, the cauris rules (084)
    // and the history's own labels: French from the server, put through
    // translate() by the app. Those with a number in them ({min},
    // {referral}) are said by the app from the step's key instead.
    final english = RegExp(r"^  '((?:[^'\\]|\\.)*)':", multiLine: true)
        .allMatches(File('lib/core/l10n/en.dart').readAsStringSync())
        .map((m) => m.group(1)!.replaceAll("\\'", "'"))
        .toSet();
    final sql = File('../database/migrations/097_le_chemin.sql').readAsStringSync();
    final token = RegExp(r"'((?:[^']|'')*)'|null|array\[[^\]]*\]|-?\d+|[()]");
    List<List<String?>> rows(String block) {
      final out = <List<String?>>[];
      List<String?>? row;
      for (final m in token.allMatches(block)) {
        final t = m.group(0)!;
        if (t == '(') {
          row = [];
        } else if (t == ')') {
          if (row != null) out.add(row);
          row = null;
        } else {
          row?.add(m.group(1)?.replaceAll("''", "'"));
        }
      }
      return out;
    }

    String between(String text, String from, String to) {
      final i = text.indexOf(from);
      expect(i, isNot(-1), reason: 'no « $from »');
      return text.substring(i + from.length, text.indexOf(to, i));
    }

    final words = <String>{};
    final steps = rows(between(sql, 'insert into path_steps', 'on conflict (key)'));
    expect(steps.length, greaterThanOrEqualTo(17), reason: 'the 097 steps were not read');
    for (final r in steps.skip(1)) {
      // key, stage, sort, profiles, title, title_farm, line, line_farm, …
      for (final s in [r[4], r[5], r[6], r[7]]) {
        if (s != null && !s.contains('{')) words.add(s);
      }
    }
    final stages = RegExp(r"array\['Ouvrir'[^\]]*\]").firstMatch(sql)!.group(0)!;
    words.addAll(RegExp(r"'([^']+)'").allMatches(stages).map((m) => m.group(1)!));
    final history = between(sql, "'label', coalesce(r.label, case l.reason", 'else l.reason end');
    words.addAll(RegExp(r"then '((?:[^']|'')*)'")
        .allMatches(history)
        .map((m) => m.group(1)!.replaceAll("''", "'")));
    final rules = File('../database/migrations/084_cauris.sql').readAsStringSync();
    for (final r in rows(between(rules,
        'insert into cauris_rules (key, points, daily_cap, label, sort) values', 'on conflict'))) {
      if (r.length == 5 && r[3] != null) words.add(r[3]!);
    }
    expect(words, contains('Remplir'));
    expect(words, contains('Mon cahier de la ferme'));
    expect(words, contains('Étape du chemin'));
    final missing = [for (final w in words) if (!english.contains(w)) w];
    expect(missing, isEmpty, reason: 'add these to lib/core/l10n/en.dart');
  });

  test('a tool still locked is said by the app, in English too', () {
    expect(
        pathLockText('en', 'Factures : 8 articles en vente et 3 en photo pour les débloquer.'),
        'Invoices: 8 items for sale and 3 with a photo to unlock them.');
    expect(pathLockText('fr', 'Carnet de crédit : 3 commandes terminées pour le débloquer.'),
        'Carnet de crédit : 3 commandes terminées pour le débloquer.');
    expect(pathLockText('en', 'Production : terminez l\'étape Remplir pour la débloquer.'),
        'Production: finish the Fill stage to unlock it.');
    expect(pathLockText('en', 'Autre chose.'), isNull);
  });

  test('placeholders are filled, an unknown phrase stays French', () {
    expect(translate('en', 'Étape {n} sur 4 · {title}', {'n': 2, 'title': 'Fill'}),
        'Stage 2 of 4 · Fill');
    expect(translate('fr', 'Étape {n} sur 4 · {title}', {'n': 2, 'title': 'Remplir'}),
        'Étape 2 sur 4 · Remplir');
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
