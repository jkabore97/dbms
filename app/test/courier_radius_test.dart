import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/features/courier/courier_screen.dart';

/// The board asks for the phone's position (122): one line says why, the
/// position goes to the board, and a refusal leaves a board that says what
/// would fill it.
class _Courier extends CourierRepository {
  _Courier({this.city = ''}) : super(null);

  final String city;
  final boards = <(double?, double?)>[];

  @override
  bool get isConfigured => true;
  @override
  Future<String?> status() async => 'approved';
  @override
  Future<List<DeliveryJob>> board({double? lat, double? lng}) async {
    boards.add((lat, lng));
    return const [];
  }

  @override
  Future<List<DeliveryJob>> mine() async => const [];
  @override
  Future<List<CourierEarnings>> earnings() async => const [];
  @override
  Future<List<CashHeld>> cash() async => const [];
  @override
  Future<CourierReach> reach() async => CourierReach(city: city, radiusKm: 15);
}

class _Where extends CourierWhere {
  _Where(this.permission);

  LocationPermission permission;
  int requests = 0;

  @override
  Future<LocationPermission> check() async => permission;
  @override
  Future<LocationPermission> request() async {
    requests++;
    return permission = LocationPermission.whileInUse;
  }

  @override
  Future<Position> current() async => Position(
        latitude: 12.3714,
        longitude: -1.5197,
        timestamp: DateTime(2026, 10, 9),
        accuracy: 20,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('asks once with the radius, then the board gets the position',
      (tester) async {
    final courier = _Courier();
    final where = _Where(LocationPermission.denied);
    await tester.pumpWidget(
        MaterialApp(home: CourierScreen(courier: courier, where: where)));
    await _settle(tester);

    expect(find.text('Pour voir les livraisons à moins de 15 km'), findsOneWidget);
    expect(courier.boards.single, (null, null),
        reason: 'the first board never waits for the position');
    await tester.tap(find.text('Activer la position'));
    await _settle(tester);

    expect(where.requests, 1);
    expect(courier.boards.last, (12.3714, -1.5197));
    expect(find.text('Aucune livraison à prendre pour le moment. Revenez un peu plus tard.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('« Plus tard » with no city: the empty board says why',
      (tester) async {
    final courier = _Courier();
    final where = _Where(LocationPermission.denied);
    await tester.pumpWidget(
        MaterialApp(home: CourierScreen(courier: courier, where: where)));
    await _settle(tester);
    await tester.tap(find.text('Plus tard'));
    await _settle(tester);

    expect(where.requests, 0);
    expect(courier.boards, [(null, null)]);
    expect(find.text('Activez la position pour voir les livraisons proches'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a refused position with a declared city: the usual empty text',
      (tester) async {
    final courier = _Courier(city: 'Ouagadougou');
    final where = _Where(LocationPermission.deniedForever);
    await tester.pumpWidget(
        MaterialApp(home: CourierScreen(courier: courier, where: where)));
    await _settle(tester);

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'refused for good: nothing to ask, the board falls back quietly');
    expect(find.text('Aucune livraison à prendre pour le moment. Revenez un peu plus tard.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('already allowed: no question, the position goes straight in',
      (tester) async {
    final courier = _Courier();
    final where = _Where(LocationPermission.whileInUse);
    await tester.pumpWidget(
        MaterialApp(home: CourierScreen(courier: courier, where: where)));
    await _settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(courier.boards.last, (12.3714, -1.5197));
    await tester.pumpWidget(const SizedBox());
  });
}
