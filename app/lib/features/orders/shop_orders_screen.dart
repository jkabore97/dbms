import 'dart:async';

import '../../core/theme/kaj_card.dart';
import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import '../../core/nav/url_tabs.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/models.dart';
import '../../core/format/money.dart';
import '../../core/nav/app_scope.dart';
import '../../core/notify/alert_tone.dart';
import '../../core/orders/orders.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/mara_mark.dart';
import '../storefront/shop_skeleton.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'order_walkthrough.dart';
import '../../core/notify/bell_room.dart';
import '../common/keyboard_sheet.dart';

/// The shop's orders: who wants what, and the one button that moves each
/// one along. "À traiter" is what needs an answer or a hand; "Historique"
/// is everything that is done.
///
/// Accepting an order takes its articles off the shelf (101), and a
/// cancellation after that puts them back; refusing moves nothing. Handed
/// over or delivered, the order records its own sale on the server — the
/// till must not ring it again, and the list says so.
class ShopOrdersScreen extends StatefulWidget {
  const ShopOrdersScreen({super.key, required this.org, required this.retail});

  final OrgSummary org;
  final RetailRepository retail;

  @override
  State<ShopOrdersScreen> createState() => _ShopOrdersScreenState();
}

class _ShopOrdersScreenState extends State<ShopOrdersScreen>
    with SingleTickerProviderStateMixin, UrlTabsMixin {
  @override
  List<String> get tabSlugs => const ['a-traiter', 'historique'];

  List<ShopOrder> _orders = const [];

  /// Whether [_orders] has been read once: before that, every order is
  /// "unseen" and none of them is news.
  bool _listed = false;

  /// How long each open order has sat, and which are stuck (073).
  Map<String, OrderClock> _clocks = const {};

  /// Cash couriers hold for the shop (073).
  List<CashOwed> _cash = const [];
  bool _loading = true;
  String? _error;
  String? _busyId;

  /// The clocks move on their own: a quiet re-read every minute.
  Timer? _poll;

  /// A new or moved order arrives as it happens (074).
  void Function()? _unwatch;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _load();
    _unwatch = widget.retail.watchOrders(widget.org.id, () {
      // A burst of changes (the order, then its event) is one re-read.
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 600), () {
        if (mounted && _busyId == null) _load(silent: true);
      });
    });
    _poll = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && !_loading && _busyId == null) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _settle?.cancel();
    _unwatch?.call();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.retail.shopOrders(widget.org.id),
        // The clocks and the cash are lines on the cards, not the page: if
        // they fail, the orders still show.
        widget.retail
            .orderClocks(widget.org.id)
            .catchError((_) => const <String, OrderClock>{}),
        widget.retail
            .cashOwed(widget.org.id)
            .catchError((_) => const <CashOwed>[]),
      ]);
      if (!mounted) return;
      // A quiet re-read that brings an order this list has never shown is
      // a new order: the phone rings as Compte › Préférences says.
      final fresh = results[0] as List<ShopOrder>;
      final seen = {for (final o in _orders) o.id};
      if (silent && _listed && fresh.any((o) => !seen.contains(o.id))) {
        unawaited(AlertTone.ring());
      }
      _listed = true;
      setState(() {
        _orders = fresh;
        _clocks = results[1] as Map<String, OrderClock>;
        _cash = results[2] as List<CashOwed>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (silent) return;
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

  /// One step at a time (115): the order's walkthrough at its stage —
  /// answer, prepare, hand over, paid. The list is read again however it
  /// was left: a stage may have been written before.
  Future<void> _walk(ShopOrder order) async {
    await OrderWalkthrough.open(context,
        org: widget.org, retail: widget.retail, order: order);
    if (mounted) await _load(silent: true);
  }

  /// "Je livre moi-même" (073): nobody took it; the shop carries it.
  Future<void> _deliverSelf(ShopOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Livrer vous-même ?')),
        content: Text(context.tr('La commande de {customerName} passe « en route ». Vous encaissez la livraison ; marquez-la livrée une fois remise.', {'customerName': order.customerName})),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.tr('Retour'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.tr('Je livre moi-même'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyId = order.id);
    try {
      await widget.retail.deliverSelf(order.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthRepository.describeError(error))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _showCash() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CashSheet(cash: _cash, retail: widget.retail),
    );
    if (changed == true) await _load();
  }

  Future<void> _showCouriers() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CouriersSheet(orgId: widget.org.id, retail: widget.retail),
    );
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
    // « Commandes en ligne » hidden by Mara's switchboard (110): the vitrine
    // takes none; those already here are answered as before.
    final closed = AppScope.maybeOf(context)
            ?.session
            .accessFor(widget.org.id)
            .isHidden('online_orders') ??
        false;
    final cash = _cash.isEmpty
        ? null
        : _CashBanner(cash: _cash, onTap: _showCash);

    return Scaffold(
        appBar: AppBar(
          // An association is asked for its services, not sold to (098).
          title: Text(widget.org.profile == 'association' ||
                  widget.org.profile == 'church'
              ? context.tr('Demandes')
              : context.tr('Commandes')),
          actions: [
            if (widget.org.isAdmin)
              IconButton(
                tooltip: context.tr('Mes livreurs'),
                onPressed: _showCouriers,
                icon: const Icon(Icons.sports_motorsports_outlined),
              ),
            IconButton(
              tooltip: context.tr('Actualiser'),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            bellRoom,
          ],
          bottom: TabBar(controller: tabs, tabs: [
            Tab(text: 'À traiter${open.isEmpty ? '' : ' (${open.length})'}'),
            const Tab(text: 'Historique'),
          ]),
        ),
        body: _loading
            ? ShopSkeleton.list()
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
                              child: Text(context.tr('Réessayer'))),
                        ],
                      ),
                    ),
                  )
                : TabBarView(controller: tabs, children: [
                    _List(
                      orders: open,
                      empty: 'Aucune commande à traiter. Les clients '
                          'commandent depuis votre vitrine.',
                      busyId: _busyId,
                      onWalk: _walk,
                      onOpen: _open,
                      onSetPaid: _setPaid,
                      clocks: _clocks,
                      onDeliverSelf: _deliverSelf,
                      header: closed
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                KajCard(
                                  key: const Key('orders-closed-note'),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    leading: const Icon(Icons.storefront_outlined),
                                    title: Text(context.tr('Commandes fermées pour le moment')),
                                    subtitle: Text(context.tr('Mara a fermé les commandes de votre vitrine : vos clients la regardent sans commander. Celles déjà reçues restent ici.')),
                                  ),
                                ),
                                ?cash,
                              ],
                            )
                          : cash,
                      // 101: the order books its own sale when it is done.
                      note: context.tr('La vente est enregistrée quand la commande est remise ou livrée — ne la passez pas à la caisse'),
                    ),
                    _List(
                      orders: past,
                      empty: 'Aucune commande passée pour le moment.',
                      busyId: _busyId,
                      onWalk: _walk,
                      onOpen: _open,
                      onSetPaid: _setPaid,
                      clocks: _clocks,
                      onDeliverSelf: _deliverSelf,
                    ),
                  ]),
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.orders,
    required this.empty,
    required this.busyId,
    required this.onWalk,
    required this.onOpen,
    required this.onSetPaid,
    this.clocks = const {},
    this.onDeliverSelf,
    this.header,
    this.note,
  });

  /// One line above the cards, when there are any.
  final String? note;

  final Map<String, OrderClock> clocks;
  final Future<void> Function(ShopOrder)? onDeliverSelf;

  /// Above the cards: the cash couriers hold (073).
  final Widget? header;

  final List<ShopOrder> orders;
  final String empty;
  final String? busyId;
  final Future<void> Function(ShopOrder) onWalk;
  final Future<void> Function(String) onOpen;
  final Future<void> Function(ShopOrder, bool) onSetPaid;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty && header == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(empty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        ?header,
        if (note != null && orders.isNotEmpty)
          Padding(
            key: const Key('orders-sale-note'),
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.point_of_sale_outlined,
                    size: 20, color: maraBrown),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(note!,
                      style: const TextStyle(color: maraDeep, fontSize: 13)),
                ),
              ],
            ),
          ),
        for (final o in orders)
          _OrderCard(
            order: o,
            busy: busyId == o.id,
            onWalk: onWalk,
            onOpen: onOpen,
            onSetPaid: onSetPaid,
            clock: clocks[o.id],
            onDeliverSelf: onDeliverSelf,
          ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.busy,
    required this.onWalk,
    required this.onOpen,
    required this.onSetPaid,
    this.clock,
    this.onDeliverSelf,
  });

  final OrderClock? clock;
  final Future<void> Function(ShopOrder)? onDeliverSelf;

  final ShopOrder order;
  final bool busy;
  final Future<void> Function(ShopOrder) onWalk;
  final Future<void> Function(String) onOpen;
  final Future<void> Function(ShopOrder, bool) onSetPaid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(order.currency);
    final when = DateFormat('EEE d MMM, HH:mm', 'fr_FR').format(order.createdAt);
    final phone = (order.phone ?? '').trim();
    final whatsapp = whatsappUrl(order.phone);
    final action = stageAction(order);

    return KajCard(
      child: InkWell(
        key: Key('order-card-${order.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: action.isEmpty || busy ? null : () => onWalk(order),
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
                  label: Text(context.tr(
                      orderStatusLabel(order.status, booking: order.isBooking))),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
                '$when · ${context.tr(fulfilmentLabel(order.fulfilment, appointment: order.isBooking))} · '
                '${paymentLabel(order.paymentMethod)}'
                '${order.isPaid ? context.tr(' · payé') : ''}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            // The state's clock (073): "Prête depuis 25 min".
            if (order.isOpen && clock?.since != null)
              Text(
                  '${context.tr(orderStatusLabel(order.status, booking: order.isBooking))} ${clock!.sinceLabel()}'
                  '${clock!.selfDelivered ? context.tr(' · vous livrez') : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: clock!.stuck
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant)),
            if (!order.isOpen && (clock?.outcome ?? '').isNotEmpty)
              Text('Livraison échouée : ${deliveryOutcomeLabel(clock!.outcome)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.error)),
            if (clock?.stuck == true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        switch (order.status) {
                          'pending' => 'Le client attend votre réponse.',
                          'ready' => "Aucun livreur ne l'a prise. Appelez un "
                              'de vos livreurs, ou livrez-la vous-même.',
                          _ => 'Cette livraison est en route depuis longtemps : '
                              'appelez le livreur.',
                        },
                        style: TextStyle(
                            color: theme.colorScheme.onErrorContainer)),
                    if (order.status == 'ready' &&
                        order.fulfilment == 'delivery' &&
                        onDeliverSelf != null) ...[
                      const SizedBox(height: 6),
                      FilledButton.tonalIcon(
                        onPressed: busy ? null : () => onDeliverSelf!(order),
                        icon: const Icon(Icons.directions_bike_outlined,
                            size: 18),
                        label: Text(context.tr('Je livre moi-même')),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(phone, style: theme.textTheme.bodyMedium),
                  IconButton(
                    tooltip: context.tr('Appeler'),
                    icon: const Icon(Icons.call_outlined, size: 20),
                    onPressed: () => onOpen('tel:$phone'),
                  ),
                  if (whatsapp != null)
                    IconButton(
                      tooltip: context.tr('WhatsApp'),
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
                    // A service booked (098), not goods to prepare.
                    if (l.isService)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          key: const Key('order-line-service'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: maraCaramel.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(context.tr('Service'),
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
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
                    child: Text(context.tr('Total'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600))),
                Text(money.format(order.total),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            // What the courier collects for the run (061): the shop sees it
            // so a "why did he ask for 800?" has an answer at the counter.
            if (order.fulfilment == 'delivery')
              Text(
                  order.deliveryFee == null
                      ? context.tr('Livraison : prix à convenir avec le livreur')
                      : 'Livraison : ${money.format(order.deliveryFee!)} '
                          'au livreur, à la porte',
                  style: theme.textTheme.bodySmall),
            if ((order.address ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(context.tr('Livraison : {address}', {'address': order.address}),
                        style: theme.textTheme.bodySmall),
                  ),
                  if (order.hasDropPin)
                    TextButton(
                      onPressed: () => onOpen(
                          directionsUrl(order.dropLat!, order.dropLng!)),
                      child: Text(context.tr('Itinéraire')),
                    ),
                ],
              ),
            ],
            if ((order.courierName ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(context.tr('Livreur : {courierName}', {'courierName': order.courierName}),
                  style: theme.textTheme.bodySmall),
            ],
            if ((order.note ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(context.tr('Note : {note}', {'note': order.note}), style: theme.textTheme.bodySmall),
            ],
            if (action.isNotEmpty || order.isOpen || order.isPaid) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // The order's next step, one screen at a time (115).
                  if (action.isNotEmpty)
                    FilledButton.icon(
                      key: Key('order-walk-${order.id}'),
                      onPressed: busy ? null : () => onWalk(order),
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: Text(context.tr(action)),
                    ),
                  // The money's word lives beside the state's: the shop
                  // confirms a payment arrived, or unsays a mis-tap.
                  if (!order.isPaid && order.isOpen)
                    OutlinedButton.icon(
                      onPressed:
                          busy ? null : () => onSetPaid(order, true),
                      icon: const Icon(Icons.price_check_outlined, size: 18),
                      label: Text(context.tr('Paiement reçu')),
                    )
                  else if (order.isPaid)
                    TextButton(
                      onPressed:
                          busy ? null : () => onSetPaid(order, false),
                      child: Text(context.tr('Annuler le paiement')),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}


/// "Argent chez les livreurs" (073): one line above the orders.
class _CashBanner extends StatelessWidget {
  const _CashBanner({required this.cash, required this.onTap});

  final List<CashOwed> cash;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = cash.fold<double>(0, (s, c) => s + c.total);
    return KajCard(
      color: theme.colorScheme.tertiaryContainer,
      child: ListTile(
        leading: const Icon(Icons.payments_outlined),
        title: Text(
            'Argent chez les livreurs : ${moneyFormat(cash.first.currency).format(total)}'),
        subtitle: Text('${cash.length} commande${cash.length > 1 ? 's' : ''} '
            'payée${cash.length > 1 ? 's' : ''} en espèces à la porte'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _CashSheet extends StatefulWidget {
  const _CashSheet({required this.cash, required this.retail});

  final List<CashOwed> cash;
  final RetailRepository retail;

  @override
  State<_CashSheet> createState() => _CashSheetState();
}

class _CashSheetState extends State<_CashSheet> {
  late final _left = [...widget.cash];
  String? _busy;
  bool _changed = false;

  Future<void> _received(CashOwed c) async {
    setState(() => _busy = c.orderId);
    try {
      await widget.retail.confirmCashReceived(c.orderId);
      setState(() {
        _left.remove(c);
        _changed = true;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthRepository.describeError(error))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = DateFormat('d MMM, HH:mm', 'fr_FR');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('Argent chez les livreurs'),
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(context.tr('Touchez « Reçu » quand le livreur vous a remis l\'argent de la commande.'),
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              if (_left.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(context.tr('Tout est réglé.'), textAlign: TextAlign.center),
                ),
              for (final c in _left)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${c.courierName} · '
                      '${moneyFormat(c.currency).format(c.total)}'),
                  subtitle: Text([
                    if ((c.customerName ?? '').isNotEmpty) c.customerName!,
                    if (c.deliveredAt != null) day.format(c.deliveredAt!),
                    if ((c.courierPhone ?? '').isNotEmpty) c.courierPhone!,
                  ].join(' · ')),
                  trailing: FilledButton.tonal(
                    onPressed: _busy != null ? null : () => _received(c),
                    child: Text(context.tr('Reçu')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shop's own couriers (073): its ready orders are theirs for the first
/// minutes, before the street's.
class _CouriersSheet extends StatefulWidget {
  const _CouriersSheet({required this.orgId, required this.retail});

  final String orgId;
  final RetailRepository retail;

  @override
  State<_CouriersSheet> createState() => _CouriersSheetState();
}

class _CouriersSheetState extends State<_CouriersSheet> {
  final _phone = TextEditingController();
  List<OrgCourier> _list = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await widget.retail.orgCouriers(widget.orgId);
      if (mounted) setState(() => _list = list);
    } catch (_) {}
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.retail.addOrgCourier(widget.orgId, _phone.text);
      _phone.clear();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = AuthRepository.describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(OrgCourier c) async {
    setState(() => _busy = true);
    try {
      await widget.retail.removeOrgCourier(widget.orgId, c.userId);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = AuthRepository.describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyboardSheet(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      // The fields scroll; the button stays above the keyboard (A6).
      footer: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phone,
                    enabled: !_busy,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: context.tr('Numéro du livreur'),
                      hintText: context.tr('Inscrit et validé comme livreur Mara'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _add,
                  child: Text(context.tr('Ajouter')),
                ),
              ],
            ),
      children: [
            Text(context.tr('Mes livreurs'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
                context.tr('Vos commandes prêtes leur sont proposées en premier, seuls, pendant 10 minutes ; ensuite à tous les livreurs Mara.'),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final c in _list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sports_motorsports_outlined),
                title: Text(c.name),
                subtitle: c.phone == null ? null : Text(c.phone!),
                trailing: IconButton(
                  tooltip: context.tr('Retirer {name}', {'name': c.name}),
                  icon: const Icon(Icons.close),
                  onPressed: _busy ? null : () => _remove(c),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
      ],
    );
  }
}
