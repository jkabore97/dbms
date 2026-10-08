// The app's own files, kept for use without a connection — on the web, by
// the service worker (web/mara_sw.js); on Android they are the app itself.
export 'offline_app_stub.dart' if (dart.library.js_interop) 'offline_app_web.dart';
