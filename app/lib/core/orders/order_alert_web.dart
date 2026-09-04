import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// The browser half of the doorbell.
///
/// A shopkeeper's tab is usually behind the till spreadsheet or another
/// page; the Notification API is what reaches past that — a system banner
/// with the shop's name on it, even when the tab is not the one on screen.
/// The browser only grants it from a person's own gesture, which is why
/// [request] is wired to a button and never called on page load.
class OrderAlertPlatform {
  const OrderAlertPlatform._();

  static bool get supported {
    try {
      return web.window.hasProperty('Notification'.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  static bool get granted =>
      supported && web.Notification.permission == 'granted';

  static Future<bool> request() async {
    if (!supported) return false;
    try {
      final answer = await web.Notification.requestPermission().toDart;
      return answer.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  static void show(String title, String body) {
    if (!granted) return;
    try {
      web.Notification(title, web.NotificationOptions(body: body));
    } catch (_) {
      // A browser that grants the permission but refuses the constructor
      // (some Android WebViews) — the in-app line still rings.
    }
  }
}
