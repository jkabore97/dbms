import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/capture/notebook_reading.dart';

/// The reader's response parser: a clean body becomes editable lines, and
/// everything else — missing fields, bad numbers, garbage — degrades to "no
/// lines" rather than a crash. The person retakes the photo; that is the
/// fix either way.
void main() {
  test('a clean response becomes lines', () {
    final lines = parseNotebookLines(
        '{"lines":[{"name":"Riz 25kg","quantity":2,"unit_price":17500},'
        '{"name":"Savon","quantity":10,"unit_price":250}]}');
    expect(lines, hasLength(2));
    expect(lines.first.name, 'Riz 25kg');
    expect(lines.first.quantity, 2);
    expect(lines.first.unitCost, 17500);
    // Handwriting was never printed with a checkable total.
    expect(lines.first.checked, isFalse);
  });

  test('broken entries are skipped, good ones kept', () {
    final lines = parseNotebookLines('{"lines":['
        '{"name":"","quantity":2,"unit_price":100},'
        '{"name":"Sucre","quantity":0,"unit_price":100},'
        '{"name":"Sel","quantity":"beaucoup","unit_price":100},'
        '{"name":"Huile","quantity":3,"unit_price":-5},'
        '{"name":"Tomate","quantity":4,"unit_price":150}]}');
    expect(lines, hasLength(1));
    expect(lines.first.name, 'Tomate');
  });

  test('garbage is no lines, not a crash', () {
    expect(parseNotebookLines('pas du JSON'), isEmpty);
    expect(parseNotebookLines('{"autre":"chose"}'), isEmpty);
    expect(parseNotebookLines('{"lines":"pas une liste"}'), isEmpty);
    expect(parseNotebookLines(''), isEmpty);
  });
}
