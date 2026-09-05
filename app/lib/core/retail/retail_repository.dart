import 'package:supabase_flutter/supabase_flutter.dart';

import '../rates/currency_rates.dart';
import '../orders/orders.dart';
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
  // Orders sent from the vitrine (055). Reading needs membership,
  // answering needs write access — both said by the server.
  // ----------------------------------------------------------------

  /// The shop's orders, open first, newest first.
  Future<List<ShopOrder>> shopOrders(String orgId) async {
    final rows = await _requireClient()
        .rpc('shop_orders', params: {'p_org_id': orgId}) as List<dynamic>;
    return rows
        .map((r) => ShopOrder.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// How many are still waiting for an answer — the badge on the till.
  Future<int> pendingOrders(String orgId) async {
    final n = await _requireClient()
        .rpc('shop_pending_orders', params: {'p_org_id': orgId});
    return (n as num?)?.toInt() ?? 0;
  }

  /// Moves an order along: accepted, refused, ready, picked_up, delivered,
  /// cancelled. The server refuses any move not drawn in 055.
  Future<void> decideOrder(String orderId, String status) async {
    await _requireClient().rpc('decide_order', params: {
      'p_order_id': orderId,
      'p_status': status,
    });
  }

  /// The shop's word that the money arrived (057) — or that a tap was a
  /// mistake. Only the shop's writers may say either.
  Future<void> setOrderPaid(String orderId, bool paid) async {
    await _requireClient().rpc('set_order_paid', params: {
      'p_order_id': orderId,
      'p_paid': paid,
    });
  }

  // ----------------------------------------------------------------
  // What is on the shelves
  // ----------------------------------------------------------------

  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async {
    // is_published was missing from this list for a while: the edit sheet
    // then read every article as "not on the vitrine", showed the switch
    // off, and saving the sheet — any edit, a price — quietly unpublished
    // an article that was in the window. The row must carry everything the
    // sheet can write back.
    const columns = 'id, name, barcode, serial, cost_price, sale_price, '
        'quantity, expires_on, low_stock_at, is_ingredient, is_published';
    try {
      return await _products(orgId, '$columns, description',
          activeOnly: activeOnly);
    } on PostgrestException catch (error) {
      // The app deploys before the owner pastes the bundle; between the two
      // the column of 064 is not there yet. A shelf with no descriptions
      // beats no shelf at all.
      if (error.code != '42703') rethrow;
      return _products(orgId, columns, activeOnly: activeOnly);
    }
  }

  Future<List<Product>> _products(String orgId, String columns,
      {required bool activeOnly}) async {
    final client = _requireClient();
    var query = client.from('products').select(columns).eq('org_id', orgId);
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
  /// [customerName] turns the sale into a credit sale when [method] is
  /// 'credit': same lines, same stock movement, same day totals — the money
  /// lands in créances and the carnet gains a debt naming what was taken.
  Future<String> recordSale({
    required String orgId,
    required List<SaleLineDraft> lines,
    String method = 'cash',
    String? note,
    String? clientUuid,
    String? deviceId,
    String? customerName,
    String? customerPhone,
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
      'p_client_uuid': ?clientUuid,
      'p_device_id': ?deviceId,
      if (customerName != null && customerName.isNotEmpty)
        'p_customer_name': customerName,
      if (customerPhone != null && customerPhone.isNotEmpty)
        'p_customer_phone': customerPhone,
    });
    return id as String;
  }

  // ----------------------------------------------------------------
  // Corrections (042). Undoing a transaction the honest way: a reversal that
  // cancels it in both the stock count and the ledger, so accounting and
  // analysis correct themselves. Reads for the corrections screen, and the
  // one write it needs that did not exist before (a delivery's reversal).
  // ----------------------------------------------------------------

  /// Recent sales, newest first — for the corrections screen. Each carries
  /// whether it has already been returned.
  Future<List<SaleSummary>> recentSales(String orgId, {int limit = 50}) async {
    final client = _requireClient();
    final rows = await client.rpc('recent_sales', params: {
      'p_org_id': orgId,
      'p_limit': limit,
    }) as List<dynamic>;
    return rows
        .map((r) => SaleSummary.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Recent deliveries (purchases/stock entries), newest first — for the
  /// corrections screen. Each carries whether it has already been reversed.
  Future<List<Delivery>> recentDeliveries(String orgId, {int limit = 50}) async {
    final client = _requireClient();
    final rows = await client.rpc('recent_deliveries', params: {
      'p_org_id': orgId,
      'p_limit': limit,
    }) as List<dynamic>;
    return rows
        .map((r) => Delivery.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Reverses a delivery: the goods leave the count they were added to, and the
  /// purchase is reversed in the books. Owner/admin only, enforced server-side.
  Future<void> reverseReceipt(String receiptId, {String? reason}) async {
    final client = _requireClient();
    await client.rpc('reverse_receipt', params: {
      'p_receipt_id': receiptId,
      if (reason != null && reason.trim().isNotEmpty) 'p_reason': reason.trim(),
    });
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
  // Wave mobile payment (037). Prep: the QR handle and the receipt facts.
  // ----------------------------------------------------------------

  /// The business's Wave handle — what its payment QR encodes — or null when
  /// the owner has not set one, in which case the sale sheet never offers Wave.
  Future<String?> waveMerchant(String orgId) async {
    final client = _requireClient();
    final row = await client
        .from('orgs')
        .select('wave_merchant')
        .eq('id', orgId)
        .maybeSingle();
    final value = row?['wave_merchant'] as String?;
    return (value != null && value.trim().isNotEmpty) ? value : null;
  }

  /// Sets (or clears, with null) the business's Wave handle. Admin-only,
  /// enforced by set_org_wave() server-side.
  Future<void> setWaveMerchant(String orgId, String? merchant) async {
    final client = _requireClient();
    await client.rpc('set_org_wave', params: {
      'p_org_id': orgId,
      'p_merchant': merchant,
    });
  }

  /// Stamps the Wave sender's name (and reference) onto a recorded sale and
  /// marks the payment confirmed — the step the webhook will one day take.
  Future<void> confirmWavePayment({
    required String saleId,
    required String sender,
    String? reference,
  }) async {
    final client = _requireClient();
    await client.rpc('attach_wave_payment', params: {
      'p_sale_id': saleId,
      'p_sender': sender,
      if (reference != null && reference.isNotEmpty) 'p_ref': reference,
      'p_status': 'confirmed',
    });
  }

  // ----------------------------------------------------------------
  // Multi-currency (039). The owner's rates, read at the till; the tender
  // stamped after a foreign-currency sale.
  // ----------------------------------------------------------------

  /// The business's exchange rates. Empty when the owner has set none — the
  /// sale sheet then shows no currency chips at all.
  Future<List<CurrencyRate>> currencyRates(String orgId) async {
    final client = _requireClient();
    final rows = await client
        .from('org_currency_rates')
        .select('currency, rate')
        .eq('org_id', orgId)
        .order('currency');
    return (rows as List)
        .map((r) => CurrencyRate.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Describes how a recorded sale was physically paid when the cash was a
  /// foreign currency. Receipt facts only — the ledger already holds the sale
  /// in the home currency and cannot be steered by this.
  Future<void> attachSaleTender({
    required String saleId,
    required String currency,
    required double amount,
    required double rate,
  }) async {
    final client = _requireClient();
    await client.rpc('attach_sale_tender', params: {
      'p_sale_id': saleId,
      'p_currency': currency,
      'p_amount': amount,
      'p_rate': rate,
    });
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
      'p_sale_price': ?salePrice,
      'p_cost_price': ?costPrice,
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
      'p_unit_cost': ?unitCost,
      if (expiresOn != null) 'p_expires_on': _date(expiresOn),
      'p_method': method,
      'p_client_uuid': ?clientUuid,
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
    bool? isIngredient,
    bool? isPublished,
    String? description,
  }) async {
    final client = _requireClient();
    // `.select()` turns a silent no-op into a fact we can check. A PostgREST
    // update that matches no row — because RLS refused it, or the id is not in
    // this org — returns success with an empty list, and that is exactly how
    // "editing an article did nothing, with no error" reached the shop floor
    // once. If nothing came back, the edit did not land: say so, loudly,
    // rather than popping the sheet as if it had.
    final rows = await client
        .from('products')
        .update({
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
          'sale_price': ?salePrice,
          'cost_price': ?costPrice,
          if (expiresOn != null) 'expires_on': _date(expiresOn),
          'low_stock_at': ?lowStockAt,
          'is_active': ?isActive,
          'is_ingredient': ?isIngredient,
          'is_published': ?isPublished,
          // An emptied field clears the description rather than keeping the
          // old words on the vitrine: null, not the empty string.
          if (description != null)
            'description':
                description.trim().isEmpty ? null : description.trim(),
        })
        .eq('id', productId)
        .select('id');
    if ((rows as List).isEmpty) {
      throw StateError(
        "La modification n'a pas été enregistrée. Vérifiez que vous avez le "
        'droit de modifier les articles de cette boutique.',
      );
    }
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
