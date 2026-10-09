import 'push_client_stub.dart' if (dart.library.js_interop) 'push_client_web.dart';

/// The ring that reaches a closed app.
///
/// The doorbell (OrderAlert) reaches a tab in the background; this reaches
/// a phone in a pocket. A person says yes once, on a device; that device's
/// address is saved under their account (060, 115), and the push Worker
/// (workers/push) sends to it whenever the bell writes them a row.
///
///   * In a browser: Web Push, armed by --dart-define=PUSH_URL (the
///     Worker's origin, for its VAPID key); without it the app offers no
///     push at all, so nothing is promised that cannot ring.
///   * On Android (115): Firebase Cloud Messaging, armed by the build
///     carrying android/app/google-services.json; without it Firebase does
///     not start and the app offers no push either.
class PushClient {
  const PushClient._();

  static const url = String.fromEnvironment('PUSH_URL');

  /// Whether this build and this platform can offer push at all. On Android
  /// known only once [prepare] has run.
  static bool get available => PushPlatform.available(url);

  /// Starts what the platform needs (Firebase on Android) and says whether
  /// push can be offered. Cheap, and safe to call more than once.
  static Future<bool> prepare() async {
    await PushPlatform.prepare();
    return available;
  }

  /// Whether the person already allowed notifications on this device.
  static Future<bool> granted() => PushPlatform.granted();

  /// Asks (from a user gesture) and answers with what to save, or null when
  /// refused or unsupported. With permission already given it asks nothing.
  static Future<PushSubscriptionInfo?> subscribe() =>
      PushPlatform.subscribe(url);

  /// This device's current address, without asking anything — null when it
  /// has none.
  static Future<PushSubscriptionInfo?> current() => PushPlatform.current();

  /// Withdraws this device; answers the endpoint to forget, if there was one.
  static Future<String?> unsubscribe() => PushPlatform.unsubscribe();

  /// The app's own address of each push the person taps (Android; a
  /// browser's tap is the service worker's to open). The router goes there.
  static Stream<String> get opened => PushPlatform.opened;
}

/// One device's address: what save_push_subscription() (a browser) or
/// save_fcm_token() (an Android phone) stores.
class PushSubscriptionInfo {
  const PushSubscriptionInfo({
    required this.endpoint,
    this.p256dh = '',
    this.auth = '',
    this.userAgent,
    this.fcmToken,
  });

  /// A phone's: its FCM token, the endpoint `fcm:<token>` (115).
  const PushSubscriptionInfo.fcm(String token, {this.userAgent})
      : endpoint = 'fcm:$token',
        p256dh = '',
        auth = '',
        fcmToken = token;

  final String endpoint;
  final String p256dh;
  final String auth;
  final String? userAgent;
  final String? fcmToken;
}
