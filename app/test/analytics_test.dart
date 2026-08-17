import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:kaj_app/core/analytics/analytics_repository.dart';
import 'package:kaj_app/core/analytics/models.dart';
import 'package:kaj_app/features/analytics/charts.dart';
import 'package:kaj_app/features/analytics/owner_analytics_screen.dart';

/// A repository that answers from memory, so the screen can be pumped with no
/// server. It extends the real one (constructed with a null client) and
/// overrides only the read the screen calls.
class _FakeAnalytics extends AnalyticsRepository {
  _FakeAnalytics(this._data) : super(null);
  final OwnerAnalytics _data;

  @override
  Future<OwnerAnalytics> owner(String orgId, {int? days = 30}) async => _data;
}

OwnerAnalytics _sample() => OwnerAnalytics(
      headline: const SalesHeadline(
        saleCount: 3,
        revenue: 36000,
        cost: 24500,
        margin: 11500,
        units: 15,
        avgBasket: 12000,
        productsSold: 2,
      ),
      products: const [
        ProductPerformance(
            name: 'Riz 5kg',
            units: 10,
            revenue: 30000,
            margin: 10000,
            saleCount: 2,
            perDay: 9.6),
        ProductPerformance(
            name: 'Huile 1L',
            units: 5,
            revenue: 6000,
            margin: 1500,
            saleCount: 1,
            perDay: 5),
      ],
      byHour: const [
        TimeBucket(index: 9, saleCount: 1, revenue: 18000),
        TimeBucket(index: 10, saleCount: 1, revenue: 12000),
        TimeBucket(index: 15, saleCount: 1, revenue: 6000),
      ],
      byWeekday: const [
        TimeBucket(index: 1, saleCount: 1, revenue: 18000),
        TimeBucket(index: 2, saleCount: 2, revenue: 18000),
      ],
      daily: [
        DayPoint(day: DateTime(2026, 8, 10), saleCount: 1, revenue: 18000),
        DayPoint(day: DateTime(2026, 8, 11), saleCount: 2, revenue: 18000),
      ],
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  group('models', () {
    test('a headline row parses, ints and doubles alike', () {
      final h = SalesHeadline.fromRow({
        'sale_count': 3,
        'revenue': 36000,
        'cost': 24500.0,
        'margin': 11500,
        'units': 15.0,
        'avg_basket': 12000,
        'products_sold': 2,
      });
      expect(h.saleCount, 3);
      expect(h.revenue, 36000);
      expect(h.margin, 11500);
      expect(h.units, 15);
      // 11500 / 36000 ≈ 0.319.
      expect((h.marginRate * 100).round(), 32);
    });

    test('an empty headline is zeroed, not null', () {
      expect(SalesHeadline.empty.revenue, 0);
      expect(SalesHeadline.empty.marginRate, 0);
    });

    test('a product row keeps its velocity', () {
      final p = ProductPerformance.fromRow({
        'name': 'Riz 5kg',
        'units': 10,
        'revenue': 30000,
        'margin': 10000,
        'sale_count': 2,
        'per_day': 9.6,
      });
      expect(p.name, 'Riz 5kg');
      expect(p.perDay, 9.6);
    });

    test('a day point parses its date', () {
      final d = DayPoint.fromRow(
          {'day': '2026-08-11', 'sale_count': 2, 'revenue': 18000});
      expect(d.day.year, 2026);
      expect(d.day.month, 8);
      expect(d.day.day, 11);
    });
  });

  group('the owner screen', () {
    Future<void> pump(WidgetTester tester, OwnerAnalytics data) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: OwnerAnalyticsScreen(
          analytics: _FakeAnalytics(data),
          orgId: 'org-1',
          orgName: 'Boutique',
          currency: 'XOF',
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('renders the headline and the best/slowest products',
        (tester) async {
      await pump(tester, _sample());

      // Revenue is the emphasised figure; margin, sales and the products show.
      expect(find.textContaining('36'), findsWidgets); // 36 000 FCFA
      expect(find.text('Ce qui se vend'), findsOneWidget);
      expect(find.text('Riz 5kg'), findsWidgets);
      expect(find.text('Le plus vendu'), findsOneWidget);
      expect(find.text('Le plus lent'), findsOneWidget);
      // The three chart sections are present.
      expect(find.text('Quand ça se vend'), findsOneWidget);
      expect(find.text('Tendance'), findsOneWidget);
    });

    testWidgets('an empty period shows the empty state, no charts',
        (tester) async {
      await pump(
        tester,
        const OwnerAnalytics(
          headline: SalesHeadline.empty,
          products: [],
          byHour: [],
          byWeekday: [],
          daily: [],
        ),
      );

      expect(find.text('Aucune vente sur cette période'), findsOneWidget);
      expect(find.text('Ce qui se vend'), findsNothing);
    });
  });

  group('charts', () {
    testWidgets('a bar chart paints with values and with none',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: BarChart(values: [1, 5, 3], labels: ['a', 'b', 'c']),
        ),
      ));
      expect(find.byType(BarChart), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: BarChart(values: [], labels: [])),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a line chart paints and tolerates a single point',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LineChart(values: [1, 2, 3, 2, 4])),
      ));
      expect(find.byType(LineChart), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LineChart(values: [3])),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
