import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/theme/motion.dart';

/// The street showed two shops of seven (094): each tile listened to the
/// grid around it, a shrink-wrapped grid that never scrolls, so a tile
/// below the first screen never learnt it had come into view.
void main() {
  testWidgets('a tile in a grid inside the page appears once scrolled to',
      (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final page = ScrollController();
    addTearDown(page.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: page,
          children: [
            const SizedBox(height: 300),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 8; i++)
                  ScrollReveal(
                      child: SizedBox(
                          key: Key('tile-$i'), height: 200, child: Text('$i'))),
              ],
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    double opacityOf(int i) => tester
        .widget<AnimatedOpacity>(find
            .ancestor(
                of: find.byKey(Key('tile-$i')),
                matching: find.byType(AnimatedOpacity))
            .first)
        .opacity;
    expect(opacityOf(0), 1);
    expect(opacityOf(7), 0, reason: 'far below the screen, not yet shown');
    page.jumpTo(page.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(opacityOf(7), 1, reason: 'scrolled to, so shown');
  });
}
