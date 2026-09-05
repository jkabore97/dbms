import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// What the app tells the crash reporter, and what it keeps to itself.
///
/// Until this existed an error in production was invisible unless a user
/// described it — and a shopkeeper who hits a white screen does not file a
/// report, she stops using the app. Sentry catches what Flutter's own
/// handlers see (uncaught errors, framework errors) and sends the stack.
///
/// Kept to itself, on purpose: no personal data (`sendDefaultPii` off — no
/// user email or ip on an event), no performance traces (they cost quota
/// and answer nothing a stack does not), and nothing at all when the build
/// has no DSN. The DSN is public by design (it ships in every client and
/// can only *send*), so it may live in a repository variable.
class CrashReporting {
  const CrashReporting._();

  /// The build-time switch: `--dart-define=SENTRY_DSN=...`. Empty means off.
  static const dsn = String.fromEnvironment('SENTRY_DSN');

  static bool get enabled => dsn.isNotEmpty;

  /// Applies the app's policy to Sentry's options. Split out so a test can
  /// prove the policy without starting the SDK.
  static void configure(SentryFlutterOptions options, {String? version}) {
    options.dsn = dsn;
    options.environment = kReleaseMode ? 'production' : 'development';
    if (version != null && version.isNotEmpty) options.release = 'kaj@$version';
    options.sendDefaultPii = false;
    options.tracesSampleRate = 0.0;
    options.attachScreenshot = false;
    // Debug-mode errors are seen on the developer's own screen; reporting
    // them would fill the inbox with work in progress.
    options.debug = false;
  }

  /// Runs [app] under the reporter when a DSN exists, and bare otherwise —
  /// the same code path either way, so a build without a DSN cannot behave
  /// differently from one with.
  static Future<void> run(Future<void> Function() app, {String? version}) {
    if (!enabled) return app();
    return SentryFlutter.init(
      (options) => configure(options, version: version),
      appRunner: app,
    );
  }

  /// A caught error worth knowing about, without crashing anything.
  static Future<void> report(Object error, [StackTrace? stack]) async {
    if (!enabled) return;
    await Sentry.captureException(error, stackTrace: stack);
  }
}
