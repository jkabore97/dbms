import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/theme/motion.dart';
import 'package:kaj_app/features/storefront/shop_style.dart';

/// The street's motion, the goods sites' way: blocks rise as they scroll
/// into view, photographs lean in under the pointer, links draw their
/// underline, the strip over the header turns its lines, the header steps
/// out of the way going down and back going up, and a sheet is a drawer
/// on a desk.
void main() {
  double opacityOf(WidgetTester tester, Key key) => tester
      .widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byKey(key),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;

  testWidgets('ScrollReveal: in view rises at once, below the fold waits', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              const ScrollReveal(child: SizedBox(key: Key('top'), height: 100)),
              const SizedBox(height: 2000),
              const ScrollReveal(child: SizedBox(key: Key('far'), height: 100)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(opacityOf(tester, const Key('top')), 1);
    // ListView builds lazily: the far block is not even built yet. Scroll
    // until it is, and it rises once there.
    await tester.dragUntilVisible(
      find.byKey(const Key('far')),
      find.byType(ListView),
      const Offset(0, -400),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(opacityOf(tester, const Key('far')), 1);
  });

  testWidgets('ZoomOnHover: the picture leans in, and back', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: ZoomOnHover(child: ColoredBox(color: Colors.red)),
          ),
        ),
      ),
    );
    double scale() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(scale(), 1);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(ZoomOnHover)));
    await tester.pump();
    expect(scale(), greaterThan(1));
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(scale(), 1);
  });

  testWidgets('UnderlineLink: a link that taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: UnderlineLink(
              label: 'Toutes les vitrines',
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Toutes les vitrines'));
    expect(taps, 1);
    expect(find.bySemanticsLabel('Toutes les vitrines'), findsOneWidget);
  });

  testWidgets('the strip over the header turns its lines', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ShopAnnouncement(lines: ['Un', 'Deux'])),
      ),
    );
    expect(find.text('Un'), findsOneWidget);
    await tester.pump(ShopAnnouncement.every);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Deux'), findsOneWidget);
    expect(find.text('Un'), findsNothing);
  });

  testWidgets('the header steps away going down, and back going up', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShopPage(
          title: 'Les vitrines',
          announcements: ShopPage.street,
          body: ListView(
            children: [
              for (var i = 0; i < 60; i++)
                SizedBox(height: 80, child: Text('ligne $i')),
            ],
          ),
        ),
      ),
    );
    double heightFactor() =>
        tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).heightFactor!;
    expect(heightFactor(), 1);
    expect(find.text(ShopPage.street.first), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(heightFactor(), 0, reason: 'scrolling into the page hides it');

    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pump();
    expect(heightFactor(), 1, reason: 'the first move back brings it back');
  });

  group('a sheet', () {
    Future<void> open(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showShopSheet<void>(
                    context: context,
                    builder: (_) => const Text('Votre commande'),
                  ),
                  child: const Text('Ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('is a drawer from the right on a desk', (tester) async {
      await open(tester, 1280);
      expect(find.text('Votre commande'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getTopLeft(find.text('Votre commande')).dx,
          greaterThanOrEqualTo(1280 - 440),
          reason: 'the drawer sits at the right edge');
      await tester.tap(find.byTooltip('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text('Votre commande'), findsNothing);
    });

    testWidgets('comes up from the bottom on a phone', (tester) async {
      await open(tester, 390);
      expect(find.text('Votre commande'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });
}
