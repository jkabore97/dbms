import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

  test('the home page itself names Mara and links both policies', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('<h1>Mara'));
    expect(html, contains('href="/confidentialite"'));
    expect(html, contains('href="/conditions"'));
  });
}
