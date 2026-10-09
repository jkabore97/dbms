import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';
import '../rates/currency_rates.dart';
import '../orders/orders.dart';
import '../db/local_db.dart';
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
  RetailRepository(this._client, {LocalDb? outbox, void Function()? onQueued})
      // ignore: prefer_initializing_formals
      : _outbox = outbox,
        // ignore: prefer_initializing_formals
        _onQueued = onQueued;

  final SupabaseClient? _client;

  /// Where a sale goes when the network does not answer (package 7). Null
  /// in tests and builds without a local database: the till then says
  /// "pas de connexion" as before.
  final LocalDb? _outbox;

  /// Nudges the sync loop after a sale is queued.
  final void Function()? _onQueued;

  bool get canQueueSales => _outbox != null;

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

  /// A refusal with its reason, which the customer reads (115's
  /// refuse_order). On a database before 115 the refusal still goes
  /// through decide_order, without the reason.
  Future<void> refuseOrder(String orderId, String reason) async {
    final client = _requireClient();
    try {
      await client.rpc('refuse_order',
          params: {'p_order_id': orderId, 'p_reason': reason.trim()});
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
      await decideOrder(orderId, 'refused');
    }
  }

  /// How long each open order has sat in its state, and which are stuck
  /// (073). Keyed by order id; empty on a database before 073.
  Future<Map<String, OrderClock>> orderClocks(String orgId) async {
    final client = _client;
    if (client == null) return const {};
    try {
      final rows = await client
          .rpc('shop_order_clocks', params: {'p_org_id': orgId}) as List<dynamic>;
      return {
        for (final r in rows)
          '${(r as Map)['order_id']}':
              OrderClock.fromRow(Map<String, dynamic>.from(r)),
      };
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return const {};
      rethrow;
    }
  }

  /// Calls [onChange] whenever one of the shop's orders is placed or moves
  /// (074, Supabase Realtime under the orders' own row security). Returns
  /// the way to stop listening; a no-op without a client.
  void Function() watchOrders(String orgId, void Function() onChange) {
    final client = _client;
    if (client == null) return () {};
    final channel = client
        .channel('orders-$orgId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'org_id',
            value: orgId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return () => client.removeChannel(channel);
  }

  /// "Je livre moi-même" (073): a delivery nobody took, carried by the shop.
  Future<void> deliverSelf(String orderId) async {
    await _requireClient()
        .rpc('shop_deliver_self', params: {'p_order_id': orderId});
  }

  /// Cash orders couriers delivered and have not handed over yet (073).
  Future<List<CashOwed>> cashOwed(String orgId) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client
          .rpc('shop_cash_owed', params: {'p_org_id': orgId}) as List<dynamic>;
      return rows
          .map((r) => CashOwed.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return const [];
      rethrow;
    }
  }

  /// The shop's word that a courier handed over an order's cash (073).
  Future<void> confirmCashReceived(String orderId) async {
    await _requireClient()
        .rpc('confirm_cash_received', params: {'p_order_id': orderId});
  }

  /// The shop's own couriers (073).
  Future<List<OrgCourier>> orgCouriers(String orgId) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client
          .rpc('org_courier_list', params: {'p_org_id': orgId}) as List<dynamic>;
      return rows
          .map((r) => OrgCourier.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return const [];
      rethrow;
    }
  }

  /// Names an approved courier, found by phone, as the shop's own; returns
  /// their name.
  Future<String> addOrgCourier(String orgId, String phone) async {
    final v = await _requireClient().rpc('add_org_courier', params: {
      'p_org_id': orgId,
      'p_phone': phone,
    });
    return '$v';
  }

  Future<void> removeOrgCourier(String orgId, String userId) async {
    await _requireClient().rpc('remove_org_courier', params: {
      'p_org_id': orgId,
      'p_user_id': userId,
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

  /// True once [products] found a database before 098, with no
  /// `is_service` column: « Mes services » then says so rather than
  /// saving a service that would land as an article.
  bool servicesMissing = false;

  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async {
    // is_published was missing from this list for a while: the edit sheet
    // then read every article as "not on the vitrine", showed the switch
    // off, and saving the sheet — any edit, a price — quietly unpublished
    // an article that was in the window. The row must carry everything the
    // sheet can write back.
    const columns = 'id, name, barcode, serial, cost_price, sale_price, '
        'quantity, expires_on, low_stock_at, is_ingredient, is_published';
    try {
      final rows = await _products(orgId,
          '$columns, description, unit, available_from, is_service, price_from',
          activeOnly: activeOnly);
      servicesMissing = false;
      return rows;
    } on PostgrestException catch (error) {
      // Before 098: no services yet, every row is goods.
      if (error.code != '42703') rethrow;
      servicesMissing = true;
    }
    try {
      return await _products(
          orgId, '$columns, description, unit, available_from',
          activeOnly: activeOnly);
    } on PostgrestException catch (error) {
      if (error.code == '42703') {
        // Before 083: no unit or date yet, the description is there.
        try {
          return await _products(orgId, '$columns, description',
              activeOnly: activeOnly);
        } on PostgrestException catch (e) {
          if (e.code != '42703') rethrow;
        }
      }
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

  /// Keeps a sale on the phone to be sent when the network returns, with
  /// the same parameters [recordSale] would have sent and the same client
  /// uuid, so a sale that did land is not sold twice.
  Future<void> queueSale({
    required String orgId,
    required List<SaleLineDraft> lines,
    required String clientUuid,
    String method = 'cash',
    String? note,
    String? customerName,
  }) async {
    final outbox = _outbox;
    if (outbox == null) {
      throw StateError('Pas de connexion. Réessayez quand le réseau revient.');
    }
    await outbox.queueSale(orgId: orgId, clientUuid: clientUuid, params: {
      'p_org_id': orgId,
      'p_lines': lines.map((l) => l.toJson()).toList(),
      'p_method': method,
      if (note != null && note.isNotEmpty) 'p_note': note,
      'p_client_uuid': clientUuid,
      if (customerName != null && customerName.isNotEmpty)
        'p_customer_name': customerName,
    });
    _onQueued?.call();
  }

  /// Sales on this phone waiting for the network, for [orgId].
  Future<int> pendingSales(String orgId) async =>
      await _outbox?.pendingSales(orgId) ?? 0;

  /// Sales this phone kept offline that the server then refused for good
  /// (101: the stock was not there), for the owner to read.
  Future<List<Map<String, Object?>>> refusedSales(String orgId) async =>
      await _outbox?.refusedActions(orgId) ?? const [];

  /// The owner has read it; nothing was recorded, so nothing else moves.
  Future<void> dismissRefused(String clientUuid) async =>
      _outbox?.dismissRefused(clientUuid);

  /// The stock is corrected: the refused sale is sent again as it was, with
  /// its own client_uuid, and the outbox is woken.
  Future<void> requeueRefused(String clientUuid) async {
    await _outbox?.requeueRefused(clientUuid);
    _onQueued?.call();
  }

  /// What the sales waiting on this phone will still take from the shelf
  /// (by product id, or `name:<name>` for a typed line).
  Future<Map<String, double>> pendingSaleQuantities(String orgId) async =>
      await _outbox?.pendingSaleQuantities(orgId) ?? const {};

  /// The shelf as the server holds it now, for [productIds]: the Wave till
  /// asks before it shows its QR, so a customer never pays for what the
  /// server will refuse.
  Future<Map<String, double>> freshStock(
      String orgId, List<String> productIds) async {
    if (productIds.isEmpty) return const {};
    final rows = await _requireClient()
        .from('products')
        .select('id, quantity')
        .eq('org_id', orgId)
        .inFilter('id', productIds);
    return {
      for (final r in rows as List)
        '${(r as Map)['id']}': (r['quantity'] as num?)?.toDouble() ?? 0,
    };
  }

  /// "Tout publier" (070): every active, priced, non-ingredient article on
  /// the vitrine at once. Returns how many were published. Refused unless
  /// the articles dial lets this person edit.
  Future<int> publishAll(String orgId) async {
    final v = await _requireClient()
        .rpc('publish_all_products', params: {'p_org_id': orgId});
    return (v as num?)?.toInt() ?? 0;
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
    bool isService = false,
  }) async {
    final client = _requireClient();
    final params = {
      'p_org_id': orgId,
      'p_name': name,
      'p_sale_price': ?salePrice,
      'p_cost_price': ?costPrice,
      if (barcode != null && barcode.isNotEmpty) 'p_barcode': barcode,
      if (expiresOn != null) 'p_expires_on': _date(expiresOn),
      if (currentUserId != null) 'p_actor': currentUserId,
    };
    // The kind being created (098): a service never revives or converts an
    // article of that name, an article never takes back a service — the
    // server refuses either in French.
    try {
      final id = await client.rpc('ensure_product',
          params: {...params, 'p_is_service': isService});
      return id as String;
    } on PostgrestException catch (error) {
      // Before 098 there is no p_is_service, and no service either: an
      // article is created the way it always was. A service is not.
      if (isService || !isSchemaOutOfDate(error)) rethrow;
    }
    final id = await client.rpc('ensure_product', params: params);
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

  /// Every article's picture for a shop, product id → photo key (079): its
  /// most recent photograph, PDFs left out. One call for the whole Articles
  /// page instead of one per row. Empty on a database before 079, or with
  /// no signal — the page then shows initials, as for an article with none.
  Future<Map<String, String>> photoKeys(String orgId) async {
    final client = _client;
    if (client == null) return const {};
    try {
      final rows = await client.rpc('product_photo_keys', params: {
        'p_org_id': orgId,
      }) as List<dynamic>;
      return _photoKeysHeard[orgId] = {
        for (final r in rows)
          if (r is Map && r['product_id'] != null && r['photo_key'] != null)
            '${r['product_id']}': '${r['photo_key']}',
      };
    } catch (_) {
      // No signal (122): the keys last heard while the app is open, so the
      // till and the list still find the pictures the phone holds.
      return _photoKeysHeard[orgId] ?? const {};
    }
  }

  /// [photoKeys]' last answer per business, for every repository of the app.
  static final _photoKeysHeard = <String, Map<String, String>>{};

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
    String? unit,
    DateTime? availableFrom,
    bool clearAvailableFrom = false,
    double? quantity,
    bool? isService,
    bool? priceFrom,
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
          // 083's farm fields: sent only when given, so a shop's edit on a
          // database before 083 still saves.
          if (unit != null) 'unit': unit.trim().isEmpty ? null : unit.trim(),
          if (availableFrom != null) 'available_from': _date(availableFrom),
          if (clearAvailableFrom) 'available_from': null,
          // A farm counts what it has to sell by hand: it grew it, it did
          // not buy it, so no purchase is booked (receive() would).
          'quantity': ?quantity,
          // 098's service fields: sent only by the services sheet, so an
          // article's edit on a database before 098 still saves.
          'is_service': ?isService,
          'price_from': ?priceFrom,
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
