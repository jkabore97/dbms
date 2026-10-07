import 'package:flutter/services.dart';

/// The Android half of the ring: MainActivity's `bf.kaj.app/tone` channel
/// plays the asset through the notification volume (so a phone on silent
/// stays silent) and buzzes with the vibrator. No plugin, nothing heavy.
///
/// Where the channel is missing (tests, a build without it) the tone is
/// skipped and the buzz falls back to the system's haptic feedback.
class AlertTonePlatform {
  const AlertTonePlatform._();

  static const _channel = MethodChannel('bf.kaj.app/tone');

  static Future<void> play(String asset) async {
    try {
      await _channel.invokeMethod<void>('play', {'asset': asset});
    } catch (_) {
      // Quiet rather than an error.
    }
  }

  static Future<void> vibrate() async {
    try {
      await _channel.invokeMethod<void>('vibrate');
    } catch (_) {
      try {
        await HapticFeedback.vibrate();
      } catch (_) {}
    }
  }
}
