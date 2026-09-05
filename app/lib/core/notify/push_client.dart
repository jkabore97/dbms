import 'push_client_stub.dart' if (dart.library.js_interop) 'push_client_web.dart';

/// The ring that reaches a closed app.
///
/// The doorbell (OrderAlert) reaches a tab in the background; this reaches
/// a phone in a pocket. A person says yes once, in a browser; that
/// browser's address (endpoint and keys) is saved under their account
/// (060), and the push Worker (workers/push) sends to it whenever the bell
/// writes them a row — an order in, a delivery taken, a job on the board.
///
/// Armed by --dart-define=PUSH_URL, the Worker's origin; without it the
/// app offers no push toggle at all, so nothing is promised that cannot
/// ring. The Android build compiles the silent stub: with the app closed,
/// Android needs FCM, which is a separate project this build does not have.
class PushClient {
  const PushClient._();

  static const url = String.fromEnvironment('PUSH_URL');

  /// Whether this build and this platform can offer push at all.
  static bool get available => url.isNotEmpty && PushPlatform.supported;

  /// Asks the browser (from a user gesture) and answers with what to save,
  /// or null when refused or unsupported.
  static Future<PushSubscriptionInfo?> subscribe() =>
      PushPlatform.subscribe(url);

  /// Withdraws this browser; answers the endpoint to forget, if there was one.
  static Future<String?> unsubscribe() => PushPlatform.unsubscribe();
}

/// One browser's address: what save_push_subscription() stores.
class PushSubscriptionInfo {
  const PushSubscriptionInfo({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
    this.userAgent,
  });

  final String endpoint;
  final String p256dh;
  final String auth;
  final String? userAgent;
}
