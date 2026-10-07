import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

/// The browser half of the ring: an <audio> element on the bundled asset,
/// and `navigator.vibrate` where the browser has it (Chrome on Android; not
/// a desktop, not an iPhone — there it is simply skipped).
class AlertTonePlatform {
  const AlertTonePlatform._();

  static Future<void> play(String asset) async {
    try {
      final audio = web.HTMLAudioElement()
        ..src = ui_web.assetManager.getAssetUrl(asset);
      await audio.play().toDart;
    } catch (_) {
      // A browser that refuses sound before the first tap — quiet, not an
      // error.
    }
  }

  static Future<void> vibrate() async {
    try {
      final navigator = web.window.navigator;
      if (!navigator.hasProperty('vibrate'.toJS).toDart) return;
      navigator.vibrate(<JSNumber>[180.toJS, 90.toJS, 180.toJS].toJS);
    } catch (_) {}
  }
}
