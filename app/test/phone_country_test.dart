import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/phone/country_codes.dart';

/// The country code in front of a phone number, asserted on the thing that
/// goes wrong when it is assumed instead of chosen.
///
/// Every phone field in this app was a plain `TextField` with
/// `prefixText: '+226  '`. That prefix was paint: not part of the value, not
/// changeable, and ignored by the code that built E.164. So a number from
/// Abidjan typed into it did not look wrong — it *became* +226 followed by an
/// Ivorian subscriber number, which is a real Burkinabè number belonging to
/// somebody else. The invitation SMS went to that stranger and the person it
/// was meant for waited for a code that never came.
///
/// Nothing in the app could catch that, because both numbers are valid
/// strings. The assertion that catches it is the one below.
void main() {
  group('normalizing against a chosen country', () {
    test('the same digits under two countries are two different numbers', () {
      const typed = '70 12 34 56';
      expect(AuthRepository.normalizePhone(typed, defaultCode: '+226'),
          '+22670123456');
      expect(AuthRepository.normalizePhone(typed, defaultCode: '+225'),
          '+22570123456');
    });

    test('an explicit + is never overwritten by the picker', () {
      // Somebody who types the whole thing has said which country they mean,
      // and the picker must not argue with them.
      expect(
        AuthRepository.normalizePhone('+33 6 12 34 56 78', defaultCode: '+226'),
        '+33612345678',
      );
    });

    test('a national trunk zero is dropped before the code is applied', () {
      expect(AuthRepository.normalizePhone('070 12 34 56', defaultCode: '+225'),
          '+22570123456');
    });

    test('00 is the same thing as +', () {
      expect(AuthRepository.normalizePhone('0033612345678', defaultCode: '+226'),
          '+33612345678');
    });

    test('default is still Burkina Faso when nothing is chosen', () {
      expect(AuthRepository.normalizePhone('70123456'), '+22670123456');
      expect(defaultCountry.dial, '+226');
      expect(defaultCountry.iso, 'BF');
    });
  });

  group('the list itself', () {
    test('every dialling code is a + and digits', () {
      for (final country in allCountries) {
        expect(country.dial.startsWith('+'), isTrue, reason: country.name);
        expect(RegExp(r'^\+\d{1,4}$').hasMatch(country.dial), isTrue,
            reason: '${country.name} has dial ${country.dial}');
      }
    });

    test('every ISO code is two letters and appears once', () {
      final seen = <String>{};
      for (final country in allCountries) {
        expect(RegExp(r'^[A-Z]{2}$').hasMatch(country.iso), isTrue,
            reason: country.name);
        expect(seen.add(country.iso), isTrue,
            reason: '${country.iso} is listed twice');
      }
    });

    test('the neighbours a shop in Ouagadougou actually calls are first', () {
      final isos = westAfrica.map((c) => c.iso).toList();
      expect(isos.first, 'BF');
      expect(isos, containsAll(['CI', 'ML', 'NE', 'SN', 'TG', 'BJ', 'GH']));
    });
  });

  group('reading a stored number back', () {
    test('an E.164 number resolves to its country', () {
      expect(countryOfNumber('+22670123456')?.iso, 'BF');
      expect(countryOfNumber('+22107123456')?.iso, 'SN');
      expect(countryOfNumber('+33612345678')?.iso, 'FR');
    });

    test('the longest matching code wins, not the first', () {
      // +226 must not be read as some shorter code that happens to prefix it.
      final bf = countryOfNumber('+22670123456');
      expect(bf?.dial, '+226');
      expect(bf?.dial.length, greaterThanOrEqualTo(4));
    });

    test('a number with no + is not guessed at', () {
      // Guessing here would be how a local number silently acquires a country
      // it was never given. The picker's own default covers that case.
      expect(countryOfNumber('70123456'), isNull);
    });

    test('round trip: split for display, rebuilt for the server', () {
      // The case that caught the trunk-zero bug. An Ivorian mobile begins 07
      // and that zero is a digit, so splitting the stored number for display
      // and rebuilding it must give back exactly what was stored.
      const stored = '+22507123456';
      final country = countryOfNumber(stored)!;
      final local = country.localPart(stored);
      expect(local, '07123456');
      expect(country.toE164(local), stored);
    });

    test('every country survives the round trip it will actually see', () {
      for (final country in allCountries) {
        // A plausible subscriber part for that plan, including the leading
        // zero where the plan has one.
        final local = country.trunkZero ? '712345678' : '071234567';
        final stored = country.toE164(local);
        expect(country.toE164(country.localPart(stored)), stored,
            reason: '${country.name} loses digits on a round trip');
      }
    });
  });

  group('searching for a country', () {
    test('by name, accent-insensitively enough to be usable', () {
      expect(countryMatches(countryByIso('CI'), 'ivoire'), isTrue);
      expect(countryMatches(countryByIso('FR'), 'fran'), isTrue);
    });

    test('by ISO code', () {
      expect(countryMatches(countryByIso('GH'), 'gh'), isTrue);
    });

    test('by dialling code, with or without the plus', () {
      expect(countryMatches(countryByIso('CI'), '225'), isTrue);
      expect(countryMatches(countryByIso('CI'), '+225'), isTrue);
      expect(countryMatches(countryByIso('CI'), '226'), isFalse);
    });

    test('an empty query matches everything', () {
      expect(countryMatches(defaultCountry, '  '), isTrue);
    });

    test('an unknown ISO falls back rather than throwing', () {
      expect(countryByIso('ZZ').iso, 'BF');
      expect(countryByIso(null).iso, 'BF');
    });
  });
}
