import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/core/theme/motion.dart';

/// The motion contract: every platform opens a page the same way, nothing
/// ripples, a tile lifts under the pointer, and content settles in once —
/// all of it on the shared clock, because motion that varies is a show.
void main() {
  group('the theme carries the motion', () {
    test('every platform opens a page with the paper transition', () {
      final theme = kajTheme(kajPalette);
      final builders = theme.pageTransitionsTheme.builders;
      for (final platform in TargetPlatform.values) {
        expect(builders[platform], isA<PaperPageTransitionsBuilder>(),
            reason: 'no paper transition on $platform');
      }
    });

    test('nothing ripples: the splash is gone, the states are quiet', () {
      final theme = kajTheme(kajPalette);
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.splashColor, Colors.transparent);
      // The hover and press answers exist but stay whispers of ink.
      expect(theme.hoverColor.a, lessThan(0.1));
      expect(theme.highlightColor.a, lessThan(0.1));
    });

    test('the stagger is capped so a long list never queues', () {
      expect(KajMotion.stagger(0), Duration.zero);
      expect(KajMotion.stagger(3), const Duration(milliseconds: 135));
      // The ninth tile settles with the first, not after the eighth.
      expect(KajMotion.stagger(8), Duration.zero);
      expect(KajMotion.stagger(100), KajMotion.stagger(4));
    });
  });

  group('Lift', () {
    testWidgets('rests flat and rises under the pointer', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(
          child: Lift(child: SizedBox(width: 100, height: 100)),
        ),
      ));
      AnimatedScale scaleOf() =>
          tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleOf().scale, 1.0);

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SizedBox)));
      await tester.pump();
      expect(scaleOf().scale, greaterThan(1.0));

      await gesture.moveTo(Offset.zero);
      await tester.pump();
      expect(scaleOf().scale, 1.0);
    });

    testWidgets('a disabled lift stays perfectly still', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(
          child: Lift(
              enabled: false, child: SizedBox(width: 100, height: 100)),
        ),
      ));
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SizedBox)));
      await tester.pump();
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        1.0,
      );
    });
  });

  group('Reveal', () {
    testWidgets('the content is present from the first frame and settles in',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Reveal(child: Text('bonjour')),
      ));
      // Findable at once — an entrance must never hide information from
      // a test or a screen reader, only ease it in.
      expect(find.text('bonjour'), findsOneWidget);
      AnimatedOpacity fade() =>
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(fade().opacity, 0);

      await tester.pump(); // The post-frame callback lands.
      await tester.pump(KajMotion.settle);
      expect(fade().opacity, 1);
    });

    testWidgets('a delayed reveal waits its turn, then settles',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Reveal(
          delay: Duration(milliseconds: 90),
          child: Text('bonjour'),
        ),
      ));
      AnimatedOpacity fade() =>
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      await tester.pump(const Duration(milliseconds: 50));
      expect(fade().opacity, 0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(fade().opacity, 1);
    });
  });
}
