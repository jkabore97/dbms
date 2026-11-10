// 173c: the iPhone app opens « Acheter mes billets » and « Mes billets »
// itself (Universal Links). The app declares marakaj.com; the site's
// Worker serves Apple's list (workers/kaj-app tests). The bundle id stays.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the iPhone app declares applinks:marakaj.com, Sign in with Apple kept, its bundle id unchanged', () {
    final ent = File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(ent, contains('<key>com.apple.developer.associated-domains</key>'));
    expect(ent, contains('<string>applinks:marakaj.com</string>'));
    expect(ent, contains('<key>com.apple.developer.applesignin</key>'));
    final proj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(proj, contains('PRODUCT_BUNDLE_IDENTIFIER = bf.kaj.app;'));
  });

  test('the router knows both addresses Apple sends to the app', () {
    final src = File('lib/core/nav/router.dart').readAsStringSync();
    expect(src, contains("static const buyTickets = '/achat-billets';"));
    expect(src, contains("static const myTickets = '/billets';"));
  });
}
