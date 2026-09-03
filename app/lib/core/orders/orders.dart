/// Orders (055): a customer's réservation at a shop, seen from both sides.
///
/// An order is a promise, not a sale: the goods and the money change hands
/// when the customer collects or the shop delivers, and *that* is recorded
/// in the till as it always was. So nothing here touches stock or the
/// books; it is a list of who wants what, and where it stands.
library;

/// One line of an order, as it was when the order was placed — the name and
/// the price are snapshots, so a later price change does not rewrite what
/// the customer was told.
class OrderLine {
  const OrderLine({
    required this.name,
    required this.unitPrice,
    required this.quantity,
  });

  final String name;
  final double unitPrice;
  final double quantity;

  double get total => unitPrice * quantity;

  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        name: (j['name'] as String?) ?? '',
        unitPrice: _num(j['unit_price']) ?? 0,
        quantity: _num(j['quantity']) ?? 0,
      );
}

/// Where an order stands. The shop moves it forward; the customer can only
/// cancel while it is still pending.
///
///   pending → accepted → ready → picked_up | delivered
///   ready → in_transit → delivered      (a courier carries it, 056)
///   pending → refused
///   pending → cancelled (by the customer)
///   accepted | ready → cancelled (by the shop)
const orderStatuses = [
  'pending',
  'accepted',
  'ready',
  'in_transit',
  'picked_up',
  'delivered',
  'refused',
  'cancelled',
];

/// Still needs something from somebody.
bool orderIsOpen(String status) =>
    status == 'pending' ||
    status == 'accepted' ||
    status == 'ready' ||
    status == 'in_transit';

/// What a person reads.
String orderStatusLabel(String status) => switch (status) {
      'pending' => 'En attente',
      'accepted' => 'Acceptée',
      'ready' => 'Prête',
      'in_transit' => 'En route',
      'picked_up' => 'Récupérée',
      'delivered' => 'Livrée',
      'refused' => 'Refusée',
      'cancelled' => 'Annulée',
      _ => status,
    };

String fulfilmentLabel(String fulfilment) =>
    fulfilment == 'delivery' ? 'Livraison' : 'Retrait en boutique';

/// How the order is paid (057).
String paymentLabel(String method) =>
    method == 'wave' ? 'Wave' : 'Espèces';

/// An order as its customer sees it.
class CustomerOrder {
  const CustomerOrder({
    required this.id,
    required this.shopName,
    required this.shopSlug,
    required this.status,
    required this.fulfilment,
    required this.total,
    required this.currency,
    required this.createdAt,
    required this.lines,
    this.note,
    this.address,
    this.phone,
    this.courierName,
    this.paymentMethod = 'cash',
    this.paidAt,
    this.shopWave,
  });

  final String id;
  final String shopName;
  final String shopSlug;
  final String status;
  final String fulfilment;
  final String? note;
  final String? address;
  final String? phone;
  final double total;
  final String currency;
  final DateTime createdAt;
  final List<OrderLine> lines;

  /// Who carries it, once a livreur took the course (056).
  final String? courierName;

  /// 'cash' or 'wave' (057); [paidAt] is set only by the shop's
  /// confirmation, and [shopWave] is the link to pay a Wave order with.
  final String paymentMethod;
  final DateTime? paidAt;
  final String? shopWave;

  bool get isOpen => orderIsOpen(status);
  bool get isPaid => paidAt != null;

  /// The customer can pay now: a Wave order the shop has accepted (paying
  /// before the shop says yes would be money in limbo) and not yet
  /// confirmed as paid.
  bool get canPayNow =>
      paymentMethod == 'wave' &&
      !isPaid &&
      shopWave != null &&
      (status == 'accepted' || status == 'ready' || status == 'in_transit');

  factory CustomerOrder.fromRow(Map<String, dynamic> row) => CustomerOrder(
        id: row['id'] as String,
        shopName: (row['shop_name'] as String?) ?? '',
        shopSlug: (row['shop_slug'] as String?) ?? '',
        status: (row['status'] as String?) ?? 'pending',
        fulfilment: (row['fulfilment'] as String?) ?? 'pickup',
        note: row['note'] as String?,
        address: row['address'] as String?,
        phone: row['phone'] as String?,
        total: _num(row['total']) ?? 0,
        currency: (row['currency'] as String?) ?? 'XOF',
        createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal() ??
            DateTime.now(),
        courierName: row['courier_name'] as String?,
        paymentMethod: (row['payment_method'] as String?) ?? 'cash',
        paidAt: row['paid_at'] == null
            ? null
            : DateTime.tryParse('${row['paid_at']}')?.toLocal(),
        shopWave: row['shop_wave'] as String?,
        lines: _lines(row['lines']),
      );
}

/// An order as the shop sees it.
class ShopOrder {
  const ShopOrder({
    required this.id,
    required this.customerName,
    required this.status,
    required this.fulfilment,
    required this.total,
    required this.currency,
    required this.createdAt,
    required this.lines,
    this.phone,
    this.note,
    this.address,
    this.courierName,
    this.paymentMethod = 'cash',
    this.paidAt,
  });

  final String id;
  final String customerName;
  final String? phone;
  final String status;
  final String fulfilment;
  final String? note;
  final String? address;
  final double total;
  final String currency;
  final DateTime createdAt;
  final List<OrderLine> lines;

  /// Who carries it, once a livreur took the course (056).
  final String? courierName;

  /// 'cash' or 'wave' (057); [paidAt] is the shop's own confirmation.
  final String paymentMethod;
  final DateTime? paidAt;

  bool get isOpen => orderIsOpen(status);
  bool get isPaid => paidAt != null;

  /// What the shop may do next, in the order the buttons are shown.
  List<String> get nextStatuses => switch (status) {
        'pending' => const ['accepted', 'refused'],
        'accepted' => fulfilment == 'delivery'
            ? const ['ready', 'delivered', 'cancelled']
            : const ['ready', 'picked_up', 'cancelled'],
        'ready' => fulfilment == 'delivery'
            ? const ['delivered', 'cancelled']
            : const ['picked_up', 'cancelled'],
        // On a motorbike: the shop can only confirm the end of the journey.
        'in_transit' => const ['delivered'],
        _ => const [],
      };

  factory ShopOrder.fromRow(Map<String, dynamic> row) => ShopOrder(
        id: row['id'] as String,
        customerName: (row['customer_name'] as String?) ?? 'Client',
        phone: row['phone'] as String?,
        status: (row['status'] as String?) ?? 'pending',
        fulfilment: (row['fulfilment'] as String?) ?? 'pickup',
        note: row['note'] as String?,
        address: row['address'] as String?,
        total: _num(row['total']) ?? 0,
        currency: (row['currency'] as String?) ?? 'XOF',
        createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal() ??
            DateTime.now(),
        courierName: row['courier_name'] as String?,
        paymentMethod: (row['payment_method'] as String?) ?? 'cash',
        paidAt: row['paid_at'] == null
            ? null
            : DateTime.tryParse('${row['paid_at']}')?.toLocal(),
        lines: _lines(row['lines']),
      );
}

/// The verb on the button that moves an order to [status].
String orderActionLabel(String status) => switch (status) {
      'accepted' => 'Accepter',
      'refused' => 'Refuser',
      'ready' => 'Prête',
      'in_transit' => 'En route',
      'picked_up' => 'Récupérée',
      'delivered' => 'Livrée',
      'cancelled' => 'Annuler',
      _ => status,
    };

List<OrderLine> _lines(Object? raw) {
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((m) => OrderLine.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
  return const [];
}

double? _num(Object? v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
