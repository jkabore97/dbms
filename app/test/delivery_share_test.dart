import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/features/admin/settlement_screen.dart';

/// The platform's part of a delivery fee on the phone (067, M10 block 4):
/// the courier's tally reads share and net, a database before 067 reads
/// every franc as the courier's, and the platform's settlement page says
/// what each courier owes for the month and sets the rate for the next.
class _Admin extends AdminRepository {
  _Admin({this.rows = const [], this.pct = 10}) : super(null);

  final List<CourierSettlement> rows;
  final int pct;
  final asked = <DateTime>[];
  final settings = <String, Object?>{};

  @override
  Future<PlanTerms> planTerms() async => PlanTerms(deliverySharePct: pct);

  @override
  Future<List<CourierSettlement>> deliverySettlement(DateTime month) async {
    asked.add(month);
    return rows;
  }

  @override
  Future<void> setPlatformSetting(String key, Object? value) async {
    settings[key] = value;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  group("the courier's tally", () {
    test('reads share and net beside the fees', () {
      final e = CourierEarnings.fromRow({
        'period': 'today',
        'courses': 2,
        'fees': '2050.00',
        'km': 4.0,
        'share': '205.00',
        'net': '1845.00',
      });
      expect(e.fees, 2050);
      expect(e.share, 205);
      expect(e.net, 1845);
    });

    test('a database before 067 gives the courier every franc', () {
      final e = CourierEarnings.fromRow(
          {'period': 'week', 'courses': 3, 'fees': 2400, 'km': 6.0});
      expect(e.share, 0);
      expect(e.net, 2400);
    });

    test('the terms carry the rate for the next order, 10 by default', () {
      expect(PlanTerms.fromJson({'delivery_share_pct': 15}).deliverySharePct, 15);
      expect(PlanTerms.defaults.deliverySharePct, 10);
    });
  });

  group('the settlement page', () {
    testWidgets('says what each courier owes, steps a month back, saves the rate',
        (tester) async {
      final admin = _Admin(
        rows: const [
          CourierSettlement(
              courierId: 'c1',
              name: 'Moussa',
              phone: '+226 70 00 00 04',
              courses: 12,
              fees: 9600,
              share: 960,
              net: 8640),
          CourierSettlement(
              courierId: 'c2',
              name: 'Aminata',
              courses: 3,
              fees: 2400,
              share: 240,
              net: 2160),
        ],
      );
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: SettlementScreen(admin: admin)));
      await tester.pump();
      await tester.pump();

      // Narrow no-break spaces in the French thousands: match around them.
      expect(find.textContaining(RegExp(r'1.200 F CFA dus à Kaj')), findsOneWidget);
      expect(find.text('Moussa'), findsOneWidget);
      expect(find.textContaining(RegExp(r'12 courses · encaissé 9.600 F · gardé 8.640 F')),
          findsOneWidget);
      expect(find.text('960 F'), findsOneWidget);
      expect(find.text('240 F'), findsOneWidget);
      expect(find.textContaining("Aujourd'hui : 10 %"), findsOneWidget);

      final now = DateTime.now();
      expect(admin.asked.single, DateTime(now.year, now.month));

      // The current month is the latest there is: no stepping forward.
      final forward = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.chevron_right));
      expect(forward.onPressed, isNull);

      await tester.tap(find.byTooltip('Mois précédent'));
      await tester.pump();
      await tester.pump();
      expect(admin.asked.last, DateTime(now.year, now.month - 1));

      await tester.enterText(find.widgetWithText(TextField, 'Part (%)'), '15');
      final save = find.text('Enregistrer le taux');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump();
      expect(admin.settings['delivery_share_pct'], 15);
      expect(find.textContaining('15 % sur les prochaines livraisons'),
          findsOneWidget);
    });

    testWidgets('a month with no delivery says so, and the rate is the platform\'s',
        (tester) async {
      final admin = _Admin(pct: 15);
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: SettlementScreen(admin: admin)));
      await tester.pump();
      await tester.pump();
      expect(find.text('Aucune livraison ce mois-ci.'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^0 F CFA dus à Kaj')), findsOneWidget);
      expect(find.textContaining("Aujourd'hui : 15 %"), findsOneWidget);
      expect(find.widgetWithText(TextField, '15'), findsOneWidget);
    });
  });
}
