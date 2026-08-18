import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

/// Invoicing, for any business.
///
/// This used to live inside `FarmRepository`, which is where 009 put it
/// because the first person to need an invoice was Ignace selling trays to a
/// hotel. Nothing about it was ever farm-specific: `create_invoice()` checks
/// `can_write_org()` and no profile, and a shop billing a wholesaler or a
/// church billing a hall hire is the same three rows.
///
/// **Server-only, deliberately.** Everything else in this app writes to the
/// device first and syncs later, and invoicing does not. Three reasons, all of
/// them about the number: it has to be unique within the business, it has to
/// be consecutive to be worth anything to an auditor, and two devices offline
/// cannot agree on the next one. An invoice also creates a debt somebody else
/// is expected to honour, which is not a thing a disconnected phone should
/// decide by itself.
///
/// So the sheet needs signal, and says so. That is a real limitation and it is
/// the right one: an offline invoice numbered optimistically is an invoice
/// that gets renumbered later, and a renumbered invoice is the exact thing the
/// numbering exists to prevent.
class InvoicingRepository {
  InvoicingRepository(this._client);

  final SupabaseClient? _client;
  static const _uuid = Uuid();

  bool get isConfigured => _client != null;

  /// Everything issued, newest first — not only what is unpaid. You cannot
  /// re-send a document the collections list has already dropped.
  Future<List<InvoiceSummary>> list(
    String orgId, {
    bool includePaid = true,
    int limit = 200,
  }) async {
    final client = _require();
    final rows = await client.rpc('list_invoices', params: {
      'p_org_id': orgId,
      'p_include_paid': includePaid,
      'p_limit': limit,
    }) as List<dynamic>;
    return rows
        .map((r) => InvoiceSummary.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// The document itself: header, both addresses, lines, totals.
  ///
  /// Two round trips rather than one nested call, because `invoice_header()`
  /// and `invoice_lines_of()` are SECURITY INVOKER — RLS decides what comes
  /// back, and a function that joined them would still be two policy checks.
  Future<InvoiceDocument> document(String invoiceId) async {
    final client = _require();
    final headers = await client.rpc('invoice_header', params: {
      'p_invoice_id': invoiceId,
    }) as List<dynamic>;

    if (headers.isEmpty) {
      // Empty means RLS refused it or it does not exist, and the client
      // cannot tell those apart — which is the point of RLS.
      throw StateError("Cette facture est introuvable.");
    }

    final lineRows = await client.rpc('invoice_lines_of', params: {
      'p_invoice_id': invoiceId,
    }) as List<dynamic>;

    return InvoiceDocument.fromRows(
      Map<String, dynamic>.from(headers.first as Map),
      lineRows
          .map((r) => InvoiceLine.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList(),
    );
  }

  /// Raises one. Idempotent by [clientUuid], which is generated here rather
  /// than by the caller so a double tap on a slow connection cannot produce
  /// two invoices for the same sale.
  Future<String> create({
    required String orgId,
    required String customerName,
    required List<InvoiceLine> lines,
    String? customerPhone,
    String? customerAddress,
    String? category,
    int? dueDays,
    DateTime? dueOn,
    DateTime? issuedOn,
    String? memo,
    String? clientUuid,
  }) async {
    final client = _require();
    final id = await client.rpc('create_invoice', params: {
      'p_org_id': orgId,
      'p_customer_name': customerName.trim(),
      'p_lines': lines.map((l) => l.toJson()).toList(),
      if (category != null && category.isNotEmpty) 'p_category': category,
      if (customerPhone != null && customerPhone.isNotEmpty)
        'p_customer_phone': customerPhone,
      if (customerAddress != null && customerAddress.isNotEmpty)
        'p_customer_address': customerAddress,
      if (dueOn != null) 'p_due_on': _day(dueOn),
      if (dueDays != null && dueDays > 0) 'p_due_days': dueDays,
      if (issuedOn != null) 'p_issued_on': _day(issuedOn),
      if (memo != null && memo.isNotEmpty) 'p_memo': memo,
      'p_client_uuid': clientUuid ?? _uuid.v4(),
    });
    return id as String;
  }

  /// Corrects an invoice (040): the server withdraws the old document
  /// (contre-passing its entry) and issues a replacement that names it, in one
  /// transaction. Admin-only server-side; refuses an invoice money has
  /// already arrived against.
  Future<String> revise({
    required String invoiceId,
    required String customerName,
    required List<InvoiceLine> lines,
    String? customerPhone,
    String? customerAddress,
    int? dueDays,
    DateTime? dueOn,
    DateTime? issuedOn,
    String? memo,
  }) async {
    final client = _require();
    final id = await client.rpc('revise_invoice', params: {
      'p_invoice_id': invoiceId,
      'p_customer_name': customerName.trim(),
      'p_lines': lines.map((l) => l.toJson()).toList(),
      if (customerPhone != null && customerPhone.isNotEmpty)
        'p_customer_phone': customerPhone,
      if (customerAddress != null && customerAddress.isNotEmpty)
        'p_customer_address': customerAddress,
      if (dueOn != null) 'p_due_on': _day(dueOn),
      if (dueDays != null && dueDays > 0) 'p_due_days': dueDays,
      if (issuedOn != null) 'p_issued_on': _day(issuedOn),
      if (memo != null && memo.isNotEmpty) 'p_memo': memo,
    });
    return id as String;
  }

  /// Money against an invoice. Settling is its own act — an invoice is not
  /// paid because somebody ticked it, it is paid because cash arrived.
  Future<void> recordPayment({
    required String invoiceId,
    required double amount,
    String method = 'cash',
    DateTime? paidOn,
    String? clientUuid,
  }) async {
    final client = _require();
    await client.rpc('record_invoice_payment', params: {
      'p_invoice_id': invoiceId,
      'p_amount': amount,
      'p_method': method,
      if (paidOn != null) 'p_paid_on': _day(paidOn),
      'p_client_uuid': clientUuid ?? _uuid.v4(),
    });
  }

  /// Withdraws one. The journal entry is reversed, not deleted — what
  /// happened, happened — and a part-paid invoice is refused by the server.
  Future<void> cancel(String invoiceId, {String? reason}) async {
    final client = _require();
    await client.rpc('cancel_invoice', params: {
      'p_invoice_id': invoiceId,
      if (reason != null && reason.isNotEmpty) 'p_reason': reason,
    });
  }

  /// What goes at the top of every invoice this business issues.
  Future<BillingDetails> billingDetails(String orgId) async {
    final client = _require();
    final row = await client
        .from('orgs')
        .select('address, phone, email, tax_id, tax_label, invoice_footer')
        .eq('id', orgId)
        .maybeSingle();
    if (row == null) return const BillingDetails();
    return BillingDetails.fromRow(Map<String, dynamic>.from(row));
  }

  /// Admin only, and enforced by the server rather than by hiding the button:
  /// what is on the header is what the business claims about itself to a
  /// customer and to a tax office.
  Future<void> saveBillingDetails({
    required String orgId,
    String? address,
    String? phone,
    String? email,
    String? taxId,
    String? taxLabel,
    String? footer,
  }) async {
    final client = _require();
    await client.rpc('set_org_billing', params: {
      'p_org_id': orgId,
      // Sent even when empty: an empty string is how somebody clears a line
      // they typed by mistake, and omitting it would make that impossible.
      'p_address': address ?? '',
      'p_phone': phone ?? '',
      'p_email': email ?? '',
      'p_tax_id': taxId ?? '',
      'p_tax_label': taxLabel ?? '',
      'p_invoice_footer': footer ?? '',
    });
  }

  static String _day(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';

  SupabaseClient _require() {
    final client = _client;
    if (client == null) {
      throw StateError(
        "Cette version de l'application a été compilée sans serveur.",
      );
    }
    return client;
  }
}
