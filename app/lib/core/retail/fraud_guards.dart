import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';

/// The fraud guards of batch 151 (migration 146), on the business's side:
/// a shopper blocked from ordering, and the till closed at the end of the
/// day.

/// True when the server has not had 146 yet: the function or the table is
/// not there. The screens then say the feature is coming, and nothing else
/// changes.
bool isGuardMissing(Object error) {
  if (isSchemaOutOfDate(error)) return true;
  if (error is PostgrestException) {
    final code = error.code ?? '';
    return code == 'PGRST205' || code == '42P01' || code == '42883' ||
        error.message.contains('Could not find the table') ||
        error.message.contains('does not exist');
  }
  return false;
}

/// A shopper this business no longer takes orders from.
class BlockedCustomer {
  const BlockedCustomer({
    required this.customerId,
    required this.name,
    this.reason,
    this.blockedAt,
  });

  factory BlockedCustomer.fromRow(Map<String, dynamic> r) => BlockedCustomer(
        customerId: '${r['customer_id']}',
        name: ((r['name'] as String?) ?? '').trim(),
        reason: (r['reason'] as String?)?.trim(),
        blockedAt: r['created_at'] == null ? null : DateTime.tryParse('${r['created_at']}')?.toLocal(),
      );

  final String customerId;
  final String name;
  final String? reason;
  final DateTime? blockedAt;
}

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

/// One « Clôturer la caisse »: the cash counted against the server's
/// expected (the float, the day's cash sales, less its cash returns).
class TillClosing {
  const TillClosing({
    required this.day,
    required this.expected,
    required this.counted,
    required this.gap,
    this.id,
    this.currency = 'XOF',
    this.openingFloat = 0,
    this.cashSales = 0,
    this.cashReturns = 0,
    this.closerName,
    this.note,
    this.closedAt,
  });

  factory TillClosing.fromRow(Map<String, dynamic> r) => TillClosing(
        id: r['id'] as String?,
        day: DateTime.tryParse('${r['day']}') ?? DateTime.now(),
        currency: (r['currency'] as String?) ?? 'XOF',
        openingFloat: _num(r['opening_float']),
        cashSales: _num(r['cash_sales']),
        cashReturns: _num(r['cash_returns']),
        expected: _num(r['expected']),
        counted: _num(r['counted']),
        gap: _num(r['gap']),
        closerName: r['closer_name'] as String?,
        note: r['note'] as String?,
        closedAt: r['closed_at'] == null ? null : DateTime.tryParse('${r['closed_at']}')?.toLocal(),
      );

  final String? id;
  final DateTime day;
  final String currency;
  final double openingFloat;
  final double cashSales;
  final double cashReturns;
  final double expected;
  final double counted;

  /// Counted − expected: below zero, money is missing.
  final double gap;
  final String? closerName;
  final String? note;
  final DateTime? closedAt;
}

/// The doors of 146 a business uses. Null client: a build with no server.
class FraudGuardsRepository {
  FraudGuardsRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  SupabaseClient _require() {
    final c = _client;
    if (c == null) {
      throw StateError('Cette version de l\'application a été compilée sans serveur.');
    }
    return c;
  }

  /// « Bloquer ce client », from one of the business's orders.
  Future<void> blockCustomer(String orderId, {String? reason}) async {
    await _require().rpc('block_customer', params: {
      'p_order_id': orderId,
      if (reason != null && reason.trim().isNotEmpty) 'p_reason': reason.trim(),
    });
  }

  Future<void> unblockCustomer(String orgId, String customerId) async {
    await _require().rpc('unblock_customer', params: {
      'p_org_id': orgId,
      'p_customer_id': customerId,
    });
  }

  /// The business's blocked shoppers, newest first (RLS: its admins only).
  Future<List<BlockedCustomer>> blockedCustomers(String orgId) async {
    final rows = await _require()
        .from('blocked_customers')
        .select('customer_id, name, reason, created_at')
        .eq('org_id', orgId)
        .order('created_at', ascending: false);
    return [for (final r in rows) BlockedCustomer.fromRow(Map<String, dynamic>.from(r))];
  }

  /// Closes the till for [day] (the phone's day): the cash counted, the
  /// change it started with. The server says what was expected.
  Future<TillClosing> closeTill(
    String orgId, {
    required DateTime day,
    required double counted,
    double openingFloat = 0,
    String? note,
  }) async {
    final v = await _require().rpc('close_till', params: {
      'p_org_id': orgId,
      'p_day': '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}',
      'p_utc_offset_minutes': day.timeZoneOffset.inMinutes,
      'p_counted': counted,
      'p_float': openingFloat,
      if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
    });
    return TillClosing.fromRow(Map<String, dynamic>.from(v as Map));
  }

  /// The closings this person may read (the owner: all; a cashier: theirs).
  Future<List<TillClosing>> tillClosings(String orgId, {int limit = 20}) async {
    final rows = await _require()
        .from('till_closings')
        .select()
        .eq('org_id', orgId)
        .order('closed_at', ascending: false)
        .limit(limit);
    return [for (final r in rows) TillClosing.fromRow(Map<String, dynamic>.from(r))];
  }
}
