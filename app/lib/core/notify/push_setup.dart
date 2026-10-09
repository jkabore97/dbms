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
      return true;
    } catch (_) {
      return false;
    }
  }
}
