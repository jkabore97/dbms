// The rows the analytics functions of 036 return, as things the screens can
// hold. Every numeric field arrives from Postgres as a `num` (int or double
// depending on the value), so each is read through `_d` into a double the
// charts and formatters can use without caring which it was.

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
int _i(dynamic v) => v == null ? 0 : (v as num).toInt();

/// The cards at the top of the owner's analytics: the whole business in six
/// numbers over the chosen window.
class SalesHeadline {
  const SalesHeadline({
    required this.saleCount,
    required this.revenue,
    required this.cost,
    required this.margin,
    required this.units,
    required this.avgBasket,
    required this.productsSold,
  });

  final int saleCount;
  final double revenue;
  final double cost;
  final double margin;
  final double units;
  final double avgBasket;
  final int productsSold;

  /// Margin as a share of revenue, 0..1. Zero when nothing sold.
  double get marginRate => revenue == 0 ? 0 : margin / revenue;

  factory SalesHeadline.fromRow(Map<String, dynamic> r) => SalesHeadline(
        saleCount: _i(r['sale_count']),
        revenue: _d(r['revenue']),
        cost: _d(r['cost']),
        margin: _d(r['margin']),
        units: _d(r['units']),
        avgBasket: _d(r['avg_basket']),
        productsSold: _i(r['products_sold']),
      );

  static const empty = SalesHeadline(
    saleCount: 0,
    revenue: 0,
    cost: 0,
    margin: 0,
    units: 0,
    avgBasket: 0,
    productsSold: 0,
  );
}

/// One product's line in the "what sells more or less, and how fast" list.
class ProductPerformance {
  const ProductPerformance({
    required this.name,
    required this.units,
    required this.revenue,
    required this.margin,
    required this.saleCount,
    required this.perDay,
  });

  final String name;
  final double units;
  final double revenue;
  final double margin;
  final int saleCount;

  /// Units sold per day over the span it actually sold on — the "how fast".
  final double perDay;

  factory ProductPerformance.fromRow(Map<String, dynamic> r) =>
      ProductPerformance(
        name: (r['name'] ?? '') as String,
        units: _d(r['units']),
        revenue: _d(r['revenue']),
        margin: _d(r['margin']),
        saleCount: _i(r['sale_count']),
        perDay: _d(r['per_day']),
      );
}

/// A single labelled bar: an hour of the day, or a day of the week.
class TimeBucket {
  const TimeBucket({
    required this.index,
    required this.saleCount,
    required this.revenue,
  });

  final int index;
  final int saleCount;
  final double revenue;

  factory TimeBucket.fromHour(Map<String, dynamic> r) => TimeBucket(
        index: _i(r['hour']),
        saleCount: _i(r['sale_count']),
        revenue: _d(r['revenue']),
      );

  factory TimeBucket.fromWeekday(Map<String, dynamic> r) => TimeBucket(
        index: _i(r['dow']),
        saleCount: _i(r['sale_count']),
        revenue: _d(r['revenue']),
      );
}

/// One day on the revenue trend line.
class DayPoint {
  const DayPoint({
    required this.day,
    required this.saleCount,
    required this.revenue,
  });

  final DateTime day;
  final int saleCount;
  final double revenue;

  factory DayPoint.fromRow(Map<String, dynamic> r) => DayPoint(
        day: DateTime.parse(r['day'] as String),
        saleCount: _i(r['sale_count']),
        revenue: _d(r['revenue']),
      );
}

/// One business on the platform-wide comparison.
class BusinessPerformance {
  const BusinessPerformance({
    required this.orgId,
    required this.orgName,
    required this.profile,
    required this.saleCount,
    required this.revenue,
    required this.margin,
    required this.units,
    required this.lastSale,
  });

  final String orgId;
  final String orgName;
  final String profile;
  final int saleCount;
  final double revenue;
  final double margin;
  final double units;
  final DateTime? lastSale;

  factory BusinessPerformance.fromRow(Map<String, dynamic> r) =>
      BusinessPerformance(
        orgId: r['org_id'] as String,
        orgName: (r['org_name'] ?? '') as String,
        profile: (r['profile'] ?? '') as String,
        saleCount: _i(r['sale_count']),
        revenue: _d(r['revenue']),
        margin: _d(r['margin']),
        units: _d(r['units']),
        lastSale: r['last_sale'] == null
            ? null
            : DateTime.parse(r['last_sale'] as String),
      );
}

/// The one-line total across every business, for the platform console.
class PlatformHeadline {
  const PlatformHeadline({
    required this.businesses,
    required this.activeBusinesses,
    required this.saleCount,
    required this.revenue,
    required this.margin,
  });

  final int businesses;
  final int activeBusinesses;
  final int saleCount;
  final double revenue;
  final double margin;

  factory PlatformHeadline.fromRow(Map<String, dynamic> r) => PlatformHeadline(
        businesses: _i(r['businesses']),
        activeBusinesses: _i(r['active_businesses']),
        saleCount: _i(r['sale_count']),
        revenue: _d(r['revenue']),
        margin: _d(r['margin']),
      );

  static const empty = PlatformHeadline(
    businesses: 0,
    activeBusinesses: 0,
    saleCount: 0,
    revenue: 0,
    margin: 0,
  );
}

/// The whole owner analytics payload, fetched together so the screen paints in
/// one pass rather than four staggered spinners.
class OwnerAnalytics {
  const OwnerAnalytics({
    required this.headline,
    required this.products,
    required this.byHour,
    required this.byWeekday,
    required this.daily,
  });

  final SalesHeadline headline;
  final List<ProductPerformance> products;
  final List<TimeBucket> byHour;
  final List<TimeBucket> byWeekday;
  final List<DayPoint> daily;

  bool get isEmpty => headline.saleCount == 0;
}
