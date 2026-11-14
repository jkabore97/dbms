import 'package:web/web.dart' as web;

/// Whether this browser refuses the page its localStorage (« Bloquer les
/// données des sites », some apps' built-in browsers): merely reading
/// `window.localStorage` then throws a SecurityError. The value is used —
/// a bare `localStorage.length;` was dropped by the compiler and the check
/// always said « not blocked ».
bool browserStorageBlocked() {
  try {
    final storage = web.window.localStorage;
    return storage.getItem('mk-storage-probe') == '\u0000';
  } catch (_) {
    return true;
  }
}
