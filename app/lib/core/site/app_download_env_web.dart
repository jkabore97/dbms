import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'app_download_env.dart';

const _key = 'mara.app_download.shown_at';

/// The browser as it is: the phone's system from its user agent, the
/// installed web app (display-mode standalone, or Safari's own flag), and
/// when the pop-up was last shown, in this browser's storage.
AppDownloadEnv browserEnv() {
  final nav = web.window.navigator;
  final ua = nav.userAgent;
  final AppPhone? phone;
  if (RegExp('Android', caseSensitive: false).hasMatch(ua)) {
    phone = AppPhone.android;
  } else if (RegExp('iPhone|iPad|iPod').hasMatch(ua) ||
      // iPadOS asks for the desktop site: a « Macintosh » that can be touched.
      (ua.contains('Macintosh') && nav.maxTouchPoints > 1)) {
    phone = AppPhone.ios;
  } else {
    phone = null;
  }
  var standalone = false;
  try {
    standalone = web.window.matchMedia('(display-mode: standalone)').matches ||
        web.window.matchMedia('(display-mode: fullscreen)').matches ||
        // Safari on iOS, opened from the home screen.
        nav.getProperty<JSAny?>('standalone'.toJS).dartify() == true;
  } catch (_) {}
  return AppDownloadEnv(
    phone: phone,
    standalone: standalone,
    readShownAt: () {
      try {
        final v = web.window.localStorage.getItem(_key);
        return v == null ? null : DateTime.tryParse(v);
      } catch (_) {
        return null;
      }
    },
    writeShownAt: (at) {
      try {
        web.window.localStorage.setItem(_key, at.toIso8601String());
      } catch (_) {}
    },
  );
}
