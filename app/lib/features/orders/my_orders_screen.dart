import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format/money.dart';
import '../../core/nav/router.dart';
import '../../core/orders/orders.dart';
import '../../core/storefront/storefront_repository.dart';
import '../storefront/shop_style.dart';

/// A customer's orders: what they asked for, where each one stands, and
/// the one thing they can still do about a pending one — withdraw it.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key, required this.storefront});

  final StorefrontRepository storefront;

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  List<CustomerOrder> _orders = const [];
  bool _loading = true;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!widget.storefront.isConfigured) {
      setState(() {
        _error = "Vos commandes ont besoin d'une connexion.";
        _loading = false;
      });
      return;
    }
    try {
      final orders = await widget.storefront.myOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Vos commandes n'ont pas pu être chargées. Vérifiez le réseau.";
        _loading = false;
      });
    }
  }

  Future<void> _cancel(CustomerOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler cette commande ?'),
        content: Text('${order.shopName} ne la verra plus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Garder')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Annuler la commande')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyId = order.id);
    try {
      await widget.storefront.cancelOrder(order.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Trop tard : la boutique a déjà répondu.")));
      await _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _orders.where((o) => o.isOpen).toList();
    final past = _orders.where((o) => !o.isOpen).toList();

    return ShopPage(
      title: 'Mes commandes',
      leading: IconButton(
        tooltip: 'Les vitrines',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go(Routes.directory),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ShopNotice(
                  text: _error!,
                  action: OutlinedButton(
                      onPressed: _load, child: const Text('Réessayer')),
                )
              : _orders.isEmpty
                  ? ShopNotice(
                      text: "Vous n'avez pas encore commandé.",
                      action: FilledButton(
                        onPressed: () => context.go(Routes.directory),
                        child: const Text('Voir les vitrines'),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        ShopWidth(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 28),
                              if (open.isNotEmpty) ...[
                                ShopSectionLabel('En cours',
                                    note: '${open.length}'),
                                const SizedBox(height: 12),
                                for (final o in open)
                                  _OrderCard(
                                    order: o,
                                    busy: _busyId == o.id,
                                    onCancel: o.status == 'pending'
                                        ? () => _cancel(o)
                                        : null,
                                  ),
                                const SizedBox(height: 28),
                              ],
                              if (past.isNotEmpty) ...[
                                ShopSectionLabel('Passées',
                                    note: '${past.length}'),
                                const SizedBox(height: 12),
                                for (final o in past)
                                  _OrderCard(order: o, busy: false),
                              ],
                              const ShopFooter(),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.busy, this.onCancel});

  final CustomerOrder order;
  final bool busy;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(order.currency);
    final when = DateFormat('d MMM, HH:mm', 'fr_FR').format(order.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: ShopStyle.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => context.go(Routes.storefront(order.shopSlug)),
                  child: Text(order.shopName,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: ShopStyle.ink)),
                ),
              ),
              _StatusChip(status: order.status),
            ],
          ),
          const SizedBox(height: 2),
          Text('$when · ${fulfilmentLabel(order.fulfilment)}',
              style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
          const SizedBox(height: 12),
          for (final l in order.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${_qty(l.quantity)} × ${l.name}',
                        style: const TextStyle(
                            fontSize: 15, color: ShopStyle.ink)),
                  ),
                  Text(money.format(l.total),
                      style: const TextStyle(
                          fontSize: 14, color: ShopStyle.mist)),
                ],
              ),
            ),
          const Divider(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text('Total',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ShopStyle.ink)),
              ),
              Text(money.format(order.total),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ShopStyle.ink)),
            ],
          ),
          if ((order.address ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Livraison : ${order.address}',
                style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
          ],
          if ((order.courierName ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Livreur : ${order.courierName}',
                style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
          ],
          if ((order.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Note : ${order.note}',
                style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
          ],
          if (onCancel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy ? null : onCancel,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Annuler la commande'),
            ),
          ],
        ],
      ),
    );
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final open = orderIsOpen(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: open ? ShopStyle.ink : ShopStyle.stone,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(orderStatusLabel(status),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: open ? ShopStyle.paper : ShopStyle.mist)),
    );
  }
}
