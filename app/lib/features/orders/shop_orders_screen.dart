import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/models.dart';
import '../../core/format/money.dart';
import '../../core/orders/orders.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/storefront/storefront_repository.dart';

/// The shop's orders: who wants what, and the one button that moves each
/// one along. "À traiter" is what needs an answer or a hand; "Historique"
/// is everything that is done.
///
/// Answering an order does not sell anything: when the customer collects,
/// the till records the sale as it always has. This screen is the list
/// on the wall behind the counter, not the till.
class ShopOrdersScreen extends StatefulWidget {
  const ShopOrdersScreen({super.key, required this.org, required this.retail});

  final OrgSummary org;
  final RetailRepository retail;

  @override
  State<ShopOrdersScreen> createState() => _ShopOrdersScreenState();
}

class _ShopOrdersScreenState extends State<ShopOrdersScreen> {
  List<ShopOrder> _orders = const [];
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
    try {
      final orders = await widget.retail.shopOrders(widget.org.id);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _setPaid(ShopOrder order, bool paid) async {
    setState(() => _busyId = order.id);
    try {
      await widget.retail.setOrderPaid(order.id, paid);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthRepository.describeError(error))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _move(ShopOrder order, String status) async {
    if (status == 'refused' || status == 'cancelled') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(status == 'refused'
              ? 'Refuser cette commande ?'
              : 'Annuler cette commande ?'),
          content: Text('${order.customerName} en sera informé.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Retour')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(orderActionLabel(status))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busyId = order.id);
    try {
      await widget.retail.decideOrder(order.id, status);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthRepository.describeError(error))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final open = _orders.where((o) => o.isOpen).toList();
    final past = _orders.where((o) => !o.isOpen).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Commandes'),
          actions: [
            IconButton(
              tooltip: 'Actualiser',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: 'À traiter${open.isEmpty ? '' : ' (${open.length})'}'),
            const Tab(text: 'Historique'),
          ]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                              onPressed: _load,
                              child: const Text('Réessayer')),
                        ],
                      ),
                    ),
                  )
                : TabBarView(children: [
                    _List(
                      orders: open,
                      empty: 'Aucune commande à traiter. Les clients '
                          'commandent depuis votre vitrine.',
                      busyId: _busyId,
                      onMove: _move,
                      onOpen: _open,
                      onSetPaid: _setPaid,
                    ),
                    _List(
                      orders: past,
                      empty: 'Aucune commande passée pour le moment.',
                      busyId: _busyId,
                      onMove: _move,
                      onOpen: _open,
                      onSetPaid: _setPaid,
                    ),
                  ]),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.orders,
    required this.empty,
    required this.busyId,
    required this.onMove,
    required this.onOpen,
    required this.onSetPaid,
  });

  final List<ShopOrder> orders;
  final String empty;
  final String? busyId;
  final Future<void> Function(ShopOrder, String) onMove;
  final Future<void> Function(String) onOpen;
  final Future<void> Function(ShopOrder, bool) onSetPaid;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(empty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: orders.length,
      itemBuilder: (context, i) => _OrderCard(
        order: orders[i],
        busy: busyId == orders[i].id,
        onMove: onMove,
        onOpen: onOpen,
        onSetPaid: onSetPaid,
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.busy,
    required this.onMove,
    required this.onOpen,
    required this.onSetPaid,
  });

  final ShopOrder order;
  final bool busy;
  final Future<void> Function(ShopOrder, String) onMove;
  final Future<void> Function(String) onOpen;
  final Future<void> Function(ShopOrder, bool) onSetPaid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(order.currency);
    final when = DateFormat('EEE d MMM, HH:mm', 'fr_FR').format(order.createdAt);
    final phone = (order.phone ?? '').trim();
    final whatsapp = whatsappUrl(order.phone);
    final next = order.nextStatuses;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(order.customerName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Chip(
                  label: Text(orderStatusLabel(order.status)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
                '$when · ${fulfilmentLabel(order.fulfilment)} · '
                '${paymentLabel(order.paymentMethod)}'
                '${order.isPaid ? ' · payé' : ''}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(phone, style: theme.textTheme.bodyMedium),
                  IconButton(
                    tooltip: 'Appeler',
                    icon: const Icon(Icons.call_outlined, size: 20),
                    onPressed: () => onOpen('tel:$phone'),
                  ),
                  if (whatsapp != null)
                    IconButton(
                      tooltip: 'WhatsApp',
                      icon: const Icon(Icons.chat_outlined, size: 20),
                      onPressed: () => onOpen(whatsapp),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            for (final l in order.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${_qty(l.quantity)} × ${l.name}',
                          style: theme.textTheme.bodyMedium),
                    ),
                    Text(money.format(l.total),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                    child: Text('Total',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600))),
                Text(money.format(order.total),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            if ((order.address ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text('Livraison : ${order.address}',
                        style: theme.textTheme.bodySmall),
                  ),
                  if (order.hasDropPin)
                    TextButton(
                      onPressed: () => onOpen(
                          directionsUrl(order.dropLat!, order.dropLng!)),
                      child: const Text('Itinéraire'),
                    ),
                ],
              ),
            ],
            if ((order.courierName ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Livreur : ${order.courierName}',
                  style: theme.textTheme.bodySmall),
            ],
            if ((order.note ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Note : ${order.note}', style: theme.textTheme.bodySmall),
            ],
            if (next.isNotEmpty || order.isOpen || order.isPaid) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  // The money's word lives beside the state's: the shop
                  // confirms a payment arrived, or unsays a mis-tap.
                  if (!order.isPaid && order.isOpen)
                    OutlinedButton.icon(
                      onPressed:
                          busy ? null : () => onSetPaid(order, true),
                      icon: const Icon(Icons.price_check_outlined, size: 18),
                      label: const Text('Paiement reçu'),
                    )
                  else if (order.isPaid)
                    TextButton(
                      onPressed:
                          busy ? null : () => onSetPaid(order, false),
                      child: const Text('Annuler le paiement'),
                    ),
                  for (var i = 0; i < next.length; i++)
                    if (next[i] == 'refused' || next[i] == 'cancelled')
                      TextButton(
                        onPressed: busy ? null : () => onMove(order, next[i]),
                        style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error),
                        child: Text(orderActionLabel(next[i])),
                      )
                    else if (i == 0)
                      FilledButton(
                        onPressed: busy ? null : () => onMove(order, next[i]),
                        child: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : Text(orderActionLabel(next[i])),
                      )
                    else
                      OutlinedButton(
                        onPressed: busy ? null : () => onMove(order, next[i]),
                        child: Text(orderActionLabel(next[i])),
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}
