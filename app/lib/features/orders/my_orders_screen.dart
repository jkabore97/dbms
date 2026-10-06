import 'dart:async';

import '../../core/theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format/money.dart';
import '../../core/nav/router.dart';
import '../../core/orders/orders.dart';
import '../../core/storefront/storefront_repository.dart';
import '../storefront/shop_skeleton.dart';
import '../pay/wave_buttons.dart';
import 'order_tracking_panel.dart';
import '../storefront/shop_style.dart';
import 'package:kaj_app/core/l10n/tr.dart';

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

  /// While an order is open the page keeps up by itself (073): every
  /// thirty seconds, silently, the list and each card's timeline.
  Timer? _poll;
  int _tick = 0;
  static const _pollEvery = Duration(seconds: 30);

  /// The shop's answer, the courier, the door — as they happen (074).
  void Function()? _unwatch;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _load();
    _unwatch = widget.storefront.watchMyOrders(() {
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 600), () {
        if (mounted && !_loading && _busyId == null) _load(silent: true);
      });
    });
    _poll = Timer.periodic(_pollEvery, (_) {
      if (!mounted || _loading || _busyId != null) return;
      if (!_orders.any((o) => o.isOpen)) return;
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _settle?.cancel();
    _unwatch?.call();
    super.dispose();
  }

  Future<void> _call(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri);
  }

  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    if (!widget.storefront.isConfigured) {
      setState(() {
        _error = context.tr('Vos commandes ont besoin d\'une connexion.');
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
        _tick++;
      });
    } catch (_) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _error = context.tr('Vos commandes n\'ont pas pu être chargées. Vérifiez le réseau.');
        _loading = false;
      });
    }
  }

  /// Opens the shop's own Wave link. The app cannot see the money move —
  /// the shop confirms in its till and the order then shows "Payé".
  Future<void> _payWithWave(CustomerOrder order) async {
    final raw = order.shopWave;
    if (raw == null) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('Payer avec Wave')),
          content: Text('Dans votre application Wave, envoyez '
              '${moneyFormat(order.currency).format(order.total)} '
              'au marchand : $raw'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('Compris'))),
          ],
        ),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _cancel(CustomerOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Annuler cette commande ?')),
        content: Text(context.tr('{shopName} ne la verra plus.', {'shopName': order.shopName})),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.tr('Garder'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.tr('Annuler la commande'))),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('Trop tard : la boutique a déjà répondu.'))));
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
      title: context.tr('Mes commandes'),
      announcements: ShopPage.street,
      leading: IconButton(
        tooltip: context.tr('Les vitrines'),
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go(Routes.directory),
      ),
      body: _loading
          ? ShopSkeleton.list()
          : _error != null
              ? ShopNotice(
                  text: _error!,
                  action: OutlinedButton(
                      onPressed: _load, child: Text(context.tr('Réessayer'))),
                )
              : _orders.isEmpty
                  ? ShopNotice(
                      text: "Vous n'avez pas encore commandé.",
                      action: FilledButton(
                        onPressed: () => context.go(Routes.directory),
                        child: Text(context.tr('Voir les vitrines')),
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
                                for (final (i, o) in open.indexed)
                                  ScrollReveal(
                                  delay: KajMotion.stagger(i),
                                  child: _OrderCard(
                                    order: o,
                                    busy: _busyId == o.id,
                                    onCancel: o.status == 'pending'
                                        ? () => _cancel(o)
                                        : null,
                                    onPay: o.canPayNow
                                        ? () => _payWithWave(o)
                                        : null,
                                    // Kaj's Wave checkout first (076); the
                                    // shop's own link when it is not on.
                                    wave: o.canPayByWave
                                        ? WaveButtons(
                                            kind: 'order',
                                            ref: o.id,
                                            orgId: o.orgId,
                                            onUnavailable: null,
                                          )
                                        : null,
                                    tracking: OrderTrackingPanel(
                                      key: ValueKey('track-${o.id}'),
                                      orderId: o.id,
                                      storefront: widget.storefront,
                                      onCall: _call,
                                      refreshKey: _tick,
                                    ),
                                  ),
                                  ),
                                const SizedBox(height: 28),
                              ],
                              if (past.isNotEmpty) ...[
                                ShopSectionLabel('Passées',
                                    note: '${past.length}'),
                                const SizedBox(height: 12),
                                for (final (i, o) in past.indexed)
                                  ScrollReveal(
                                    delay: KajMotion.stagger(i),
                                    child: _OrderCard(order: o, busy: false),
                                  ),
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
  const _OrderCard({
    required this.order,
    required this.busy,
    this.onCancel,
    this.onPay,
    this.tracking,
    this.wave,
  });

  /// « Payer avec Wave / par carte » through Kaj (076). When it is not
  /// offered it draws the shop's own link instead ([onPay]).
  final Widget? wave;

  final CustomerOrder order;
  final bool busy;

  /// The open order's timeline (073).
  final Widget? tracking;
  final VoidCallback? onCancel;
  final VoidCallback? onPay;

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
          Text(
              '$when · ${fulfilmentLabel(order.fulfilment)} · '
              '${order.isPaid ? 'Payé' : paymentLabel(order.paymentMethod)}',
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
          // The delivery's price (061), fixed when the order was placed and
          // handed to the courier at the door — shown apart from the goods,
          // which may have been paid another way.
          if (order.fulfilment == 'delivery') ...[
            Row(
              children: [
                Expanded(
                  child: Text(context.tr('Livraison'),
                      style: const TextStyle(fontSize: 14, color: ShopStyle.mist)),
                ),
                Text(
                    order.deliveryFee == null
                        ? 'à discuter'
                        : '${money.format(order.deliveryFee!)} au livreur',
                    style: const TextStyle(fontSize: 14, color: ShopStyle.mist)),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Expanded(
                child: Text(context.tr('Total'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ShopStyle.ink)),
              ),
              Text(money.format(order.grandTotal),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ShopStyle.ink)),
            ],
          ),
          if ((order.address ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(context.tr('Livraison : {address}', {'address': order.address}),
                style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
          ],
          if ((order.courierName ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(context.tr('Livreur : {courierName}', {'courierName': order.courierName}),
                style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
          ],
          if ((order.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(context.tr('Note : {note}', {'note': order.note}),
                style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
          ],
          ?tracking,
          if (wave != null || onPay != null) ...[
            const SizedBox(height: 12),
            _PayArea(
              wave: wave,
              fallback: onPay == null
                  ? null
                  : FilledButton.icon(
                      onPressed: busy ? null : onPay,
                      icon: const Icon(Icons.phone_iphone_outlined, size: 18),
                      label: Text(
                          'Payer avec Wave · ${moneyFormat(order.currency).format(order.total)}'),
                    ),
            ),
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
                  : Text(context.tr('Annuler la commande')),
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


/// Kaj's Wave checkout when it is offered, else the shop's own link.
class _PayArea extends StatelessWidget {
  const _PayArea({this.wave, this.fallback});

  final Widget? wave;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final w = wave;
    if (w is WaveButtons) {
      return WaveButtons(
        key: w.key,
        kind: w.kind,
        ref: w.ref,
        orgId: w.orgId,
        onUnavailable: fallback,
      );
    }
    return fallback ?? const SizedBox.shrink();
  }
}
