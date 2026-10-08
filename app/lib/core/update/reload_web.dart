import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// "Recharger" on the update banner: the new build, now. index.html's
/// `maraUpdate` has the service worker (web/mara_sw.js) hand over the build
/// it prepared — a reload from the phone — or, when it cannot have it ready
/// in time, steps it aside so the reload comes from the network. A page
/// without it (a local build) simply reloads.
void reloadPage() {
  final update = web.window.getProperty<JSAny?>('maraUpdate'.toJS);
  if (update.isA<JSFunction>()) {
    (update as JSFunction).callAsFunction();
    return;
  }
  web.window.location.reload();
}
