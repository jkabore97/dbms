import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_client.dart';

/// Everywhere that is not a browser — the Android app (115): Firebase Cloud
/// Messaging. Firebase starts only in a build that carries
/// android/app/google-services.json (the Gradle plugin is applied only
/// then); without it initializeApp fails, [available] stays false, and the
/// app offers no push rather than a switch that never rings. Off Android
/// (a test on the host) it is never started.
class PushPlatform {
  const PushPlatform._();

  static bool _ready = false;
  static Future<void>? _starting;
  static final _opened = StreamController<String>.broadcast();

  /// FCM needs no Worker address on the phone: the Worker reaches Google.
  static bool available(String pushUrl) => _ready;

  static Future<void> prepare() => _starting ??= _start();

  static Future<void> _start() async {
    // The real phone, not the platform a test pretends to be.
    if (!Platform.isAndroid) return;
    try {
      await Firebase.initializeApp();
      _ready = true;
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data));
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) _open(first.data);
    } catch (_) {
      _ready = false;
    }
  }

  /// Where the Worker said a tap lands (payloadFor's path): one of the
  /// app's own addresses, never anything else.
  static void _open(Map<String, dynamic> data) {
    final path = data['path'];
    if (path is String && path.startsWith('/') && !path.startsWith('//')) _opened.add(path);
  }

  static Stream<String> get opened => _opened.stream;

  static Future<bool> granted() async {
    if (!_ready) return false;
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  /// Asks (Android 13 and later show the system's question; older ones
  /// allow at install) and answers this phone's token.
  static Future<PushSubscriptionInfo?> subscribe(String pushUrl) async {
    if (!_ready) return null;
    try {
      final s = await FirebaseMessaging.instance.requestPermission();
      if (s.authorizationStatus != AuthorizationStatus.authorized &&
          s.authorizationStatus != AuthorizationStatus.provisional) {
        return null;
      }
      return await current();
    } catch (_) {
      return null;
    }
  }

  static Future<PushSubscriptionInfo?> current() async {
    if (!_ready) return null;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      return token == null || token.isEmpty
          ? null
          : PushSubscriptionInfo.fcm(token, userAgent: 'Android');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> unsubscribe() async {
    if (!_ready) return null;
    try {
      final now = await current();
      await FirebaseMessaging.instance.deleteToken();
      return now?.endpoint;
    } catch (_) {
      return null;
    }
  }
}
