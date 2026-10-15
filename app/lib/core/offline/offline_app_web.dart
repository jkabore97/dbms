import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// The web: the app's files are kept by web/mara_sw.js, the service worker
/// every visitor gets (index.html registers it once the app shows). It
/// keeps what a visit used, cache-first; « Télécharger pour hors ligne »
/// asks it to keep the rest — the business half, every asset — and every
/// later build keeps it too.
class OfflineApp {
  const OfflineApp._();

  static bool get needsCopy => _supported;

  static bool get _supported {
    try {
      return web.window.navigator.hasProperty('serviceWorker'.toJS).toDart &&
          web.window.hasProperty('caches'.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  /// The worker in charge of this page, or null (none yet, or not ours).
  static Future<web.ServiceWorker?> _worker() async {
    final reg =
        await web.window.navigator.serviceWorker.getRegistration('/').toDart;
    final active = reg?.active;
    if (active == null || !active.scriptURL.endsWith('/mara_sw.js')) {
      return null;
    }
    return active;
  }

  /// Asks the worker one thing and waits for its answer, which comes back
  /// on a port of its own; [onMessage] returns true when it is the last.
  static Future<bool> _ask(
    web.ServiceWorker worker,
    String type,
    bool Function(JSObject data) onMessage, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final done = Completer<bool>();
    final channel = web.MessageChannel();
    channel.port1.onmessage = ((web.MessageEvent event) {
      final data = event.data as JSObject?;
      if (data == null || done.isCompleted) return;
      if (onMessage(data)) done.complete(true);
    }).toJS;
    worker.postMessage(JSObject()..['type'] = type.toJS, [channel.port2].toJS);
    return done.future.timeout(timeout, onTimeout: () => false);
  }

  /// Whether this browser keeps the whole app for use without a network.
  static Future<bool> get kept async {
    if (!_supported) return false;
    try {
      final worker = await _worker();
      if (worker == null) return false;
      var offline = false;
      await _ask(worker, 'status', (data) {
        offline = (data['offline'] as JSBoolean?)?.toDart ?? false;
        return true;
      });
      return offline;
    } catch (_) {
      return false;
    }
  }

  /// « Télécharger pour hors ligne »: the worker fetches and keeps every
  /// file of this build a business needs (both halves of the app, every
  /// asset, this browser's engine), and says how far it got.
  static Future<bool> keep({void Function(int done, int total)? progress}) async {
    if (!_supported) return false;
    try {
      // On the very first visit the worker may still be settling in.
      final container = web.window.navigator.serviceWorker;
      var worker = await _worker();
      if (worker == null) {
        await container.ready.toDart.timeout(const Duration(seconds: 20));
        worker = await _worker();
      }
      if (worker == null) return false;
      return await _ask(worker, 'precache', (data) {
        final type = (data['type'] as JSString?)?.toDart;
        final count = (data['done'] as JSNumber?)?.toDartInt ?? 0;
        if (type == 'progress') {
          final total = (data['total'] as JSNumber?)?.toDartInt ?? count;
          progress?.call(count, total);
          return false;
        }
        // A file missing from this build (another renderer's engine, say)
        // is not a failure; the shell and the code are what count.
        return type == 'done';
      }, timeout: const Duration(minutes: 10));
    } catch (_) {
      return false;
    }
  }

  /// Takes the copy back off this browser (Compte › Hors ligne): the
  /// worker drops everything it kept and steps down; the next visit keeps
  /// only what it uses, like any visitor's.
  static Future<void> forget() async {
    if (!_supported) return;
    try {
      final worker = await _worker();
      if (worker != null) await _ask(worker, 'forget', (_) => true);
    } catch (_) {}
  }

  // ----------------------------------------------------------------
  // The browser's promise to keep this site's storage
  // ----------------------------------------------------------------
  // Unsent sales, the outbox and the photo queue live in IndexedDB (the
  // sqflite wasm database). A browser may clear a site's storage to make
  // room, and Safari clears that of a site not visited for seven days —
  // a shop's phone left a week in a drawer would lose what it had not
  // sent. navigator.storage.persist() asks the browser to keep it until
  // the person clears it themselves.

  static web.StorageManager? get _storage {
    try {
      final navigator = web.window.navigator;
      if (!navigator.hasProperty('storage'.toJS).toDart) return null;
      final storage = navigator.storage;
      if (!storage.hasProperty('persist'.toJS).toDart) return null;
      return storage;
    } catch (_) {
      return null;
    }
  }

  /// Whether the browser already promised to keep it — asked without
  /// asking the person anything.
  static Future<bool> get storageKept async {
    final storage = _storage;
    if (storage == null) return false;
    try {
      return (await storage.persisted().toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  /// Asks for the promise. The browser decides: Chrome and Safari answer
  /// on their own (how much the site is used, whether it is on the home
  /// screen), Firefox may ask the person. Called synchronously from a tap
  /// where it can be, so the request carries that gesture. Never throws.
  static Future<bool> keepStorage() async {
    final storage = _storage;
    if (storage == null) return false;
    try {
      return (await storage.persist().toDart).toDart;
    } catch (_) {
      return false;
    }
  }
}
