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
}
