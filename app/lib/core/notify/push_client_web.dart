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

  /// A browser with push, and a build that knows the Worker.
  static bool available(String pushUrl) => pushUrl.isNotEmpty && supported;

  /// Nothing to start in a browser.
  static Future<void> prepare() async {}

  static Future<bool> granted() async {
    try {
      return web.window.hasProperty('Notification'.toJS).toDart &&
          web.Notification.permission == 'granted';
    } catch (_) {
      return false;
    }
  }

  /// A browser's tap is opened by the service worker (push_sw.js /
  /// mara_sw.js), not by the page: nothing comes through here.
  static Stream<String> get opened => const Stream.empty();

  /// The subscription this browser already holds, asking nothing.
  static Future<PushSubscriptionInfo?> current() async {
    if (!supported) return null;
    try {
      final registration =
          await web.window.navigator.serviceWorker.getRegistration('/').toDart;
      if (registration == null) return null;
      final subscription = await registration.pushManager.getSubscription().toDart;
      if (subscription == null) return null;
      return _info(subscription);
    } catch (_) {
      return null;
    }
  }

  static PushSubscriptionInfo? _info(web.PushSubscription subscription) {
    final p256dh = subscription.getKey('p256dh');
    final auth = subscription.getKey('auth');
    if (p256dh == null || auth == null) return null;
    return PushSubscriptionInfo(
      endpoint: subscription.endpoint,
      p256dh: _toB64url(p256dh.toDart.asUint8List()),
      auth: _toB64url(auth.toDart.asUint8List()),
      userAgent: web.window.navigator.userAgent,
    );
  }

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
      // The browser's question first, at the tap itself (115): Firefox and
      // Safari only ask from inside the person's gesture, and the key's
      // download and the worker's wait below could outlast it.
      if (web.Notification.permission == 'default') {
        final answer = await web.Notification.requestPermission().toDart;
        if (answer.toDart != 'granted') return null;
      }
      if (web.Notification.permission != 'granted') return null;

      final keyResponse = await http.get(Uri.parse('$pushUrl/v1/key'));
      if (keyResponse.statusCode != 200) return null;
      final key = (jsonDecode(keyResponse.body) as Map)['key'] as String?;
      if (key == null || key.isEmpty) return null;

      final registration = await _activeRegistration();
      if (registration == null) return null;
      final options = web.PushSubscriptionOptionsInit(
        userVisibleOnly: true,
        applicationServerKey: _fromB64url(key).toJS,
      );
      web.PushSubscription subscription;
      try {
        subscription = await registration.pushManager.subscribe(options).toDart;
      } catch (_) {
        // A subscription made with another key (a VAPID pair renewed) is
        // refused as it stands: dropped, and made again with this one.
        final old = await registration.pushManager.getSubscription().toDart;
        if (old == null) rethrow;
        await old.unsubscribe().toDart;
        subscription = await registration.pushManager.subscribe(options).toDart;
      }
      return _info(subscription);
    } catch (_) {
      // Refused, offline, or a browser that lies about support: no
      // subscription, and the caller says so in words.
      return null;
    }
  }

  /// The registration holding this site's scope with a worker running —
  /// what pushManager.subscribe needs. The worker every visitor has is
  /// mara_sw.js (index.html), which carries the push handlers
  /// (push_handlers.js); registering push_sw.js over it would throw the
  /// kept app away, so the bare one is registered only when no worker
  /// holds the scope, or none became active in time (mara_sw.js refuses
  /// to install in a build the deploy did not prepare).
  static Future<web.ServiceWorkerRegistration?> _activeRegistration() async {
    final container = web.window.navigator.serviceWorker;
    final current = await container.getRegistration('/').toDart;
    if (current != null && current.active != null) return current;
    if (current != null) {
      final ready = await container.ready.toDart
          .then<web.ServiceWorkerRegistration?>((r) => r)
          .timeout(const Duration(seconds: 15), onTimeout: () => null);
      if (ready != null && ready.active != null) return ready;
    }
    await container.register('/push_sw.js'.toJS, web.RegistrationOptions(scope: '/')).toDart;
    return container.ready.toDart
        .then<web.ServiceWorkerRegistration?>((r) => r)
        .timeout(const Duration(seconds: 15), onTimeout: () => null);
  }

  static Future<String?> unsubscribe() async {
    if (!supported) return null;
    try {
      final registration =
          await web.window.navigator.serviceWorker.getRegistration('/').toDart;
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
