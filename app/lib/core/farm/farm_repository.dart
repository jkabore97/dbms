import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// The farm's reads, and the writes that cannot be made offline.
///
/// The split matters and is not the same one the church module makes.
///
/// RECORDING is offline-first and does not live here. Feed arriving, feed
/// eaten, birds dying, eggs collected — all four go through `LocalDb`, land in
/// the outbox, and reach the server whenever the server becomes reachable.
/// That is the whole premise of the farm module: Ignace is the user with no
/// signal, and a recording screen that needs the network is a recording screen
/// he will stop using in favour of a notebook.
///
/// READING is not, with one exception. How much feed is left and how many
/// birds are alive are computed from every movement ever made, most of which
/// happened on other people's devices; the phone can only ever know its own
/// share. So the counts come from the server, and the screens say when they
/// could not.
///
/// The exception is that the caller writes what it reads to the device — see
/// `LocalDb.cacheFarmItems` and `cacheFlocks`. Not so the counts can be shown
/// offline as if they were current, but so the recording sheets can offer real
/// item names and real batch codes, which is a different and much weaker
/// claim.
///
/// INVOICING is server-only and deliberately so. An invoice number has to be
/// unique within the business and an invoice creates a debt; neither is
/// something a disconnected device can decide on its own.
class FarmRepository {
  FarmRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  // ----------------------------------------------------------------
  // What the farm has
  // ----------------------------------------------------------------

  Future<List<StockItem>> stockOnHand(String orgId) async {
    final client = _requireClient();
    final rows = await client.rpc(
      'stock_on_hand',
      params: {'p_org_id': orgId},
    ) as List<dynamic>;

    return rows
        .map((r) => StockItem.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<Flock>> flocks(String orgId, {bool includeClosed = false}) async {
    final client = _requireClient();
    final rows = await client.rpc('flock_status', params: {
      'p_org_id': orgId,
      'p_include_closed': includeClosed,
    }) as List<dynamic>;

    return rows
        .map((r) => Flock.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<FarmDay> day(String orgId, {DateTime? on}) async {
    final client = _requireClient();
    final rows = await client.rpc('farm_daily_summary', params: {
      'p_org_id': orgId,
      if (on != null) 'p_day': _date(on),
    }) as List<dynamic>;

    if (rows.isEmpty) return FarmDay.empty;
    return FarmDay.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<List<OutstandingInvoice>> outstandingInvoices(String orgId) async {
    final client = _requireClient();
    final rows = await client.rpc(
      'outstanding_invoices',
      params: {'p_org_id': orgId},
    ) as List<dynamic>;

    return rows
        .map((r) =>
            OutstandingInvoice.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // ----------------------------------------------------------------
  // Writes that need the server
  // ----------------------------------------------------------------

  /// A batch of birds arriving.
  ///
  /// Server-only, unlike everything else Ignace records, because the batch
  /// code has to be unique within the business: two devices inventing
  /// "B-2026-01" offline would produce one flock with two histories, and no
  /// report could add them back together.
  Future<String> openFlock({
    required String orgId,
    required String batchCode,
    required int birdCount,
    String? breed,
    String? entityId,
    DateTime? arrivedOn,
  }) async {
    final client = _requireClient();
    final id = await client.rpc('open_flock', params: {
      'p_org_id': orgId,
      'p_batch_code': batchCode.trim(),
      'p_bird_count': birdCount,
      if (breed != null && breed.trim().isNotEmpty) 'p_breed': breed.trim(),
      if (entityId != null) 'p_entity_id': entityId,
      if (arrivedOn != null) 'p_arrived_on': _date(arrivedOn),
    });
    return id as String;
  }

  /// Closes a batch: sold off, or cleared out. Nothing is deleted — a closed
  /// flock keeps all of its history and stops appearing on the home screen.
  Future<void> closeFlock(String flockId, {DateTime? on}) async {
    final client = _requireClient();
    await client
        .from('flocks')
        .update({'closed_on': _date(on ?? DateTime.now())}).eq('id', flockId);
  }

  /// The reorder threshold, which is the number that makes counting sacks
  /// worth doing. An ordinary write under RLS — the person who notices the
  /// feed runs out early is the person feeding the birds, not an admin.
  Future<void> setReorderLevel(String itemId, double? level) async {
    final client = _requireClient();
    await client.from('items').update({'reorder_level': level}).eq('id', itemId);
  }

  Future<void> renameItem(String itemId, String name, {String? unit}) async {
    final client = _requireClient();
    await client.from('items').update({
      'name': name.trim(),
      if (unit != null && unit.trim().isNotEmpty) 'unit': unit.trim(),
    }).eq('id', itemId);
  }

  /// Delivered now, paid later. The income is real the day it is invoiced;
  /// what is missing is the cash, and that gap is the receivable.
  Future<String> createInvoice({
    required String orgId,
    required String customerName,
    required List<InvoiceLineDraft> lines,
    String? customerPhone,
    String category = "Ventes d'œufs",
    DateTime? dueOn,
    String? memo,
  }) async {
    final client = _requireClient();
    final id = await client.rpc('create_invoice', params: {
      'p_org_id': orgId,
      'p_customer_name': customerName.trim(),
      'p_lines': lines.map((l) => l.toJson()).toList(),
      'p_category': category,
      if (customerPhone != null && customerPhone.trim().isNotEmpty)
        'p_customer_phone': customerPhone.trim(),
      if (dueOn != null) 'p_due_on': _date(dueOn),
      if (memo != null && memo.trim().isNotEmpty) 'p_memo': memo.trim(),
    });
    return id as String;
  }

  /// The hotel settles up, in full or in part. Moves cash and clears the
  /// receivable; recognises no new income, because that happened when the
  /// invoice was raised.
  Future<void> recordInvoicePayment({
    required String invoiceId,
    required double amount,
    String method = 'cash',
    DateTime? paidOn,
  }) async {
    final client = _requireClient();
    await client.rpc('record_invoice_payment', params: {
      'p_invoice_id': invoiceId,
      'p_amount': amount,
      'p_method': method,
      if (paidOn != null) 'p_paid_on': _date(paidOn),
    });
  }

  /// Seeds the farm's chart of accounts. Called once, from the settings
  /// screen, for a business created before this module existed — a farm set up
  /// after it will have been seeded server-side.
  Future<void> seedAccounts(String orgId) async {
    final client = _requireClient();
    await client.rpc('seed_farm_accounts', params: {'p_org_id': orgId});
  }

  static String _date(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';

  // ----------------------------------------------------------------
  // Animals that are not birds, and things that grow (019)
  // ----------------------------------------------------------------

  /// What kind of farm this is, counted. Read before anything else so the
  /// home screen leads with what this farm actually does rather than showing
  /// a goat farmer an empty poultry panel.
  Future<FarmShape> shape(String orgId) async {
    final client = _requireClient();
    final rows = await client.rpc('farm_profile_summary', params: {
      'p_org_id': orgId,
    }) as List<dynamic>;
    if (rows.isEmpty) return const FarmShape();
    return FarmShape.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<List<Herd>> herds(String orgId, {bool includeClosed = false}) async {
    final client = _requireClient();
    final rows = await client.rpc('herd_status', params: {
      'p_org_id': orgId,
      'p_include_closed': includeClosed,
    }) as List<dynamic>;
    return rows
        .map((r) => Herd.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<String> openHerd({
    required String orgId,
    required String species,
    required String label,
    required int headCount,
    String? breed,
    String? purpose,
  }) async {
    final client = _requireClient();
    final id = await client.rpc('open_herd', params: {
      'p_org_id': orgId,
      'p_species': species,
      'p_label': label,
      'p_head_count': headCount,
      if (breed != null && breed.isNotEmpty) 'p_breed': breed,
      if (purpose != null && purpose.isNotEmpty) 'p_purpose': purpose,
    });
    return id as String;
  }

  /// A death, a birth, a weighing, a vaccination. Idempotent by
  /// [clientUuid]: a phone at the far end of a field retries.
  Future<String> recordHerdEvent({
    required String orgId,
    required String herdId,
    required String kind,
    double quantity = 0,
    DateTime? occurredOn,
    String? note,
    String? clientUuid,
  }) async {
    final client = _requireClient();
    final id = await client.rpc('record_herd_event', params: {
      'p_org_id': orgId,
      'p_herd_id': herdId,
      'p_kind': kind,
      'p_quantity': quantity,
      if (occurredOn != null) 'p_occurred_on': _date(occurredOn),
      if (note != null && note.isNotEmpty) 'p_note': note,
      if (clientUuid != null) 'p_client_uuid': clientUuid,
    });
    return id as String;
  }

  Future<List<CropCycle>> cropCycles(String orgId,
      {bool includeClosed = false}) async {
    final client = _requireClient();
    final rows = await client.rpc('crop_status', params: {
      'p_org_id': orgId,
      'p_include_closed': includeClosed,
    }) as List<dynamic>;
    return rows
        .map((r) => CropCycle.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// The plot is found or created from its name, so nobody has to define a
  /// field before recording on it — the same bargain `ensure_account()`
  /// makes with an account name.
  Future<String> openCropCycle({
    required String orgId,
    required String crop,
    String? plotName,
    String? variety,
    DateTime? plantedOn,
    DateTime? expectedOn,
    double? expectedYield,
    String unit = 'kg',
  }) async {
    final client = _requireClient();
    final id = await client.rpc('open_crop_cycle', params: {
      'p_org_id': orgId,
      'p_crop': crop,
      if (plotName != null && plotName.isNotEmpty) 'p_plot_name': plotName,
      if (variety != null && variety.isNotEmpty) 'p_variety': variety,
      if (plantedOn != null) 'p_planted_on': _date(plantedOn),
      if (expectedOn != null) 'p_expected_on': _date(expectedOn),
      if (expectedYield != null) 'p_expected_yield': expectedYield,
      'p_unit': unit,
    });
    return id as String;
  }

  /// What came off the field. Posts nothing to the ledger on purpose:
  /// harvesting is not earning money, it is earning it later — or eating it.
  /// Selling goes through `record_farm_sale()` as it always did.
  Future<String> recordHarvest({
    required String orgId,
    required String cropCycleId,
    required double quantity,
    String? unit,
    String grade = 'first',
    DateTime? harvestedOn,
    String? note,
    String? clientUuid,
  }) async {
    final client = _requireClient();
    final id = await client.rpc('record_harvest', params: {
      'p_org_id': orgId,
      'p_crop_cycle_id': cropCycleId,
      'p_quantity': quantity,
      if (unit != null && unit.isNotEmpty) 'p_unit': unit,
      'p_grade': grade,
      if (harvestedOn != null) 'p_harvested_on': _date(harvestedOn),
      if (note != null && note.isNotEmpty) 'p_note': note,
      if (clientUuid != null) 'p_client_uuid': clientUuid,
    });
    return id as String;
  }

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
