import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/observability/crash_reporting.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// The crash reporter's policy, proven without starting the SDK: off with
/// no DSN, and when on, stacks only — no personal data, no traces, no
/// screenshots of somebody's till.
void main() {
  test('a build with no DSN reports nothing, and runs the app bare', () async {
    // No --dart-define in a test run.
    expect(CrashReporting.enabled, isFalse);
    var ran = false;
    await CrashReporting.run(() async => ran = true);
    expect(ran, isTrue);
    // Reporting is a silent no-op, never a throw.
    await CrashReporting.report(StateError('x'), StackTrace.current);
  });

  test('the policy keeps people out of the events', () {
    final options = SentryFlutterOptions();
    CrashReporting.configure(options, version: '0.1.0');
    expect(options.sendDefaultPii, isFalse);
    expect(options.tracesSampleRate, 0.0);
    expect(options.attachScreenshot, isFalse);
    expect(options.release, 'kaj@0.1.0');
    expect(options.environment, 'development'); // tests are not release mode
    expect(options.debug, isFalse);
  });
}
