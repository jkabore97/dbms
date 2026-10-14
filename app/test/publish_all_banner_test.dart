import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/retail/publish_all_banner.dart';

/// A shop with priced articles, none on the vitrine: ELIM's case, told to
/// « add 5 » while 57 were there.
class _Shelf extends RetailRepository {
  _Shelf({required this.published, required this.ready}) : super(null);

  int published;
  int ready;
  final int min = 5;
  int publishes = 0;

  @override
  Future<({int published, int ready, int min})?> vitrineShelf(
          String orgId) async =>
      (published: published, ready: ready, min: min);

  @override
  Future<int> publishAll(String orgId) async {
    publishes++;
    final n = ready;
    published += ready;
    ready = 0;
    return n;
  }
}

Future<void> _pump(WidgetTester tester, _Shelf shelf,
    {double width = 390, double scale = 1}) async {
  tester.view.physicalSize = Size(width * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
          size: Size(width, 844), textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [PublishAllBanner(orgId: 'o', retail: shelf)],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('57 ready, none shown: one tap puts them all on the vitrine',
      (tester) async {
    final shelf = _Shelf(published: 0, ready: 57);
    await _pump(tester, shelf);
    expect(find.text('Déjà 57 prêts pour la vitrine'), findsOneWidget);
    await tester.tap(find.byKey(const Key('publish-all-go')));
    await tester.pumpAndSettle();
    expect(shelf.publishes, 1);
    expect(find.byKey(const Key('publish-all-banner')), findsNothing);
  });

  testWidgets('the vitrine already at its minimum: nothing said',
      (tester) async {
    await _pump(tester, _Shelf(published: 6, ready: 4));
    expect(find.byKey(const Key('publish-all-banner')), findsNothing);
  });

  testWidgets('nothing ready: nothing said', (tester) async {
    await _pump(tester, _Shelf(published: 1, ready: 0));
    expect(find.byKey(const Key('publish-all-banner')), findsNothing);
  });

  testWidgets('320 px at 1.3: no overflow', (tester) async {
    await _pump(tester, _Shelf(published: 0, ready: 57),
        width: 320, scale: 1.3);
    expect(find.byKey(const Key('publish-all-banner')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
