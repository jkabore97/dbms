import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/pin_codec.dart';

void main() {
  group('PinCodec', () {
    test('the same code and salt always produce the same hash', () {
      final salt = PinCodec.newSalt();
      expect(PinCodec.hash('1379', salt), PinCodec.hash('1379', salt));
    });

    test('two devices with the same code do not share a hash', () {
      final a = PinCodec.newSalt();
      final b = PinCodec.newSalt();
      expect(a, isNot(b));
      expect(PinCodec.hash('1379', a), isNot(PinCodec.hash('1379', b)));
    });

    test('the code is never recoverable from what is stored', () {
      final salt = PinCodec.newSalt();
      final hash = PinCodec.hash('1379', salt);
      expect(hash, isNot(contains('1379')));
      expect(salt, isNot(contains('1379')));
    });

    test('verify accepts the right code and rejects everything else', () {
      final salt = PinCodec.newSalt();
      final hash = PinCodec.hash('1379', salt);

      expect(PinCodec.verify('1379', salt: salt, hash: hash), isTrue);
      expect(PinCodec.verify('1378', salt: salt, hash: hash), isFalse);
      expect(PinCodec.verify('', salt: salt, hash: hash), isFalse);
      expect(PinCodec.verify('13790', salt: salt, hash: hash), isFalse);
    });

    test('verify against another device\'s salt fails', () {
      final salt = PinCodec.newSalt();
      final hash = PinCodec.hash('1379', salt);
      expect(
        PinCodec.verify('1379', salt: PinCodec.newSalt(), hash: hash),
        isFalse,
      );
    });

    group('validate', () {
      test('accepts a reasonable four-digit code', () {
        expect(PinCodec.validate('1379'), isNull);
        expect(PinCodec.validate('2580'), isNull);
      });

      test('rejects anything that is not four digits', () {
        expect(PinCodec.validate('137'), isNotNull);
        expect(PinCodec.validate('13790'), isNotNull);
        expect(PinCodec.validate('13a9'), isNotNull);
        expect(PinCodec.validate(''), isNotNull);
      });

      test('rejects the codes everyone tries first', () {
        expect(PinCodec.validate('0000'), isNotNull);
        expect(PinCodec.validate('1111'), isNotNull);
        expect(PinCodec.validate('1234'), isNotNull);
        expect(PinCodec.validate('4321'), isNotNull);
        expect(PinCodec.validate('6789'), isNotNull);
      });
    });
  });
}
