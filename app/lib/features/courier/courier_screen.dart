import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/courier/courier_repository.dart';
import '../../core/format/money.dart';
import '../../core/nav/app_scope.dart';
import '../../core/notify/push_client.dart';
import '../../core/orders/order_alert.dart';
import '../../core/orders/orders.dart';
import '../../core/nav/router.dart';
import '../../core/nav/url_tabs.dart';
import '../../core/storefront/storefront_repository.dart';
import '../storefront/shop_skeleton.dart';
import '../storefront/shop_style.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The livreur's whole world on one page.
///
/// The same address serves every stage of being a courier, because the
/// stages are the server's to say: never registered → the pitch and one
/// button; pending → "à l'étude"; suspended → said in words; approved →
/// two tabs, the board of ready deliveries and their own courses. A job
/// card carries the three things a courier acts on — where to collect
/// (with the itinerary), where to bring (with the itinerary), what to
/// collect at the door — and exactly one button per state.
class CourierScreen extends StatefulWidget {
  const CourierScreen({super.key, required this.courier});

  final CourierRepository courier;

  @override
  State<CourierScreen> createState() => _CourierScreenState();
}

class _CourierScreenState extends State<CourierScreen>
    with SingleTickerProviderStateMixin, UrlTabsMixin {
  @override
  List<String> get tabSlugs => const ['disponibles', 'courses'];

  String? _status;
  List<DeliveryJob> _board = const [];
  List<DeliveryJob> _mine = const [];
  List<CourierEarnings> _earnings = const [];

  /// Cash collected at doors, not yet handed to the shops (073).
  List<CashHeld> _cash = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// The page re-checks itself (the #110 lesson, here for couriers): an
  /// applicant waiting on "à l'étude" is carried in when the platform says
  /// yes, and an approved courier's board fills without pulling to refresh.
  /// Approval rings the bell, but this page has no bell — so it asks.
  Timer? _poll;
  int _ticks = 0;
  static const _pollEvery = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(_pollEvery, (_) => _recheck());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Every tick while waiting for approval; every third (a minute) on the
  /// board. Silent, and never while the courier is mid-action.
  Future<void> _recheck() async {
    if (!mounted || _busy || _loading || !widget.courier.isConfigured) return;
    _ticks++;
    if (_status == 'approved' && _ticks % 3 != 0) return;
    if (_status == 'suspended') return;
    await _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    if (!widget.courier.isConfigured) {
      setState(() {
        _error = context.tr('L\'espace livreur a besoin d\'une connexion.');
        _loading = false;
      });
      return;
    }
    try {
      final status = await widget.courier.status();
      var board = const <DeliveryJob>[];
      var mine = const <DeliveryJob>[];
      var earnings = const <CourierEarnings>[];
      var cash = const <CashHeld>[];
      if (status == 'approved') {
        final here = _here;
        final results = await Future.wait([
          // Nearest shop first from where the phone last was (073), once
          // known; the first load never waits for it.
          widget.courier.board(lat: here?.latitude, lng: here?.longitude),
          widget.courier.mine(),
          // The tally is a strip, not the page: if it fails, the board
          // still shows and the strip is simply absent.
          widget.courier
              .earnings()
              .catchError((_) => const <CourierEarnings>[]),
          widget.courier.cash().catchError((_) => const <CashHeld>[]),
        ]);
        board = results[0] as List<DeliveryJob>;
        mine = results[1] as List<DeliveryJob>;
        earnings = results[2] as List<CourierEarnings>;
        cash = results[3] as List<CashHeld>;
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _board = board;
        _mine = mine;
        _earnings = earnings;
        _cash = cash;
        _loading = false;
      });
      if (status == 'approved' && _here == null && !_locating) {
        unawaited(_locate());
      }
    } catch (_) {
      if (!mounted) return;
      if (silent) return; // No signal is not news: what is on screen stays.
      setState(() {
        _error = context.tr('L\'espace livreur n\'a pas pu être chargé. Vérifiez le réseau.');
        _loading = false;
      });
    }
  }

  Position? _here;
  bool _locating = false;

  /// Learns where the phone last was, then re-sorts the board nearest first.
  Future<void> _locate() async {
    _locating = true;
    final here = await _lastKnown();
    if (!mounted || here == null) return;
    _here = here;
    try {
      final board = await widget.courier
          .board(lat: here.latitude, lng: here.longitude);
      if (mounted) setState(() => _board = board);
    } catch (_) {}
  }

  /// Where the phone last was, without asking: null when unknown, refused
  /// or on a platform without the plugin.
  static Future<Position?> _lastKnown() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getLastKnownPosition()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  /// "Livré" (073): the shopper's four digits close the delivery.
  Future<void> _deliver(DeliveryJob job) async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _CodeDialog(),
    );
    if (code == null) return;
    await _act(() => widget.courier.deliver(job.orderId, code),
        "Code refusé : demandez au client les 4 chiffres affichés dans sa commande.");
  }

  /// "Échec" (073): why the door did not open.
  Future<void> _fail(DeliveryJob job) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(context.tr('Pourquoi la livraison échoue ?'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final (key, label) in const [
              ('absent', 'Client absent'),
              ('unreachable', 'Client injoignable'),
              ('refused', 'Le client refuse la commande'),
              ('other', 'Autre raison'),
            ])
              ListTile(
                title: Text(label),
                onTap: () => Navigator.of(sheet).pop(key),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                  context.tr('La commande est annulée et vous rapportez le colis à la boutique. La boutique et le client sont prévenus.'),
                  style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
            ),
          ],
        ),
      ),
    );
    if (reason == null) return;
    await _act(() => widget.courier.fail(job.orderId, reason),
        "L'échec n'a pas pu être enregistré.");
  }

  Future<void> _register() async {
    setState(() => _busy = true);
    try {
      await widget.courier.register();
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('L\'inscription n\'a pas pu partir. Vérifiez le réseau.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(Future<void> Function() call, String failed) async {
    setState(() => _busy = true);
    try {
      await call();
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failed)));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Whether this browser already carries the ring. Read once at build:
  /// the bell button stays until the person says yes.
  bool _alertsOn = OrderAlert.granted;

  /// Asked from the bell button — the browser grants a notification from
  /// a person's own gesture only. Two rings in one yes: the tab in the
  /// background (OrderAlert) and, where the build has a push Worker, the
  /// closed app (PushClient), saved under the account so a new job on the
  /// board reaches this phone.
  Future<void> _enableAlerts() async {
    // Read before the first await: a context is not for after a gap.
    final notify = AppScope.maybeOf(context)?.notify;
    final granted = await OrderAlert.request();
    if (!mounted) return;
    var reach = 'quand cet onglet est en arrière-plan';
    if (granted && PushClient.available) {
      final sub = await PushClient.subscribe();
      if (sub != null && notify != null && notify.isConfigured) {
        try {
          await notify.savePushSubscription(sub);
          reach = "même l'application fermée";
        } catch (_) {
          // The tab still rings; the closed-app ring waits for signal.
        }
      }
    }
    if (!mounted) return;
    setState(() => _alertsOn = granted);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(granted
          ? context.tr('Alertes activées : une nouvelle livraison sonnera {reach}.', {'reach': reach})
          : context.tr('Le navigateur a refusé les alertes. Elles s\'activent dans ses paramètres de notifications.')),
    ));
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final running = _mine.where((j) => j.isRunning).length;

    return ShopPage(
      title: context.tr('Espace livreur'),
      leading: IconButton(
        tooltip: context.tr('Les vitrines'),
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go(Routes.directory),
      ),
      trailing: _status == 'approved'
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The ring on a moto in traffic: a job on the board, a
                // customer's pin, reaches a closed app once this browser
                // has said yes. Offered only where the build can keep the
                // promise, and gone once it is kept.
                if (OrderAlert.supported && !_alertsOn)
                  IconButton(
                    tooltip: context.tr('Recevoir les alertes de livraison'),
                    icon: const Icon(Icons.notifications_active_outlined),
                    onPressed: _busy ? null : _enableAlerts,
                  ),
                IconButton(
                  tooltip: context.tr('Actualiser'),
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading || _busy ? null : _load,
                ),
              ],
            )
          : null,
      body: _loading
          ? ShopSkeleton.list(rows: 3)
          : _error != null
              ? ShopNotice(
                  text: _error!,
                  action: OutlinedButton(
                      onPressed: _load, child: Text(context.tr('Réessayer'))),
                )
              : switch (_status) {
                  null => _Pitch(busy: _busy, onRegister: _register),
                  'pending' => const ShopNotice(
                      text: 'Votre inscription est à l\'étude. La plateforme '
                          'vous préviendra dès qu\'elle est validée.',
                    ),
                  'suspended' => const ShopNotice(
                      text: 'Votre accès livreur est suspendu. '
                          'Contactez la plateforme.',
                    ),
                  _ => Column(
                        children: [
                          // What today paid (062): the one strip on the
                          // page a courier reads before anything else.
                          if (_earnings.isNotEmpty)
                            _EarningsStrip(
                                earnings: _earnings,
                                currency: _mine.isNotEmpty
                                    ? _mine.first.currency
                                    : 'XOF'),
                          if (_cash.isNotEmpty) _CashStrip(cash: _cash),
                          Material(
                            color: ShopStyle.paper,
                            child: TabBar(controller: tabs, tabs: [
                              Tab(
                                  text:
                                      'Disponibles${_board.isEmpty ? '' : ' (${_board.length})'}'),
                              Tab(
                                  text:
                                      'Mes courses${running == 0 ? '' : ' ($running)'}'),
                            ]),
                          ),
                          Expanded(
                            child: TabBarView(controller: tabs, children: [
                              _JobList(
                                jobs: _board,
                                empty: 'Aucune livraison à prendre pour le '
                                    'moment. Revenez un peu plus tard.',
                                busy: _busy,
                                onOpen: _open,
                                actionsFor: (job) => [
                                  FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _act(
                                            () => widget.courier
                                                .take(job.orderId),
                                            'Trop tard : un autre livreur '
                                            "l'a prise."),
                                    child: Text(context.tr('J\'accepte')),
                                  ),
                                ],
                              ),
                              _JobList(
                                jobs: _mine,
                                empty: 'Aucune course. Prenez-en une dans '
                                    'Disponibles.',
                                busy: _busy,
                                onOpen: _open,
                                actionsFor: (job) => switch (job.status) {
                                  'ready' => [
                                      // The course on a map: my dot, the
                                      // shop, the door, and the leg ahead.
                                      OutlinedButton.icon(
                                        onPressed: () => context.push(
                                            Routes.courierJob(job.orderId)),
                                        icon: const Icon(Icons.map_outlined,
                                            size: 18),
                                        label: Text(context.tr('Carte')),
                                      ),
                                      FilledButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _act(
                                                () => widget.courier.mark(
                                                    job.orderId, 'in_transit'),
                                                "Le retrait n'a pas pu être "
                                                'enregistré.'),
                                        child: Text(context.tr('Colis récupéré')),
                                      ),
                                      OutlinedButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _act(
                                                () => widget.courier
                                                    .release(job.orderId),
                                                'Cette course ne peut plus '
                                                'être remise.'),
                                        child: Text(context.tr('Remettre')),
                                      ),
                                    ],
                                  'in_transit' => [
                                      OutlinedButton.icon(
                                        onPressed: () => context.push(
                                            Routes.courierJob(job.orderId)),
                                        icon: const Icon(Icons.map_outlined,
                                            size: 18),
                                        label: Text(context.tr('Carte')),
                                      ),
                                      FilledButton(
                                        onPressed:
                                            _busy ? null : () => _deliver(job),
                                        child: Text(context.tr('Livré')),
                                      ),
                                      OutlinedButton(
                                        onPressed:
                                            _busy ? null : () => _fail(job),
                                        child: Text(context.tr('Échec')),
                                      ),
                                    ],
                                  _ => const [],
                                },
                              ),
                            ]),
                          ),
                        ],
                      ),
                },
    );
  }
}

/// Today, this week, this month — courses, money, kilometres — on the
/// stone band the street uses for what matters most. Today is written
/// large; the week and the month sit beside it in small type.
class _EarningsStrip extends StatelessWidget {
  const _EarningsStrip({required this.earnings, required this.currency});

  final List<CourierEarnings> earnings;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(currency);
    final today = earnings.where((e) => e.period == 'today').firstOrNull;
    final rest = earnings.where((e) => e.period != 'today').toList();
    return ColoredBox(
      color: ShopStyle.stone,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('AUJOURD\'HUI'),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: ShopStyle.mist)),
                  const SizedBox(height: 2),
                  // What the courier keeps (067): the fees minus the
                  // platform's part, said beside it so settlement day
                  // never surprises.
                  Text(money.format(today?.net ?? 0),
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: ShopStyle.ink)),
                  Text(
                      '${today?.courses ?? 0} course${(today?.courses ?? 0) > 1 ? 's' : ''}'
                      ' · ${(today?.km ?? 0).toStringAsFixed(1)} km'
                      '${(today?.share ?? 0) > 0 ? ' · part Mara ${money.format(today!.share)}' : ''}',
                      style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
                ],
              ),
            ),
            for (final e in rest)
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(CourierEarnings.label(e.period),
                        style: const TextStyle(
                            fontSize: 11, color: ShopStyle.mist)),
                    Text(money.format(e.net),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: ShopStyle.ink)),
                    Text('${e.courses} · ${e.km.toStringAsFixed(0)} km',
                        style: const TextStyle(
                            fontSize: 12, color: ShopStyle.mist)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What being a livreur is, for somebody who is not one yet.
class _Pitch extends StatelessWidget {
  const _Pitch({required this.busy, required this.onRegister});

  final bool busy;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ColoredBox(
          color: ShopStyle.stone,
          child: ShopWidth(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Livrez pour les\nboutiques du quartier.'),
                  style: const TextStyle(
                      fontSize: 30,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                      color: ShopStyle.ink),
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr('Les boutiques préparent des commandes à livrer. Vous les prenez quand vous voulez, vous encaissez le montant à la porte et vous réglez la boutique. La plateforme valide chaque livreur avant sa première course.'),
                  style: const TextStyle(
                      fontSize: 16, height: 1.45, color: ShopStyle.ink),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: busy ? null : onRegister,
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: ShopStyle.paper))
                      : Text(context.tr('M\'inscrire comme livreur')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({
    required this.jobs,
    required this.empty,
    required this.busy,
    required this.onOpen,
    required this.actionsFor,
  });

  final List<DeliveryJob> jobs;
  final String empty;
  final bool busy;
  final Future<void> Function(String url) onOpen;
  final List<Widget> Function(DeliveryJob) actionsFor;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return ShopNotice(text: empty);
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ShopWidth(
          child: Column(
            children: [
              const SizedBox(height: 20),
              for (final job in jobs)
                _JobCard(
                    job: job, onOpen: onOpen, actions: actionsFor(job)),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }
}

/// One course: collect here, bring there, collect this much.
class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.onOpen,
    required this.actions,
  });

  final DeliveryJob job;
  final Future<void> Function(String url) onOpen;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(job.currency);
    final when = DateFormat('HH:mm', 'fr_FR').format(job.createdAt);
    final phone = (job.phone ?? '').trim();
    final done = job.status != null && !job.isRunning;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: ShopStyle.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Opacity(
        opacity: done ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(job.shopName,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: ShopStyle.ink)),
                ),
                Text('$when · ${money.format(job.total)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ShopStyle.ink)),
              ],
            ),
            if (job.ownShop || job.toShopKm != null) ...[
              const SizedBox(height: 4),
              Text(
                [
                  if (job.ownShop) 'Votre boutique',
                  if (job.toShopKm != null)
                    'à ${job.toShopKm!.toStringAsFixed(1)} km de vous',
                ].join(' · '),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: job.ownShop ? ShopStyle.ink : ShopStyle.mist),
              ),
            ],
            const SizedBox(height: 10),
            _Leg(
              icon: Icons.storefront_outlined,
              label: context.tr('Retirer'),
              place: (job.shopAddress ?? '').trim().isEmpty
                  ? job.shopName
                  : job.shopAddress!.trim(),
              onRoute: job.shopHasPin
                  ? () => onOpen(directionsUrl(job.shopLat!, job.shopLng!))
                  : null,
            ),
            const SizedBox(height: 6),
            _Leg(
              icon: Icons.home_outlined,
              label: context.tr('Livrer'),
              place: (job.dropAddress ?? '').trim().isEmpty
                  ? context.tr('Adresse chez le client')
                  : job.dropAddress!.trim(),
              // The customer pinned their door (058): the itinerary goes to
              // the pin, not to a guess at the written address.
              onRoute: job.hasDropPin
                  ? () => onOpen(directionsUrl(job.dropLat!, job.dropLng!))
                  : null,
            ),
            if (job.customerName != null || phone.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        if (job.customerName != null) job.customerName!,
                        if (phone.isNotEmpty) phone,
                      ].join(' · '),
                      style: const TextStyle(
                          fontSize: 14, color: ShopStyle.mist),
                    ),
                  ),
                  if (phone.isNotEmpty) ...[
                    IconButton(
                      tooltip: context.tr('Appeler'),
                      icon: const Icon(Icons.call_outlined, size: 20),
                      onPressed: () => onOpen('tel:$phone'),
                    ),
                    if (whatsappUrl(phone) != null)
                      IconButton(
                        tooltip: context.tr('WhatsApp'),
                        icon: const Icon(Icons.chat_outlined, size: 20),
                        onPressed: () => onOpen(whatsappUrl(phone)!),
                      ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 6),
            // What the run pays (061), before the courier takes it: the
            // fee and the distance it was priced on. A far job is worth
            // taking when its price says so, instead of rotting on the board.
            Text(
                job.deliveryFee == null
                    ? context.tr('Course : prix à convenir')
                    : 'Course : ${money.format(job.deliveryFee!)}'
                        '${job.distanceKm == null ? '' : ' · ${job.distanceKm!.toStringAsFixed(1)} km'}',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ShopStyle.ink)),
            const SizedBox(height: 4),
            Text(
                job.isPaid
                    ? (job.deliveryFee == null
                        ? 'Marchandise déjà payée (${paymentLabel(job.paymentMethod)}) '
                            '— seule la course est à encaisser'
                        : 'Marchandise déjà payée (${paymentLabel(job.paymentMethod)}) '
                            '— à encaisser : ${money.format(job.deliveryFee!)} (course)')
                    : 'À encaisser à la porte : '
                        '${money.format(job.total + (job.deliveryFee ?? 0))}'
                        '${job.deliveryFee == null ? '' : ' (dont course ${money.format(job.deliveryFee!)})'}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ShopStyle.mist)),
            if (done) ...[
              const SizedBox(height: 6),
              Text(
                  job.status == 'delivered'
                      ? context.tr('Livrée')
                      : context.tr('Terminée ({status})', {'status': job.status}),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ShopStyle.mist)),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({
    required this.icon,
    required this.label,
    required this.place,
    this.onRoute,
  });

  final IconData icon;
  final String label;
  final String place;
  final VoidCallback? onRoute;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: ShopStyle.mist),
        const SizedBox(width: 8),
        Expanded(
          child: Text(context.tr('{label} : {place}', {'label': label, 'place': place}),
              style: const TextStyle(fontSize: 15, color: ShopStyle.ink)),
        ),
        if (onRoute != null)
          TextButton(onPressed: onRoute, child: Text(context.tr('Itinéraire'))),
      ],
    );
  }
}


/// The four digits the shopper sees in their order (073).
class _CodeDialog extends StatefulWidget {
  const _CodeDialog();

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Code du client')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Demandez au client les 4 chiffres affichés dans sa commande : ils prouvent que le colis est bien arrivé.')),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 10),
            decoration: const InputDecoration(
                border: OutlineInputBorder(), counterText: ''),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Annuler')),
        ),
        FilledButton(
          onPressed: _code.text.trim().length == 4
              ? () => Navigator.of(context).pop(_code.text.trim())
              : null,
          child: Text(context.tr('Valider la livraison')),
        ),
      ],
    );
  }
}

/// The shops' money in the courier's pocket (073): one line, the detail on
/// a tap. The course stays the courier's; the goods' price is the shop's.
class _CashStrip extends StatelessWidget {
  const _CashStrip({required this.cash});

  final List<CashHeld> cash;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(cash.first.currency);
    final total = cash.fold<double>(0, (s, c) => s + c.total);
    final shops = <String, double>{};
    for (final c in cash) {
      shops[c.shopName] = (shops[c.shopName] ?? 0) + c.total;
    }
    return Material(
      color: ShopStyle.paper,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(context.tr('À remettre aux boutiques'),
                      style:
                          const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                for (final e in shops.entries)
                  ListTile(
                    title: Text(e.key),
                    trailing: Text(money.format(e.value),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Text(
                      context.tr('La boutique confirme dans Mara quand elle a reçu l\'argent ; la ligne disparaît alors d\'ici.'),
                      style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
                ),
              ],
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Row(
            children: [
              const Icon(Icons.payments_outlined, size: 20, color: ShopStyle.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    'À remettre aux boutiques : ${money.format(total)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ShopStyle.ink)),
              ),
              const Icon(Icons.chevron_right, color: ShopStyle.mist),
            ],
          ),
        ),
      ),
    );
  }
}
