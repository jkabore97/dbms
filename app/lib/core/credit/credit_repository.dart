import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// One customer's line in the carnet: what they owe in total and how old the
/// oldest unpaid debt is — the number that decides who gets visited first.
class DebtorRow {
  const DebtorRow({
    required this.customerId,
    required this.name,
    required this.totalOwed,
    this.phone,
    this.oldestDebt,
    this.openDebts = 0,
  });

  final String customerId;
  final String name;
  final String? phone;
  final double totalOwed;
  final DateTime? oldestDebt;
  final int openDebts;

  int? get daysOld =>
      oldestDebt == null ? null : DateTime.now().difference(oldestDebt!).inDays;

  factory DebtorRow.fromRow(Map<String, dynamic> r) => DebtorRow(
        customerId: r['customer_id'] as String,
        name: r['customer_name'] as String,
        phone: r['phone'] as String?,
        totalOwed: (r['total_owed'] as num).toDouble(),
        oldestDebt: r['oldest_debt'] == null
            ? null
            : DateTime.parse(r['oldest_debt'] as String),
        openDebts: (r['open_debts'] as num?)?.toInt() ?? 0,
      );
}

/// One debt of one customer, with what has been repaid against it.
class DebtRow {
  const DebtRow({
    required this.debtId,
    required this.label,
    required this.amount,
    required this.paid,
    required this.remaining,
    required this.occurredAt,
  });

  final String debtId;
  final String label;
  final double amount;
  final double paid;
  final double remaining;
  final DateTime occurredAt;

  factory DebtRow.fromRow(Map<String, dynamic> r) => DebtRow(
        debtId: r['debt_id'] as String,
        label: r['label'] as String,
        amount: (r['amount'] as num).toDouble(),
        paid: (r['paid'] as num).toDouble(),
        remaining: (r['remaining'] as num).toDouble(),
        occurredAt: DateTime.parse(r['occurred_at'] as String),
      );
}

/// One open debt's due date (117).
typedef DebtDate = ({String debtId, String customerId, DateTime dueOn});

/// The carnet de crédit, server side.
///
/// Online-only, like the invoices: a debt is a claim against a named person
/// and the amount that settles a dispute, so the server's copy is the one
/// that counts. A credit sale of articles is the exception — it is a sale
/// (record_sale), kept in the outbox like any other when there is no
/// signal, and its due date waits there behind it (LocalDb.queueDebtDue).
class CreditRepository {
  CreditRepository(this._client);

  final SupabaseClient? _client;
  static const _uuid = Uuid();

  bool get isConfigured => _client != null;

  SupabaseClient get _c {
    final c = _client;
    if (c == null) {
      throw StateError(
          "Cette version de l'application a été compilée sans serveur.");
    }
    return c;
  }

  Future<List<DebtorRow>> debtors(String orgId) async {
    final rows = await _c.rpc('customer_debts', params: {'p_org_id': orgId});
    return (rows as List)
        .map((r) => DebtorRow.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<DebtRow>> debtsOf(String orgId, String customerId) async {
    final rows = await _c.rpc('debts_of_customer', params: {
      'p_org_id': orgId,
      'p_customer_id': customerId,
    });
    return (rows as List)
        .map((r) => DebtRow.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// The keys mirror `record_credit_sale()` in 024 exactly — the payload
  /// shape is asserted by test, because a drifted key fails on somebody's
  /// phone days later, not here. Answers the debt's id.
  Future<String> recordCreditSale({
    required String orgId,
    required String customerName,
    required double amount,
    required String label,
    String? customerPhone,
    String? category,
    String? clientUuid,
  }) async {
    final id = await _c.rpc('record_credit_sale', params: {
      'p_org_id': orgId,
      'p_customer_name': customerName,
      'p_amount': amount,
      'p_label': label,
      if (customerPhone != null && customerPhone.isNotEmpty)
        'p_customer_phone': customerPhone,
      if (category != null && category.isNotEmpty) 'p_category': category,
      'p_recorded_by': _c.auth.currentUser?.id,
      'p_client_uuid': clientUuid ?? _uuid.v4(),
    });
    return id as String;
  }

  /// When the customer said they would pay (117). By the debt's id (a sum
  /// just written) or by the credit sale's client_uuid. Answers the debt's
  /// id, or null when that sale is not on the server (yet).
  Future<String?> setDue({
    required String orgId,
    required DateTime? dueOn,
    String? debtId,
    String? saleClientUuid,
  }) async {
    final id = await _c.rpc('set_debt_due', params: {
      'p_org_id': orgId,
      'p_due_on': dueOn == null ? null : day(dueOn),
      'p_debt_id': ?debtId,
      'p_sale_client_uuid': ?saleClientUuid,
      'p_recorded_by': _c.auth.currentUser?.id,
    });
    return id as String?;
  }

  /// Each open debt that has a date (117), earliest first, with its
  /// customer — for the carnet's « en retard » and each debt's date.
  Future<List<DebtDate>> dueDates(String orgId) async {
    final rows = await _c.rpc('debt_dates', params: {'p_org_id': orgId});
    return [
      for (final r in rows as List)
        (
          debtId: '${(r as Map)['debt_id']}',
          customerId: '${r['customer_id']}',
          dueOn: DateTime.parse('${r['due_on']}'),
        ),
    ];
  }

  /// A repayment by customer (117): spread over their open debts, oldest
  /// first, in one transaction. [clientUuid] makes a retry harmless.
  /// Answers what they still owe.
  Future<double> repay({
    required String orgId,
    required String customerId,
    required double amount,
    String method = 'cash',
    String? clientUuid,
  }) async {
    final left = await _c.rpc('repay_customer', params: {
      'p_org_id': orgId,
      'p_customer_id': customerId,
      'p_amount': amount,
      'p_method': method,
      'p_recorded_by': _c.auth.currentUser?.id,
      'p_client_uuid': clientUuid ?? _uuid.v4(),
    });
    return (left as num).toDouble();
  }

  /// yyyy-mm-dd, as Postgres reads a date.
  static String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
