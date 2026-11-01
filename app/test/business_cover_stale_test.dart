// The bar's second freeze (160c): a sheet still leaving when its navigator
// goes away (the business's pages rebuilt, the business left) never
// finished its exit animation, so BusinessCover kept it as covering the
// pages — the bar stayed behind them, under the pages' full-size layers,
// and took no tap until the app restarted.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/nav/business_cover.dart';

void main() {
  testWidgets('a sheet whose navigator went away mid-exit no longer covers the bar', (tester) async {
    final cover = BusinessCover();
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        observers: [cover],
        pages: [MaterialPage<void>(child: Builder(builder: (c) { ctx = c; return const Scaffold(body: Text('page')); }))],
        onDidRemovePage: (_) {},
      ),
    ));
    expect(cover.covered, isFalse, reason: 'a page covers nothing');
    showModalBottomSheet<void>(context: ctx, builder: (_) => const SizedBox(height: 200, child: Text('sheet')));
    await tester.pumpAndSettle();
    expect(cover.covered, isTrue, reason: 'the sheet covers the pages');
    Navigator.of(ctx).pop();
    await tester.pump(const Duration(milliseconds: 20));
    expect(cover.covered, isTrue, reason: 'still leaving, over the bar');
    // The navigator goes away before the sheet has finished leaving.
    await tester.pumpWidget(const MaterialApp(home: Text('elsewhere')));
    await tester.pumpAndSettle();
    expect(cover.covered, isFalse, reason: 'a sheet no navigator holds covers nothing');
  });

  testWidgets('a sheet closed normally uncovers the bar once it has left', (tester) async {
    final cover = BusinessCover();
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        observers: [cover],
        pages: [MaterialPage<void>(child: Builder(builder: (c) { ctx = c; return const Scaffold(body: Text('page')); }))],
        onDidRemovePage: (_) {},
      ),
    ));
    expect(cover.covered, isFalse, reason: 'a page covers nothing');
    showModalBottomSheet<void>(context: ctx, builder: (_) => const SizedBox(height: 200, child: Text('sheet')));
    await tester.pumpAndSettle();
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();
    expect(cover.covered, isFalse);
  });
}
