import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import '../../core/retail/stock_rule.dart';
import '../../core/theme/mara_mark.dart';

/// Something recorded on this phone with no signal that the server then
/// refused for good (101: the stock was not there). It was never recorded:
/// the outbox stopped sending it (SyncService) and it waits here until the
/// owner has read it — not retried forever, not dropped in silence.
class RefusedAction {
  const RefusedAction({
    required this.clientUuid,
    required this.action,
    required this.what,
    required this.reason,
  });

  final String clientUuid;

  /// 'record_sale' (the till) or 'move_stock' (a farm's feed).
  final String action;

  /// « 2 × Savon, 1 × Huile », « 4 Aliment ».
  final String what;

  /// The server's sentence, as it came.
  final String reason;

  static RefusedAction fromRow(Map<String, Object?> row) {
    final action = row['action'] as String;
    var what = '';
    try {
      final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      if (action == 'record_sale') {
        what = [
          for (final l in (payload['p_lines'] as List? ?? const []))
            '${stockQty(((l as Map)['quantity'] as num?)?.toDouble() ?? 0)} × ${l['name'] ?? ''}',
        ].join(', ');
      } else {
        what = '${stockQty((payload['p_quantity'] as num?)?.toDouble() ?? 0)} '
            '${payload['p_item_name'] ?? ''}';
      }
    } catch (_) {}
    return RefusedAction(
      clientUuid: row['client_uuid'] as String,
      action: action,
      what: what.trim(),
      reason: (row['last_error'] as String?) ?? '',
    );
  }
}

/// One card per refused action, on the home: what it was, why, and
/// « Compris » to put it away.
class RefusedNotice extends StatelessWidget {
  const RefusedNotice({super.key, required this.actions, required this.onDismiss});

  final List<RefusedAction> actions;
  final ValueChanged<RefusedAction> onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              key: Key('refused-${a.clientUuid}'),
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              decoration: BoxDecoration(
                color: maraCaramel.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: maraBrown.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.block_outlined, color: maraBrown, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.action == 'record_sale'
                                  ? context.tr('Vente refusée : rien n\'a été enregistré')
                                  : context.tr('Sortie de stock refusée : rien n\'a été enregistré'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, color: maraDeep, fontSize: 15),
                            ),
                            if (a.what.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(a.what, style: const TextStyle(color: maraDeep)),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              stockShortText(context.trLanguage, a.reason) ?? a.reason,
                              style: const TextStyle(
                                  color: maraBrown, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => onDismiss(a),
                      child: Text(context.tr('Compris')),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
