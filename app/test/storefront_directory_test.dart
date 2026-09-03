import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';

void main() {
  group('parseGoogleMapsLink', () {
    test('reads the @lat,lng of a full place link', () {
      final p = parseGoogleMapsLink(
          'https://www.google.com/maps/place/March%C3%A9+Rood+Woko/'
          '@12.3714,-1.5197,17z/data=!3m1!4b1');
      expect(p, isNotNull);
      expect(p!.lat, closeTo(12.3714, 1e-9));
      expect(p.lng, closeTo(-1.5197, 1e-9));
    });

    test('reads a ?q=lat,lng search link', () {
      final p = parseGoogleMapsLink('https://maps.google.com/?q=12.37,-1.52');
      expect(p, equals((lat: 12.37, lng: -1.52)));
    });

    test('reads the !3d!4d pair buried in the data segment', () {
      final p = parseGoogleMapsLink(
          'https://www.google.com/maps/place/x/data=!4m5!3m4!3d12.37!4d-1.52');
      expect(p, equals((lat: 12.37, lng: -1.52)));
    });

    test('accepts a bare "lat, lng" typed by hand', () {
      expect(parseGoogleMapsLink(' 12.37, -1.52 '),
          equals((lat: 12.37, lng: -1.52)));
      expect(parseGoogleMapsLink('12.37,-1.52'),
          equals((lat: 12.37, lng: -1.52)));
    });

    test('a short goo.gl link carries no position', () {
      expect(parseGoogleMapsLink('https://maps.app.goo.gl/AbCdEf123'), isNull);
    });

    test('garbage and empty text are null', () {
      expect(parseGoogleMapsLink(''), isNull);
      expect(parseGoogleMapsLink('boutique esperance'), isNull);
      expect(parseGoogleMapsLink('12.37'), isNull);
    });

    test('a position off the world is refused', () {
      expect(parseGoogleMapsLink('@95,-1.52,17z'), isNull);
      expect(parseGoogleMapsLink('12.37, 181'), isNull);
    });
  });

  group('DirectoryEntry.fromRow', () {
    test('reads numbers whether PostgREST sends them as num or string', () {
      final e = DirectoryEntry.fromRow({
        'org_id': 'o1',
        'name': 'Boutique Espérance',
        'slug': 'boutique-esperance',
        'profile': 'generic',
        'blurb': null,
        'address': 'Rood Woko',
        'lat': '12.3714',
        'lng': -1.5197,
        'distance_km': '1.25',
      });
      expect(e.hasLocation, isTrue);
      expect(e.lat, closeTo(12.3714, 1e-9));
      expect(e.lng, closeTo(-1.5197, 1e-9));
      expect(e.distanceKm, closeTo(1.25, 1e-9));
    });

    test('an unplaced shop has no location and no distance', () {
      final e = DirectoryEntry.fromRow({
        'org_id': 'o2',
        'name': 'Ferme Wend-Panga',
        'slug': 'ferme-wend-panga',
        'profile': 'farm',
      });
      expect(e.hasLocation, isFalse);
      expect(e.distanceKm, isNull);
      expect(e.profile, 'farm');
    });
  });

  group('distanceLabel', () {
    test('metres under a kilometre, one decimal above', () {
      expect(distanceLabel(0.4), '400 m');
      expect(distanceLabel(0.999), '999 m');
      expect(distanceLabel(1.0), '1.0 km');
      expect(distanceLabel(2.34), '2.3 km');
    });

    test('null in, null out', () {
      expect(distanceLabel(null), isNull);
    });
  });
}
