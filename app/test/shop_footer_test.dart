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
    expect(find.textContaining('POWERED BY KAJ'), findsOneWidget);
    expect(find.textContaining('Marakaj', findRichText: true), findsWidgets);
    final kaj = (tester.widget<Text>(find.byKey(const Key('powered-by')))
            .textSpan! as TextSpan)
        .children!
        .first as TextSpan;
    expect(kaj.text, 'KAJ');
    expect(kaj.style!.fontWeight, FontWeight.w800, reason: 'KAJ in bold');
    expect(find.text('KAJ CONSULTING'), findsNothing);
    expect(find.text('Au Service du Peuple'), findsOneWidget);
    expect(find.byKey(const Key('kaj-logo')), findsNothing, reason: 'words only');
    expect(find.bySemanticsLabel('Powered by KAJ'), findsOneWidget);
    expect(find.text('Des vitrines de quartier, tenues par les boutiques.'),
        findsNothing);
  });

  testWidgets('« Toutes les vitrines » comes first, then the footer band, '
      'centred', (tester) async {
    // 600 wide, and settled: the band's wordmark is a picture whose width
    // is known once decoded, and the test font draws the slogan twice as
    // wide as a real one — at 400 the slogan's line wrapped or not with
    // the runner's timing (CI went red on 1 November for that alone).
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(child: ShopFooter(onDirectory: () {}))),
    ));
    await tester.pumpAndSettle();
    final link = tester.getCenter(find.byKey(const Key('footer-directory')));
    final band = tester.getRect(find.byKey(const Key('shop-footer')));
    final powered = tester.getCenter(find.byKey(const Key('powered-by')));
    expect(link.dy, lessThan(band.top), reason: 'the link sits above the footer');
    expect(band.width, 600, reason: 'the band spans the page');
    expect(powered.dx, closeTo(300, 1), reason: 'centred');
    expect(link.dx, closeTo(300, 1));
    expect(band.contains(powered), isTrue);
    expect(band.height, lessThan(90), reason: 'a small footer');
  });
}
