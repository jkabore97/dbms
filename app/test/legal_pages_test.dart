import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The privacy policy and the terms live twice: in the app's own screens,
/// and as plain pages the site serves to readers that run no JavaScript
/// (Google's verification of the sign-in screen reads those). The two must
/// say the same thing, paragraph for paragraph.
void main() {
  // The Dart screens' text, with adjacent literals joined and escapes read.
  String dartText() {
    final src = File('lib/features/account/legal_screens.dart').readAsStringSync();
    return src
        .replaceAll(RegExp(r"'\s*\n\s*'"), '')
        .replaceAll(r"\'", "'");
  }

  // The worker's paragraphs, in order.
  List<String> jsBlocks(String name) {
    final src = File('../workers/kaj-app/src/legal.js').readAsStringSync();
    final start = src.indexOf('export const $name');
    final end = src.indexOf('};', start);
    return RegExp(r'^\s*"(.*)",$', multiLine: true)
        .allMatches(src.substring(start, end))
        .map((m) => m.group(1)!)
        .where((b) => !b.startsWith('title'))
        .toList();
  }

  for (final doc in ['PRIVACY', 'TERMS']) {
    test('$doc: every paragraph of the site page is in the app, and back', () {
      final dart = dartText();
      final blocks = jsBlocks(doc);
      expect(blocks, isNotEmpty);
      for (final b in blocks) {
        expect(dart.contains("'$b'"), isTrue, reason: 'missing in the app: $b');
      }
    });
  }

  test('the app screens have no paragraph the site lacks', () {
    final dart = dartText();
    final all = {...jsBlocks('PRIVACY'), ...jsBlocks('TERMS')};
    final privacy = dart.substring(
        dart.indexOf('class PrivacyScreen'), dart.indexOf('class FaqScreen'));
    for (final m in RegExp(r"^\s*'(.+)',$", multiLine: true).allMatches(privacy)) {
      expect(all.contains(m.group(1)), isTrue,
          reason: 'missing on the site: ${m.group(1)}');
    }
  });

  // « Aide Mara » (/aide, workers/kaj-app/src/help.js) answers a few of the
  // app's questions, French with the English under each: the same words
  // as FaqScreen and en.dart.
  test('the site\'s help page asks the app\'s own questions, in both languages', () {
    final src = File('../workers/kaj-app/src/help.js').readAsStringSync();
    final faq = src.substring(src.indexOf('export const FAQ'), src.indexOf('];', src.indexOf('export const FAQ')));
    final strings = RegExp(r'^\s*"(.*)",$', multiLine: true).allMatches(faq).map((m) => m.group(1)!).toList();
    expect(strings.length, inInclusiveRange(20, 24), reason: '5 to 6 questions, four lines each');
    final dart = dartText();
    final screen = dart.substring(dart.indexOf('class FaqScreen'));
    for (var i = 0; i < strings.length; i += 4) {
      final (q, a, qEn, aEn) = (strings[i], strings[i + 1], strings[i + 2], strings[i + 3]);
      expect(screen.contains("context.tr('# $q')"), isTrue, reason: 'not an app question: $q');
      expect(screen.contains("context.tr('$a')"), isTrue, reason: 'not an app answer: $a');
      expect(translate('en', '# $q'), '# $qEn', reason: q);
      expect(translate('en', a), aEn, reason: a);
    }
  });

  test('the home page itself names Mara and links both policies', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('<h1>Mara'));
    expect(html, contains('href="/confidentialite"'));
    expect(html, contains('href="/conditions"'));
  });
}
