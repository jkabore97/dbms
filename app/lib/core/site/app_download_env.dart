/// Where the web's « download the app » pop-up runs: which phone, whether
/// Mara is already installed there, and when the pop-up was last shown.
/// The browser's answer is app_download_env_web.dart's; the Android app
/// and the tests get [AppDownloadEnv.none] (no pop-up) unless they say
/// otherwise.
library;

enum AppPhone { android, ios }

class AppDownloadEnv {
  const AppDownloadEnv({
    required this.phone,
    required this.standalone,
    required this.readShownAt,
    required this.writeShownAt,
  });

  /// Not a browser at all.
  const AppDownloadEnv.none()
      : phone = null,
        standalone = false,
        readShownAt = _never,
        writeShownAt = _forget;

  /// The phone's system, or null on a computer.
  final AppPhone? phone;

  /// Opened as the installed web app (from the home screen).
  final bool standalone;

  final DateTime? Function() readShownAt;
  final void Function(DateTime at) writeShownAt;

  static DateTime? _never() => null;
  static void _forget(DateTime _) {}
}
