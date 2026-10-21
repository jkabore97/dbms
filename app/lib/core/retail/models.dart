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
    this.isPublished = false,
    this.description,
    this.unit,
    this.availableFrom,
    this.isService = false,
    this.priceFrom = false,
    this.stockTracked = true,
    this.durationMinutes,
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

  /// Shown on the shop's public vitrine (052), when the shop has opened one.
  /// Off by default: the shop picks each article it puts in the window.
  final bool isPublished;

  /// The two lines a shopkeeper would say across the counter — size, taste,
  /// origin — shown under the name on the vitrine (064). Null when the shop
  /// wrote nothing.
  final String? description;

  /// How it is sold — « plateau », « kg », « tête » (083). Null is « l'unité ».
  final String? unit;

  /// For a batch or a harvest still to come (083): until this day the
  /// vitrine offers it as a pre-order. Null when it is there now.
  final DateTime? availableFrom;

  /// A service, not goods (098): a haircut, a lesson, a hall for the
  /// evening. No stock — never « épuisé », never counted, never moved by a
  /// sale — and its own section on the vitrine, booked rather than added.
  final bool isService;

  /// « à partir de » (098): the price is where it starts, not what it is.
  final bool priceFrom;

  /// « Suivre le stock » (131): false for an article whose count is not
  /// kept — a ticket, a book sold at the door, a shop that does not count.
  /// It has no count (always 0 server-side), is never « Rupture » or
  /// « épuisé », and orders and sales move nothing. True before 131.
  final bool stockTracked;

  /// How long a service takes, in minutes (136); null when not said — or
  /// on a database before 136, where the service flow wrote it into the
  /// description as « Durée : 1 h » (see duration.dart's legacyDuration).
  final int? durationMinutes;

  /// Whether its count means something: goods, followed.
  bool get counted => !isService && stockTracked;

  /// What the shop makes on one unit at today's prices. Negative means it is
  /// being sold for less than it cost, which is worth seeing.
  double get margin => salePrice - costPrice;

  bool get isLow =>
      counted && lowStockAt != null && quantity <= lowStockAt!;

  /// What the till's copy on the phone keeps of it (LocalDb.cacheProducts),
  /// in the server's own column names so [Product.fromRow] reads it back.
  Map<String, Object?> toShelfRow() => {
        'id': id,
        'name': name,
        'barcode': barcode,
        'sale_price': salePrice,
        'quantity': quantity,
        'unit': unit,
        'is_ingredient': isIngredient,
        'is_service': isService,
        'price_from': priceFrom,
        'stock_tracked': stockTracked,
      };

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
      // Absent before 052: an app ahead of its database reads "not shown".
      isPublished: row['is_published'] == true,
      description: (row['description'] as String?)?.trim().isEmpty == true
          ? null
          : row['description'] as String?,
      unit: (row['unit'] as String?)?.trim().isEmpty == true
          ? null
          : row['unit'] as String?,
      availableFrom: row['available_from'] == null
          ? null
          : DateTime.tryParse('${row['available_from']}'),
      // Absent before 098: goods, at their plain price.
      isService: row['is_service'] == true,
      priceFrom: row['price_from'] == true,
      // Absent before 131: every article is followed.
      stockTracked: row['stock_tracked'] != false,
      // Absent before 136: not said in minutes.
      durationMinutes: (row['duration_minutes'] as num?)?.toInt(),
    );
  }
}

/// One photo of an item's gallery (136): the document it is, its key.
class GalleryPhoto {
  const GalleryPhoto({required this.documentId, required this.photoKey});

  final String documentId;
  final String photoKey;
}

/// An item's photos in order — the first is its cover — and how many it
/// may hold: 1 on Basic, max_item_photos_pro (5) on Mara Pro (136).
class ItemGallery {
  const ItemGallery({required this.photos, required this.limit});

  final List<GalleryPhoto> photos;
  final int limit;

  /// Room for one more photo.
  bool get hasRoom => photos.length < limit;

  /// Basic: one photo an item; a second is Mara Pro's.
  bool get coverOnly => limit <= 1;

  factory ItemGallery.fromJson(Map<String, dynamic> j) => ItemGallery(
        photos: [
          for (final p in (j['photos'] as List? ?? const []))
            if (p is Map && p['document_id'] != null && p['photo_key'] != null)
              GalleryPhoto(documentId: '${p['document_id']}', photoKey: '${p['photo_key']}'),
        ],
        limit: (j['limit'] as num?)?.toInt() ?? 1,
      );
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

/// A delivery that arrived — one row of `recent_deliveries` (016/042). Shown on
/// the corrections screen so an owner can undo a purchase that was a mistake or
/// a test. [reversed] is true once it has been put back.
class Delivery {
  const Delivery({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    required this.lineTotal,
    required this.receivedAt,
    this.receivedBy,
    this.reversed = false,
  });

  final String id;
  final String productName;
  final double quantity;
  final double unitCost;
  final double lineTotal;
  final DateTime receivedAt;
  final String? receivedBy;
  final bool reversed;

  factory Delivery.fromRow(Map<String, dynamic> row) {
    double parse(Object? v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    return Delivery(
      id: row['id'] as String,
      productName: (row['product_name'] as String?) ?? '',
      quantity: parse(row['quantity']),
      unitCost: parse(row['unit_cost']),
      lineTotal: parse(row['line_total']),
      receivedAt: DateTime.parse(row['received_at'] as String),
      receivedBy: row['received_by'] as String?,
      reversed: row['reversed'] == true,
    );
  }
}

/// A recorded sale — one row of `recent_sales` (042). Shown on the corrections
/// screen so an owner can return one that was a mistake or a test.
class SaleSummary {
  const SaleSummary({
    required this.id,
    required this.method,
    required this.total,
    required this.occurredAt,
    this.note,
    this.soldBy,
    this.reversed = false,
  });

  final String id;
  final String method;
  final double total;
  final DateTime occurredAt;
  final String? note;
  final String? soldBy;
  final bool reversed;

  factory SaleSummary.fromRow(Map<String, dynamic> row) {
    double parse(Object? v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    return SaleSummary(
      id: row['id'] as String,
      method: (row['method'] as String?) ?? 'cash',
      total: parse(row['total']),
      occurredAt: DateTime.parse(row['occurred_at'] as String),
      note: row['note'] as String?,
      soldBy: row['sold_by'] as String?,
      reversed: row['reversed'] == true,
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
    this.flockId,
    this.herdId,
  });

  final String? productId;

  /// A farm's group of animals sold from « Vente » (150's sell_animals):
  /// the server finds or makes the article that follows it. Null for every
  /// other line — a shop's, an association's, a farm's eggs.
  final String? flockId;
  final String? herdId;
  final String name;
  final double quantity;
  final double unitPrice;

  bool get isAnimals => flockId != null || herdId != null;

  double get lineTotal => quantity * unitPrice;

  Map<String, Object?> toJson() => {
        if (productId != null) 'product_id': productId,
        if (flockId != null) 'flock_id': flockId,
        if (herdId != null) 'herd_id': herdId,
        'name': name,
        'quantity': quantity,
        'unit_price': unitPrice,
      };
}
