import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/theme/kaj_card.dart';
import 'package:kaj_app/core/theme/motion.dart';

/// The business side's cards arrive the street's way (ScrollReveal) and
/// are otherwise exactly Cards: every parameter passes through.
void main() {
  testWidgets('a KajCard is a Card that rises into view', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KajCard(
            color: Colors.amber,
            elevation: 3,
            margin: EdgeInsets.all(7),
            child: Text('Ventes du jour'),
          ),
        ),
      ),
    );
    final card = tester.widget<Card>(find.byType(Card));
    expect(card.color, Colors.amber);
    expect(card.elevation, 3);
    expect(card.margin, const EdgeInsets.all(7));
    expect(find.byType(ScrollReveal), findsOneWidget);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final opacity = tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.text('Ventes du jour'),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;
    expect(opacity, 1);
  });

  testWidgets('under « less motion » it is simply there', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: KajCard(child: Text('Stock'))),
        ),
      ),
    );
    expect(
      find.ancestor(
        of: find.text('Stock'),
        matching: find.byType(AnimatedOpacity),
      ),
      findsNothing,
    );
  });
}
