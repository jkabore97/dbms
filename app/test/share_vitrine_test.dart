import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/storefront/share_vitrine.dart';

/// The owner: « I thought the preview would show the store I'm sharing more
/// than Mara itself. Also the link is still using the old domain. Make the
/// sharing on WhatsApp nicer, especially for WhatsApp status. »
const _shop = PublicShop(
  orgId: 'o1',
  name: 'Tony Pizza',
  slug: 'tony-pizza',
  profile: 'retail',
  blurb: 'Pizzas, burgers et fritures.',
  style: StorefrontStyle(tagline: 'La pizza du quartier'),
);

const _items = [
  PublicItem(id: 'a', name: 'Margherita', price: 5000, inStock: true),
  PublicItem(id: 'b', name: 'Pepperoni', price: 6500, inStock: true, photoKey: 'k'),
  PublicItem(id: 'c', name: 'Calzone', price: 6000, inStock: true),
  PublicItem(id: 'd', name: 'Burger', price: 3500, inStock: true),
  PublicItem(id: 'e', name: 'Frites', price: 1000, inStock: true),
];

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  test('the link is always marakaj.com', () {
    expect(publicShopUrl('tony-pizza'), 'https://marakaj.com/s/tony-pizza');
  });

  test('the card shows four articles, photographed first', () {
    final picked = StatusCard.pick(_items);
    expect(picked, hasLength(4));
    expect(picked.first.id, 'b');
  });

  testWidgets('the message names the shop, its line, then the link alone',
      (tester) async {
    late String text;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        text = ShareVitrine.message(context, _shop);
        return const SizedBox();
      }),
    ));
    expect(text.split('\n'), [
      '*Tony Pizza*',
      'La pizza du quartier',
      '',
      'Voir les articles et commander :',
      'https://marakaj.com/s/tony-pizza',
    ]);
  });

  testWidgets('three ways out: status, a contact, the link', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                ShareVitrine.open(context, shop: _shop, items: _items),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Partager Tony Pizza'), findsOneWidget);
    expect(find.byKey(const Key('share-status')), findsOneWidget);
    expect(find.byKey(const Key('share-contact')), findsOneWidget);
    expect(find.byKey(const Key('share-copy')), findsOneWidget);
    expect(find.text('https://marakaj.com/s/tony-pizza'), findsOneWidget);
  });

  testWidgets('the status picture: name, line, prices, where to order',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: StatusCard(shop: _shop, items: StatusCard.pick(_items)),
    ));
    await tester.pump();
    expect(find.text('Tony Pizza'), findsOneWidget);
    expect(find.text('La pizza du quartier'), findsOneWidget);
    expect(find.text('Pepperoni'), findsOneWidget);
    expect(find.text('Frites'), findsNothing);
    expect(find.text('Commandez ici'), findsOneWidget);
    expect(find.text('marakaj.com/s/tony-pizza'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
