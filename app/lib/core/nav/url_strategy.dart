/// Clean addresses on the web, and nothing at all on Android.
///
/// The conditional export is what keeps `flutter_web_plugins` out of the
/// mobile build: it is a web-only package, and importing it unconditionally
/// breaks the APK rather than being ignored.
export 'url_strategy_stub.dart'
    if (dart.library.js_interop) 'url_strategy_web.dart';
