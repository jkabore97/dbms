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
    this.lines = const {},
  });

  final String clientUuid;

  /// 'record_sale' (the till) or 'move_stock' (a farm's feed).
  final String action;

  /// « 2 × Savon, 1 × Huile », « 4 Aliment ».
  final String what;

  /// The server's sentence, as it came.
  final String reason;

  /// A refused sale's quantities by article name, as it was rung up.
  final Map<String, double> lines;

  /// How many of the article the server named are missing for this sale to
  /// go through: what it asks for less what the server said is left. Null
  /// when the reason names no article.
  ({String name, double missing})? get shortfall {
    final item = stockShortItem(reason);
    if (item == null) return null;
    final asked = lines.entries
        .where((e) => e.key.trim().toLowerCase() == item.name.trim().toLowerCase())
        .fold<double>(0, (sum, e) => sum + e.value);
    final left = item.left < 0 ? 0.0 : item.left;
    return (name: item.name, missing: asked > left ? asked - left : 1);
  }

  static RefusedAction fromRow(Map<String, Object?> row) {
    final action = row['action'] as String;
    var what = '';
    final lines = <String, double>{};
    try {
      final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      if (action == 'record_sale') {
        for (final l in (payload['p_lines'] as List? ?? const [])) {
          final name = '${(l as Map)['name'] ?? ''}';
          lines[name] =
              (lines[name] ?? 0) + ((l['quantity'] as num?)?.toDouble() ?? 0);
        }
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
      lines: lines,
    );
  }
}

/// One card per refused action, on the home: what it was, why, and
/// « Compris » to put it away — and, for a sale, « Corriger le stock puis
/// refaire la vente » when [onFix] is given.
class RefusedNotice extends StatelessWidget {
  const RefusedNotice(
      {super.key, required this.actions, required this.onDismiss, this.onFix});

  final List<RefusedAction> actions;
  final ValueChanged<RefusedAction> onDismiss;

  /// Opens the stock entry for the article the server named, then sends the
  /// same sale again. Offered for a refused sale only; null hides it (a
  /// farm's feed, a person who cannot enter stock).
  final ValueChanged<RefusedAction>? onFix;

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
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      if (onFix != null &&
                          a.action == 'record_sale' &&
                          a.shortfall != null)
                        TextButton.icon(
                          key: Key('refused-fix-${a.clientUuid}'),
                          onPressed: () => onFix!(a),
                          icon: const Icon(Icons.inventory_2_outlined, size: 20),
                          label: Text(
                              context.tr('Corriger le stock puis refaire la vente')),
                        ),
                      TextButton(
                        onPressed: () => onDismiss(a),
                        child: Text(context.tr('Compris')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
