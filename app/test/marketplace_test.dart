import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';

/// The welcome page, on the app's side (054): the window's pin, the
/// featured row, the itinerary link, and what the platform reads back.
void main() {
  group('the window says where the shop is', () {
    test('a placed shop has a location', () {
      final shop = PublicShop.fromRow({
        'org_id': 'o',
        'name': 'Boutique Espérance',
        'slug': 'esperance',
        'lat': '12.3714',
        'lng': -1.5197,
      });
      expect(shop.hasLocation, isTrue);
      expect(shop.lat, closeTo(12.3714, 1e-9));
      expect(shop.lng, closeTo(-1.5197, 1e-9));
    });

    test('a database one migration behind (no pin columns) is unplaced', () {
      final shop = PublicShop.fromRow({
        'org_id': 'o',
        'name': 'Boutique Espérance',
        'slug': 'esperance',
      });
      expect(shop.hasLocation, isFalse);
    });
  });

  test('the itinerary link opens directions to the pin', () {
    expect(directionsUrl(12.3714, -1.5197),
        'https://www.google.com/maps/dir/?api=1&destination=12.3714,-1.5197');
  });

  group('an article à la une', () {
    test('reads its row, shop included', () {
      final item = FeaturedItem.fromRow({
        'id': 'p1',
        'name': 'Riz parfumé 25kg',
        'sale_price': '17500',
        'in_stock': true,
        'photo_key': 'org/o/x.jpg',
        'shop_name': 'Boutique Espérance',
        'shop_slug': 'esperance',
        'currency': 'XOF',
      });
      expect(item.price, 17500);
      expect(item.inStock, isTrue);
      expect(item.shopSlug, 'esperance');
      expect(item.photoKey, 'org/o/x.jpg');
    });
  });

  group('what the platform chooses from', () {
    test('a spot still ahead is live; a past or absent one is not', () {
      final ahead = FeaturedCandidate.fromRow({
        'product_id': 'p1',
        'name': 'Riz',
        'sale_price': 17500,
        'shop_name': 'A',
        'shop_slug': 'a',
        'featured_until':
            DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
      });
      final past = FeaturedCandidate.fromRow({
        'product_id': 'p2',
        'name': 'Savon',
        'sale_price': 450,
        'shop_name': 'A',
        'shop_slug': 'a',
        'featured_until': DateTime.now()
            .subtract(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
      });
      final never = FeaturedCandidate.fromRow({
        'product_id': 'p3',
        'name': 'Lait',
        'sale_price': 3200,
        'shop_name': 'B',
        'shop_slug': 'b',
      });
      expect(ahead.live, isTrue);
      expect(past.live, isFalse);
      expect(never.live, isFalse);
      expect(never.featuredUntil, isNull);
    });
  });
}
