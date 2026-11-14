import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/memory_auth_storage.dart';

/// A browser that refuses the page its storage (the owner's screenshot:
/// « SecurityError: Failed to read the 'localStorage' property ») keeps the
/// session and the sign-in's verifier in memory, and the app starts.
void main() {
  test('the session in memory: kept, read, removed', () async {
    final s = MemoryLocalStorage();
    await s.initialize();
    expect(await s.hasAccessToken(), isFalse);
    await s.persistSession('{"access_token":"x"}');
    expect(await s.hasAccessToken(), isTrue);
    expect(await s.accessToken(), '{"access_token":"x"}');
    await s.removePersistedSession();
    expect(await s.accessToken(), isNull);
  });

  test('the sign-in verifier in memory', () async {
    final a = MemoryAsyncStorage();
    await a.setItem(key: 'k', value: 'v');
    expect(await a.getItem(key: 'k'), 'v');
    await a.removeItem(key: 'k');
    expect(await a.getItem(key: 'k'), isNull);
  });

  test('off the web, nothing is blocked: the device storage as before', () {
    expect(keepSessionInMemory(), isFalse);
  });
}
