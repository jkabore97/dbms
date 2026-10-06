import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/orders/orders.dart';
import '../../core/storefront/storefront_repository.dart';
import '../storefront/shop_style.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// Where an order is, for the person who placed it (073).
///
/// The audit: a shopper saw one status word — no time, no courier, no way
/// to tell a slow order from a stuck one. This is the timeline each order
/// card carries while it is open: every step with its time, the courier's
/// name and a call button once they are on the road, the shop's number,
/// and for a delivery the four digits to give at the door.
class OrderTrackingPanel extends StatefulWidget {
  const OrderTrackingPanel({
    super.key,
    required this.orderId,
    required this.storefront,
    required this.onCall,
    this.refreshKey = 0,
  });

  final String orderId;
  final StorefrontRepository storefront;
  final void Function(String url) onCall;

  /// Bumped by the screen when it re-reads its orders; the panel follows.
  final int refreshKey;

  @override
  State<OrderTrackingPanel> createState() => _OrderTrackingPanelState();
}

class _OrderTrackingPanelState extends State<OrderTrackingPanel> {
  OrderTracking? _t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(OrderTrackingPanel old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.storefront.tracking(widget.orderId);
      if (mounted) setState(() => _t = t);
    } catch (_) {
      // No signal: the card keeps its status word.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return const SizedBox.shrink();
    final delivery = t.fulfilment == 'delivery';
    final steps = <(String, String)>[
      ('pending', 'Envoyée'),
      ('accepted', 'Acceptée'),
      ('ready', delivery ? context.tr('Prête, attend le livreur') : context.tr('Prête à retirer')),
      if (delivery) ('in_transit', 'En route'),
      (delivery ? 'delivered' : 'picked_up', delivery ? context.tr('Livrée') : context.tr('Retirée')),
    ];
    final order = [for (final s in steps) s.$1];
    final at = order.indexOf(t.status);
    final hour = DateFormat('HH:mm', 'fr_FR');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        for (var i = 0; i < steps.length; i++)
          _Step(
            label: steps[i].$2,
            time: t.reached(steps[i].$1) == null
                ? null
                : hour.format(t.reached(steps[i].$1)!),
            done: at >= 0 && i < at,
            current: i == at,
            last: i == steps.length - 1,
            note: i == at && i < steps.length - 1 ? _since(t) : null,
          ),
        if (delivery && t.code != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ShopStyle.stone,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('CODE À DONNER AU LIVREUR'),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: ShopStyle.mist)),
                const SizedBox(height: 4),
                Text(t.code!,
                    semanticsLabel: 'Code ${t.code!.split('').join(' ')}',
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8,
                        color: ShopStyle.ink)),
                Text(
                    context.tr('Donnez-le seulement quand vous avez votre commande en main.'),
                    style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (t.status == 'in_transit' && (t.courierPhone ?? '').isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => widget.onCall('tel:${t.courierPhone}'),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: Text('Appeler ${t.courierName ?? 'le livreur'}'),
              ),
            if ((t.shopPhone ?? '').isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => widget.onCall('tel:${t.shopPhone}'),
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: Text(context.tr('Appeler la boutique')),
              ),
          ],
        ),
      ],
    );
  }

  String? _since(OrderTracking t) {
    final label = OrderClock(since: t.since).sinceLabel();
    if (label.isEmpty) return null;
    if (t.status == 'in_transit' && t.selfDelivered) {
      return context.tr('{shopName} vous livre lui-même · {label}', {'shopName': t.shopName, 'label': label});
    }
    if (t.status == 'in_transit' && t.courierName != null) {
      return context.tr('{courierName} · {label}', {'courierName': t.courierName, 'label': label});
    }
    return label;
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.done,
    required this.current,
    required this.last,
    this.time,
    this.note,
  });

  final String label;
  final String? time;
  final bool done;
  final bool current;
  final bool last;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final lit = done || current;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: lit ? ShopStyle.ink : ShopStyle.paper,
                    border: Border.all(
                        color: lit ? ShopStyle.ink : ShopStyle.line, width: 2),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: done ? ShopStyle.ink : ShopStyle.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight:
                                    current ? FontWeight.w700 : FontWeight.w500,
                                color: lit ? ShopStyle.ink : ShopStyle.mist)),
                      ),
                      if (time != null)
                        Text(time!,
                            style: const TextStyle(
                                fontSize: 13, color: ShopStyle.mist)),
                    ],
                  ),
                  if (note != null)
                    Text(note!,
                        style: const TextStyle(
                            fontSize: 13, color: ShopStyle.mist)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
