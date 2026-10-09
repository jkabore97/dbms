import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/format/money.dart';
import '../../core/nav/app_scope.dart';
import '../../core/notify/alert_tone.dart';
import '../../core/orders/order_alert.dart';

import '../../l10n/strings.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/cauris/cauris_repository.dart';
import '../cauris/path_card.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/retail/staff.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/theme/motion.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../capture/capture_action.dart';
import '../home/home_counts.dart';
import '../home/home_nav.dart';
import '../notify/push_offer.dart';
import 'article_flow.dart';
import '../common/step_flow.dart';
import 'sale_flow.dart';
import '../money/expense_flow.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';
import '../common/refused_notice.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// Esperance's home screen.
///
/// The church screen leads with money because money is what a church records.
/// The farm leads with eggs and birds. A shop leads with two things: what came
/// in today, and what is about to rot.
///
/// The expiry panel is the reason this module exists. Her losses do not come
/// from theft or from arithmetic, they come from stock quietly reaching its
/// date on a shelf nobody looked at. So it is not a badge or a menu item — it
/// sits above the fold, in money rather than in counts, and it is the first
/// thing on screen when there is anything to say.
///
/// Everything here is read from the server, unlike the farm. A shop has more
/// than one person behind the counter and no device knows what another one
/// sold; showing this phone's share as though it were the day's takings would
/// be a lie told confidently. When the server cannot be reached the screen
/// says so and offers a retry, and selling still works — `record_sale()` is
/// idempotent, so the sheet can retry safely.
class StoreHomeScreen extends StatefulWidget {
  const StoreHomeScreen({
    super.key,
    this.invoicing,
    required this.org,
    this.retail,
    this.staff,
    this.capture,
    this.accountAction,
    this.access = OrgAccess.allEdit,
    this.cauris,
  });

  final OrgSummary org;

  /// Le Chemin's reader; the app's own unless a test gives one.
  final CaurisRepository? cauris;

  /// The owner's dial from 031: which tools this person is shown here.
  final OrgAccess access;

  /// Null in a build with no server.
  final RetailRepository? retail;

  /// Wages. Null in a build with no server, and every screen behind it is
  /// refused by RLS for anyone who is not an org admin.
  final StaffRepository? staff;

  /// Photographs. Null in a build with no server, and not configured in a
  /// build made before the upload Worker had a URL — in both cases the camera
  /// button is hidden rather than shown and failing.
  final CaptureRepository? capture;

  /// Invoicing. Every business bills somebody — a shop bills a
  /// wholesaler, a church bills a hall hire — and until 020 this was
  /// reachable from the farm alone. Null in a build with no server:
  /// invoicing is the one thing here that cannot work offline.
  final InvoicingRepository? invoicing;

  final Widget? accountAction;

  @override
  State<StoreHomeScreen> createState() => _StoreHomeScreenState();
}

class _StoreHomeScreenState extends State<StoreHomeScreen>
    with HomeCounts<StoreHomeScreen> {
  @override
  String get countsOrgId => widget.org.id;

  @override
  bool get countsShown => !widget.org.isObserverOnly;

  NumberFormat get _money => moneyFormat(widget.org.currency);

  StoreDay _day = const StoreDay();
  List<ExpiringProduct> _expiring = const [];
  int _pendingOrders = 0;
  List<Product> _products = const [];
  double _lossesAvoided = 0;
  int _photosWaiting = 0;

  /// Sales kept on this phone for want of signal (package 7).
  int _salesWaiting = 0;

  /// Sales kept offline that the server refused (101), until read.
  List<RefusedAction> _refused = const [];

  /// Le Chemin (097), for an admin: the card with the next step. Null
  /// hides it.
  PathState? _path;

  /// The server has no path yet (before 097): the fallback card, never
  /// an empty home.
  bool _pathMissing = false;

  bool _loading = true;
  String? _error;

  /// The doorbell (see OrderAlert): while this screen is open the pending
  /// count is re-read quietly, and a rise rings — a system banner where the
  /// browser allows it, always the badge. A shopkeeper serving the counter
  /// does not refresh pages; the page has to come to her.
  Timer? _doorbell;

  static const _doorbellEvery = Duration(seconds: 90);

  @override
  void dispose() {
    _doorbell?.cancel();
    super.dispose();
  }

  void _armDoorbell() {
    if (_doorbell != null) return;
    final retail = widget.retail;
    if (retail == null || !retail.isConfigured) return;
    if (!widget.access.canSee('orders')) return;
    _doorbell = Timer.periodic(_doorbellEvery, (_) => _listenForOrders());
  }

  Future<void> _listenForOrders() async {
    final retail = widget.retail;
    if (retail == null || !mounted) return;
    final int pending;
    try {
      pending = await retail.pendingOrders(widget.org.id);
    } catch (_) {
      return; // No signal is not news; the next tick tries again.
    }
    if (!mounted) return;
    final rose = pending > _pendingOrders;
    setState(() => _pendingOrders = pending);
    if (!rose) return;
    // Rung here only while this home is the page on top: the orders list,
    // pushed over it, rings for itself the moment an order lands.
    if (ModalRoute.of(context)?.isCurrent ?? true) unawaited(AlertTone.ring());
    OrderAlert.show(
      context.tr('Nouvelle commande — {name}', {'name': widget.org.name}),
      pending > 1
          ? context.tr('{n} commandes à traiter sur la vitrine.', {'n': pending})
          : context.tr('{n} commande à traiter sur la vitrine.', {'n': pending}),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          context.tr('Nouvelle commande : {pending} à traiter sur la vitrine.', {'pending': pending})),
      action: SnackBarAction(
        label: context.tr('Voir'),
        onPressed: () =>
            context.push(Routes.inside(widget.org.id, 'commandes')),
      ),
    ));
  }

  @override
  void initState() {
    super.initState();
    _armDoorbell();
    _load();
  }

  Future<void> _load() async {
    // Read before the first await: a context is not for after a gap.
    final scopeClient = AppScope.read(context)?.auth.client;
    final sync = AppScope.read(context)?.sync;
    final retail = widget.retail;
    if (retail == null || !retail.isConfigured) {
      setState(() {
        _loading = false;
        _error = context.tr('Cette version a été compilée sans serveur.');
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // The phone's own count first: it answers with no signal at all, which
    // is exactly when it matters. A drain is tried on the way.
    try {
      await sync?.syncNow();
      final waiting = await retail.pendingSales(widget.org.id);
      final refused = [
        for (final r in await retail.refusedSales(widget.org.id))
          RefusedAction.fromRow(r),
      ];
      if (mounted) {
        setState(() {
          _salesWaiting = waiting;
          _refused = refused;
        });
      }
    } catch (_) {}

    try {
      final day = await retail.day(widget.org.id);
      final expiring = await retail.expiring(widget.org.id);
      final products = await retail.products(widget.org.id);
      final avoided = await retail.lossesAvoided(widget.org.id);
      // A database one migration behind has no orders; the badge stays
      // quiet rather than failing the home screen.
      var pending = 0;
      try {
        pending = await retail.pendingOrders(widget.org.id);
      } catch (_) {
        pending = 0;
      }

      // Photographs taken before there was signal go now, quietly. Failing to
      // send them must not fail the home screen — the bytes are still on the
      // device and the banner below says so.
      var waiting = 0;
      final capture = widget.capture;
      if (capture != null && capture.isConfigured) {
        try {
          await capture.drain();
        } catch (_) {
          // Reported by the count, not by an error.
        }
        waiting = (await capture.queueHealth(widget.org.id)).waiting;
      }

      // The owner's next step (097): best-effort, never in the way of the
      // day.
      PathState? path;
      var pathMissing = false;
      if (widget.org.isAdmin) {
        final cauris = widget.cauris ?? CaurisRepository(scopeClient);
        // Cauris for a complete vitrine (084), read where it is seen.
        unawaited(cauris.milestones(widget.org.id));
        try {
          path = await cauris.pathState(widget.org.id,
              onMissing: () => pathMissing = true);
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _path = path;
        _pathMissing = pathMissing;
        _day = day;
        _pendingOrders = pending;
        _expiring = expiring;
        _products = products;
        _lossesAvoided = avoided;
        _photosWaiting = waiting;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  /// A sale the server refused for want of stock: « Ajouter un article »
  /// (115) opens on the article it named and the number missing; once
  /// received, the same sale (same client_uuid) is sent again.
  Future<void> _fixRefused(RefusedAction a) async {
    final retail = widget.retail;
    final short = a.shortfall;
    if (retail == null || short == null) return;
    final received = await ArticleFlow.open(context,
        org: widget.org,
        retail: retail,
        capture: widget.capture,
        initialName: short.name,
        initialQuantity: short.missing);
    if (received != true || !mounted) return;
    await retail.requeueRefused(a.clientUuid);
    if (!mounted) return;
    setState(() => _refused = [
          for (final r in _refused)
            if (r.clientUuid != a.clientUuid) r,
        ]);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(context.tr('Stock corrigé : la vente repart.'))));
    await _load();
  }

  Future<void> _sell() async {
    final retail = widget.retail;
    if (retail == null) return;

    // One entry at a time (115): the full-screen « Vente » flow.
    final recorded = await StepFlow.push(
      context,
      SaleFlow(
        orgId: widget.org.id,
        orgName: widget.org.name,
        retail: retail,
        currency: widget.org.currency,
        capture: widget.access.canEdit('photos') ? widget.capture : null,
        products: _products,
        canCredit: widget.access.canEdit('credits') &&
            !PathGate.locks(context, widget.org, 'credits'),
        // The last answer the device heard when offline (batch 115).
        allowWave: AppScope.read(context)?.session.waveAllowedFor(widget.org.id) ?? false,
      ),
    );
    if (recorded == true) await _load();
  }

  Future<void> _photograph() async {
    final capture = widget.capture;
    if (capture == null) return;

    // Straight to the camera. No sheet, no choice, no field: a choice is a
    // field, and every field at capture time loses a user.
    final taken = await CaptureAction.take(
      context,
      orgId: widget.org.id,
      capture: capture,
    );
    if (taken) await _load();
  }

  Future<void> _openGallery() async {
    final capture = widget.capture;
    if (capture == null) return;

    await context.push(Routes.inside(widget.org.id, 'photos'));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cameraReady =
        widget.capture != null && widget.capture!.isConfigured;
    // Taking a photo needs 'edit' on Photos — the server says the same since
    // 069; looking at the gallery needs only that it is not hidden.
    final canPhotograph = cameraReady && widget.access.canEdit('photos');
    final atRisk = _expiring.fold<double>(0, (sum, p) => sum + p.valueAtRisk);

    final nav = _nav(cameraReady);
    return nav.frame(context, Scaffold(
      // The name, the switch (several activities only), the bell and the
      // account — nothing else. Every tool has its place, with its word, on
      // the bar at the foot (HomeNav).
      appBar: AppBar(
        title: Text(widget.org.name),
        actions: [
          if (widget.accountAction != null) widget.accountAction!,
          bellRoom,
        ],
      ),
      bottomNavigationBar: nav.bar(context),
      // Selling is what a till does all day, so the sale is the big, filled,
      // labelled button — impossible to miss and sized for a thumb in a hurry.
      // The camera keeps its place for the shop that also photographs its
      // deliveries, but as the smaller companion above it rather than the
      // headline: a sale's value is known the moment it happens, so the button
      // that records it should be the obvious one.
      floatingActionButton: (widget.retail == null && !canPhotograph)
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // The camera sits above the till button when both are here, as
                // a small round secondary. On a shop with no sale button (a
                // pure capture business) it stays the big labelled one, so that
                // shop still has a clear primary action.
                if (canPhotograph)
                  widget.retail != null
                      ? FloatingActionButton.small(
                          heroTag: 'photo',
                          onPressed: _photograph,
                          tooltip: Strings.of(context).photo,
                          child: const Icon(Icons.photo_camera),
                        )
                      : FloatingActionButton.extended(
                          heroTag: 'photo',
                          onPressed: _photograph,
                          icon: const Icon(Icons.photo_camera),
                          label: Text(Strings.of(context).photo),
                        ),
                if (canPhotograph && widget.retail != null)
                  const SizedBox(height: 12),
                if (widget.retail != null)
                  FloatingActionButton.extended(
                    heroTag: 'sell',
                    onPressed: _sell,
                    // Filled in the shop's own brand colour rather than the
                    // softer container tint an extended FAB takes by default,
                    // so the one button she reaches for most stands out from
                    // the aurora behind it. onPrimary keeps the label legible
                    // on it — the palette is WCAG-checked for exactly this pair.
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    icon: const Icon(Icons.point_of_sale),
                    label: Text(
                      Strings.of(context).sale,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),

            if (_error != null) ...[
              _Panel(
                colour: theme.colorScheme.errorContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!,
                        style: TextStyle(
                            color: theme.colorScheme.onErrorContainer)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(Strings.of(context).retry),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Pictures this phone is still holding. Not an error: taking one
            // with no signal is the module working, and calling it a failure
            // would teach her to stop taking them exactly when they matter.
            if (_refused.isNotEmpty)
              RefusedNotice(
                actions: _refused,
                onDismiss: (a) async {
                  await widget.retail?.dismissRefused(a.clientUuid);
                  if (mounted) {
                    setState(() => _refused = [
                          for (final r in _refused)
                            if (r.clientUuid != a.clientUuid) r,
                        ]);
                  }
                },
                onFix: widget.retail != null && widget.access.canEdit('products')
                    ? _fixRefused
                    : null,
              ),
            if (_salesWaiting > 0) ...[
              _Panel(
                colour: theme.colorScheme.secondaryContainer,
                child: Row(
                  children: [
                    const Icon(Icons.cloud_upload_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _salesWaiting > 1
                            ? context.tr('{n} ventes en attente d\'envoi. Elles partiront dès le retour du réseau ; le total du jour les comptera alors.', {'n': _salesWaiting})
                            : context.tr('{n} vente en attente d\'envoi. Elle partira dès le retour du réseau ; le total du jour la comptera alors.', {'n': _salesWaiting}),
                      ),
                    ),
                    TextButton(
                      onPressed: _load,
                      child: Text(Strings.of(context).send),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_photosWaiting > 0) ...[
              _Panel(
                colour: theme.colorScheme.secondaryContainer,
                child: Row(
                  children: [
                    const Icon(Icons.cloud_upload_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('{n} photo(s) sur cet appareil, en attente de réseau.', {'n': _photosWaiting}),
                      ),
                    ),
                    TextButton(
                      onPressed: _load,
                      child: Text(Strings.of(context).send),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Le Chemin (097): the one next thing to do. Gone once the
            // path is walked.
            if (PathCard.shows(widget.org, _path)) ...[
              PathCard(
                org: widget.org,
                state: _path!,
                onChanged: _load,
                // The first sale is made here, at the till.
                onHere: widget.retail == null ? null : _sell,
              ),
              const SizedBox(height: 16),
            ] else if (_pathMissing && PathFallbackCard.shows(widget.org)) ...[
              PathFallbackCard(org: widget.org, onBack: _load),
              const SizedBox(height: 16),
            ],

            // The ring with the app closed (115), offered while THIS device
            // is not in the person's book — not merely until the browser's
            // permission was given (the bug: such a browser never rang) —
            // and the tab's doorbell for whoever answers the orders. Every
            // member who records something is offered it; an observer only
            // watches.
            if (!widget.org.isObserverOnly)
              PushOfferCard(
                notify: AppScope.maybeOf(context)?.notify,
                doorbell: widget.retail != null && widget.access.canSee('orders'),
                message: context.tr('Soyez prévenu à chaque commande de la vitrine.'),
              ),

            // What is about to be lost, first and in money.
            if (_expiring.isNotEmpty) ...[
              _Panel(
                colour: theme.colorScheme.tertiaryContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _expiring.length > 1
                                ? context.tr('{n} articles bientôt périmés', {'n': _expiring.length})
                                : context.tr('{n} article bientôt périmé', {'n': _expiring.length}),
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_money.format(atRisk)} en jeu',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ..._expiring.take(4).map(
                          (p) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Expanded(child: Text(p.name)),
                                Text(
                                  p.isExpired
                                      ? context.tr('périmé')
                                      : context.tr('dans {daysLeft} j', {'daysLeft': p.daysLeft}),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: p.isExpired
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // The day.
            // The day's takings, in the shop's own colours. This is the one
            // figure Esperance looks for when she opens the app, so it is the
            // one thing on the screen that is painted rather than filled.
            _Panel(
              gradient: kajGradient(KajTheme.of(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Aujourd\'hui'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: KajTheme.of(context).ink.withValues(alpha: 0.82),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Hidden at the counter when asked (Compte › Sécurité):
                  // a touch shows it, another hides it again.
                  _Discreet(
                    hidden: AppScope.read(context)?.security?.hideAmounts ?? false,
                    child: Text(
                      _money.format(_day.netSales),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: KajTheme.of(context).ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_day.saleCount > 1 ? context.tr('{n} ventes', {'n': _day.saleCount}) : context.tr('{n} vente', {'n': _day.saleCount})}'
                    '${_day.returnsTotal > 0 ? ' · ${context.tr('{amount} rendus', {'amount': _money.format(_day.returnsTotal)})}' : ''}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: KajTheme.of(context).ink),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_lossesAvoided > 0)
              _Panel(
                colour: theme.colorScheme.secondaryContainer,
                child: Row(
                  children: [
                    const Icon(Icons.savings_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(Strings.of(context).lossesAvoided,
                              style: theme.textTheme.titleSmall),
                          Text(
                            _money.format(_lossesAvoided),
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            context.tr('Marchandise vendue avant sa date'),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 80),
          ],
        ),
      ),
    ));
  }

  Future<void> _openThenReload(String rest) async {
    await context.push(Routes.inside(widget.org.id, rest));
    if (mounted) await _load();
  }

  /// Mon chemin, from the till: a step done at the till comes back here
  /// and opens the sale sheet. The gates and the path are read again.
  Future<void> _openChemin() async {
    final session = AppScope.read(context)?.session;
    final r = await context.push<Object?>(Routes.inside(
        widget.org.id, pathCheminRest(fromTill: widget.retail != null)));
    await session?.reloadFeatures(widget.org.id);
    if (!mounted) return;
    await _load();
    if (r == pathSellResult && mounted) await _sell();
  }

  Future<void> _openExpense() async {
    final saved = await StepFlow.push(
      context,
      ExpenseFlow(
        db: AppScope.of(context).db,
        orgId: widget.org.id,
        profile: widget.org.profile,
        currency: widget.org.currency,
        capture: widget.capture,
      ),
    );
    if (saved == true && mounted) await _load();
  }

  /// The shop's five: Vente (this screen), Articles, Commandes, Factures,
  /// and Plus for what is consulted rather than worked in.
  HomeNav _nav(bool cameraReady) {
    final s = Strings.of(context);
    final slug = widget.org.slug;
    return HomeNav(
      home: HomeDestination(
        icon: Icons.payments_outlined,
        selectedIcon: Icons.payments,
        label: s.sale,
        onTap: () {},
        route: '',
      ),
      primary: [
        if (widget.retail != null && widget.access.canSee('products'))
          HomeDestination(
            icon: Icons.sell_outlined,
            label: s.productsLabel,
            // Articles at zero or under their alert level (115).
            badge: homeCount('articles'),
            route: 'produits',
            onTap: () => _openThenReload('produits'),
          ),
        // Orders sent from the vitrine (055), with how many are waiting.
        if (widget.retail != null && widget.access.canSee('orders'))
          HomeDestination(
            icon: Icons.inbox_outlined,
            label: context.tr('Commandes'),
            // Orders and bookings not answered yet (115's home_counts,
            // live with the bell; the doorbell's own count before 115).
            badge: homeCountsKnown
                ? homeCount('orders') + homeCount('bookings')
                : _pendingOrders,
            route: 'commandes',
            onTap: () => _openThenReload('commandes'),
          ),
        if (widget.invoicing != null && widget.access.canSee('invoices'))
          HomeDestination(
            icon: Icons.receipt_long_outlined,
            label: s.invoices,
            // Invoices past their due date and not paid (115).
            badge: homeCount('invoices'),
            route: 'factures',
            onTap: () => PathGate.open(context, widget.org, 'invoices',
                () => context.push(Routes.inside(widget.org.id, 'factures'))),
          ),
      ],
      more: [
        // Money out (115): rent, transport, a repair — one question a
        // screen, kept on the phone like a sale.
        if (!widget.org.isObserverOnly)
          HomeDestination(
            icon: Icons.north_east,
            label: context.tr('Dépense'),
            onTap: _openExpense,
          ),
        if (widget.org.isAdmin)
          HomeDestination(
            icon: Icons.route_outlined,
            label: context.tr('Mon chemin'),
            route: 'chemin',
            onTap: _openChemin,
          ),
        // What the shop does rather than sells (098), on the vitrine —
        // unless Mara's switchboard hid the services (110).
        if (widget.retail != null &&
            widget.access.canSee('products') &&
            !widget.access.isHidden('services'))
          HomeDestination(
            icon: Icons.event_available_outlined,
            label: context.tr('Mes services'),
            route: 'services',
            onTap: () => _openThenReload('services'),
          ),
        if (widget.access.canSee('production'))
          HomeDestination(
            icon: Icons.precision_manufacturing_outlined,
            label: s.production,
            route: 'production',
            onTap: () => PathGate.open(context, widget.org, 'production',
                () => _openThenReload('production')),
          ),
        if (cameraReady && widget.access.canSee('photos'))
          HomeDestination(
            icon: Icons.photo_library_outlined,
            label: s.photos,
            route: 'photos',
            onTap: _openGallery,
          ),
        // The business's people (100), as on the farm's and the
        // association's homes.
        if (widget.org.isAdmin)
          HomeDestination(
            icon: Icons.groups_outlined,
            label: context.tr('Équipe'),
            // Invitations not claimed yet (115).
            badge: homeCount('invitations'),
            route: 'equipe',
            onTap: () => context.push(Routes.inside(widget.org.id, 'equipe')),
          ),
        // The administration's hub (108), for whoever runs the business.
        if (widget.org.isAdmin)
          HomeDestination(
            icon: Icons.admin_panel_settings_outlined,
            label: context.tr('Administration'),
            route: 'administration',
            onTap: () => _openThenReload('administration'),
          ),
        // The doors out to the public side, said in words: going to the
        // street is a choice, never something to fall into backwards.
        if (slug != null && slug.isNotEmpty)
          HomeDestination(
            icon: Icons.visibility_outlined,
            label: context.tr('Voir ma vitrine'),
            onTap: () => context.go(Routes.storefront(slug)),
          ),
        HomeDestination(
          icon: Icons.storefront_outlined,
          label: context.tr('Voir le marché'),
          onTap: () => context.go(Routes.directory),
        ),
        HomeDestination(
          icon: Icons.account_circle_outlined,
          label: s.account,
          // The carnet's credits past their date (115, 117's due date):
          // the shop's carnet is opened from Compte — counted only for
          // somebody who may see the carnet.
          badge: widget.access.canSee('credits') ? homeCount('credit') : 0,
          route: 'compte',
          onTap: () => context.push(Routes.inside(widget.org.id, 'compte')),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.colour, this.gradient})
      : assert(colour != null || gradient != null,
            'a panel is either filled or painted');

  final Widget child;

  /// A flat fill, for the panels that support the day rather than being it.
  final Color? colour;

  /// A gradient, for the one panel the screen is opened to read.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    // Each panel of the day rises as it comes into view, as the street's
    // blocks do.
    return ScrollReveal(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: gradient == null ? colour : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }
}


/// A figure that can be kept from the customer's eyes: dots until touched.
class _Discreet extends StatefulWidget {
  const _Discreet({required this.hidden, required this.child});

  final bool hidden;
  final Widget child;

  @override
  State<_Discreet> createState() => _DiscreetState();
}

class _DiscreetState extends State<_Discreet> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.hidden) return widget.child;
    return Semantics(
      button: true,
      label: _shown ? null : context.tr('Montant caché, toucher pour afficher'),
      child: InkWell(
        onTap: () => setState(() => _shown = !_shown),
        borderRadius: BorderRadius.circular(8),
        child: _shown
            ? widget.child
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('• • • • •',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: KajTheme.of(context).ink)),
                  const SizedBox(width: 10),
                  Icon(Icons.visibility_outlined,
                      color: KajTheme.of(context).ink),
                ],
              ),
      ),
    );
  }
}
