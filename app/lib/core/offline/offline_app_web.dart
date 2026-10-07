import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// The web: the app's files are kept by web/offline_sw.js, a network-first
/// worker that answers from its copy only when the network does not.
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

  /// Whether this browser already keeps the copy.
  static Future<bool> get kept async {
    if (!_supported) return false;
    try {
      final reg = await web.window.navigator.serviceWorker
          .getRegistration('/')
          .toDart;
      final script = reg?.active?.scriptURL ?? '';
      if (!script.endsWith('offline_sw.js')) return false;
      return (await web.window.caches.has('mara-offline-v1').toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  /// « Télécharger pour hors ligne »: registers the worker and has it fetch
  /// and keep every file this page has loaded, plus the ones it will need
  /// (the business half, the engine for either renderer, the database).
  static Future<bool> keep({void Function(int done, int total)? progress}) async {
    if (!_supported) return false;
    try {
      final container = web.window.navigator.serviceWorker;
      await container.register('offline_sw.js'.toJS).toDart;
      final reg = await container.ready.toDart;
      final worker = reg.active;
      if (worker == null) return false;

      final origin = web.window.location.origin;
      final urls = <String>{'$origin/'};
      final entries = web.window.performance.getEntriesByType('resource').toDart;
      for (final e in entries) {
        final name = e.name;
        if (name.startsWith(origin) && !name.contains('/version.json')) {
          urls.add(name.split('#').first);
        }
      }
      for (final path in const [
        'index.html',
        'flutter_bootstrap.js',
        'flutter.js',
        'main.dart.js',
        'main.dart.js_1.part.js',
        'manifest.json',
        'favicon.png',
        'sqflite_sw.js',
        'sqlite3.wasm',
        'push_sw.js',
        'canvaskit/canvaskit.js',
        'canvaskit/canvaskit.wasm',
        'canvaskit/chromium/canvaskit.js',
        'canvaskit/chromium/canvaskit.wasm',
        'assets/FontManifest.json',
        'assets/AssetManifest.bin.json',
        'assets/fonts/MaterialIcons-Regular.otf',
      ]) {
        urls.add('$origin/$path');
      }

      final done = Completer<bool>();
      final channel = web.MessageChannel();
      channel.port1.onmessage = ((web.MessageEvent event) {
        final data = event.data as JSObject?;
        if (data == null) return;
        final type = (data['type'] as JSString?)?.toDart;
        final count = (data['done'] as JSNumber?)?.toDartInt ?? 0;
        if (type == 'progress') {
          final total = (data['total'] as JSNumber?)?.toDartInt ?? urls.length;
          progress?.call(count, total);
        } else if (type == 'done' && !done.isCompleted) {
          // A file missing from this build (the other renderer's engine,
          // say) is not a failure; the shell and the code are what count.
          done.complete(true);
        }
      }).toJS;
      final message = JSObject()
        ..['type'] = 'precache'.toJS
        ..['urls'] = [for (final u in urls) u.toJS].toJS;
      worker.postMessage(message, [channel.port2].toJS);
      return await done.future.timeout(const Duration(minutes: 5),
          onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  /// Takes the copy back off this browser (Compte › Hors ligne).
  static Future<void> forget() async {
    if (!_supported) return;
    try {
      final reg = await web.window.navigator.serviceWorker
          .getRegistration('/')
          .toDart;
      await web.window.caches.delete('mara-offline-v1').toDart;
      if ((reg?.active?.scriptURL ?? '').endsWith('offline_sw.js')) {
        await reg!.unregister().toDart;
      }
    } catch (_) {}
  }
}
