import 'package:supabase_flutter/supabase_flutter.dart';

import 'browser_storage_stub.dart'
    if (dart.library.js_interop) 'browser_storage_web.dart' as browser;

export 'browser_storage_stub.dart'
    if (dart.library.js_interop) 'browser_storage_web.dart' show browserStorageBlocked;

/// The session kept in memory only: for a browser that refuses the page its
/// storage. Supabase's own storage reads `window.localStorage` at start and
/// the app stopped on « L'application n'a pas pu démarrer » (the owner's
/// screenshot). With this the app opens and works; the person signs in
/// again on their next visit, as a private window would.
class MemoryLocalStorage extends LocalStorage {
  MemoryLocalStorage();
  String? _session;

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => _session != null;
  @override
  Future<String?> accessToken() async => _session;
  @override
  Future<void> removePersistedSession() async => _session = null;
  @override
  Future<void> persistSession(String persistSessionString) async => _session = persistSessionString;
}

/// The PKCE verifier, in memory for the same browsers: a sign-in started
/// and finished on the same page still works.
class MemoryAsyncStorage extends GotrueAsyncStorage {
  MemoryAsyncStorage();
  final _items = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _items[key];
  @override
  Future<void> setItem({required String key, required String value}) async => _items[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

/// Whether the session must stay in memory on this device.
bool keepSessionInMemory() => browser.browserStorageBlocked();
