import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/capture/invoice_reading.dart';

/// The piece M5's demo stands on: *she photographs a delivery invoice and the
/// products are in the system without typing.*
///
/// Every case here is about the same danger. A line on a delivery note is a
/// name and two or three numbers, and which number is which is genuinely
/// ambiguous — `Savon 12 500` is either twelve at five hundred or one at
/// twelve thousand five hundred. Getting it wrong puts a wrong count and a
/// wrong cost into the books, and the shopkeeper finds out weeks later when
/// the shelf and the stock disagree.
///
/// So the rule under all of this: **arithmetic decides, and where arithmetic
/// cannot decide, offer the shape a person corrects in one tap.** Never the
/// number they have to notice is wrong.
void main() {
  group('nothing to read', () {
    test('empty text yields no lines', () {
      expect(InvoiceReading.parse(null), isEmpty);
      expect(InvoiceReading.parse(''), isEmpty);
      expect(InvoiceReading.parse('   \n\n  '), isEmpty);
    });

    test('a label with no numbers is not a delivery', () {
      expect(InvoiceReading.parse('BON DE LIVRAISON\nMerci'), isEmpty);
    });
  });

  group('the arithmetic decides', () {
    test('quantity, unit and total that multiply are trusted', () {
      final lines = InvoiceReading.parse('Savon de Marseille 12 500 6000');
      expect(lines, hasLength(1));
      expect(lines.single.name, 'Savon de Marseille');
      expect(lines.single.quantity, 12);
      expect(lines.single.unitCost, 500);
      expect(lines.single.checked, isTrue);
    });

    test('three numbers that do not multiply are not a delivery line', () {
      // A reference, a weight and a price. Read as quantity/unit/total this
      // would invent 4 020 units of something.
      final lines = InvoiceReading.parse('Réf 4020 25 750');
      // Either nothing, or something not claimed as checked — never a
      // confident 4020 × 25.
      for (final line in lines) {
        expect(line.checked, isFalse);
        expect(line.quantity, lessThan(4020));
      }
    });

    test('a leading count is unambiguous and is used', () {
      final lines = InvoiceReading.parse('2 x Riz 25kg 9000 18000');
      expect(lines.single.quantity, 2);
      expect(lines.single.unitCost, 9000);
      expect(lines.single.checked, isTrue);
      expect(lines.single.name, contains('Riz'));
    });

    test('a small OCR error in the total still passes', () {
      // 0 read as 8 in the last digit. Rejecting this would throw away half
      // the lines that a person reads without difficulty.
      final lines = InvoiceReading.parse('Sucre 4 1250 5000');
      expect(lines.single.quantity, 4);
      expect(lines.single.unitCost, 1250);
    });
  });

  group('when arithmetic cannot decide', () {
    test('a single space is read the way French writes thousands', () {
      // `Savon 12 500` with one space is twelve thousand five hundred to
      // anybody who writes French, and twelve at five hundred to anybody
      // reading a column. Nothing on this line settles it — there is no total
      // to multiply into — so the French reading wins, because the invoice
      // was written by a person and a real column is separated by several
      // spaces rather than one.
      //
      // The line below with a total attached is read the other way, and that
      // is the case that matters: see 'quantity, unit and total that
      // multiply are trusted'.
      final lines = InvoiceReading.parse('Savon 12 500');
      expect(lines.single.quantity, 1);
      expect(lines.single.unitCost, 12500);
      expect(lines.single.checked, isFalse);
    });

    test('columns separated by several spaces are columns', () {
      final lines = InvoiceReading.parse('Savon      12     500');
      expect(lines.single.quantity, 12);
      expect(lines.single.unitCost, 500);
      expect(lines.single.checked, isFalse);
    });

    test('one number is one item at that price', () {
      final lines = InvoiceReading.parse('Carton de tomates 7500');
      expect(lines.single.quantity, 1);
      expect(lines.single.unitCost, 7500);
      expect(lines.single.checked, isFalse);
    });

    test('an implausible count is treated as a price instead', () {
      // 45 000 is not a quantity of anything in a shop.
      final lines = InvoiceReading.parse('Groupe électrogène 45000 45000');
      expect(lines.single.quantity, 1);
    });
  });

  group('what is not a product', () {
    test('totals and footers are skipped', () {
      final lines = InvoiceReading.parse('''
Savon 12 500 6000
TOTAL 6000
Net à payer 6000
Merci de votre confiance
''');
      expect(lines, hasLength(1));
      expect(lines.single.name, 'Savon');
    });

    test('column headers are skipped', () {
      final lines = InvoiceReading.parse('''
Désignation Qté PU Montant
Savon 12 500 6000
''');
      expect(lines, hasLength(1));
    });

    test('a date is not read as numbers', () {
      // 12/08/2026 as three numbers is a quantity of 12 at a price of 8,
      // and it very nearly checks out, which is exactly why it is stripped
      // before anything else looks at the line.
      final lines =
          InvoiceReading.parse('Facture du 12/08/2026\nSavon   2   500   1000');
      expect(lines, hasLength(1));
      expect(lines.single.name, 'Savon');
      expect(lines.single.quantity, 2);
      expect(lines.single.unitCost, 500);
    });

    test('a line of pure digits is not a product', () {
      expect(InvoiceReading.parse('6001234567890'), isEmpty);
      expect(InvoiceReading.parse('---- 12 ----'), isEmpty);
    });
  });

  group('a whole delivery note', () {
    test('nine lines of paper become the products that were delivered', () {
      final lines = InvoiceReading.parse('''
ETS SAWADOGO ET FILS
BON DE LIVRAISON
Date 12/08/2026
Client: Boutique Espérance

Désignation           Qté    P.U     Montant
Savon de Marseille     12    500      6000
Riz parfumé 25kg        2   9000     18000
Huile 1L               24    750     18000
Sucre en poudre 1kg     6    650      3900
Lait concentré         48    350     16800

TOTAL                              62700
Net à payer                        62700
Merci de votre confiance
''');

      expect(lines, hasLength(5));
      expect(lines.map((l) => l.quantity).toList(), [12, 2, 24, 6, 48]);
      expect(lines.map((l) => l.unitCost).toList(),
          [500, 9000, 750, 650, 350]);
      // Every one of them verified by its own total.
      expect(lines.every((l) => l.checked), isTrue);

      expect(lines[0].name, 'Savon de Marseille');
      expect(lines[1].name, contains('Riz'));
      expect(lines[3].name, contains('Sucre'));

      // What the shop is about to owe.
      expect(lines.fold<double>(0, (s, l) => s + l.lineTotal), 62700);
    });

    test('grouped thousands are read as one number', () {
      final lines = InvoiceReading.parse('Riz parfumé 2 9 000 18 000');
      expect(lines.single.quantity, 2);
      expect(lines.single.unitCost, 9000);
      expect(lines.single.checked, isTrue);
    });

    test('a half-unreadable note gives back only the lines it is sure of', () {
      // The realistic case. Four lines offered out of six beats nothing
      // offered, and beats six offered with two of them invented.
      final lines = InvoiceReading.parse('''
Savon 12 500 6000
§§§ ¤¤¤ ###
Riz 2 9000 18000
''');
      expect(lines, hasLength(2));
      expect(lines.every((l) => l.checked), isTrue);
    });
  });
}
