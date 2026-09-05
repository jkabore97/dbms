import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/courier/job_map_screen.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The course on a map: the two legs named with their places, the leg
/// ahead as the big button, the fee; the courier's own dot following the
/// phone with the distance to each leg; and, refused, an honest line
/// instead of a missing dot. The haversine agrees with the database's.
class _OneCourse extends CourierRepository {
  _OneCourse(this.jobs) : super(null);

  final List<DeliveryJob> jobs;

  @override
  bool get isConfigured => true;

  @override
  Future<List<DeliveryJob>> mine() async => jobs;
}

/// The phone's location, scripted: a permission answer and a stream of
/// fixes. Stands in for the plugin, which has no implementation under
/// `flutter test` and never answers at all.
class _Gps extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  _Gps(this.permission, [this.fixes = const []]);

  final LocationPermission permission;
  final List<Position> fixes;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      Stream.fromIterable(fixes);
}

Position _at(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 9, 5, 10),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

DeliveryJob _job({String status = 'ready'}) => DeliveryJob(
      orderId: 'o1',
      shopName: 'Boutique Awa',
      shopAddress: 'Rood Woko',
      shopLat: 12.3714,
      shopLng: -1.5197,
      customerName: 'Moussa',
      phone: '+22670000000',
      dropAddress: 'Dassasgho, en face de la pharmacie',
      dropLat: 12.3894,
      dropLng: -1.5197,
      status: status,
      total: 17500,
      currency: 'XOF',
      createdAt: DateTime(2026, 9, 5, 10),
      deliveryFee: 800,
      distanceKm: 2.0016,
    );

void main() {
  late GeolocatorPlatform original;

  setUp(() => original = GeolocatorPlatform.instance);
  tearDown(() => GeolocatorPlatform.instance = original);

  test('distanceKm is the database haversine: 0.018° of latitude is 2.0016 km',
      () {
    expect(distanceKm(12.3714, -1.5197, 12.3894, -1.5197),
        closeTo(2.0016, 0.001));
    expect(distanceKm(12.3714, -1.5197, 12.3714, -1.5197), 0);
  });

  Future<void> pumpMap(WidgetTester tester, DeliveryJob job,
      {String orderId = 'o1'}) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: JobMapScreen(orderId: orderId, courier: _OneCourse([job])),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('at the shop: both legs, the shop as the leg ahead, the fee',
      (tester) async {
    GeolocatorPlatform.instance = _Gps(LocationPermission.deniedForever);
    await pumpMap(tester, _job());
    expect(find.text('Boutique · Rood Woko'), findsOneWidget);
    expect(find.text('Client · Dassasgho, en face de la pharmacie'),
        findsOneWidget);
    expect(find.text('Vers la boutique'), findsOneWidget);
    expect(find.text('Vers le client'), findsOneWidget);
    expect(find.text('Colis récupéré'), findsOneWidget);
    expect(find.text('Livré'), findsNothing);
    expect(find.textContaining('Course : '), findsOneWidget);
    // Refused: the missing dot is said, not hidden.
    expect(
      find.text('Sans votre position, la carte montre la boutique et le client.'),
      findsOneWidget,
    );
  });

  testWidgets('with a fix, each leg says how far it is from me',
      (tester) async {
    // Standing at the shop: 0 m to it, 2.0 km to the door.
    GeolocatorPlatform.instance =
        _Gps(LocationPermission.whileInUse, [_at(12.3714, -1.5197)]);
    await pumpMap(tester, _job());
    expect(find.text('0 m'), findsOneWidget);
    expect(find.text('2.0 km'), findsOneWidget);
    expect(find.textContaining('Sans votre position'), findsNothing);
  });

  testWidgets('on the road: the client is the leg ahead and Livré is offered',
      (tester) async {
    GeolocatorPlatform.instance = _Gps(LocationPermission.deniedForever);
    await pumpMap(tester, _job(status: 'in_transit'));
    expect(find.text('Vers la boutique'), findsNothing);
    expect(find.text('Vers le client'), findsOneWidget);
    expect(find.text('Livré'), findsOneWidget);
    expect(find.text('Colis récupéré'), findsNothing);
  });

  testWidgets('a course that is not mine says so', (tester) async {
    GeolocatorPlatform.instance = _Gps(LocationPermission.deniedForever);
    await pumpMap(tester, _job(), orderId: 'other');
    expect(find.text("Cette course n'est pas, ou plus, la vôtre."),
        findsOneWidget);
  });
}
