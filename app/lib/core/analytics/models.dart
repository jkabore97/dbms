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

// ------------------------------------------------------------------
// A farm's analyses (101's farm_analytics): one jsonb, read as it comes.
// ------------------------------------------------------------------

/// What came in and went out over one stretch of time, and what the flocks
/// did in it.
class FarmPeriod {
  const FarmPeriod({
    this.income = 0,
    this.expenses = 0,
    this.eggs = 0,
    this.deaths = 0,
    this.orders = 0,
    this.ordersTotal = 0,
    this.productionCost = 0,
  });

  final double income;
  final double expenses;
  final double eggs;
  final double deaths;
  final int orders;
  final double ordersTotal;
  final double productionCost;

  double get result => income - expenses;

  factory FarmPeriod.fromJson(Map<String, dynamic>? r) => r == null
      ? const FarmPeriod()
      : FarmPeriod(
          income: _d(r['income']),
          expenses: _d(r['expenses']),
          eggs: _d(r['eggs']),
          deaths: _d(r['deaths']),
          orders: _i(r['orders']),
          ordersTotal: _d(r['orders_total']),
          productionCost: _d(r['production_cost']),
        );
}

/// One name and an amount: an article sold, an account of the books.
class NamedAmount {
  const NamedAmount({required this.name, required this.amount, this.units = 0});

  final String name;
  final double amount;
  final double units;
}

/// An open flock: how many are left of how many, and how well it lays.
class FlockFigure {
  const FlockFigure({
    required this.batchCode,
    required this.started,
    required this.alive,
    required this.died,
    required this.diedInWindow,
    required this.eggs7d,
    required this.layRate,
  });

  final String batchCode;
  final int started;
  final int alive;
  final double died;
  final double diedInWindow;
  final int eggs7d;

  /// Eggs a day per bird alive, over the last seven days (009), 0..1.
  final double layRate;

  /// Birds lost of those that arrived, 0..1.
  double get mortality => started == 0 ? 0 : died / started;
}

/// What was eaten or used of one item: this month, last month, the window.
class FeedUse {
  const FeedUse({
    required this.name,
    required this.unit,
    required this.month,
    required this.lastMonth,
    required this.window,
  });

  final String name;
  final String unit;
  final double month;
  final double lastMonth;
  final double window;
}

/// Money in and out on one day.
class FarmDay {
  const FarmDay({required this.day, required this.income, required this.expenses});

  final DateTime day;
  final double income;
  final double expenses;
}

class FarmAnalytics {
  const FarmAnalytics({
    required this.month,
    required this.lastMonth,
    required this.window,
    required this.products,
    required this.expenses,
    required this.income,
    required this.flocks,
    required this.feed,
    required this.daily,
  });

  final FarmPeriod month;
  final FarmPeriod lastMonth;
  final FarmPeriod window;

  /// What sold, best first (the till's lines and the vitrine's finished
  /// orders).
  final List<NamedAmount> products;
  final List<NamedAmount> expenses;
  final List<NamedAmount> income;
  final List<FlockFigure> flocks;
  final List<FeedUse> feed;
  final List<FarmDay> daily;

  bool get isEmpty =>
      window.income == 0 &&
      window.expenses == 0 &&
      window.eggs == 0 &&
      window.deaths == 0 &&
      products.isEmpty &&
      flocks.isEmpty &&
      feed.isEmpty;

  factory FarmAnalytics.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String key) => [
          for (final r in (j[key] as List? ?? const []))
            Map<String, dynamic>.from(r as Map),
        ];
    final periods = Map<String, dynamic>.from((j['periods'] as Map?) ?? const {});
    Map<String, dynamic>? period(String key) => periods[key] == null
        ? null
        : Map<String, dynamic>.from(periods[key] as Map);
    return FarmAnalytics(
      month: FarmPeriod.fromJson(period('month')),
      lastMonth: FarmPeriod.fromJson(period('last_month')),
      window: FarmPeriod.fromJson(period('window')),
      products: [
        for (final r in list('products'))
          NamedAmount(
              name: (r['name'] ?? '') as String,
              amount: _d(r['revenue']),
              units: _d(r['units'])),
      ],
      expenses: [
        for (final r in list('expenses'))
          NamedAmount(name: (r['name'] ?? '') as String, amount: _d(r['amount'])),
      ],
      income: [
        for (final r in list('income'))
          NamedAmount(name: (r['name'] ?? '') as String, amount: _d(r['amount'])),
      ],
      flocks: [
        for (final r in list('flocks'))
          FlockFigure(
            batchCode: (r['batch_code'] ?? '') as String,
            started: _i(r['started']),
            alive: _i(r['alive']),
            died: _d(r['died']),
            diedInWindow: _d(r['died_window']),
            eggs7d: _i(r['eggs_7d']),
            layRate: _d(r['lay_rate']),
          ),
      ],
      feed: [
        for (final r in list('feed'))
          FeedUse(
            name: (r['name'] ?? '') as String,
            unit: (r['unit'] ?? '') as String,
            month: _d(r['month']),
            lastMonth: _d(r['last_month']),
            window: _d(r['window']),
          ),
      ],
      daily: [
        for (final r in list('daily'))
          FarmDay(
            day: DateTime.parse(r['day'] as String),
            income: _d(r['income']),
            expenses: _d(r['expenses']),
          ),
      ],
    );
  }
}
