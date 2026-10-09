import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

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
  static bool _listening = false;
  static String? _error;
  static Future<void>? _starting;
  static final _opened = StreamController<String>.broadcast();

  /// MainActivity's `bf.kaj.app/notify` (120): the system's own answer on
  /// the permission — which Firebase cannot give: it says « denied » for
  /// a phone never asked as for one that refused for good — and the
  /// app's notification settings.
  static const _channel = MethodChannel('bf.kaj.app/notify');

  /// FCM needs no Worker address on the phone: the Worker reaches Google.
  static bool available(String pushUrl) => _ready;

  static Future<void> prepare() => _starting ??= _start();

  /// After a failed start, once more (the diagnostics' « Réessayer »).
  static Future<void> retry() {
    if (!_ready) _starting = null;
    return prepare();
  }

  static Future<void> _start() async {
    // The real phone, not the platform a test pretends to be.
    if (!Platform.isAndroid) return;
    try {
      // No options: they come from the resources the google-services
      // Gradle plugin generates from android/app/google-services.json. A
      // build made without the file has none, and this throws.
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      _ready = true;
      _error = null;
      if (!_listening) {
        _listening = true;
        FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data));
        final first = await FirebaseMessaging.instance.getInitialMessage();
        if (first != null) _open(first.data);
      }
    } catch (e) {
      _ready = false;
      _error = '$e';
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
      final allowed = await ask(() async =>
          (await FirebaseMessaging.instance.requestPermission()).authorizationStatus);
      if (!allowed) return null;
      return await current();
    } catch (_) {
      return null;
    }
  }

  /// The system's question, then — only once it has answered — a word to
  /// MainActivity, which notes a real refusal (the system then offers a
  /// reason to show): after a second one it stops asking, and [permission]
  /// can tell « blocked ». Noted before the question, a dialog dismissed
  /// without an answer (back, a tap beside it) marked the phone « blocked »
  /// though the system would still ask. Answers whether it is allowed.
  @visibleForTesting
  static Future<bool> ask(Future<AuthorizationStatus> Function() request) async {
    final status = await request();
    try {
      await _channel.invokeMethod<void>('answered');
    } catch (_) {}
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
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

  static Future<PushPermission> permission() async {
    if (!Platform.isAndroid) return PushPermission.unsupported;
    try {
      return switch (await _channel.invokeMethod<String>('permission')) {
        'granted' => PushPermission.granted,
        'blocked' => PushPermission.blocked,
        _ => PushPermission.prompt,
      };
    } catch (_) {
      // An app without the channel: Firebase's word, never « blocked ».
      return await granted() ? PushPermission.granted : PushPermission.prompt;
    }
  }

  static Future<bool> openSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<PushDeviceFacts> facts() async {
    if (!Platform.isAndroid) {
      return PushDeviceFacts(platform: Platform.operatingSystem);
    }
    await prepare();
    return PushDeviceFacts(
      platform: 'Android',
      firebaseReady: _ready,
      firebaseError: _error,
    );
  }
}
