import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/features/courier/courier_screen.dart';

/// What today paid, on the courier's screen: today written large, the
/// week and the month beside it, read through the model whether PostgREST
/// sends numbers or strings — and absent, not broken, when the tally
/// cannot be fetched.
class _Approved extends CourierRepository {
  _Approved({this.tally = const [], this.tallyFails = false}) : super(null);

  final List<CourierEarnings> tally;
  final bool tallyFails;

  @override
  bool get isConfigured => true;

  @override
  Future<String?> status() async => 'approved';

  @override
  Future<List<DeliveryJob>> available() async => const [];

  @override
  Future<List<DeliveryJob>> mine() async => const [];

  @override
  Future<List<CourierEarnings>> earnings() async {
    if (tallyFails) throw StateError('no signal');
    return tally;
  }
}

void main() {
  test('CourierEarnings reads numbers as sent and names its periods', () {
    final e = CourierEarnings.fromRow(
        {'period': 'today', 'courses': '2', 'fees': '1600', 'km': 4.0032});
    expect(e.courses, 2);
    expect(e.fees, 1600);
    expect(e.km, closeTo(4.0032, 1e-9));
    expect(CourierEarnings.label('today'), "Aujourd'hui");
    expect(CourierEarnings.label('week'), 'Cette semaine');
    expect(CourierEarnings.label('month'), 'Ce mois');
  });

  Future<void> pump(WidgetTester tester, _Approved courier) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: CourierScreen(courier: courier)));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('today is written large, the week and month beside it',
      (tester) async {
    await pump(
        tester,
        _Approved(tally: const [
          CourierEarnings(period: 'today', courses: 2, fees: 1600, km: 4.0),
          CourierEarnings(period: 'week', courses: 5, fees: 4200, km: 12.3),
          CourierEarnings(period: 'month', courses: 9, fees: 7600, km: 25.9),
        ]));
    expect(find.text("AUJOURD'HUI"), findsOneWidget);
    expect(find.text('2 courses · 4.0 km'), findsOneWidget);
    expect(find.text('Cette semaine'), findsOneWidget);
    expect(find.text('5 · 12 km'), findsOneWidget);
    expect(find.text('Ce mois'), findsOneWidget);
    expect(find.text('9 · 26 km'), findsOneWidget);
  });

  testWidgets('a tally that cannot be fetched is absent, not a broken page',
      (tester) async {
    await pump(tester, _Approved(tallyFails: true));
    expect(find.text("AUJOURD'HUI"), findsNothing);
    // The board is still there.
    expect(find.textContaining('Disponibles'), findsOneWidget);
  });
}
