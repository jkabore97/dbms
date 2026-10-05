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
    this.deliveryFee,
    this.orgId,
  });

  final String id;

  /// The shop's id: whether its sales can be paid through Kaj's Wave (076).
  final String? orgId;
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

  /// What the delivery costs (061), fixed when the order was placed and
  /// paid to the courier at the door. Null on a pickup, or when no price
  /// could be computed — the app then says "à discuter".
  final double? deliveryFee;

  bool get isOpen => orderIsOpen(status);
  bool get isPaid => paidAt != null;

  /// Goods plus the delivery, which is what changes hands.
  double get grandTotal => total + (deliveryFee ?? 0);

  /// The customer can pay now: a Wave order the shop has accepted (paying
  /// before the shop says yes would be money in limbo) and not yet
  /// confirmed as paid.
  bool get canPayNow =>
      paymentMethod == 'wave' &&
      !isPaid &&
      shopWave != null &&
      (status == 'accepted' || status == 'ready' || status == 'in_transit');

  /// The same moment, through Kaj's Wave checkout (076): no shop link
  /// needed, the shop is paid on its own number afterwards.
  bool get canPayByWave =>
      paymentMethod == 'wave' &&
      !isPaid &&
      orgId != null &&
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
        deliveryFee: _num(row['delivery_fee']),
        orgId: row['org_id'] as String?,
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
    this.dropLat,
    this.dropLng,
    this.deliveryFee,
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

  /// The customer's own pin (058), when they shared one with a delivery.
  final double? dropLat;
  final double? dropLng;

  /// The delivery's price (061), fixed at order time; null on a pickup.
  final double? deliveryFee;

  bool get isOpen => orderIsOpen(status);
  bool get isPaid => paidAt != null;
  bool get hasDropPin => dropLat != null && dropLng != null;

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
        dropLat: _num(row['drop_lat']),
        dropLng: _num(row['drop_lng']),
        deliveryFee: _num(row['delivery_fee']),
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

DateTime? _when(Object? v) =>
    v == null ? null : DateTime.tryParse('$v')?.toLocal();
double _amount(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// How long an order has sat where it is (073), and whether that is too long.
class OrderClock {
  const OrderClock({
    this.since,
    this.stuck = false,
    this.selfDelivered = false,
    this.outcome,
  });

  factory OrderClock.fromRow(Map<String, dynamic> r) => OrderClock(
        since: _when(r['since']),
        stuck: r['stuck'] == true,
        selfDelivered: r['self_delivered'] == true,
        outcome: r['outcome'] as String?,
      );

  final DateTime? since;
  final bool stuck;
  final bool selfDelivered;

  /// Why a delivery failed: absent, refused, unreachable, other.
  final String? outcome;

  /// "depuis 25 min", "depuis 2 h 10".
  String sinceLabel([DateTime? now]) {
    final at = since;
    if (at == null) return '';
    final d = (now ?? DateTime.now()).difference(at);
    if (d.inMinutes < 1) return "à l'instant";
    if (d.inMinutes < 60) return 'depuis ${d.inMinutes} min';
    final m = d.inMinutes % 60;
    if (d.inHours < 24) {
      return 'depuis ${d.inHours} h${m == 0 ? '' : ' ${m.toString().padLeft(2, '0')}'}';
    }
    return 'depuis ${d.inDays} j';
  }
}

/// Why a door did not open, in the shop's and shopper's words.
String deliveryOutcomeLabel(String? outcome) => switch (outcome) {
      'absent' => 'client absent',
      'refused' => 'refusée par le client',
      'unreachable' => 'client injoignable',
      'other' => 'autre raison',
      _ => '',
    };

/// Cash a courier holds for the shop (073).
class CashOwed {
  const CashOwed({
    required this.orderId,
    required this.courierName,
    required this.total,
    this.courierPhone,
    this.customerName,
    this.currency = 'XOF',
    this.deliveredAt,
  });

  factory CashOwed.fromRow(Map<String, dynamic> r) => CashOwed(
        orderId: '${r['order_id']}',
        courierName: '${r['courier_name'] ?? 'Livreur'}',
        courierPhone: r['courier_phone'] as String?,
        customerName: r['customer_name'] as String?,
        total: _amount(r['total']),
        currency: '${r['currency'] ?? 'XOF'}',
        deliveredAt: _when(r['delivered_at']),
      );

  final String orderId;
  final String courierName;
  final String? courierPhone;
  final String? customerName;
  final double total;
  final String currency;
  final DateTime? deliveredAt;
}

/// A courier a shop named as its own (073).
class OrgCourier {
  const OrgCourier({required this.userId, required this.name, this.phone});

  factory OrgCourier.fromRow(Map<String, dynamic> r) => OrgCourier(
        userId: '${r['user_id']}',
        name: '${r['name'] ?? 'Livreur'}',
        phone: r['phone'] as String?,
      );

  final String userId;
  final String name;
  final String? phone;
}

/// The shopper's view of where an order is (073).
class OrderTracking {
  const OrderTracking({
    required this.status,
    this.fulfilment = 'pickup',
    this.outcome,
    this.selfDelivered = false,
    this.since,
    this.shopName = '',
    this.shopPhone,
    this.courierName,
    this.courierPhone,
    this.code,
    this.events = const [],
  });

  factory OrderTracking.fromJson(Map<String, dynamic> j) {
    final shop = j['shop'] is Map ? Map<String, dynamic>.from(j['shop']) : const {};
    final courier =
        j['courier'] is Map ? Map<String, dynamic>.from(j['courier']) : null;
    return OrderTracking(
      status: '${j['status']}',
      fulfilment: '${j['fulfilment'] ?? 'pickup'}',
      outcome: j['outcome'] as String?,
      selfDelivered: j['self'] == true,
      since: _when(j['since']),
      shopName: '${shop['name'] ?? ''}',
      shopPhone: shop['phone'] as String?,
      courierName: courier?['name'] as String?,
      courierPhone: courier?['phone'] as String?,
      code: j['code'] as String?,
      events: [
        if (j['events'] is List)
          for (final e in j['events'] as List)
            if (e is Map && _when(e['at']) != null)
              (status: '${e['status']}', at: _when(e['at'])!),
      ],
    );
  }

  final String status;
  final String fulfilment;
  final String? outcome;
  final bool selfDelivered;
  final DateTime? since;
  final String shopName;
  final String? shopPhone;
  final String? courierName;
  final String? courierPhone;

  /// The four digits the shopper gives the courier at the door.
  final String? code;
  final List<({String status, DateTime at})> events;

  /// When the order reached [status], if it did.
  DateTime? reached(String status) {
    for (final e in events.reversed) {
      if (e.status == status) return e.at;
    }
    return null;
  }
}
