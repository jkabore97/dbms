import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/errors.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/features/setup/setup_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

import 'tr_literals.dart';

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

  // French's marks: an accent, a guillemet, or one of its small words.
  final french = RegExp(
      r"[àâçéèêëîïôûùüœÀÂÇÉÈÊÔ«»]|\b(le|la|les|des|du|une|un|et|pour|avec|sur|dans|vos|votre|aucun|aucune|pas|est|sont|au|aux|en|de|mes|mon|vous|ce|cette)\b",
      caseSensitive: false);
  // A literal passed to context.tr() / translate() is the key, not raw.
  final viaTr = RegExp(r"(\btr|\btranslate)\(\s*(\w+,\s*)?$");
  // What is French on purpose, allowed by name (the literal's words, every
  // interpolation a space): a language named in itself, a person's own
  // quoted note, the brand, an address.
  const allowed = {
    'Français', // the language's own name, on the language choice
    '«   »', // a person's own words, quoted
    '  ·  ©   Mara', // the footer: the year and the brand
    'Mara ·  ', // a printed report's foot: the brand and the date
    'marakaj.com/s/ ', // a vitrine's address
    'Durée :  ', // a service's description, stored in the vitrine's language
  };
  Iterable<(String, Literal)> all() sync* {
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart') || f.path.contains('/l10n/')) continue;
      for (final l in literals(f.readAsStringSync())) {
        if (!viaTr.hasMatch(l.before) && !allowed.contains(l.text)) yield (f.path, l);
      }
    }
  }

  test('no raw French sentence is handed straight to a widget (122)', () {
    // A heuristic, not a parser: a literal (single or double quotes, joined
    // with the ones next to it) right after Text(, a tab's or a span's
    // text, a field's label, hint, helper or error, a tooltip or a semantic
    // label, that reads as French and is not passed through context.tr().
    final at = RegExp(r"(?:\bText\(|\btext:|labelText:|hintText:|helperText:|errorText:|"
        r"tooltip:|semanticLabel:|\bhint:|barrierLabel:|ShopSectionLabel\(|helpText:)\s*$");
    final raw = [
      for (final (path, l) in all())
        if (at.hasMatch(l.before) && french.hasMatch(l.text)) '$path:${l.line}: ${l.text}',
    ];
    expect(raw, isEmpty, reason: 'wrap these in context.tr() and add their English');
  });

  test('no French built around a value — « Valeur : \${x} », « \$n en jeu » (122)', () {
    // An interpolated literal cannot be a key of en.dart: it reaches the
    // screen in French whatever the language. Caught: one that reads as
    // French anywhere, and any word at all where a widget shows it.
    final shown = RegExp(r"(?:\bText\(|\btext:|labelText:|hintText:|helperText:|errorText:|"
        r"tooltip:|semanticLabel:|\bhint:|\blabel:|\btitle:|\bsubtitle:|\bmessage:|"
        r"\bdescription:|ShopSectionLabel\()\s*$");
    final word = RegExp(r"[A-Za-zÀ-ÿ]{3,}");
    final raw = [
      for (final (path, l) in all())
        if (l.interpolated &&
            (french.hasMatch(l.text) || (shown.hasMatch(l.before) && word.hasMatch(l.text))))
          '$path:${l.line}: ${l.text}',
    ];
    expect(raw, isEmpty,
        reason: "say these as context.tr('… {x} …', {'x': …}) and add their English");
  });

  test('the literal reader sees through interpolation, quotes and comments', () {
    final ls = literals(r'''
// Text('Commentaire ignoré')
Text('Valeur : ${money.format(v, 'XOF')}');
x = "Rien d'autre" 'ici $n';
y = context.tr('{n} en stock', {'n': n});
''');
    expect([for (final l in ls) (l.line, l.text, l.interpolated)], [
      (2, 'Valeur :  ', true),
      (3, "Rien d'autreici  ", true),
      (4, '{n} en stock', false),
      (4, 'n', false),
    ]);
    expect(ls.first.before, endsWith('Text('));
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
