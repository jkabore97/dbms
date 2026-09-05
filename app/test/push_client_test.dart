import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/notify/push_client.dart';

/// The push client on a platform with no browser and a build with no
/// Worker: it must say so, and never hand back a subscription that cannot
/// ring — a toggle that appears and does nothing teaches people the app
/// is broken.
void main() {
  test('without a push Worker or a browser, push is honestly unavailable',
      () async {
    expect(PushClient.url, isEmpty); // no --dart-define in a test run
    expect(PushClient.available, isFalse);
    expect(await PushClient.subscribe(), isNull);
    expect(await PushClient.unsubscribe(), isNull);
  });

  test('a subscription carries exactly what the address book stores', () {
    const sub = PushSubscriptionInfo(
      endpoint: 'https://push.example/abc',
      p256dh: 'BP...',
      auth: 'a...',
      userAgent: 'Chrome on Android',
    );
    expect(sub.endpoint, 'https://push.example/abc');
    expect(sub.p256dh, 'BP...');
    expect(sub.auth, 'a...');
    expect(sub.userAgent, 'Chrome on Android');
  });
}
