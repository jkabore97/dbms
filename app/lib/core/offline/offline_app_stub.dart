/// Android (and tests): the app's files are installed with it — there is
/// nothing to download, so this step is already done.
class OfflineApp {
  const OfflineApp._();

  /// Whether this platform keeps a copy of the app itself (the web).
  static bool get needsCopy => false;

  static Future<bool> get kept async => true;

  static Future<bool> keep({void Function(int done, int total)? progress}) async =>
      true;

  static Future<void> forget() async {}

  /// Whether the platform promised to keep the app's storage. An app's own
  /// files on Android and iOS are never cleared to make room the way a
  /// browser clears a site's, so: yes, already.
  static Future<bool> get storageKept async => true;

  /// Nothing to ask outside a browser.
  static Future<bool> keepStorage() async => true;
}
