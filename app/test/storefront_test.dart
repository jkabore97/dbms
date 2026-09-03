import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';

/// The shop window, on the app's side: what an article knows about being in
/// it, how the street's rows read, and how a shopper reaches the shop.
void main() {
  group('an article knows whether it is in the window', () {
    test('reads is_published from the row', () {
      final shown = Product.fromRow({
        'id': 'p1',
        'name': 'Sucre 1kg',
        'is_published': true,
      });
      final hidden = Product.fromRow({
        'id': 'p2',
        'name': 'Savon',
        'is_published': false,
      });
      expect(shown.isPublished, isTrue);
      expect(hidden.isPublished, isFalse);
    });

    test('a database one migration behind (no column) means not shown', () {
      // The app runs ahead of the database by design; absent must read as
      // "not in the window", never crash and never show.
      final product = Product.fromRow({'id': 'p3', 'name': 'Lait'});
      expect(product.isPublished, isFalse);
    });
  });

  group('the street reads the window', () {
    test('a shop row parses, with sensible defaults', () {
      final shop = PublicShop.fromRow({
        'org_id': 'o1',
        'name': 'Boutique Esperance',
        'slug': 'boutique-esperance',
        'profile': null,
        'blurb': null,
        'phone': '+226 70 12 34 56',
        'address': 'Marché de Gounghin',
        'theme': null,
        'currency': null,
      });
      expect(shop.name, 'Boutique Esperance');
      expect(shop.profile, 'generic');
      expect(shop.currency, 'XOF');
      expect(shop.address, 'Marché de Gounghin');
    });

    test('an item reads the price Postgres sends as a string and in_stock as a yes/no',
        () {
      // numeric arrives as a string over PostgREST often enough that parsing it
      // wrongly would put "0 F" under every article in the window.
      final item = PublicItem.fromRow({
        'id': 'p1',
        'name': 'Sucre 1kg',
        'sale_price': '750.00',
        'in_stock': true,
        'photo_key': 'org/o1/sucre.jpg',
      });
      expect(item.price, 750);
      expect(item.inStock, isTrue);
      expect(item.photoKey, 'org/o1/sucre.jpg');

      final gone = PublicItem.fromRow({
        'id': 'p2',
        'name': 'Lait',
        'sale_price': 1000,
        'in_stock': false,
        'photo_key': null,
      });
      expect(gone.inStock, isFalse);
      expect(gone.photoKey, isNull);
    });
  });

  group('contacting the shop', () {
    test('a stored E.164 number becomes a wa.me link of digits only', () {
      expect(whatsappUrl('+226 70 12 34 56'), 'https://wa.me/22670123456');
    });

    test('no number, no link', () {
      expect(whatsappUrl(null), isNull);
      expect(whatsappUrl('   '), isNull);
    });
  });
}
