import 'package:flutter/foundation.dart';

import 'notifications_repository.dart';
import 'push_client.dart';

/// Whether this device rings with the app closed, and the two ways to get
/// it there (115).
///
/// The bug this replaces: the shop's home hid its offer as soon as the
/// browser's permission was granted — but a permission is not a
/// subscription. A browser that had said yes to the doorbell, or whose
/// subscription row was lost, was never offered again and never rang.
/// Now the question is « is THIS device's address in my book? ».
class PushSetup {
  const PushSetup._();

  /// Ticks each time a device is turned on from somewhere (the pop-up at
  /// the app's opening, a card, the settings, the diagnostics): every offer
  /// still drawn looks again and disappears (120).
  static final changes = ValueNotifier<int>(0);

  /// Whether push can be offered here at all (the build, the platform).
  static Future<bool> available() => PushClient.prepare();

  /// Silent, at sign-in and on each return to the app: with the permission
  /// already given, this device's address is (re)written to the book if it
  /// is missing — nothing is ever asked. Answers whether the device is on.
  static Future<bool> ensure(NotificationsRepository notify) async {
    try {
      if (!notify.isConfigured || notify.me == null) return false;
      if (!await PushClient.prepare()) return false;
      if (!await PushClient.granted()) return false;
      final sub = await PushClient.current() ?? await PushClient.subscribe();
      if (sub == null) return false;
      if (!await notify.hasPushSubscription(sub.endpoint)) {
        await notify.savePushSubscription(sub);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether this device is on: allowed, holding an address, and that
  /// address in the person's book.
  static Future<bool> isOn(NotificationsRepository notify) async {
    try {
      if (!notify.isConfigured || !await PushClient.prepare()) return false;
      if (!await PushClient.granted()) return false;
      final sub = await PushClient.current();
      return sub != null && await notify.hasPushSubscription(sub.endpoint);
    } catch (_) {
      return false;
    }
  }

  /// From the person's own tap: asks the device, then saves its address.
  /// Answers whether it is now on.
  static Future<bool> enable(NotificationsRepository notify) async {
    try {
      if (!await PushClient.prepare()) return false;
      final sub = await PushClient.subscribe();
      if (sub == null) return false;
      await notify.savePushSubscription(sub);
      changes.value++;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Where this device stands, for the pop-up at the app's opening (120):
  /// already on (written back silently if it was only missing from the
  /// book), to be asked, blocked in the device's settings, or with nothing
  /// to offer (a build or a platform without push, nobody signed in).
  static Future<PushStanding> standing(NotificationsRepository notify) async {
    try {
      if (!notify.isConfigured || notify.me == null) return PushStanding.unavailable;
      if (await ensure(notify)) return PushStanding.on;
      if (!PushClient.available) return PushStanding.unavailable;
      return switch (await PushClient.permission()) {
        PushPermission.blocked => PushStanding.blocked,
        PushPermission.unsupported => PushStanding.unavailable,
        _ => PushStanding.askable,
      };
    } catch (_) {
      return PushStanding.unavailable;
    }
  }

  /// Everything between this device and a ring, step by step (120): what
  /// the diagnostics panel shows. Never asks the person anything.
  static Future<PushDiagnosis> diagnose(NotificationsRepository notify) async {
    final facts = await PushClient.facts();
    final permission = await PushClient.permission();
    final available = await PushClient.prepare();
    PushSubscriptionInfo? sub;
    String? error;
    try {
      sub = available ? await PushClient.current() : null;
    } catch (e) {
      error = '$e';
    }
    bool? saved;
    if (sub != null && notify.isConfigured && notify.me != null) {
      try {
        saved = await notify.hasPushSubscription(sub.endpoint);
      } catch (e) {
        error = '$e';
      }
    }
    return PushDiagnosis(
      facts: facts,
      available: available,
      buildHasWorker: PushClient.url.isNotEmpty,
      permission: permission,
      address: sub?.endpoint,
      saved: saved,
      signedIn: notify.isConfigured && notify.me != null,
      error: error,
    );
  }

  /// « Réessayer l'enregistrement »: starts again what failed, asks the
  /// device if it may still be asked (this is the person's own tap), and
  /// writes the address. Answers whether the device is now on.
  static Future<bool> retry(NotificationsRepository notify) async {
    try {
      if (!await PushClient.retry()) return false;
      if (await ensure(notify)) {
        changes.value++;
        return true;
      }
      return await enable(notify);
    } catch (_) {
      return false;
    }
  }
}

/// See [PushSetup.standing].
enum PushStanding { on, askable, blocked, unavailable }

/// See [PushSetup.diagnose].
class PushDiagnosis {
  const PushDiagnosis({
    required this.facts,
    required this.available,
    required this.buildHasWorker,
    required this.permission,
    required this.address,
    required this.saved,
    required this.signedIn,
    this.error,
  });

  final PushDeviceFacts facts;

  /// Whether this build, on this platform, can offer push at all.
  final bool available;

  /// Whether the build knows the push Worker (PUSH_URL) — what a browser
  /// needs for its key; a phone does not.
  final bool buildHasWorker;
  final PushPermission permission;

  /// This device's token (Android, `fcm:…`) or subscription (a browser).
  final String? address;

  /// Whether [address] is in the person's book on the server; null when
  /// there is no address, or nobody signed in, to look for.
  final bool? saved;
  final bool signedIn;
  final String? error;
}
