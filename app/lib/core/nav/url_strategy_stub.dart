/// Android has no address bar, so there is no URL strategy to choose.
///
/// This exists so `main()` can call one function unconditionally: the web
/// implementation is swapped in by the conditional export in
/// `url_strategy.dart`, and the mobile build never sees `flutter_web_plugins`
/// at all — importing it there is a compile error, not a no-op.
void useCleanUrls() {}
