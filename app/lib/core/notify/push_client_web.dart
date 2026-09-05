import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'push_client.dart';

/// The browser half of Web Push: register the push service worker, ask the
/// browser for a subscription bound to the site's VAPID key (fetched from
/// the push Worker so it can never drift from the one that signs), and hand
/// back the endpoint and keys the server needs to reach this browser.
///
/// The browser asks the person for permission inside `subscribe`; that is
/// why callers wire it to a button and never to a page load.
class PushPlatform {
  const PushPlatform._();

  static bool get supported {
    try {
      return web.window.navigator.hasProperty('serviceWorker'.toJS).toDart &&
          web.window.hasProperty('PushManager'.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<PushSubscriptionInfo?> subscribe(String pushUrl) async {
    if (!supported || pushUrl.isEmpty) return null;
    try {
      final keyResponse = await http.get(Uri.parse('$pushUrl/v1/key'));
      if (keyResponse.statusCode != 200) return null;
      final key = (jsonDecode(keyResponse.body) as Map)['key'] as String?;
      if (key == null || key.isEmpty) return null;

      final container = web.window.navigator.serviceWorker;
      await container.register('push_sw.js'.toJS).toDart;
      final registration = await container.ready.toDart;
      final subscription = await registration.pushManager
          .subscribe(web.PushSubscriptionOptionsInit(
            userVisibleOnly: true,
            applicationServerKey: _fromB64url(key).toJS,
          ))
          .toDart;

      final p256dh = subscription.getKey('p256dh');
      final auth = subscription.getKey('auth');
      if (p256dh == null || auth == null) return null;
      return PushSubscriptionInfo(
        endpoint: subscription.endpoint,
        p256dh: _toB64url(p256dh.toDart.asUint8List()),
        auth: _toB64url(auth.toDart.asUint8List()),
        userAgent: web.window.navigator.userAgent,
      );
    } catch (_) {
      // Refused, offline, or a browser that lies about support: no
      // subscription, and the caller says so in words.
      return null;
    }
  }

  static Future<String?> unsubscribe() async {
    if (!supported) return null;
    try {
      final registration =
          await web.window.navigator.serviceWorker.getRegistration('push_sw.js').toDart;
      if (registration == null) return null;
      final subscription = await registration.pushManager.getSubscription().toDart;
      if (subscription == null) return null;
      final endpoint = subscription.endpoint;
      await subscription.unsubscribe().toDart;
      return endpoint;
    } catch (_) {
      return null;
    }
  }

  static Uint8List _fromB64url(String text) {
    final normalised = text.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalised.padRight((normalised.length + 3) ~/ 4 * 4, '=');
    return base64Decode(padded);
  }

  static String _toB64url(Uint8List bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');
}
