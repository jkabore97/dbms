import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// One past transformation: what was made, from what, at what cost.
class ProductionRun {
  const ProductionRun({
    required this.runId,
    required this.productName,
    required this.quantity,
    required this.totalCost,
    required this.unitCost,
    required this.occurredAt,
    this.inputs = const [],
  });

  final String runId;
  final String productName;
  final double quantity;
  final double totalCost;
  final double unitCost;
  final DateTime occurredAt;
  final List<ProductionInputLine> inputs;

  factory ProductionRun.fromRow(Map<String, dynamic> r) => ProductionRun(
        runId: r['run_id'] as String,
        productName: r['product_name'] as String,
        quantity: (r['quantity'] as num).toDouble(),
        totalCost: (r['total_cost'] as num).toDouble(),
        unitCost: (r['unit_cost'] as num).toDouble(),
        occurredAt: DateTime.parse(r['occurred_at'] as String),
        inputs: ((r['inputs'] as List?) ?? const [])
            .map((i) =>
                ProductionInputLine.fromRow(Map<String, dynamic>.from(i as Map)))
            .toList(),
      );
}

/// One ingredient of a run, as it was consumed.
class ProductionInputLine {
  const ProductionInputLine({required this.name, required this.quantity});

  final String name;
  final double quantity;

  factory ProductionInputLine.fromRow(Map<String, dynamic> r) =>
      ProductionInputLine(
        name: r['name'] as String,
        quantity: (r['quantity'] as num).toDouble(),
      );
}

/// An ingredient being consumed by the run the sheet is composing.
class ProductionInputDraft {
  const ProductionInputDraft({required this.productId, required this.quantity});

  final String productId;
  final double quantity;

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'quantity': quantity,
      };
}

/// The transformation tool, server side.
///
/// Online-only for now, like the carnet: the run's whole value is the cost
/// arithmetic the server does, so recording one against a stale local copy
/// of ingredient costs would defeat it. The SQL is already idempotent by
/// client_uuid to receive an outbox path later.
class ProductionRepository {
  ProductionRepository(this._client);

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

  Future<List<ProductionRun>> history(String orgId) async {
    final rows = await _c.rpc('production_history', params: {'p_org_id': orgId});
    return (rows as List)
        .map((r) => ProductionRun.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// The keys mirror `record_production()` in 026 exactly — the payload
  /// shape is asserted by test, because a drifted key fails on somebody's
  /// phone days later, not here.
  Future<void> record({
    required String orgId,
    required String productName,
    required double quantity,
    required List<ProductionInputDraft> inputs,
    String? note,
  }) async {
    await _c.rpc('record_production', params: {
      'p_org_id': orgId,
      'p_quantity': quantity,
      'p_inputs': inputs.map((i) => i.toJson()).toList(),
      'p_product_name': productName,
      if (note != null && note.isNotEmpty) 'p_note': note,
      'p_recorded_by': _c.auth.currentUser?.id,
      'p_client_uuid': _uuid.v4(),
    });
  }

  /// Correcting a past run (034). The ingredients stay as recorded — only the
  /// output count, its name and note change — and the server re-derives the
  /// unit cost from the unchanged total. Refused for an observer, and for an
  /// employee the owner dialled to 'view' on production.
  Future<void> updateRun(
    String runId, {
    double? quantity,
    String? productName,
    String? note,
  }) async {
    await _c.rpc('update_production_run', params: {
      'p_run_id': runId,
      if (quantity != null) 'p_quantity': quantity,
      if (productName != null && productName.isNotEmpty)
        'p_product_name': productName,
      if (note != null && note.isNotEmpty) 'p_note': note,
    });
  }
}
