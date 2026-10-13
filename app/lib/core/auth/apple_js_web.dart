import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const _src =
    'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js';

Future<bool>? _loading;

/// Adds Apple's script to the page once and waits for `window.AppleID`;
/// false when it could not be loaded (offline, blocked) within 15 s —
/// asked again next time.
Future<bool> ensureAppleJs() {
  if (_ready()) return Future.value(true);
  return _loading ??= _load().then((ok) {
    if (!ok) _loading = null;
    return ok;
  });
}

bool _ready() {
  try {
    return web.window.has('AppleID');
  } catch (_) {
    return false;
  }
}

Future<bool> _load() async {
  final done = Completer<bool>();
  try {
    final script = web.HTMLScriptElement()
      ..src = _src
      ..async = true;
    script.onload = ((web.Event _) {
      if (!done.isCompleted) done.complete(_ready());
    }).toJS;
    script.onerror = ((web.Event _) {
      if (!done.isCompleted) done.complete(false);
    }).toJS;
    web.document.head?.appendChild(script);
  } catch (_) {
    return false;
  }
  return done.future.timeout(const Duration(seconds: 15), onTimeout: () => false);
}
