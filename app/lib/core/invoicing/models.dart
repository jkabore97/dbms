/// Postgres `numeric` arrives over PostgREST as a JSON string, not a number,
/// because a double cannot hold every value a numeric(14,2) can.
double _num(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse('$value');

/// One line of an invoice being composed, before it exists.
class InvoiceLine {
  const InvoiceLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  final String description;
  final double quantity;
  final double unitPrice;

  double get amount => quantity * unitPrice;

  bool get isComplete =>
      description.trim().isNotEmpty && quantity > 0 && unitPrice > 0;

  InvoiceLine copyWith({
    String? description,
    double? quantity,
    double? unitPrice,
  }) =>
      InvoiceLine(
        description: description ?? this.description,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
      );

  Map<String, Object?> toJson() => {
        'description': description.trim(),
        'quantity': quantity,
        'unit_price': unitPrice,
      };

  factory InvoiceLine.fromRow(Map<String, dynamic> row) => InvoiceLine(
        description: (row['description'] as String?) ?? '',
        quantity: _num(row['quantity']),
        unitPrice: _num(row['unit_price']),
      );
}

/// A row in the list of what has been issued.
class InvoiceSummary {
  const InvoiceSummary({
    required this.id,
    required this.number,
    required this.customerName,
    required this.issuedOn,
    required this.total,
    required this.paid,
    required this.outstanding,
    required this.cancelled,
    required this.daysOverdue,
    this.dueOn,
  });

  final String id;
  final String number;
  final String customerName;
  final DateTime issuedOn;
  final DateTime? dueOn;
  final double total;

  /// The sum of the payments received, which is a number and not a boolean: a
  /// hotel that pays a third now and the rest next month is the normal case.
  final double paid;

  final double outstanding;
  final bool cancelled;
  final int daysOverdue;

  bool get isPaid => !cancelled && outstanding <= 0;
  bool get isPartlyPaid => paid > 0 && outstanding > 0;
  bool get isOverdue => daysOverdue > 0;

  factory InvoiceSummary.fromRow(Map<String, dynamic> row) => InvoiceSummary(
        id: row['invoice_id'] as String,
        number: (row['number'] as String?) ?? '',
        customerName: (row['customer_name'] as String?) ?? '',
        issuedOn: _date(row['issued_on']) ?? DateTime.now(),
        dueOn: _date(row['due_on']),
        total: _num(row['total']),
        paid: _num(row['paid']),
        outstanding: _num(row['outstanding']),
        cancelled: row['cancelled'] == true,
        daysOverdue: (row['days_overdue'] as num?)?.toInt() ?? 0,
      );
}

/// Everything printed on the document itself.
///
/// Both halves of the header are here — who is billing and who is billed —
/// because an invoice that names only one of them is a note, not an invoice,
/// and the customer's own accountant cannot file it.
class InvoiceDocument {
  const InvoiceDocument({
    required this.id,
    required this.number,
    required this.issuedOn,
    required this.total,
    required this.paid,
    required this.outstanding,
    required this.customerName,
    required this.orgName,
    required this.currency,
    required this.lines,
    this.dueOn,
    this.cancelledAt,
    this.customerPhone,
    this.customerAddress,
    this.orgAddress,
    this.orgPhone,
    this.orgEmail,
    this.orgTaxId,
    this.orgTaxLabel,
    this.footer,
  });

  final String id;
  final String number;
  final DateTime issuedOn;
  final DateTime? dueOn;
  final DateTime? cancelledAt;
  final double total;
  final double paid;
  final double outstanding;

  final String customerName;
  final String? customerPhone;
  final String? customerAddress;

  final String orgName;
  final String? orgAddress;
  final String? orgPhone;
  final String? orgEmail;

  /// The tax number and what it is called where the business is registered:
  /// IFU in Burkina Faso, NIF elsewhere in the region.
  final String? orgTaxId;
  final String? orgTaxLabel;

  final String currency;
  final String? footer;
  final List<InvoiceLine> lines;

  bool get isCancelled => cancelledAt != null;
  bool get isPaid => !isCancelled && outstanding <= 0;

  /// What the header says the tax number is, ready to print. Null when the
  /// business has not given one, in which case the line is omitted rather
  /// than printed empty.
  String? get taxLine {
    final id = orgTaxId?.trim();
    if (id == null || id.isEmpty) return null;
    final label = orgTaxLabel?.trim();
    return '${label == null || label.isEmpty ? 'N° fiscal' : label} : $id';
  }

  factory InvoiceDocument.fromRows(
    Map<String, dynamic> header,
    List<InvoiceLine> lines,
  ) =>
      InvoiceDocument(
        id: header['invoice_id'] as String,
        number: (header['number'] as String?) ?? '',
        issuedOn: _date(header['issued_on']) ?? DateTime.now(),
        dueOn: _date(header['due_on']),
        cancelledAt: _date(header['cancelled_at']),
        total: _num(header['total']),
        paid: _num(header['paid']),
        outstanding: _num(header['outstanding']),
        customerName: (header['customer_name'] as String?) ?? '',
        customerPhone: header['customer_phone'] as String?,
        customerAddress: header['customer_address'] as String?,
        orgName: (header['org_name'] as String?) ?? '',
        orgAddress: header['org_address'] as String?,
        orgPhone: header['org_phone'] as String?,
        orgEmail: header['org_email'] as String?,
        orgTaxId: header['org_tax_id'] as String?,
        orgTaxLabel: header['org_tax_label'] as String?,
        currency: (header['org_currency'] as String?) ?? 'XOF',
        footer: header['invoice_footer'] as String?,
        lines: lines,
      );
}

/// The billing header a business puts on its own invoices.
class BillingDetails {
  const BillingDetails({
    this.address,
    this.phone,
    this.email,
    this.taxId,
    this.taxLabel,
    this.footer,
  });

  final String? address;
  final String? phone;
  final String? email;
  final String? taxId;
  final String? taxLabel;
  final String? footer;

  /// True when there is nothing on the header at all. Worth saying on screen:
  /// an invoice from a business with no address and no tax number is one a
  /// customer's accountant will hand straight back.
  bool get isEmpty =>
      (address ?? '').trim().isEmpty &&
      (phone ?? '').trim().isEmpty &&
      (taxId ?? '').trim().isEmpty;

  factory BillingDetails.fromRow(Map<String, dynamic> row) => BillingDetails(
        address: row['address'] as String?,
        phone: row['phone'] as String?,
        email: row['email'] as String?,
        taxId: row['tax_id'] as String?,
        taxLabel: row['tax_label'] as String?,
        footer: row['invoice_footer'] as String?,
      );
}
