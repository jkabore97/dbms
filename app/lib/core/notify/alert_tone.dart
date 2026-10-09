import 'alert_tone_io.dart' if (dart.library.js_interop) 'alert_tone_web.dart';

/// The app's own ring: a new vitrine order while a business is open.
///
/// It sounds only while the app is on screen (or, on the web, its tab is
/// open): one short tone (`assets/sounds/carillon.wav`, synthesised for
/// this app by scripts/make-tones.py — no third-party audio) and a buzz.
/// With the app closed, a notification rings with the phone's own sound
/// and vibration, which the person sets in the phone — so the app offers
/// no choice of its own (122: the tones and the « Vibrer » switch went;
/// what is left is « Notifications sur ce téléphone »).
///
/// Never an error: a phone that cannot play or vibrate stays quiet.
class AlertTone {
  const AlertTone._();

  static const asset = 'assets/sounds/carillon.wav';

  static Future<void> ring() async {
    await Future.wait([
      AlertTonePlatform.play(asset),
      AlertTonePlatform.vibrate(),
    ]);
  }
}
