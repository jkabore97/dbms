/// What a shop is made of, as the app sees it.
///
/// Every one of these is a row returned by a function in
/// `011_retail_profile.sql`. They are deliberately thin: the numbers that
/// matter — margin, value at risk, the day's net — are computed by the
/// database over every device's rows, not by this one over the rows it
/// happens to hold.
library;

/// Something on a shelf.
class Product {
  const Product({
    required this.id,
    required this.name,
    this.barcode,
    this.serial,
    this.costPrice = 0,
    this.salePrice = 0,
    this.quantity = 0,
    this.expiresOn,
    this.lowStockAt,
    this.isIngredient = false,
  });

  final String id;
  final String name;
  final String? barcode;

  /// One physical unit's number, for the goods where that matters: a phone,
  /// a radio, a panel. Null for nearly everything a shop sells.
  final String? serial;
  final double costPrice;
  final double salePrice;
  final double quantity;
  final DateTime? expiresOn;
  final double? lowStockAt;

  /// Cooked with, not sold: hidden from the sale picker, surfaced first in
  /// the production picker. A signpost, not a rule — see migration 028.
  final bool isIngredient;

  /// What the shop makes on one unit at today's prices. Negative means it is
  /// being sold for less than it cost, which is worth seeing.
  double get margin => salePrice - costPrice;

  bool get isLow => lowStockAt != null && quantity <= lowStockAt!;

  factory Product.fromRow(Map<String, dynamic> row) {
    double parse(Object? v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

    final expires = row['expires_on'] as String?;
    final low = row['low_stock_at'];

    return Product(
      id: row['id'] as String,
      name: row['name'] as String,
      barcode: row['barcode'] as String?,
      serial: row['serial'] as String?,
      costPrice: parse(row['cost_price']),
      salePrice: parse(row['sale_price']),
      quantity: parse(row['quantity']),
      expiresOn: expires == null ? null : DateTime.parse(expires),
      lowStockAt: low == null ? null : parse(low),
      isIngredient: row['is_ingredient'] == true,
    );
  }
}

/// A product close enough to its expiry date to be worth acting on, and what
/// it cost — which is the number that makes anybody act.
class ExpiringProduct {
  const ExpiringProduct({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.expiresOn,
    required this.daysLeft,
    required this.valueAtRisk,
  });

  final String productId;
  final String name;
  final double quantity;
  final DateTime expiresOn;
  final int daysLeft;
  final double valueAtRisk;

  /// Already dead. Shown differently: this is not a warning any more, it is a
  /// loss that has happened.
  bool get isExpired => daysLeft < 0;

  factory ExpiringProduct.fromRow(Map<String, dynamic> row) {
    double parse(Object? v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

    return ExpiringProduct(
      productId: row['product_id'] as String,
      name: row['name'] as String,
      quantity: parse(row['quantity']),
      expiresOn: DateTime.parse(row['expires_on'] as String),
      daysLeft: (row['days_left'] as num).toInt(),
      valueAtRisk: parse(row['value_at_risk']),
    );
  }
}

/// One day across every device that recorded into this shop.
class StoreDay {
  const StoreDay({
    this.salesTotal = 0,
    this.returnsTotal = 0,
    this.netSales = 0,
    this.saleCount = 0,
    this.itemsSold = 0,
  });

  final double salesTotal;
  final double returnsTotal;
  final double netSales;
  final int saleCount;
  final double itemsSold;

  factory StoreDay.fromRow(Map<String, dynamic> row) {
    double parse(Object? v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

    return StoreDay(
      salesTotal: parse(row['sales_total']),
      returnsTotal: parse(row['returns_total']),
      netSales: parse(row['net_sales']),
      saleCount: (row['sale_count'] as num?)?.toInt() ?? 0,
      itemsSold: parse(row['items_sold']),
    );
  }
}

/// One line of a sale being composed on screen, before it is sent.
///
/// Not a database row: this is the basket. [productId] is null for something
/// being sold that was never entered as a product, which the server turns into
/// one — the capture-first rule, applied to selling rather than to photos.
class SaleLineDraft {
  const SaleLineDraft({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.productId,
  });

  final String? productId;
  final String name;
  final double quantity;
  final double unitPrice;

  double get lineTotal => quantity * unitPrice;

  Map<String, Object?> toJson() => {
        if (productId != null) 'product_id': productId,
        'name': name,
        'quantity': quantity,
        'unit_price': unitPrice,
      };
}
