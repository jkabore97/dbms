import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/format/money.dart';
import '../../core/nav/app_scope.dart';
import '../../core/notify/push_client.dart';
import '../../core/orders/order_alert.dart';

import '../../l10n/strings.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/org_access.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/cauris/cauris_repository.dart';
import '../../core/cauris/feature_states.dart';
import '../cauris/path_card.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/retail/staff.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/theme/motion.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../capture/capture_action.dart';
import '../home/home_nav.dart';
import 'sale_sheet.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';

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
  });

  final OrgSummary org;

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

class _StoreHomeScreenState extends State<StoreHomeScreen> {
  NumberFormat get _money => moneyFormat(widget.org.currency);

  StoreDay _day = const StoreDay();
  List<ExpiringProduct> _expiring = const [];
  int _pendingOrders = 0;
  List<Product> _products = const [];
  double _lossesAvoided = 0;
  int _photosWaiting = 0;

  /// Sales kept on this phone for want of signal (package 7).
  int _salesWaiting = 0;

  /// The vitrine's checklist (070), for an owner whose window is open and
  /// unfinished: the nudge card. Null hides it.
  VitrineChecklist? _vitrine;

  /// The Basic path (085), as the session read it for this business.
  BasicProgress? get _path =>
      AppScope.read(context)?.session.featuresFor(widget.org.id)?.progress;

  bool _loading = true;
  String? _error;

  /// The doorbell (see OrderAlert): while this screen is open the pending
  /// count is re-read quietly, and a rise rings — a system banner where the
  /// browser allows it, always the badge. A shopkeeper serving the counter
  /// does not refresh pages; the page has to come to her.
  Timer? _doorbell;
  bool _alertsOn = OrderAlert.granted;

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
    OrderAlert.show(
      'Nouvelle commande — ${widget.org.name}',
      '$pending commande${pending > 1 ? 's' : ''} à traiter sur la vitrine.',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Nouvelle commande : $pending à traiter sur la vitrine.'),
      action: SnackBarAction(
        label: 'Voir',
        onPressed: () =>
            context.push(Routes.inside(widget.org.id, 'commandes')),
      ),
    ));
  }

  /// The browser only grants a notification from a person's own gesture,
  /// so this hangs off a button — never off a page load.
  ///
  /// Two rings in one yes: the doorbell for a background tab (OrderAlert),
  /// and — where the build has a push Worker — the subscription that
  /// reaches this browser with the app closed (PushClient), saved under
  /// the account so the bell's rows find it.
  Future<void> _enableAlerts() async {
    // Read before the first await: a context is not for after a gap.
    final notify = AppScope.maybeOf(context)?.notify;
    final granted = await OrderAlert.request();
    if (!mounted) return;
    var reach = 'même si cet onglet est en arrière-plan';
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
          ? 'Alertes activées : une commande sonnera $reach.'
          : "Le navigateur a refusé les alertes. Elles s'activent dans "
              'ses paramètres de notifications.'),
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
    final scopeAdmin = AppScope.read(context)?.admin;
    final scopeClient = AppScope.read(context)?.auth.client;
    final sync = AppScope.read(context)?.sync;
    final retail = widget.retail;
    if (retail == null || !retail.isConfigured) {
      setState(() {
        _loading = false;
        _error = "Cette version a été compilée sans serveur.";
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
      if (mounted) setState(() => _salesWaiting = waiting);
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

      // The owner's nudge (070): best-effort, never in the way of the day.
      VitrineChecklist? vitrine;
      if (widget.org.isAdmin) {
        try {
          vitrine = await scopeAdmin?.vitrineChecklist(widget.org.id);
        } catch (_) {}
        // Cauris for a complete vitrine (084), read where it is seen.
        unawaited(CaurisRepository(scopeClient).milestones(widget.org.id));
      }

      if (!mounted) return;
      setState(() {
        _vitrine = vitrine;
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

  Future<void> _sell() async {
    final retail = widget.retail;
    if (retail == null) return;

    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SaleSheet(
        orgId: widget.org.id,
        orgName: widget.org.name,
        retail: retail,
        currency: widget.org.currency,
        capture: widget.access.canEdit('photos') ? widget.capture : null,
        products: _products,
        canCredit: widget.access.canEdit('credits'),
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
      // The name, the bell and the account — nothing else. Every tool has
      // its place, with its word, on the bar at the foot (HomeNav).
      appBar: AppBar(
        title: Text(widget.org.name),
        actions: [
          if (widget.accountAction != null) widget.accountAction!,
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
            if (_salesWaiting > 0) ...[
              _Panel(
                colour: theme.colorScheme.secondaryContainer,
                child: Row(
                  children: [
                    const Icon(Icons.cloud_upload_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_salesWaiting vente${_salesWaiting > 1 ? 's' : ''} '
                        "en attente d'envoi. Elle${_salesWaiting > 1 ? 's' : ''} "
                        'partira${_salesWaiting > 1 ? 'nt' : ''} dès le retour '
                        'du réseau ; le total du jour la${_salesWaiting > 1 ? 's' : ''} '
                        'comptera alors.',
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
                        '$_photosWaiting photo${_photosWaiting > 1 ? 's' : ''} '
                        'sur cet appareil, en attente de réseau.',
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

            // A new business's path (085): the vitrine opens its tools.
            if (_path case final p? when p.gated) ...[
              PathCard(org: widget.org, progress: p),
              const SizedBox(height: 16),
            ] else if (_vitrine != null && _vitrine!.open && _vitrine!.score < 100) ...[
              _VitrineNudge(
                list: _vitrine!,
                onTap: () async {
                  await context
                      .push(Routes.orgSettings(widget.org.id));
                  if (mounted) await _load();
                },
              ),
              const SizedBox(height: 16),
            ],

            if (widget.retail != null &&
                widget.access.canSee('orders') &&
                OrderAlert.supported &&
                !_alertsOn) ...[
              _AlertsCard(onEnable: _enableAlerts),
              const SizedBox(height: 16),
            ],

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
                            '${_expiring.length} article'
                            '${_expiring.length > 1 ? 's' : ''} bientôt périmé'
                            '${_expiring.length > 1 ? 's' : ''}',
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
                                      ? 'périmé'
                                      : 'dans ${p.daysLeft} j',
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
                    "Aujourd'hui",
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
                    '${_day.saleCount} vente${_day.saleCount > 1 ? 's' : ''}'
                    '${_day.returnsTotal > 0 ? ' · ${_money.format(_day.returnsTotal)} rendus' : ''}',
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
                            'Marchandise vendue avant sa date',
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
      ),
      primary: [
        if (widget.retail != null && widget.access.canSee('products'))
          HomeDestination(
            icon: Icons.sell_outlined,
            label: s.productsLabel,
            onTap: () => _openThenReload('produits'),
          ),
        // Orders sent from the vitrine (055), with how many are waiting.
        if (widget.retail != null && widget.access.canSee('orders'))
          HomeDestination(
            icon: Icons.inbox_outlined,
            label: 'Commandes',
            badge: _pendingOrders,
            onTap: () => _openThenReload('commandes'),
          ),
        if (widget.invoicing != null && widget.access.canSee('invoices'))
          HomeDestination(
            icon: Icons.receipt_long_outlined,
            label: s.invoices,
            onTap: () => PathGate.guard(context, widget.org, 'invoices',
                () => context.push(Routes.inside(widget.org.id, 'factures'))),
          ),
      ],
      more: [
        if (widget.org.isAdmin)
          HomeDestination(
            icon: Icons.savings_outlined,
            label: 'Mes cauris',
            onTap: () => _openThenReload('cauris'),
          ),
        if (widget.access.canSee('production'))
          HomeDestination(
            icon: Icons.precision_manufacturing_outlined,
            label: s.production,
            onTap: () => PathGate.guard(context, widget.org, 'production',
                () => _openThenReload('production')),
          ),
        if (cameraReady && widget.access.canSee('photos'))
          HomeDestination(
            icon: Icons.photo_library_outlined,
            label: s.photos,
            onTap: _openGallery,
          ),
        // The doors out to the public side, said in words: going to the
        // street is a choice, never something to fall into backwards.
        if (slug != null && slug.isNotEmpty)
          HomeDestination(
            icon: Icons.visibility_outlined,
            label: 'Voir ma vitrine',
            onTap: () => context.go(Routes.storefront(slug)),
          ),
        HomeDestination(
          icon: Icons.storefront_outlined,
          label: 'Voir le marché',
          onTap: () => context.go(Routes.directory),
        ),
        HomeDestination(
          icon: Icons.account_circle_outlined,
          label: s.account,
          onTap: () => context.push(Routes.inside(widget.org.id, 'compte')),
        ),
      ],
    );
  }
}

/// "Votre vitrine : 40 %" on the shop's home (070): what the window still
/// lacks, one tap from the settings that fix it.
class _VitrineNudge extends StatelessWidget {
  const _VitrineNudge({required this.list, required this.onTap});

  final VitrineChecklist list;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = list.steps.where((s) => !s.done).map((s) => s.label).first;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: _Panel(
        colour: theme.colorScheme.secondaryContainer,
        child: Row(
          children: [
            const Icon(Icons.storefront_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Votre vitrine : ${list.score} %',
                      style: theme.textTheme.titleSmall),
                  Text('À faire : $next',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// Asks once whether the till may ring for a new order. A one-time choice,
/// so it is a card on the page that goes away when answered — not a button
/// that sits on the bar and then vanishes from it.
class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Panel(
      colour: theme.colorScheme.primaryContainer,
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined,
              color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Soyez prévenu à chaque commande de la vitrine.',
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
          FilledButton.tonal(
            onPressed: onEnable,
            child: const Text('Activer'),
          ),
        ],
      ),
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
      label: _shown ? null : 'Montant caché, toucher pour afficher',
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
