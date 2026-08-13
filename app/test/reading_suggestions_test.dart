import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/capture/text_reader.dart';

/// What the phone thought it saw, turned into a filled-in form.
///
/// This is the only testable half of OCR — the recognition itself needs a
/// camera and a device — and it is also the half that will be wrong in ways
/// nobody predicted. The intended way to fix a bad reading is to paste the
/// real label that failed in here as a case.
///
/// One rule runs through all of it: **when in doubt, offer nothing.** A blank
/// box costs one person ten seconds. A wrong price accepted with one tap costs
/// a shop money for as long as nobody notices, and a wrong expiry date is the
/// exact loss the retail module exists to prevent.
void main() {
  group('nothing at all', () {
    test('an empty reading suggests nothing', () {
      expect(ReadingSuggestions.parse(null).isEmpty, isTrue);
      expect(ReadingSuggestions.parse('').isEmpty, isTrue);
      expect(ReadingSuggestions.parse('   \n \n ').isEmpty, isTrue);
    });
  });

  group('the name', () {
    test('is the longest line that is mostly letters', () {
      final s = ReadingSuggestions.parse(
        'NESTLE\nLAIT CONCENTRE SUCRE\n397 G\n6001234567890',
      );
      expect(s.name, 'LAIT CONCENTRE SUCRE');
    });

    test('skips the lines a label prints about itself', () {
      // "PRIX", "EXP", "LOT" and friends are longer than the product name on
      // plenty of labels, and none of them is what the thing is called.
      final s = ReadingSuggestions.parse(
        'Savon\nPRIX DE VENTE CONSEILLE\nLOT 22841\n',
      );
      expect(s.name, 'Savon');
    });

    test('ignores lines that are mostly digits', () {
      final s = ReadingSuggestions.parse('123 456 789 012\nRiz');
      expect(s.name, 'Riz');
    });
  });

  group('the price', () {
    test('is read from a labelled line', () {
      expect(ReadingSuggestions.parse('Savon\nPRIX 500').price, 500);
      expect(ReadingSuggestions.parse('Savon\nprix: 1 500 FCFA').price, 1500);
    });

    test('is read from a bare amount with a currency', () {
      expect(ReadingSuggestions.parse('Savon\n750 F').price, 750);
      expect(ReadingSuggestions.parse('Savon\n2 500 XOF').price, 2500);
    });

    test('handles decimals where a label prints them', () {
      expect(ReadingSuggestions.parse('Savon\n12,50 €').price, 12.5);
    });

    test('offers nothing when two numbers both look like money', () {
      // A unit price and a total. Picking the larger would be the app
      // inventing a shelf price; picking the smaller would be a guess too.
      final s = ReadingSuggestions.parse('Savon\nPRIX 500\nTOTAL 1500 F');
      expect(s.price, isNull,
          reason: 'an ambiguous label must leave the box empty');
    });

    test('does not mistake a barcode for a price', () {
      final s = ReadingSuggestions.parse('Savon\n6001234567890');
      expect(s.price, isNull);
      // It is a barcode, and is offered as one.
      expect(s.barcode, '6001234567890');
    });

    test('refuses zero', () {
      expect(ReadingSuggestions.parse('Savon\nPRIX 0').price, isNull);
    });
  });

  group('the expiry date', () {
    test('reads a full date day-first', () {
      // This app is used in Burkina Faso. 03/04/2026 is the third of April,
      // and reading it the American way would move an expiry by eleven
      // months — which is why it is shown for confirmation and never applied.
      final s = ReadingSuggestions.parse('Lait\nEXP 03/04/2026');
      expect(s.expiresOn, DateTime(2026, 4, 3));
    });

    test('accepts the separators labels actually use', () {
      expect(ReadingSuggestions.parse('EXP 15-06-2027').expiresOn,
          DateTime(2027, 6, 15));
      expect(ReadingSuggestions.parse('EXP 15.06.2027').expiresOn,
          DateTime(2027, 6, 15));
    });

    test('expands a two-digit year', () {
      expect(ReadingSuggestions.parse('EXP 01/12/27').expiresOn,
          DateTime(2027, 12, 1));
    });

    test('a month and year means the end of that month', () {
      // A tin marked 04/2026 is good through April, not until the first of it.
      final s = ReadingSuggestions.parse('Lait concentré\nEXP 04/2026');
      expect(s.expiresOn, DateTime(2026, 4, 30));
    });

    test('rejects a date that does not exist', () {
      // DateTime rolls 31/02 forward to the 2nd or 3rd of March rather than
      // failing, which would silently invent an expiry.
      expect(ReadingSuggestions.parse('EXP 31/02/2026').expiresOn, isNull);
      expect(ReadingSuggestions.parse('EXP 45/13/2026').expiresOn, isNull);
    });

    test('finds nothing when there is no date', () {
      expect(ReadingSuggestions.parse('Savon\nPRIX 500').expiresOn, isNull);
    });
  });

  group('the barcode', () {
    test('accepts the lengths that are real barcodes', () {
      expect(ReadingSuggestions.parse('12345678').barcode, '12345678');
      expect(ReadingSuggestions.parse('123456789012').barcode, '123456789012');
      expect(
          ReadingSuggestions.parse('6001234567890').barcode, '6001234567890');
    });

    test('refuses a lot number or anything else digit-shaped', () {
      expect(ReadingSuggestions.parse('LOT 22841').barcode, isNull);
      expect(ReadingSuggestions.parse('1234567').barcode, isNull);
      expect(ReadingSuggestions.parse('12345678901234').barcode, isNull);
    });
  });

  group('a whole label', () {
    test('a tin of concentrated milk', () {
      final s = ReadingSuggestions.parse('''
NESTLE
LAIT CONCENTRE SUCRE
397 G
EXP 04/2026
PRIX 850 F
6001234567890
''');

      expect(s.name, 'LAIT CONCENTRE SUCRE');
      expect(s.price, 850);
      expect(s.expiresOn, DateTime(2026, 4, 30));
      expect(s.barcode, '6001234567890');
      expect(s.isEmpty, isFalse);
    });

    test('a crumpled label gives back only what it is sure of', () {
      // The realistic case: half of it unreadable. Three empty boxes and one
      // filled is a better outcome than four filled and one wrong.
      final s = ReadingSuggestions.parse('S@V0N DE M4RS3ILL3\n???\nPRlX');
      expect(s.price, isNull);
      expect(s.expiresOn, isNull);
      expect(s.barcode, isNull);
    });
  });

  group('availability', () {
    test('is false anywhere that is not a phone', () {
      // The tests run in a Dart VM, where `dart.library.io` is true and the
      // plugin is therefore compiled in — but there is no platform behind it.
      // If this ever returns true here, the conditional import has stopped
      // protecting the web build too.
      expect(TextReader.isAvailable, isFalse);
    });

    test('reading returns null rather than throwing', () async {
      expect(await TextReader.read('/nonexistent/photo.jpg'), isNull);
    });
  });
}
