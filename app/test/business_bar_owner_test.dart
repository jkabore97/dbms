// The bottom bar (108) holds the home's places. A home rebuilt from scratch
// publishes the same places as the one before; the frame must redraw, or
// its bar keeps the old home's actions and a tap reaches nothing — the
// owner: « the bottom bar buttons sometimes stop working ».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/features/home/home_nav.dart';

HomeNav _nav(List<String> taps, String who) => HomeNav(
      home: HomeDestination(icon: Icons.home, label: 'Accueil', route: '', onTap: () => taps.add('$who:home')),
      primary: [
        HomeDestination(icon: Icons.sell, label: 'Vendre', route: 'vendre', onTap: () => taps.add('$who:vendre')),
        HomeDestination(icon: Icons.inventory, label: 'Stock', route: 'stock', onTap: () => taps.add('$who:stock')),
      ],
    );

void main() {
  testWidgets('a new home with the same places: the frame is told, and the places are the new home\'s', (tester) async {
    final taps = <String>[];
    final keeper = BusinessNav();
    var told = 0;
    keeper.addListener(() => told++);
    late BuildContext first, second;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) { first = c; return const SizedBox(); })));
    keeper.publish(first, _nav(taps, 'old'));
    await tester.pump();
    expect(told, 1, reason: 'the first places drawn');
    keeper.publish(first, _nav(taps, 'old'));
    await tester.pump();
    expect(told, 1, reason: 'the same home building again: nothing to redraw');

    // The home's page rebuilt from scratch: another element, the same places.
    await tester.pumpWidget(MaterialApp(home: KeyedSubtree(key: const ValueKey(2), child: Builder(builder: (c) { second = c; return const SizedBox(); }))));
    expect(identical(first, second), isFalse);
    keeper.publish(second, _nav(taps, 'new'));
    await tester.pump();
    expect(told, 2, reason: 'a new home: the bar redraws with its actions');
    keeper.nav!.slots(second)[1].onTap();
    expect(taps, ['new:vendre'], reason: 'the tap reaches the home on screen');
  });
}
