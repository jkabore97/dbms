import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/orders/orders.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/storefront/storefront_repository.dart' show whatsappUrl, directionsUrl;
import '../../core/theme/mara_mark.dart';
import '../common/step_flow.dart';

/// Where an order is in the walkthrough, from its status.
enum OrderStage {
  /// pending: see it, accept or refuse (with a reason).
  answer,

  /// accepted goods: tick each article, then « Prête ».
  prepare,

  /// ready, on its way, or a booking accepted: handed over / delivered /
  /// the service done, then the payment.
  finish,

  /// Nothing left for the shop to do.
  none,
}

OrderStage stageOf(ShopOrder o) => switch (o.status) {
      'pending' => OrderStage.answer,
      'accepted' => o.isBooking ? OrderStage.finish : OrderStage.prepare,
      'ready' || 'in_transit' => OrderStage.finish,
      _ => OrderStage.none,
    };

/// The word on the card's button that opens the walkthrough at [o]'s stage.
String stageAction(ShopOrder o) => switch (stageOf(o)) {
      OrderStage.answer => 'Répondre',
      OrderStage.prepare => 'Préparer',
      OrderStage.finish => o.isBooking
          ? 'Terminer'
          : o.status == 'in_transit'
              ? 'Confirmer la livraison'
              : o.fulfilment == 'delivery'
                  ? 'Livrer'
                  : 'Remettre au client',
      OrderStage.none => '',
    };

/// « Commandes », one step at a time (115) — the same for a shop, a farm
/// and an association's bookings: see it → accept, or refuse with a reason
/// → prepare (tick each article) → « Prête » → handed over or delivered →
/// the payment received. Each stage writes through the functions the
/// order card's buttons called (055/073/099's decide_order, 073's
/// shop_deliver_self, 057's set_order_paid) and, for a refusal with its
/// reason, 115's refuse_order (decide_order without it before 115); the customer is told by the
/// server at each move (builder N's notifications). The order books its
/// own sale when it is handed over or delivered (101): nothing here rings
/// the till.
class OrderWalkthrough extends StatefulWidget {
  const OrderWalkthrough({
    super.key,
    required this.org,
    required this.retail,
    required this.order,
    this.store,
  });

  final OrgSummary org;
  final RetailRepository retail;
  final ShopOrder order;
  final FlowStore? store;

  /// Opens the walkthrough over the orders. The list reloads afterwards
  /// whatever it closed with: a stage may have been written before leaving.
  static Future<bool?> open(BuildContext context,
          {required OrgSummary org,
          required RetailRepository retail,
          required ShopOrder order}) =>
      StepFlow.push(
          context, OrderWalkthrough(org: org, retail: retail, order: order));

  @override
  State<OrderWalkthrough> createState() => _OrderWalkthroughState();
}

/// Why a shop says no — one tap, or its own words.
const _refuseReasons = [
  'Plus en stock',
  'Fermé en ce moment',
  'Trop loin pour livrer',
];
const _bookingReasons = [
  'Pas de place à cette heure',
  'Fermé en ce moment',
];

class _OrderWalkthroughState extends State<OrderWalkthrough> {
  final _flow = StepFlowController();
  late ShopOrder _order = widget.order;
  late OrderStage _stage = stageOf(widget.order);

  // answer
  String? _decision; // 'accepted' | 'refused'
  String? _reason; // one of the reasons, or 'other'
  final _otherReason = TextEditingController();

  // prepare
  final Set<int> _ticked = {};

  // finish
  String? _handover; // 'picked_up' | 'delivered' | 'self'
  bool? _paid;

  /// The payment could not be noted after the order was done.
  bool _paidFailed = false;

  @override
  void dispose() {
    _otherReason.dispose();
    super.dispose();
  }

  bool get _booking => _order.isBooking;
  String get _name => _order.customerName;

  List<int> get _goods => [
        for (var i = 0; i < _order.lines.length; i++)
          if (!_order.lines[i].isService) i,
      ];

  String? get _reasonText => _reason == null
      ? null
      : _reason == 'other'
          ? _otherReason.text.trim()
          : context.tr(_reason!);

  List<FlowOption<String>> get _handoverOptions {
    if (_booking) {
      return [
        FlowOption('picked_up', context.tr('Le service est rendu'),
            icon: Icons.check_circle_outline),
      ];
    }
    if (_order.status == 'in_transit') {
      return [
        FlowOption('delivered', context.tr('Livrée au client'),
            icon: Icons.home_outlined),
      ];
    }
    if (_order.fulfilment == 'delivery') {
      return [
        FlowOption('delivered', context.tr('Livrée au client'),
            icon: Icons.home_outlined,
            detail: context.tr('Le livreur ou vous l\'avez remise')),
        FlowOption('self', context.tr('Je la livre moi-même'),
            icon: Icons.directions_bike_outlined,
            detail: context.tr('Elle passe « en route » ; vous encaissez la livraison')),
      ];
    }
    return [
      FlowOption('picked_up', context.tr('Remise au client'),
          icon: Icons.storefront_outlined,
          detail: context.tr('{name} est venu la chercher', {'name': _name})),
    ];
  }

  void _toStage(OrderStage stage) {
    setState(() {
      _stage = stage;
      _decision = null;
      _reason = null;
      _otherReason.clear();
      _ticked.clear();
      _handover = null;
      _paid = null;
      _paidFailed = false;
    });
    _flow.restart();
  }

  Future<bool> _save() async {
    // The handover read before any await: it names the move.
    final handover = _handover ?? _handoverOptions.first.value;
    switch (_stage) {
      case OrderStage.answer:
        if (_decision == 'refused') {
          await widget.retail.refuseOrder(_order.id, _reasonText ?? '');
          _order = _with('refused');
        } else {
          await widget.retail.decideOrder(_order.id, 'accepted');
          _order = _with('accepted');
        }
      case OrderStage.prepare:
        await widget.retail.decideOrder(_order.id, 'ready');
        _order = _with('ready');
      case OrderStage.finish:
        if (handover == 'self') {
          await widget.retail.deliverSelf(_order.id);
          _order = _with('in_transit', self: true);
          break;
        }
        await widget.retail.decideOrder(_order.id, handover);
        _order = _with(handover);
        _paidFailed = false;
        if (_paid == true) {
          try {
            await widget.retail.setOrderPaid(_order.id, true);
          } catch (_) {
            // The order is done; « Paiement reçu » stays on its card.
            _paidFailed = true;
          }
        }
      case OrderStage.none:
        return false;
    }
    return true;
  }

  /// Delivering it oneself was the last move.
  bool _selfDelivering = false;

  /// « C'est fait »'s line and the one under it, from where the order is now.
  (String, String?) _done(BuildContext context) {
    final n = {'name': _name};
    return switch (_order.status) {
      'refused' => (
          _booking
              ? context.tr('Réservation refusée. {name} est prévenu.', n)
              : context.tr('Commande refusée. {name} est prévenu.', n),
          null
        ),
      'accepted' => (
          _booking
              ? context.tr('Réservation confirmée. {name} est prévenu.', n)
              : context.tr('Commande acceptée. {name} est prévenu.', n),
          _booking ? null : context.tr('Ses articles sont retirés de votre stock.')
        ),
      'ready' => (
          context.tr('Prête. {name} est prévenu.', n),
          _order.fulfilment == 'delivery'
              ? context.tr('Les livreurs la voient maintenant. Vous pouvez aussi la livrer vous-même.')
              : context.tr('Quand {name} vient la chercher, touchez « Remise au client ».', n)
        ),
      'in_transit' when _selfDelivering => (
          context.tr('En route : vous livrez {name}.', n),
          context.tr('Une fois remise, touchez « Confirmer la livraison ».')
        ),
      _ => (
          _booking
              ? context.tr('Réservation terminée.')
              : context.tr('Commande terminée.'),
          _booking
              ? null
              : context.tr('La vente est enregistrée toute seule — ne la passez pas à la caisse.')
        ),
    };
  }

  ShopOrder _with(String status, {bool self = false}) {
    _selfDelivering = self;
    return ShopOrder(
        id: _order.id,
        customerName: _order.customerName,
        status: status,
        fulfilment: _order.fulfilment,
        total: _order.total,
        currency: _order.currency,
        createdAt: _order.createdAt,
        lines: _order.lines,
        phone: _order.phone,
        note: _order.note,
        address: _order.address,
        courierName: _order.courierName,
        paymentMethod: _order.paymentMethod,
        paidAt: _paid == true ? DateTime.now() : _order.paidAt,
        dropLat: _order.dropLat,
        dropLng: _order.dropLng,
        deliveryFee: _order.deliveryFee,
      );
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.tr('Annuler cette commande ?')),
        content: Text(context.tr('{customerName} en sera informé.', {'customerName': _name})),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: Text(context.tr('Retour'))),
          FilledButton(
              key: const Key('order-cancel-confirm'),
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(context.tr('Annuler'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await widget.retail.decideOrder(_order.id, 'cancelled');
      nav.pop(true);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(_order.currency);
    return StepFlow(
        title: _booking ? context.tr('Réservation') : context.tr('Commande'),
        controller: _flow,
        store: widget.store,
        isDirty: () => _stage == OrderStage.prepare && _ticked.isNotEmpty,
        draft: _stage == OrderStage.prepare
            ? FlowDraft(
                key: 'order:${_order.id}',
                save: () => {'ticked': _ticked.toList()},
                restore: (a) => setState(() {
                  _ticked
                    ..clear()
                    ..addAll([
                      for (final i in (a['ticked'] as List? ?? const []))
                        if (i is int) i,
                    ]);
                }),
              )
            : null,
        saveLabel: switch (_stage) {
          OrderStage.answer =>
            context.tr(orderActionLabel(_decision ?? 'accepted')),
          OrderStage.prepare => context.tr('Prête'),
          OrderStage.finish => context.tr('Enregistrer'),
          OrderStage.none => null,
        },
        steps: switch (_stage) {
          OrderStage.answer => [
              FlowStep(
                id: 'see',
                title: _booking
                    ? context.tr('{name} demande un rendez-vous', {'name': _name})
                    : context.tr('{name} commande', {'name': _name}),
                isValid: () => _decision != null,
                builder: (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OrderSummaryCard(order: _order, onOpen: _open),
                    const SizedBox(height: 20),
                    FlowChoice<String>(
                      options: [
                        FlowOption('accepted',
                            _booking
                                ? context.tr('Accepter le rendez-vous')
                                : context.tr('Accepter la commande'),
                            icon: Icons.check),
                        FlowOption('refused', context.tr('Refuser'),
                            icon: Icons.close),
                      ],
                      value: _decision,
                      onChanged: (v) => setState(() => _decision = v),
                    ),
                  ],
                ),
              ),
              FlowStep(
                id: 'reason',
                title: context.tr('Pourquoi refuser ?'),
                help: context.tr('{name} lira cette raison.', {'name': _name}),
                shown: () => _decision == 'refused',
                isValid: () =>
                    _reason != null &&
                    (_reason != 'other' || _otherReason.text.trim().isNotEmpty),
                builder: (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FlowChoice<String>(
                      options: [
                        for (final r in _booking ? _bookingReasons : _refuseReasons)
                          FlowOption(r, context.tr(r)),
                        FlowOption('other', context.tr('Autre raison')),
                      ],
                      value: _reason,
                      onChanged: (v) => setState(() => _reason = v),
                    ),
                    if (_reason == 'other')
                      TextField(
                        key: const Key('order-reason-other'),
                        controller: _otherReason,
                        autofocus: true,
                        maxLength: 200,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: context.tr('Votre raison, en quelques mots'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          OrderStage.prepare => [
              FlowStep(
                id: 'pack',
                title: context.tr('Préparez la commande'),
                help: context.tr('Touchez chaque article une fois mis de côté.'),
                isValid: () => _goods.every(_ticked.contains),
                builder: (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _order.lines.length; i++) ...[
                      _PackTile(
                        index: i,
                        line: _order.lines[i],
                        ticked: _ticked.contains(i),
                        onTap: _order.lines[i].isService
                            ? null
                            : () => setState(() {
                                  if (!_ticked.remove(i)) _ticked.add(i);
                                  _flow.keep();
                                }),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      context.tr('{n} sur {total} prêts',
                          {'n': _ticked.length, 'total': _goods.length}),
                      key: const Key('order-pack-count'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      key: const Key('order-cancel'),
                      onPressed: _cancel,
                      style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error),
                      child: Text(context.tr('Annuler la commande')),
                    ),
                  ],
                ),
              ),
            ],
          OrderStage.finish => [
              FlowStep(
                id: 'handover',
                title: _booking
                    ? context.tr('Le rendez-vous de {name}', {'name': _name})
                    : _order.fulfilment == 'delivery'
                        ? context.tr('La livraison de {name}', {'name': _name})
                        : context.tr('{name} est là ?', {'name': _name}),
                isValid: () =>
                    _handover != null || _handoverOptions.length == 1,
                builder: (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if ((_order.courierName ?? '').isNotEmpty) ...[
                      Text(context.tr('Livreur : {courierName}',
                          {'courierName': _order.courierName})),
                      const SizedBox(height: 12),
                    ],
                    FlowChoice<String>(
                      options: _handoverOptions,
                      value: _handover ??
                          (_handoverOptions.length == 1
                              ? _handoverOptions.first.value
                              : null),
                      onChanged: (v) => setState(() => _handover = v),
                    ),
                    if (_order.nextStatuses.contains('cancelled'))
                      TextButton(
                        key: const Key('order-cancel'),
                        onPressed: _cancel,
                        style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error),
                        child: Text(_booking
                            ? context.tr('Annuler la réservation')
                            : context.tr('Annuler la commande')),
                      ),
                  ],
                ),
              ),
              FlowStep(
                id: 'paid',
                title: context.tr('Avez-vous reçu l\'argent ?'),
                help: context.tr('{amount} · {how}', {
                  'amount': money.format(_order.total),
                  'how': paymentLabel(_order.paymentMethod),
                }),
                shown: () => !_order.isPaid && _handover != 'self',
                isValid: () => _paid != null,
                builder: (_) => FlowChoice<bool>(
                  options: [
                    FlowOption(true, context.tr('Oui, payé'),
                        icon: Icons.price_check_outlined),
                    FlowOption(false, context.tr('Pas encore'),
                        icon: Icons.schedule,
                        detail: context.tr('« Paiement reçu » reste sur la commande')),
                  ],
                  value: _paid,
                  onChanged: (v) => setState(() => _paid = v),
                ),
              ),
            ],
          OrderStage.none => const [],
        },
        summary: (_) => FlowSummary(
          rows: switch (_stage) {
            OrderStage.answer => [
                FlowSummaryRow(context.tr('Client'), _name),
                FlowSummaryRow(context.tr('Total'),
                    money.format(_order.total)),
                FlowSummaryRow(
                    context.tr('Réponse'),
                    context.tr(orderActionLabel(_decision ?? 'accepted')),
                    step: 'see',
                    bold: true),
                if (_decision == 'refused')
                  FlowSummaryRow(context.tr('Raison'), _reasonText ?? '',
                      step: 'reason'),
              ],
            OrderStage.prepare => [
                FlowSummaryRow(context.tr('Client'), _name),
                FlowSummaryRow(context.tr('Articles prêts'),
                    '${_ticked.length} / ${_goods.length}',
                    step: 'pack', bold: true),
                FlowSummaryRow(
                    context.tr('Ensuite'),
                    _order.fulfilment == 'delivery'
                        ? context.tr('Proposée aux livreurs')
                        : context.tr('{name} est prévenu de venir', {'name': _name})),
              ],
            OrderStage.finish => [
                FlowSummaryRow(context.tr('Client'), _name),
                FlowSummaryRow(
                    context.tr('Fait'),
                    _handoverOptions
                            .where((o) =>
                                o.value ==
                                (_handover ?? _handoverOptions.first.value))
                            .firstOrNull
                            ?.label ??
                        '',
                    step: 'handover',
                    bold: true),
                if (!_order.isPaid && _handover != 'self')
                  FlowSummaryRow(
                      context.tr('Paiement'),
                      _paid == true
                          ? context.tr('Reçu')
                          : context.tr('Pas encore'),
                      step: 'paid'),
              ],
            OrderStage.none => const [],
          },
        ),
        onSave: _save,
        done: (context) {
          final (message, detail) = _done(context);
          return FlowDone(
          message: message,
          details: detail == null && !_paidFailed
              ? null
              : Column(
                  children: [
                    if (detail != null)
                      Text(detail, textAlign: TextAlign.center),
                    if (_paidFailed)
                      Text(
                          context.tr('Le paiement n\'a pas pu être noté : touchez « Paiement reçu » sur la commande.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ),
          actions: [
            if (stageOf(_order) != OrderStage.none)
              FlowAction(
                key: const Key('order-next-stage'),
                primary: true,
                label: context.tr(stageAction(_order)),
                icon: Icons.arrow_forward,
                onPressed: () => _toStage(stageOf(_order)),
              ),
          ],
        );
        },
    );
  }
}

/// The order as the shop reads it before answering.
class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({required this.order, required this.onOpen});

  final ShopOrder order;
  final Future<void> Function(String) onOpen;

  static String _q(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(order.currency);
    final when = DateFormat('EEE d MMM, HH:mm', 'fr_FR').format(order.createdAt);
    final phone = (order.phone ?? '').trim();
    final whatsapp = whatsappUrl(order.phone);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: maraPaper,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '$when · ${context.tr(fulfilmentLabel(order.fulfilment, appointment: order.isBooking))} · '
              '${paymentLabel(order.paymentMethod)}',
              style: theme.textTheme.bodySmall),
          if (phone.isNotEmpty)
            Row(
              children: [
                Expanded(child: Text(phone, style: theme.textTheme.bodyMedium)),
                IconButton(
                  tooltip: context.tr('Appeler'),
                  icon: const Icon(Icons.call_outlined),
                  onPressed: () => onOpen('tel:$phone'),
                ),
                if (whatsapp != null)
                  IconButton(
                    tooltip: context.tr('WhatsApp'),
                    icon: const Icon(Icons.chat_outlined),
                    onPressed: () => onOpen(whatsapp),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          for (final l in order.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${_q(l.quantity)} × ${l.name}',
                        style: theme.textTheme.titleMedium),
                  ),
                  Text(money.format(l.total), style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          const Divider(height: 16),
          Row(
            children: [
              Expanded(
                  child: Text(context.tr('Total'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700))),
              Text(money.format(order.total),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          if ((order.address ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: Text(context.tr('Livraison : {address}', {'address': order.address}))),
                if (order.hasDropPin)
                  TextButton(
                    onPressed: () =>
                        onOpen(directionsUrl(order.dropLat!, order.dropLng!)),
                    child: Text(context.tr('Itinéraire')),
                  ),
              ],
            ),
          ],
          if ((order.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(context.tr('Note : {note}', {'note': order.note}),
                style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// One line to set aside: a big tick. A service booked is not packed.
class _PackTile extends StatelessWidget {
  const _PackTile({
    required this.index,
    required this.line,
    required this.ticked,
    required this.onTap,
  });

  final int index;
  final OrderLine line;
  final bool ticked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = line.quantity == line.quantity.roundToDouble()
        ? line.quantity.toInt().toString()
        : line.quantity.toString();
    return Material(
      color: ticked
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: ticked ? theme.colorScheme.primary : Colors.transparent,
            width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('order-pack-$index'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                    line.isService
                        ? Icons.event_available_outlined
                        : ticked
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                    size: 30,
                    color: ticked ? theme.colorScheme.primary : null),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('$q × ${line.name}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (line.isService)
                  Text(context.tr('Service'), style: theme.textTheme.labelMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
