import 'package:supabase_flutter/supabase_flutter.dart';

/// The livreur's side of orders (056): registering, the board of ready
/// deliveries, and walking a taken one to the door. Every rule lives
/// server-side — who is approved, whose job it is, which step comes next —
/// so this class only carries the calls.
class CourierRepository {
  CourierRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError("L'espace livreur a besoin d'une connexion.");
    }
    return client;
  }

  /// 'pending', 'approved', 'suspended' — or null for "never registered".
  Future<String?> status() async =>
      await _requireClient().rpc('courier_status') as String?;

  Future<void> register({String? phone}) async {
    await _requireClient()
        .rpc('register_courier', params: {'p_phone': phone});
  }

  /// Ready deliveries nobody carries yet, oldest first.
  Future<List<DeliveryJob>> available() async {
    final rows =
        await _requireClient().rpc('available_deliveries') as List<dynamic>;
    return rows
        .map((r) => DeliveryJob.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// The courier's own jobs, running first.
  Future<List<DeliveryJob>> mine() async {
    final rows =
        await _requireClient().rpc('courier_deliveries') as List<dynamic>;
    return rows
        .map((r) => DeliveryJob.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> take(String orderId) async {
    await _requireClient()
        .rpc('take_delivery', params: {'p_order_id': orderId});
  }

  Future<void> release(String orderId) async {
    await _requireClient()
        .rpc('release_delivery', params: {'p_order_id': orderId});
  }

  /// 'in_transit' when the parcel is collected, 'delivered' at the door.
  Future<void> mark(String orderId, String status) async {
    await _requireClient().rpc('courier_mark', params: {
      'p_order_id': orderId,
      'p_status': status,
    });
  }
}

/// One delivery as the courier sees it: where to collect, where to bring,
/// what to collect at the door. On the open board [customerName] and
/// [phone] are absent — they arrive once the job is theirs.
class DeliveryJob {
  const DeliveryJob({
    required this.orderId,
    required this.shopName,
    required this.total,
    required this.currency,
    required this.createdAt,
    this.shopAddress,
    this.shopLat,
    this.shopLng,
    this.customerName,
    this.phone,
    this.dropAddress,
    this.dropLat,
    this.dropLng,
    this.status,
    this.paymentMethod = 'cash',
    this.paidAt,
  });

  final String orderId;
  final String shopName;
  final String? shopAddress;
  final double? shopLat;
  final double? shopLng;
  final String? customerName;
  final String? phone;
  final String? dropAddress;

  /// The customer's own pin (058), when they shared one.
  final double? dropLat;
  final double? dropLng;

  /// Null on the open board (everything there is 'ready' by definition).
  final String? status;

  /// 'cash' or 'wave' (057). [paidAt] set means nothing to collect.
  final String paymentMethod;
  final DateTime? paidAt;
  final double total;
  final String currency;
  final DateTime createdAt;

  bool get shopHasPin => shopLat != null && shopLng != null;
  bool get hasDropPin => dropLat != null && dropLng != null;
  bool get isPaid => paidAt != null;

  /// Still needs the courier: taken but not collected, or on the road.
  bool get isRunning => status == 'ready' || status == 'in_transit';

  factory DeliveryJob.fromRow(Map<String, dynamic> row) => DeliveryJob(
        orderId: row['order_id'] as String,
        shopName: (row['shop_name'] as String?) ?? '',
        shopAddress: row['shop_address'] as String?,
        shopLat: _num(row['shop_lat']),
        shopLng: _num(row['shop_lng']),
        customerName: row['customer_name'] as String?,
        phone: row['phone'] as String?,
        dropAddress: row['drop_address'] as String?,
        dropLat: _num(row['drop_lat']),
        dropLng: _num(row['drop_lng']),
        status: row['status'] as String?,
        paymentMethod: (row['payment_method'] as String?) ?? 'cash',
        paidAt: row['paid_at'] == null
            ? null
            : DateTime.tryParse('${row['paid_at']}')?.toLocal(),
        total: _num(row['total']) ?? 0,
        currency: (row['currency'] as String?) ?? 'XOF',
        createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal() ??
            DateTime.now(),
      );

  static double? _num(Object? v) =>
      v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
}
