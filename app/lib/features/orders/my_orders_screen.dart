import 'dart:async';

import '../../core/theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/orders/booking.dart';
import '../../core/orders/orders.dart';
import '../../core/shopper/shopper_repository.dart';
import '../../core/storefront/storefront_repository.dart';
import '../shopper/reorder.dart';
import '../storefront/shop_skeleton.dart';
import '../pay/wave_buttons.dart';
import 'booking_words.dart';
import 'order_tracking_panel.dart';
import '../storefront/shop_style.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// A customer's orders: what they asked for, where each one stands, and
/// the one thing they can still do about a pending one — withdraw it.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({
    super.key,
    required this.storefront,
    this.shopper,
    this.bookingsOnly = false,
    this.focusId,
  });

  final StorefrontRepository storefront;

  /// The order a notification opened (125: `?commande=<id>`): brought into
  /// view and outlined once the list is read.
  final String? focusId;

  /// « Recommander » (113) on a finished order. Null: not offered.
  final ShopperRepository? shopper;

  /// « Mes réservations » (113): the bookings of services only (098).
  final bool bookingsOnly;

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
    // Called from a timer and after awaits: the page may be gone (SH-10).
    if (!mounted) return;
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
      if (!silent) _bringFocusIntoView();
    } catch (_) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _error = context.tr('Vos commandes n\'ont pas pu être chargées. Vérifiez le réseau.');
        _loading = false;
      });
    }
  }

  final _focusKey = GlobalKey();

  void _bringFocusIntoView() {
    if (widget.focusId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = _focusKey.currentContext;
      if (at != null && at.mounted) {
        Scrollable.ensureVisible(at, duration: KajMotion.quick, alignment: 0.1);
      }
    });
  }

  /// « Accepter 11:00 » (125): the business's other time becomes the
  /// booking's, confirmed.
  Future<void> _acceptTime(CustomerOrder order) async {
    setState(() => _busyId = order.id);
    try {
      await widget.storefront.acceptBookingTime(order.id);
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('Rendez-vous confirmé : {when}',
              {'when': bookingWhen(order.proposedFor!, context.trLanguage)}))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
      await _load(silent: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
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
          content: Text(context.tr('Dans votre application Wave, envoyez {amount} au marchand : {raw}', {
            'amount': moneyFormat(order.currency).format(order.total),
            'raw': raw,
          })),
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
    final booking = order.hasSlot;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(booking
            ? context.tr('Annuler ce rendez-vous ?')
            : context.tr('Annuler cette commande ?')),
        content: Text(booking
            ? context.tr('{shopName} en sera prévenu.', {'shopName': order.shopName})
            : context.tr('{shopName} ne la verra plus.', {'shopName': order.shopName})),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.tr('Garder'))),
          FilledButton(
              key: const Key('order-cancel-yes'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(booking
                  ? context.tr('Annuler le rendez-vous')
                  : context.tr('Annuler la commande'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyId = order.id);
    try {
      await widget.storefront.cancelOrder(order.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      // 134: a booking past its cutoff, an order already paid, a Wave
      // payment still running — each says so.
      final words = '$error';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(booking && words.contains('Trop tard')
              ? context.tr('Trop tard pour annuler — appelez la boutique')
              : words.contains('déjà payé')
                  ? (booking
                      ? context.tr('Ce rendez-vous est déjà payé : appelez la boutique pour l\'annuler.')
                      : context.tr('Cette commande est déjà payée : appelez la boutique pour l\'annuler.'))
                  : words.contains('paiement Wave est en cours')
                      ? context.tr('Un paiement Wave est en cours : attendez quelques minutes ou appelez la boutique.')
                      : context.tr('Trop tard : la boutique a déjà répondu.'))));
      await _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// « Recommander » (113): the vitrine's basket filled again with what it
  /// still has of this order, and the vitrine opened on it.
  Future<void> _again(CustomerOrder order) async {
    final shopper = widget.shopper;
    final db = AppScope.maybeOf(context)?.db;
    if (shopper == null || db == null) return;
    setState(() => _busyId = order.id);
    try {
      await reorderInto(context,
          shopper: shopper, db: db, orderId: order.id, booking: order.isBooking);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.bookingsOnly
        ? _orders.where((o) => o.isBooking).toList()
        : _orders;
    final open = mine.where((o) => o.isOpen).toList();
    final past = mine.where((o) => !o.isOpen).toList();
    final again = widget.shopper != null && widget.shopper!.isConfigured;

    return ShopPage(
      title: widget.bookingsOnly ? context.tr('Mes réservations') : context.tr('Mes commandes'),
      announcements: ShopPage.street,
      leading: IconButton(
        tooltip: widget.bookingsOnly ? context.tr('Retour') : context.tr('Les vitrines'),
        icon: const Icon(Icons.arrow_back),
        onPressed: () => widget.bookingsOnly && context.canPop()
            ? context.pop()
            : context.go(Routes.directory),
      ),
      body: _loading
          ? ShopSkeleton.list()
          : _error != null
              ? ShopNotice(
                  text: _error!,
                  action: OutlinedButton(
                      onPressed: _load, child: Text(context.tr('Réessayer'))),
                )
              : mine.isEmpty
                  ? ShopNotice(
                      text: widget.bookingsOnly
                          ? context.tr('Vous n\'avez pas encore réservé de service.')
                          : context.tr('Vous n\'avez pas encore commandé.'),
                      action: FilledButton(
                        onPressed: () => context.go(Routes.directory),
                        child: Text(context.tr('Voir les vitrines')),
                      ),
                    )
                  : ShopScroll(
                      footer: const ShopWidth(child: ShopFooter()),
                      children: [
                        ShopWidth(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 28),
                              if (open.isNotEmpty) ...[
                                ShopSectionLabel(context.tr('En cours'),
                                    note: '${open.length}'),
                                const SizedBox(height: 12),
                                for (final (i, o) in open.indexed)
                                  ScrollReveal(
                                  delay: KajMotion.stagger(i),
                                  child: _OrderCard(
                                    key: o.id == widget.focusId ? _focusKey : null,
                                    focused: o.id == widget.focusId,
                                    order: o,
                                    busy: _busyId == o.id,
                                    // 134: a confirmed booking too, until
                                    // its cutoff (the card asks the server).
                                    // An order of goods already paid: the
                                    // shop gives the money back, so no
                                    // button (a booking's area says « call »).
                                    onCancel: (o.status == 'pending' && (o.hasSlot || !o.isPaid)) ||
                                            (o.hasSlot && o.status == 'accepted')
                                        ? () => _cancel(o)
                                        : null,
                                    cancelTerms: o.hasSlot && !o.awaitsCustomer &&
                                            (o.status == 'pending' || o.status == 'accepted')
                                        ? () => widget.storefront.bookingCancelTerms(o.id)
                                        : null,
                                    onCall: _call,
                                    onAcceptTime: o.awaitsCustomer
                                        ? () => _acceptTime(o)
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
                                ShopSectionLabel(context.tr('Passées'),
                                    note: '${past.length}'),
                                const SizedBox(height: 12),
                                for (final (i, o) in past.indexed)
                                  ScrollReveal(
                                    delay: KajMotion.stagger(i),
                                    child: _OrderCard(
                                      key: o.id == widget.focusId ? _focusKey : null,
                                      focused: o.id == widget.focusId,
                                      order: o,
                                      busy: _busyId == o.id,
                                      onAgain: again ? () => _again(o) : null,
                                    ),
                                  ),
                              ],
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
    super.key,
    required this.order,
    required this.busy,
    this.focused = false,
    this.onAcceptTime,
    this.onCancel,
    this.onPay,
    this.tracking,
    this.wave,
    this.onAgain,
    this.cancelTerms,
    this.onCall,
  });

  /// Until when a booking may be cancelled (134). Null: not a booking that
  /// can be, or asked of nobody.
  final Future<BookingCancelTerms?> Function()? cancelTerms;

  /// Opens tel: / WhatsApp for « appelez la boutique ».
  final Future<void> Function(String url)? onCall;

  /// « Recommander » / « Réserver à nouveau » (113), on a finished order.
  final VoidCallback? onAgain;

  /// « Payer avec Wave / par carte » through Kaj (076). When it is not
  /// offered it draws the shop's own link instead ([onPay]).
  final Widget? wave;

  final CustomerOrder order;
  final bool busy;

  /// The order a notification opened: outlined.
  final bool focused;

  /// « Accepter 11:00 »: the business proposed another time (125).
  final VoidCallback? onAcceptTime;

  /// The open order's timeline (073).
  final Widget? tracking;
  final VoidCallback? onCancel;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(order.currency);
    final when = DateFormat('d MMM, HH:mm', intlLocale()).format(order.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(
            color: focused ? ShopStyle.ink : ShopStyle.line, width: focused ? 2 : 1),
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
              _StatusChip(
                status: order.status,
                booking: order.isBooking,
                // A booking with its slot (125): where it stands, in its words.
                label: order.hasSlot
                    ? bookingStateWord(context,
                        bookingStateOf(order.status, proposedFor: order.proposedFor))
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
              '$when · ${context.tr(fulfilmentLabel(order.fulfilment, appointment: order.isBooking))} · '
              '${order.isPaid ? context.tr('Payé') : context.tr(paymentLabel(order.paymentMethod))}',
              style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
          if (order.hasSlot) ...[
            const SizedBox(height: 12),
            _Appointment(order: order, busy: busy, onAccept: onAcceptTime, onCancel: onCancel),
          ],
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
                // Wraps under its label rather than overflowing (SH-7).
                Flexible(
                  child: Text(
                      order.deliveryFee == null
                          ? context.tr('à discuter')
                          : context.tr('{fee} au livreur', {'fee': money.format(order.deliveryFee!)}),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 14, color: ShopStyle.mist)),
                ),
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
                          context.tr('Payer avec Wave · {amount}', {
                            'amount': moneyFormat(order.currency).format(order.total),
                          })),
                    ),
            ),
          ],
          if (onAgain != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: Key('again-${order.id}'),
              onPressed: busy ? null : onAgain,
              icon: busy
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.replay, size: 18),
              label: Text(order.isBooking
                  ? context.tr('Réserver à nouveau')
                  : context.tr('Recommander')),
            ),
          ],
          // A booking's cancel (134): until its cutoff, then « appelez ».
          if (cancelTerms != null && onCancel != null)
            BookingCancelArea(
              key: ValueKey('cancel-area-${order.id}-${order.status}'),
              order: order,
              busy: busy,
              terms: cancelTerms!,
              onCancel: onCancel!,
              onCall: onCall,
            )
          // A proposal is answered in its own box (« Accepter » / « Annuler »).
          else if (onCancel != null && onAcceptTime == null && order.status == 'pending') ...[
            const SizedBox(height: 12),
            OutlinedButton(
              key: Key('order-cancel-${order.id}'),
              onPressed: busy ? null : onCancel,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(order.hasSlot
                      ? context.tr('Annuler le rendez-vous')
                      : context.tr('Annuler la commande')),
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
  const _StatusChip({required this.status, this.booking = false, this.label});

  final String status;

  /// Said instead of the status's word (a booking's state, 125).
  final String? label;

  /// A booking of services (098): « Terminée », not « Récupérée ».
  final bool booking;

  @override
  Widget build(BuildContext context) {
    final open = orderIsOpen(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: open ? ShopStyle.ink : ShopStyle.stone,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label ?? context.tr(orderStatusLabel(status, booking: booking)),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: open ? ShopStyle.paper : ShopStyle.mist)),
    );
  }
}


/// « Rendez-vous » (125): the day and the time, and — when the business
/// proposed another — that time with « Accepter 11:00 » / « Annuler ».
class _Appointment extends StatelessWidget {
  const _Appointment({
    required this.order,
    required this.busy,
    this.onAccept,
    this.onCancel,
  });

  final CustomerOrder order;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final lang = context.trLanguage;
    final proposed = order.awaitsCustomer ? order.proposedFor : null;
    final state = bookingStateOf(order.status, proposedFor: order.proposedFor);
    final over = state == BookingState.declined || state == BookingState.cancelled;
    return Container(
      key: Key('appointment-${order.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ShopStyle.stone,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_outlined, size: 18, color: ShopStyle.ink),
              const SizedBox(width: 8),
              Text(context.tr('Rendez-vous'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: ShopStyle.mist)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            bookingWhen(order.bookedFor!, lang),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: proposed != null || over ? ShopStyle.mist : ShopStyle.ink,
              decoration: proposed != null ? TextDecoration.lineThrough : null,
            ),
          ),
          if (proposed != null) ...[
            const SizedBox(height: 8),
            Text(
              context.tr('{shop} propose une autre heure :', {'shop': order.shopName}),
              style: const TextStyle(fontSize: 14, color: ShopStyle.ink),
            ),
            Text(
              bookingWhen(proposed, lang),
              key: Key('appointment-proposed-${order.id}'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: ShopStyle.ink),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton(
                  key: Key('accept-time-${order.id}'),
                  onPressed: busy ? null : onAccept,
                  child: Text(context.tr('Accepter {time}', {'time': bookingTimeLabel(proposed)})),
                ),
                OutlinedButton(
                  key: Key('refuse-time-${order.id}'),
                  onPressed: busy ? null : onCancel,
                  child: Text(context.tr('Annuler')),
                ),
              ],
            ),
          ] else if (state == BookingState.requested) ...[
            const SizedBox(height: 4),
            Text(
              context.tr('En attente de la réponse de {shop}', {'shop': order.shopName}),
              style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
            ),
          ],
        ],
      ),
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


/// « Annuler le rendez-vous » until the cutoff (134) — booked_for minus the
/// platform's hours (2) — and after it « Trop tard pour annuler — appelez
/// la boutique » with a call and a WhatsApp button. On a database without
/// 134 (no terms) a requested booking keeps 125's cancel and a confirmed
/// one none, as before.
class BookingCancelArea extends StatefulWidget {
  const BookingCancelArea({
    super.key,
    required this.order,
    required this.busy,
    required this.terms,
    required this.onCancel,
    this.onCall,
    this.now,
  });

  final CustomerOrder order;
  final bool busy;
  final Future<BookingCancelTerms?> Function() terms;
  final VoidCallback onCancel;
  final Future<void> Function(String url)? onCall;

  /// The clock (a test sets it).
  final DateTime Function()? now;

  @override
  State<BookingCancelArea> createState() => _BookingCancelAreaState();
}

class _BookingCancelAreaState extends State<BookingCancelArea> {
  BookingCancelTerms? _terms;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    widget.terms().then((t) {
      if (mounted) setState(() { _terms = t; _asked = true; });
    }).catchError((_) {
      if (mounted) setState(() => _asked = true);
    });
  }

  Widget _cancelButton(BuildContext context, {String? note}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          OutlinedButton(
            key: Key('order-cancel-${widget.order.id}'),
            onPressed: widget.busy ? null : widget.onCancel,
            child: widget.busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('Annuler le rendez-vous')),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note,
                key: Key('order-cancel-until-${widget.order.id}'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: ShopStyle.mist)),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    if (!_asked) return const SizedBox.shrink();
    final t = _terms;
    if (t == null) {
      // Before 134: 125's rule — a request only.
      return order.status == 'pending' ? _cancelButton(context) : const SizedBox.shrink();
    }
    final now = (widget.now ?? DateTime.now)();
    // A request nobody answered whose time has passed: still withdrawn
    // (134 as reviewed), with no « until » to say.
    final slot = order.bookedFor;
    final stale = t.canCancel && order.status == 'pending' && slot != null && !now.isBefore(slot);
    if (t.openAt(now) || stale) {
      final until = t.until;
      return _cancelButton(context,
          note: until == null || stale
              ? null
              : context.tr('Annulable jusqu\'à {when}',
                  {'when': bookingWhen(until, context.trLanguage, short: true)}));
    }
    final phone = t.phone;
    return Container(
      key: Key('order-too-late-${order.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: ShopStyle.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              t.paidOnline
                  ? context.tr('Ce rendez-vous est déjà payé : appelez la boutique pour l\'annuler.')
                  : context.tr('Trop tard pour annuler — appelez la boutique'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ShopStyle.ink)),
          if (!t.paidOnline) ...[
            const SizedBox(height: 2),
            Text(
                context.tr('Un rendez-vous s\'annule jusqu\'à {hours} h avant.', {'hours': '${t.hours}'}),
                style: const TextStyle(fontSize: 12, color: ShopStyle.mist)),
          ],
          if (phone != null && widget.onCall != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.icon(
                  key: Key('order-call-${order.id}'),
                  onPressed: () => widget.onCall!('tel:$phone'),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: Text(context.tr('Appeler')),
                ),
                OutlinedButton.icon(
                  key: Key('order-whatsapp-${order.id}'),
                  onPressed: () => widget.onCall!(whatsappTo(phone)),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text('WhatsApp'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
