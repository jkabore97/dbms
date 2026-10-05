import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/pin_preview.dart';
import 'package:kaj_app/features/storefront/directory_map.dart';
import 'package:latlong2/latlong.dart';

/// List first, map on demand (package 3).
///
/// The audit: the map was a 340 px block under a 480 px band — a phone saw
/// a map and no shops — two shops 20 m apart drew one pin over the other,
/// and both shops were pinned in New Jersey because nothing showed the
/// owner where "Utiliser ma position" had put them.
const _awa = DirectoryEntry(
    orgId: 'o1',
    name: 'Boutique Awa',
    slug: 'awa',
    profile: 'retail',
    lat: 12.3714,
    lng: -1.5197);
const _yaar = DirectoryEntry(
    orgId: 'o2',
    name: 'Alimentation Yaar',
    slug: 'yaar',
    profile: 'retail',
    lat: 12.3716,
    lng: -1.5195);
const _away = DirectoryEntry(
    orgId: 'o3', name: 'Sans position', slug: 'away', profile: 'retail');

void main() {
  group('pins that sit together are grouped', () {
    test('close pins share a group, far ones do not', () {
      final groups = groupNearby(const [
        Offset(100, 100),
        Offset(110, 105), // 11 px away: same place on screen
        Offset(400, 300),
      ]);
      expect(groups, [
        [0, 1],
        [2]
      ]);
    });

    test('every pin lands in exactly one group', () {
      final points = [for (var i = 0; i < 30; i++) Offset(i * 13.0, i * 7.0)];
      final groups = groupNearby(points);
      final all = groups.expand((g) => g).toList()..sort();
      expect(all, [for (var i = 0; i < 30; i++) i]);
    });
  });

  group('a pin far from its currency is said before saving', () {
    test('New Jersey is far for a franc CFA shop; Ouagadougou is not', () {
      expect(pinLooksMisplaced(40.757953, -74.191392, 'XOF'), isTrue);
      expect(pinLooksMisplaced(12.3714, -1.5197, 'XOF'), isFalse);
      expect(pinLooksMisplaced(5.36, -4.0083, 'XOF'), isFalse); // Abidjan
      expect(pinLooksMisplaced(40.75, -74.19, 'USD'), isFalse);
    });

    testWidgets('the preview shows the warning for the New Jersey pin',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PinPreview(
            lat: 40.757953,
            lng: -74.191392,
            currency: 'XOF',
            onMove: (_, _) {},
            tiles: false,
          ),
        ),
      ));
      await tester.pump();
      expect(find.textContaining('loin de la zone franc CFA'), findsOneWidget);
    });
  });

  group('the map, full screen', () {
    Future<List<DirectoryEntry>> pumpMap(WidgetTester tester,
        {LatLng? here}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final opened = <DirectoryEntry>[];
      await tester.pumpWidget(MaterialApp(
        home: DirectoryMapPage(
          entries: const [_awa, _yaar, _away],
          previews: const {
            'awa': [
              ShopPreview(
                  slug: 'awa', productId: 'p1', name: 'Bissap', price: 150),
            ],
          },
          here: here,
          fallback: const LatLng(12.3714, -1.5197),
          onOpen: opened.add,
          onDirections: (_) {},
          tiles: false,
        ),
      ));
      await tester.pump();
      await tester.pump();
      return opened;
    }

    testWidgets('a strip of shop cards, with what the shop sells',
        (tester) async {
      final opened = await pumpMap(tester);
      expect(find.text('2 sur la carte · 1 sans position'), findsOneWidget);
      expect(find.text('Boutique Awa'), findsWidgets);
      expect(find.text('Bissap'), findsOneWidget);

      await tester.tap(find.text('Voir la vitrine').first);
      expect(opened.single.slug, 'awa');
    });

    testWidgets('two shops 20 m apart share one bubble at street zoom',
        (tester) async {
      await pumpMap(tester, here: const LatLng(12.3714, -1.5197));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('2'), findsOneWidget,
          reason: 'one bubble with the count, not one pin over the other');
    });

    testWidgets('the way back is a labelled button', (tester) async {
      await pumpMap(tester);
      expect(find.byTooltip('Retour à la liste'), findsOneWidget);
    });
  });
}
