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
    expect(find.text('Powered by'), findsOneWidget);
    expect(find.text('KAJ'), findsOneWidget);
    expect(find.byKey(const Key('kaj-wordmark')), findsOneWidget);
    expect(find.byKey(const Key('kaj-logo')), findsOneWidget);
    expect(find.bySemanticsLabel('Powered by KAJ'), findsOneWidget);
    expect(find.text('Des vitrines de quartier, tenues par les boutiques.'),
        findsNothing);
  });
}
