import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Hashing for the device PIN.
///
/// The PIN is not a password and is not pretending to be one. Four digits is
/// ten thousand possibilities, so anyone who can read the database file can
/// brute-force it in an instant no matter what we do here. What this buys is
/// the thing that actually matters: the PIN is never stored in a form that a
/// support engineer, a crash log, or a backup can read back and reuse — and
/// people reuse PINs across their phone, their bank, and their mobile money.
///
/// The stretching below is deliberately slow enough to be felt by a script and
/// not by a person entering four digits once.
class PinCodec {
  const PinCodec._();

  static const _iterations = 20000;
  static final _random = Random.secure();

  /// A fresh random salt, base64. One per device, regenerated whenever the PIN
  /// is changed, so two devices with the same PIN never share a hash.
  static String newSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  /// Iterated HMAC-SHA256 over the PIN, keyed by the salt.
  static String hash(String pin, String salt) {
    final key = base64Decode(salt);
    final hmac = Hmac(sha256, key);

    var digest = hmac.convert(utf8.encode(pin)).bytes;
    for (var i = 1; i < _iterations; i++) {
      digest = hmac.convert(digest).bytes;
    }

    return base64Encode(digest);
  }

  /// Constant-time comparison. Timing an offline PIN check is a stretch as
  /// attacks go, but the constant-time version is three lines.
  static bool verify(String pin, {required String salt, required String hash}) {
    final candidate = base64Decode(PinCodec.hash(pin, salt));
    final expected = base64Decode(hash);
    if (candidate.length != expected.length) return false;

    var diff = 0;
    for (var i = 0; i < candidate.length; i++) {
      diff |= candidate[i] ^ expected[i];
    }
    return diff == 0;
  }

  /// Rejects the PINs that make the whole exercise pointless. Four digits,
  /// not all the same, not a straight run up or down.
  static String? validate(String pin) {
    if (pin.length != 4 || int.tryParse(pin) == null) {
      return 'Le code doit contenir 4 chiffres.';
    }
    if (RegExp(r'^(\d)\1{3}$').hasMatch(pin)) {
      return 'Choisissez un code moins simple.';
    }
    const runs = ['0123', '1234', '2345', '3456', '4567', '5678', '6789'];
    final reversed = pin.split('').reversed.join();
    if (runs.contains(pin) || runs.contains(reversed)) {
      return 'Choisissez un code moins simple.';
    }
    return null;
  }
}
