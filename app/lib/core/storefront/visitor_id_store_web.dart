import 'package:web/web.dart' as web;

const _key = 'mara.visitor_id';

/// The browser's own copy of the visitor id (123), in its localStorage:
/// read before anything else, so a vitrine opened in this browser is one
/// visitor even when the app's local database cannot open. Null when the
/// storage is blocked (a private window) or empty.
String? readBrowserVisitorId() {
  try {
    return web.window.localStorage.getItem(_key);
  } catch (_) {
    return null;
  }
}

void writeBrowserVisitorId(String id) {
  try {
    web.window.localStorage.setItem(_key, id);
  } catch (_) {}
}
