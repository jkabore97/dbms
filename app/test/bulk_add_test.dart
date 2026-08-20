import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/retail/bulk_add.dart';

/// The quick-add parser: the one rule (trailing numbers are quantity,
/// price, optional cost; the rest is the name) exercised the way people
/// actually type.
void main() {
  test('the plain case: name, quantity, price', () {
    final lines = parseBulkLines('Savon 20 300');
    expect(lines, hasLength(1));
    expect(lines.first.ok, isTrue);
    expect(lines.first.name, 'Savon');
    expect(lines.first.quantity, 20);
    expect(lines.first.salePrice, 300);
    expect(lines.first.costPrice, isNull);
  });

  test('a name with a unit inside survives: "Sucre 1kg"', () {
    // "1kg" is not a number, so the trailing walk stops there.
    final l = parseBulkLines('Sucre 1kg 10 600 450').first;
    expect(l.ok, isTrue);
    expect(l.name, 'Sucre 1kg');
    expect(l.quantity, 10);
    expect(l.salePrice, 600);
    expect(l.costPrice, 450);
  });

  test('a name ending in a bare number gives its number up only beyond three',
      () {
    // Four trailing numbers: only the last three are read, the fourth
    // stays in the name. "Riz 25" keeps its 25.
    final l = parseBulkLines('Riz 25 10 600 450').first;
    expect(l.ok, isTrue);
    expect(l.name, 'Riz 25');
    expect(l.quantity, 10);
  });

  test('comma decimals, the French keyboard way', () {
    final l = parseBulkLines('Huile 2,5 1500').first;
    expect(l.ok, isTrue);
    expect(l.quantity, 2.5);
    expect(l.salePrice, 1500);
  });

  test('several lines, blanks skipped, errors named per line', () {
    final lines = parseBulkLines('''
Savon 20 300

Sucre
Farine 0 500
Tomate 5 250
''');
    expect(lines, hasLength(4));
    expect(lines[0].ok, isTrue);
    expect(lines[1].ok, isFalse); // no numbers at all
    expect(lines[1].error, contains('quantité et le prix'));
    expect(lines[2].ok, isFalse); // zero quantity
    // Dart elides the newline right after the opening ''' — Savon is line 1.
    expect(lines[3].ok, isTrue);
    expect(lines[3].lineNumber, 5);
  });

  test('a line of only numbers has no name', () {
    final l = parseBulkLines('10 600').first;
    expect(l.ok, isFalse);
    expect(l.error, contains('nom'));
  });

  test('a repeated name is flagged, not silently merged', () {
    // The "I typed ten, only eight appeared" report: two lines resolving to
    // the same name fold into one product server-side (ensure_product matches
    // on the lowercased name), and the second line's quantity stacks onto the
    // first. Commonest when a size the parser reads as a quantity is the only
    // thing telling two products apart.
    final lines = parseBulkLines('''
Sac ciment 50 8000
Sac ciment 25 5000
''');
    expect(lines, hasLength(2));
    expect(lines[0].ok, isTrue);
    expect(lines[0].name, 'Sac ciment');
    expect(lines[1].ok, isFalse);
    expect(lines[1].error, contains('Doublon'));
  });

  test('the duplicate check ignores case, like the server does', () {
    final lines = parseBulkLines('Savon 20 300\nsavon 5 350');
    expect(lines[0].ok, isTrue);
    expect(lines[1].ok, isFalse);
    expect(lines[1].error, contains('Doublon'));
  });

  test('distinct names on adjacent lines both stand', () {
    final lines = parseBulkLines('Savon 20 300\nSucre 10 600');
    expect(lines[0].ok, isTrue);
    expect(lines[1].ok, isTrue);
  });
}
