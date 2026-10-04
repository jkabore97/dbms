import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/features/courier/courier_screen.dart';

/// An approved courier is carried in without a reload.
///
/// The audit: approval rings the bell, but the courier page has no bell and
/// never asked again, so an applicant stayed on "à l'étude" until they
/// reloaded — the bug #110 fixed for shop applicants. The page now asks on
/// its own while somebody waits.
class _Courier extends CourierRepository {
  _Courier() : super(null);

  String? state = 'pending';
  int asked = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<String?> status() async {
    asked++;
    return state;
  }

  @override
  Future<List<DeliveryJob>> available() async => const [];

  @override
  Future<List<DeliveryJob>> mine() async => const [];

  @override
  Future<List<CourierEarnings>> earnings() async => const [];
}

void main() {
  testWidgets('approval lands while the applicant waits', (tester) async {
    final courier = _Courier();
    await tester.pumpWidget(MaterialApp(home: CourierScreen(courier: courier)));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("à l'étude"), findsOneWidget);

    // The platform says yes; nobody touches the phone.
    courier.state = 'approved';
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining("à l'étude"), findsNothing);
    expect(find.textContaining('Disponibles'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose → cancels the timer
  });

  testWidgets('the timer stops with the page', (tester) async {
    final courier = _Courier();
    await tester.pumpWidget(MaterialApp(home: CourierScreen(courier: courier)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    final before = courier.asked;
    await tester.pump(const Duration(minutes: 2));
    expect(courier.asked, before);
  });
}
