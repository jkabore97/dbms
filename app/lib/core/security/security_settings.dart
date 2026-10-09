import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:uuid/uuid.dart';

import '../db/local_db.dart';
import '../l10n/tr.dart';

/// What switching the fingerprint / Face ID on came to (Sécurité).
enum BiometricOutcome {
  /// The system prompt was answered: the phone unlocks Mara from now on.
  on,

  /// The person closed the prompt; nothing changed.
  refused,

  /// The phone can, but has no fingerprint or face recorded yet.
  notEnrolled,

  /// Anything else (locked out after too many tries, no hardware…).
  failed,
}

/// This phone's own security choices (Compte › Sécurité), kept on the phone.
///
/// The device code existed before this, but it was only asked when the
/// session had expired with no signal — a phone left on the counter opened
/// straight into the shop's money. These choices make the code a lock: the
/// app asks for it again after it has been away [lockAfter] minutes.
class SecuritySettings extends ChangeNotifier {
  SecuritySettings(this._db, {LocalAuthentication? biometrics})
      : _bio = biometrics ?? LocalAuthentication();

  final LocalDb _db;
  final LocalAuthentication _bio;

  static const _lockKey = 'security.lock_after';
  static const _bioKey = 'security.biometric';
  static const _hideKey = 'security.hide_amounts';
  static const _deviceKey = 'security.device_id';

  /// The choices offered. Null is « Jamais ». No "immediately": taking a
  /// photo leaves the app for the camera, and a lock at every return would
  /// ask for the code in the middle of a sale.
  static const choices = <int?>[1, 5, 15, 60, null];
  static const defaultLock = 5;

  int? _lockAfter = defaultLock;
  bool _biometric = true;
  bool _hideAmounts = false;
  int? _policy;
  bool _loaded = false;

  /// What this person chose; see [effectiveLock] for what applies.
  int? get lockAfter => _lockAfter;
  bool get biometric => _biometric;
  bool get hideAmounts => _hideAmounts;
  bool get loaded => _loaded;

  /// The strictest rule an owner set for this person's businesses (075),
  /// in minutes; null when none did.
  int? get policy => _policy;

  /// What the app actually does: the person's choice, never looser than the
  /// owner's rule. « Jamais » under a rule is the rule.
  int? get effectiveLock {
    final rule = _policy;
    final mine = _lockAfter;
    if (rule == null) return mine;
    if (mine == null) return rule;
    return mine < rule ? mine : rule;
  }

  /// Whether [minutes] is allowed under the owner's rule.
  bool allows(int? minutes) {
    final rule = _policy;
    if (rule == null) return true;
    return minutes != null && minutes <= rule;
  }

  /// Whether this phone has a fingerprint enrolled, learned once at load.
  bool _biometricReady = false;
  bool get biometricReady => _biometricReady;

  /// Whether this phone has a fingerprint reader or a face sensor at all,
  /// enrolled or not: Sécurité offers the switch then, and says what to do
  /// when nothing is recorded yet.
  bool _biometricHardware = false;
  bool get biometricHardware => _biometricHardware;

  Future<void> load() async {
    await refreshBiometric(notify: false);
    try {
      final lock = await _db.readPref(_lockKey);
      _lockAfter = lock == null
          ? defaultLock
          : (lock == 'never' ? null : int.tryParse(lock) ?? defaultLock);
      _biometric = (await _db.readPref(_bioKey)) != '0';
      _hideAmounts = (await _db.readPref(_hideKey)) == '1';
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> setLockAfter(int? minutes) async {
    _lockAfter = minutes;
    notifyListeners();
    await _db.writePref(_lockKey, minutes == null ? 'never' : '$minutes');
  }

  Future<void> setBiometric(bool on) async {
    _biometric = on;
    notifyListeners();
    await _db.writePref(_bioKey, on ? '1' : '0');
  }

  Future<void> setHideAmounts(bool on) async {
    _hideAmounts = on;
    notifyListeners();
    await _db.writePref(_hideKey, on ? '1' : '0');
  }

  void setPolicy(int? minutes) {
    if (_policy == minutes) return;
    _policy = minutes;
    notifyListeners();
  }

  /// This install's own id: random, made once, never a hardware id. What
  /// the device list (075) knows this phone by.
  Future<String> deviceId() async {
    final known = await _db.readPref(_deviceKey);
    if (known != null && known.length >= 8) return known;
    final id = const Uuid().v4();
    await _db.writePref(_deviceKey, id);
    return id;
  }

  /// "Android · application", "Windows · navigateur": what the device list
  /// calls this phone. Approximate on purpose — the system's own name is
  /// not the app's to read.
  static String deviceLabel() {
    final os = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iPhone',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Appareil',
    };
    return '$os · ${kIsWeb ? 'navigateur' : 'application'}';
  }

  /// Reads again what the phone has: a fingerprint added in the phone's
  /// settings while Mara was in the background shows when Sécurité opens.
  Future<void> refreshBiometric({bool notify = true}) async {
    var hardware = false;
    if (!kIsWeb) {
      try {
        hardware = await _bio.canCheckBiometrics;
      } catch (_) {}
    }
    final ready = await biometricAvailable();
    final changed =
        hardware != _biometricHardware || ready != _biometricReady;
    _biometricHardware = hardware || ready;
    _biometricReady = ready;
    if (notify && changed) notifyListeners();
  }

  /// Switching the fingerprint / Face ID on: the system's own prompt is
  /// asked once, here — that answer is the person's authorization (and, on
  /// an iPhone, what makes iOS ask for Face ID). Only a success turns it on.
  Future<BiometricOutcome> turnOnBiometric() async {
    await refreshBiometric();
    if (!_biometricReady) {
      return _biometricHardware
          ? BiometricOutcome.notEnrolled
          : BiometricOutcome.failed;
    }
    try {
      final ok = await _bio.authenticate(
        localizedReason: translate(
            trCurrent, 'Autoriser Mara à utiliser l\'empreinte ou Face ID'),
        biometricOnly: true,
      );
      if (!ok) return BiometricOutcome.refused;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          BiometricOutcome.notEnrolled,
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback =>
          BiometricOutcome.refused,
        _ => BiometricOutcome.failed,
      };
    } catch (_) {
      return BiometricOutcome.failed;
    }
    await setBiometric(true);
    return BiometricOutcome.on;
  }

  /// Whether this phone can unlock with a fingerprint or a face at all.
  /// False on the web, and wherever the plugin is missing.
  Future<bool> biometricAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _bio.canCheckBiometrics &&
          (await _bio.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Asks the system for the fingerprint. False on any refusal or error:
  /// the code is always the way in.
  Future<bool> unlockWithBiometrics() async {
    try {
      return await _bio.authenticate(
        localizedReason: translate(trCurrent, 'Déverrouiller Mara'),
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }

  /// "5 min", "1 h", "Jamais".
  static String label(int? minutes) => switch (minutes) {
        null => 'Jamais',
        60 => '1 h',
        final m => '$m min',
      };
}
