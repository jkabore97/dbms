import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/errors.dart';
import 'package:kaj_app/core/l10n/en.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tr_literals.dart';

/// The product is Marakaj (147). No screen says « Mara » any more, and a
/// sentence a server wrote before the change is read with the new name.
void main() {
  // « Mara » as a word, in any case: not « Marakaj », not « marakaj.com »,
  // not « Maraîchage », not an identifier's part (« mara-header »,
  // « mara_seal.webp », « mara.visitor_id »). Dart's \b is ASCII-only, so
  // the word's ends are spelt out.
  final oldName = RegExp(r'(?<![\wÀ-ÿ\-/])(?<!\w\.)mara(?![\wÀ-ÿ\-_/])(?!\.\w)', caseSensitive: false);

  // Literals that are identifiers on purpose, not words anyone reads.
  const allowed = {
    'lib/core/theme/kaj_theme.dart': {'mara'}, // the default palette's stored key
    'lib/features/admin/fiche/fiche_journal_tab.dart': {'mara'}, // a segment's value
    'lib/core/l10n/tr.dart': {r'(?<![\wÀ-ÿ])Mara(?![\wÀ-ÿ])'}, // the old name, to read it
  };

  test('no word of en.dart, French or English, says « Mara »', () {
    final hits = <String>[
      for (final e in enStrings.entries)
        if (oldName.hasMatch(e.key) || oldName.hasMatch(e.value)) '${e.key} → ${e.value}',
    ];
    expect(hits, isEmpty);
  });

  test('no string literal in lib/ says « Mara »', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll('\\', '/');
      for (final l in literals(f.readAsStringSync())) {
        if (!oldName.hasMatch(l.text)) continue;
        if (allowed[path]?.contains(l.text) ?? false) continue;
        hits.add('$path:${l.line}: ${l.text}');
      }
    }
    expect(hits, isEmpty);
  });

  test('the test itself sees the old name where it is', () {
    expect(oldName.hasMatch('Bienvenue sur Mara'), isTrue);
    expect(oldName.hasMatch('AVEC MARA PRO'), isTrue);
    expect(oldName.hasMatch('Mara\'s share'), isTrue);
    expect(oldName.hasMatch('écrivez à Mara.'), isTrue);
    expect(oldName.hasMatch('« Mara »'), isTrue);
    expect(oldName.hasMatch('Bienvenue sur Marakaj'), isFalse);
    expect(oldName.hasMatch('https://marakaj.com/s/awa'), isFalse);
    expect(oldName.hasMatch('Maraîchage'), isFalse);
    expect(oldName.hasMatch('assets/brand/mara_seal.webp'), isFalse);
    expect(oldName.hasMatch('mara-header'), isFalse);
  });

  group('a server from before 147', () {
    test('its labels read with the new name, in both languages', () {
      expect(translate('fr', 'Cadeau de Mara'), 'Cadeau de Marakaj');
      expect(translate('en', 'Cadeau de Mara'), 'A gift from Marakaj');
      expect(translate('en', 'Mara Pro complet'), enStrings['Marakaj Pro complet']);
      // The new server's own words are used as they are.
      expect(translate('en', 'Cadeau de Marakaj'), 'A gift from Marakaj');
      // Not the name: left alone.
      expect(translate('fr', 'Maraîchage'), 'Maraîchage');
      expect(oldNameText('Marakaj a traité « Chez Mara »'), 'Marakaj a traité « Chez Mara »');
    });

    test('its refusals and bells say Marakaj, and a Pro refusal still opens Pro', () {
      expect(brandText('Mara a arrêté votre mise en avant.'), 'Marakaj a arrêté votre mise en avant.');
      expect(brandText('Kaj Pro est actif. Kaj Consulting vous remercie.'),
          'Marakaj Pro est actif. Kaj Consulting vous remercie.');
      const old = PostgrestException(message: 'Mara Pro : la livraison fait partie de Pro.');
      const now = PostgrestException(message: 'Marakaj Pro : la livraison fait partie de Pro.');
      const older = PostgrestException(message: 'Kaj Pro : la livraison fait partie de Pro.');
      for (final e in [old, now, older]) {
        expect(isProRefusal(e), isTrue, reason: e.message);
      }
      expect(describeError(old), 'Marakaj Pro : la livraison fait partie de Pro.');
    });
  });
}
