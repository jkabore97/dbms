import 'push_client.dart';

/// Everywhere that is not a browser: no Web Push. The Android app's ring
/// with the app closed needs FCM — its own key, its own Firebase project —
/// which this build does not carry, so the honest answer here is "not
/// available" rather than a subscription that never rings.
class PushPlatform {
  const PushPlatform._();

  static bool get supported => false;

  static Future<PushSubscriptionInfo?> subscribe(String pushUrl) async => null;

  static Future<String?> unsubscribe() async => null;
}
