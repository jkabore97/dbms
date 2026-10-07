import 'package:flutter/foundation.dart';

import '../db/local_db.dart';
import 'alert_tone_io.dart' if (dart.library.js_interop) 'alert_tone_web.dart';

/// One of the four tones a person can pick (Compte › Préférences › Sons des
/// notifications). Synthesised for this app by scripts/make-tones.py — no
/// third-party audio.
class AlertToneChoice {
  const AlertToneChoice(this.id);

  /// Also the file name: `assets/sounds/<id>.wav`. Its name on screen is
  /// the settings tile's (`toneLabel`), so every word goes through tr.
  final String id;

  String get asset => 'assets/sounds/$id.wav';
}

/// What this phone does when the app itself rings: which tone, and whether
/// it also vibrates. Per device, like the language — two people behind the
/// same counter can want different things, and the phone is the person's.
@immutable
class AlertToneSettings {
  const AlertToneSettings({this.tone = AlertTone.defaultTone, this.vibrate = true});

  final String tone;
  final bool vibrate;

  AlertToneSettings copyWith({String? tone, bool? vibrate}) =>
      AlertToneSettings(tone: tone ?? this.tone, vibrate: vibrate ?? this.vibrate);

  @override
  bool operator ==(Object other) =>
      other is AlertToneSettings && other.tone == tone && other.vibrate == vibrate;

  @override
  int get hashCode => Object.hash(tone, vibrate);
}

/// The app's own ring: a new vitrine order while a business is open.
///
/// It sounds only while the app is on screen (or, on the web, its tab is
/// open). A push notification that reaches a closed browser rings with the
/// phone's own notification sound, which the app cannot choose; Android has
/// no push yet. The settings screen says so in one line.
///
/// Never an error: a phone that cannot play or vibrate stays quiet.
class AlertTone {
  const AlertTone._();

  static const defaultTone = 'carillon';

  static const choices = [
    AlertToneChoice('carillon'),
    AlertToneChoice('balafon'),
    AlertToneChoice('clochette'),
    AlertToneChoice('goutte'),
  ];

  static const _toneKey = 'alert_tone';
  static const _vibrateKey = 'alert_vibrate';

  /// The current choice; the settings tile listens to it.
  static final settings = ValueNotifier(const AlertToneSettings());

  static AlertToneChoice choiceFor(String id) =>
      choices.firstWhere((c) => c.id == id, orElse: () => choices.first);

  /// Reads the stored choice. Called once at startup.
  static Future<void> load(LocalDb db) async {
    final tone = await db.readPref(_toneKey);
    final vibrate = await db.readPref(_vibrateKey);
    settings.value = AlertToneSettings(
      tone: choices.any((c) => c.id == tone) ? tone! : defaultTone,
      vibrate: vibrate != '0',
    );
  }

  static Future<void> choose(LocalDb db, {String? tone, bool? vibrate}) async {
    settings.value = settings.value.copyWith(tone: tone, vibrate: vibrate);
    if (tone != null) await db.writePref(_toneKey, tone);
    if (vibrate != null) await db.writePref(_vibrateKey, vibrate ? '1' : '0');
  }

  /// Plays one tone, for the preview button.
  static Future<void> preview(String id) => AlertTonePlatform.play(choiceFor(id).asset);

  /// Rings as this phone was told to: the chosen tone, and a buzz if on.
  static Future<void> ring() async {
    final now = settings.value;
    await Future.wait([
      AlertTonePlatform.play(choiceFor(now.tone).asset),
      if (now.vibrate) AlertTonePlatform.vibrate(),
    ]);
  }
}
