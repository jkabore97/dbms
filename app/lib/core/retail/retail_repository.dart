import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// The shop's reads and writes.
///
/// The split here is not the farm's split, and the reason is the counter.
///
/// A sale happens with a customer standing in front of the shopkeeper, so
/// recording one must never wait for the network — `record_sale()` is called
/// with a `client_uuid` and is idempotent, so a phone that is not sure whether
/// its sale landed simply sends it again and gets the same sale back. That is
/// what makes retrying safe, and retrying is what makes the shop usable in a
/// market with two bars of signal.
///
/// The counts and the day's total are read from the server, because a shop has
/// more than one person selling and no device can know what another one sold.
/// The screens say so rather than showing this phone's share as if it were the
/// whole shop.
class RetailRepository {
  RetailRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  String? get currentUserId => _client?.auth.currentUser?.id;

  // ----------------------------------------------------------------
  // What is on the shelves
  // ----------------------------------------------------------------

  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async {
    final client = _requireClient();
    var query = client
        .from('products')
        .select('id, name, barcode, serial, cost_price, sale_price, quantity, '
            'expires_on, low_stock_at')
        .eq('org_id', orgId);
    if (activeOnly) query = query.eq('is_active', true);

    final rows = await query.order('name');
    return (rows as List)
        .map((r) => Product.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Stock that dies soon, most urgent first.
  Future<List<ExpiringProduct>> expiring(String orgId,
      {int within = 14}) async {
    final client = _requireClient();
    final rows = await client.rpc('expiring_products', params: {
      'p_org_id': orgId,
      'p_within': within,
    }) as List<dynamic>;

    return rows
        .map(
            (r) => ExpiringProduct.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// The cost of stock that was sold inside its last [within] days rather than
  /// thrown away. A definition, not a measurement — see the comment on
  /// `losses_avoided()` in 011.
  Future<double> lossesAvoided(String orgId, {int within = 14}) async {
    final client = _requireClient();
    final value = await client.rpc('losses_avoided', params: {
      'p_org_id': orgId,
      'p_within': within,
    });
    if (value == null) return 0;
    return value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  }

  Future<StoreDay> day(String orgId, {DateTime? on}) async {
    final client = _requireClient();
    final date = on ?? DateTime.now();
    final rows = await client.rpc('store_day', params: {
      'p_org_id': orgId,
      'p_on': _date(date),
    }) as List<dynamic>;

    if (rows.isEmpty) return const StoreDay();
    return StoreDay.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  // ----------------------------------------------------------------
  // Selling
  // ----------------------------------------------------------------

  /// Records a sale and returns its id.
  ///
  /// [clientUuid] is what makes a retry safe: the server returns the original
  /// sale rather than selling the same goods twice. Callers should generate it
  /// once per basket and reuse it across retries, never per attempt.
  Future<String> recordSale({
    required String orgId,
    required List<SaleLineDraft> lines,
    String method = 'cash',
    String? note,
    String? clientUuid,
    String? deviceId,
  }) async {
    final client = _requireClient();
    if (lines.isEmpty) {
      throw StateError('Ajoutez au moins un article avant d\'enregistrer.');
    }

    final id = await client.rpc('record_sale', params: {
      'p_org_id': orgId,
      'p_lines': lines.map((l) => l.toJson()).toList(),
      'p_method': method,
      if (note != null && note.isNotEmpty) 'p_note': note,
      if (clientUuid != null) 'p_client_uuid': clientUuid,
      if (deviceId != null) 'p_device_id': deviceId,
    });
    return id as String;
  }

  /// Undoes a sale by writing a return against it. The original stays.
  Future<String> recordReturn(String saleId, {String? note}) async {
    final client = _requireClient();
    final id = await client.rpc('record_return', params: {
      'p_sale_id': saleId,
      if (note != null && note.isNotEmpty) 'p_note': note,
    });
    return id as String;
  }

  // ----------------------------------------------------------------
  // Stocking
  // ----------------------------------------------------------------

  Future<String> ensureProduct({
    required String orgId,
    required String name,
    double? salePrice,
    double? costPrice,
    String? barcode,
    DateTime? expiresOn,
  }) async {
    final client = _requireClient();
    final id = await client.rpc('ensure_product', params: {
      'p_org_id': orgId,
      'p_name': name,
      if (salePrice != null) 'p_sale_price': salePrice,
      if (costPrice != null) 'p_cost_price': costPrice,
      if (barcode != null && barcode.isNotEmpty) 'p_barcode': barcode,
      if (expiresOn != null) 'p_expires_on': _date(expiresOn),
      if (currentUserId != null) 'p_actor': currentUserId,
    });
    return id as String;
  }

  /// A delivery arriving: raises the count and books the purchase.
  Future<void> receive({
    required String orgId,
    required String productId,
    required double quantity,
    double? unitCost,
    DateTime? expiresOn,
    String method = 'cash',
    String? clientUuid,
  }) async {
    final client = _requireClient();
    await client.rpc('receive_products', params: {
      'p_org_id': orgId,
      'p_product_id': productId,
      'p_quantity': quantity,
      if (unitCost != null) 'p_unit_cost': unitCost,
      if (expiresOn != null) 'p_expires_on': _date(expiresOn),
      'p_method': method,
      if (clientUuid != null) 'p_client_uuid': clientUuid,
    });
  }

  /// The serial number of one physical unit — a phone, a radio, a panel.
  /// Deliberately not unique server-side: a mistyped duplicate must not stop
  /// a sale at the counter.
  Future<void> setSerial(String productId, String serial) async {
    final client = _requireClient();
    await client.rpc('set_product_serial', params: {
      'p_product_id': productId,
      'p_serial': serial,
    });
  }

  /// The photographs of a product — the delivery note it arrived on, the
  /// picture of the thing itself. `documents.product_id` has existed since
  /// 013; this is what reads it back the other way round.
  Future<List<Map<String, dynamic>>> photos(String productId) async {
    final client = _requireClient();
    final rows = await client.rpc('product_photos', params: {
      'p_product_id': productId,
    }) as List<dynamic>;
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  /// Name, shelf price, cost, expiry and reorder point. Everything a
  /// shopkeeper is allowed to change about a product after it exists. A
  /// rename cannot rewrite history: sale lines, production inputs and
  /// receipts all snapshot the name they saw.
  Future<void> updateProduct(
    String productId, {
    String? name,
    double? salePrice,
    double? costPrice,
    DateTime? expiresOn,
    double? lowStockAt,
    bool? isActive,
  }) async {
    final client = _requireClient();
    await client.from('products').update({
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (salePrice != null) 'sale_price': salePrice,
      if (costPrice != null) 'cost_price': costPrice,
      if (expiresOn != null) 'expires_on': _date(expiresOn),
      if (lowStockAt != null) 'low_stock_at': lowStockAt,
      if (isActive != null) 'is_active': isActive,
    }).eq('id', productId);
  }

  /// Takes a product off the shelves (or puts it back) without touching its
  /// history. Owner/admin only — the server makes that check, not this app.
  Future<void> archiveProduct(String productId, {bool archived = true}) async {
    final client = _requireClient();
    await client.rpc('archive_product', params: {
      'p_product_id': productId,
      'p_archived': archived,
    });
  }

  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError(
        "Cette version de l'application a été compilée sans serveur. "
        'Reconstruisez-la avec SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY.',
      );
    }
    return client;
  }
}
