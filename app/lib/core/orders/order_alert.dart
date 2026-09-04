import 'order_alert_stub.dart' if (dart.library.js_interop) 'order_alert_web.dart';

/// The doorbell for the shop's side of the vitrine.
///
/// An order used to ring only inside the app — a bell nobody hears while
/// they are serving the counter or reading another tab. This asks the
/// browser to carry the ring past the tab: a system notification with the
/// shop's name, granted from the shopkeeper's own gesture and refused
/// gracefully everywhere it cannot exist (Android build, an old browser).
///
/// It is honest about its limit: it reaches a tab in the background, not an
/// app that is closed. The closed-app case needs push infrastructure (FCM /
/// Web Push with a server key), which is advice, not code, for now.
class OrderAlert {
  const OrderAlert._();

  /// Whether this platform can carry a ring at all.
  static bool get supported => OrderAlertPlatform.supported;

  /// Whether the person already said yes.
  static bool get granted => OrderAlertPlatform.granted;

  /// Asks, from a user gesture. Answers whether the ring may now sound.
  static Future<bool> request() => OrderAlertPlatform.request();

  /// Rings, if allowed; silent otherwise — never an error.
  static void show(String title, String body) =>
      OrderAlertPlatform.show(title, body);
}
