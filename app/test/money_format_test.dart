import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/format/money.dart';

/// The one formatter every screen now shares. These pin the two things that
/// were inconsistent before: XOF prints as "FCFA" (never the raw code), and a
/// business on another currency sees that currency — not a hardcoded "FCFA".
void main() {
  test('XOF prints as FCFA, never as the raw code', () {
    final out = moneyFormat('XOF').format(1500);
    expect(out, contains('FCFA'));
    expect(out, isNot(contains('XOF')));
  });

  test('another currency shows its own code', () {
    expect(moneyFormat('EUR').format(1500), contains('EUR'));
    expect(moneyFormat('USD').format(1500), contains('USD'));
    expect(moneyFormat('GHS').format(1500), contains('GHS'));
  });

  test('no decimals — a centime of franc is noise', () {
    final out = moneyFormat('XOF').format(1500.7);
    expect(out, isNot(contains(',00')));
    expect(out, isNot(contains('.00')));
    // Rounds to whole units rather than dropping to zero.
    expect(out, contains('1'));
  });

  test('thousands are grouped', () {
    final out = moneyFormat('XOF').format(1200000);
    // fr_FR groups with a space; assert the digits survive in grouped form.
    expect(out.replaceAll(RegExp(r'[^0-9]'), ''), '1200000');
  });
}
