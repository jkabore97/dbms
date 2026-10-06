import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/phone/country_codes.dart';

/// The length of a number, checked per country: the US number from the
/// owner's screenshot, typed under Burkina, is refused in a few words.
void main() {
  CountryCode of(String iso) =>
      [...westAfrica, ...otherCountries].firstWhere((c) => c.iso == iso);

  test('Burkina: 8 digits; a 10-digit number is refused', () {
    final bf = of('BF');
    expect(bf.lengthProblem('70 12 34 56'), isNull);
    expect(bf.lengthProblem('9733365729'), '8 chiffres pour Burkina Faso (+226)');
    expect(bf.lengthProblem('701234'), isNotNull);
  });

  test('the same number under the United States is right', () {
    expect(of('US').lengthProblem('973 336 5729'), isNull);
  });

  test("Côte d'Ivoire keeps its leading zero: 10 digits", () {
    expect(of('CI').lengthProblem('07 12 34 56 78'), isNull);
    expect(of('CI').lengthProblem('7123456'), isNotNull);
  });

  test('empty, an explicit +, or a country not listed: not checked', () {
    expect(of('BF').lengthProblem(''), isNull);
    expect(of('BF').lengthProblem('+1 973 336 5729'), isNull);
    expect(of('DE').lengthProblem('123'), isNull);
  });
}
