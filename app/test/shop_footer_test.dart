import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/features/storefront/shop_style.dart';

/// The bottom of every street page: « Powered by KAJ » with the owner's
/// mark (KAJ Consulting's K), in place of the old wordmark and tagline.
void main() {
  testWidgets('Powered by KAJ, with the KAJ Consulting mark', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ShopFooter())),
    ));
    expect(find.text('POWERED BY'), findsOneWidget);
    expect(find.byKey(const Key('kaj-logo')), findsOneWidget);
    expect(find.bySemanticsLabel('Powered by KAJ Consulting'), findsOneWidget);
    expect(find.text('Des vitrines de quartier, tenues par les boutiques.'),
        findsNothing);
  });

  testWidgets('« Toutes les vitrines » comes first, then the footer band, '
      'centred', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(child: ShopFooter(onDirectory: () {}))),
    ));
    final link = tester.getCenter(find.byKey(const Key('footer-directory')));
    final band = tester.getRect(find.byKey(const Key('shop-footer')));
    final powered = tester.getCenter(find.text('POWERED BY'));
    expect(link.dy, lessThan(band.top), reason: 'the link sits above the footer');
    expect(band.width, 400, reason: 'the band spans the page');
    expect(powered.dx, closeTo(200, 1), reason: 'centred');
    expect(link.dx, closeTo(200, 1));
    expect(band.contains(powered), isTrue);
  });
}
