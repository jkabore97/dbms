// A Google Maps link pasted for a shop's or a customer's position: the
// shapes a full link takes, and the short link a phone's « Partager »
// gives, followed by the site (kaj-app Worker, /api/maps-link).

import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';

void main() {
  test('the shapes a full link takes', () {
    expect(parseGoogleMapsLink('https://www.google.com/maps/place/X/@12.3714,-1.5196,17z'),
        (lat: 12.3714, lng: -1.5196));
    expect(parseGoogleMapsLink('https://www.google.com/maps?q=12.37%2C-1.52'), (lat: 12.37, lng: -1.52));
    expect(parseGoogleMapsLink('https://www.google.com/maps/search/?api=1&query=12.37,-1.52'),
        (lat: 12.37, lng: -1.52));
    expect(parseGoogleMapsLink('https://www.google.com/maps/search/12.37,+-1.52'), (lat: 12.37, lng: -1.52));
    expect(parseGoogleMapsLink('https://www.google.com/maps/place/X/data=!3d12.5!4d-1.6'), (lat: 12.5, lng: -1.6));
    expect(parseGoogleMapsLink('geo:12.37,-1.52?q=shop'), (lat: 12.37, lng: -1.52));
    expect(parseGoogleMapsLink('12.37, -1.52'), (lat: 12.37, lng: -1.52));
    expect(parseGoogleMapsLink('Boutique Wendé 12.371234, -1.519876'), (lat: 12.371234, lng: -1.519876));
    expect(parseGoogleMapsLink('https://maps.app.goo.gl/AbC123'), isNull);
    expect(parseGoogleMapsLink('95.5, 10.1'), isNull);
    expect(parseGoogleMapsLink('Ouvert 8, 18'), isNull);
  });

  test('the Google Maps link inside a shared text', () {
    expect(googleMapsLinkIn('Boutique Wendé\nhttps://maps.app.goo.gl/AbC123')?.host, 'maps.app.goo.gl');
    expect(googleMapsLinkIn('https://www.google.bf/maps/place/X'), isNotNull);
    expect(googleMapsLinkIn('https://evil.example/maps'), isNull);
    expect(googleMapsLinkIn('https://goo.gl/abc'), isNull);
  });

  test('a short link is asked of the site, which says where it lands', () async {
    Uri? asked;
    final at = await resolveGoogleMapsLink(
      'Boutique\nhttps://maps.app.goo.gl/AbC123',
      base: Uri.parse('https://marakaj.com/o/x/parametres'),
      fetch: (api) async {
        asked = api;
        return '{"lat":12.3714277,"lng":-1.5196603}';
      },
    );
    expect(at, (lat: 12.3714277, lng: -1.5196603));
    expect(asked!.origin, 'https://marakaj.com');
    expect(asked!.path, '/api/maps-link');
    expect(asked!.queryParameters['u'], 'https://maps.app.goo.gl/AbC123');
  });

  test('the phone app asks the site; a refusal or an error is null', () async {
    Uri? asked;
    expect(
        await resolveGoogleMapsLink('https://maps.app.goo.gl/x',
            base: Uri.parse('file:///'), fetch: (api) async {
          asked = api;
          return null;
        }),
        isNull);
    expect(asked!.origin, 'https://marakaj.com');
    expect(
        await resolveGoogleMapsLink('https://maps.app.goo.gl/x',
            base: Uri.parse('file:///'), fetch: (_) async => throw Exception('offline')),
        isNull);
    expect(await resolveGoogleMapsLink('pas un lien', fetch: (_) async => fail('not asked')), isNull);
  });

  test('a full link never asks the site', () async {
    expect(
        await resolveGoogleMapsLink('https://www.google.com/maps/@12.37,-1.52,15z',
            fetch: (_) async => fail('not asked')),
        (lat: 12.37, lng: -1.52));
  });
}
