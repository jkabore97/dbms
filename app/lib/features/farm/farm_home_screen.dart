import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/format/money.dart';

import '../../l10n/strings.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/cauris/cauris_repository.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/retail/staff.dart';
import '../../core/db/local_db.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../../core/nav/app_scope.dart';
import '../cauris/path_card.dart';
import '../common/refused_notice.dart';
import '../admin/admin_pill.dart' show AdminPill;
import '../home/home_counts.dart';
import '../home/home_nav.dart';
import '../notify/push_offer.dart';
import '../orders/home_doorbell.dart';
import 'farm_animal_flows.dart';
import 'farm_crop_flows.dart';
import 'farm_flows.dart';
import '../money/expense_flow.dart';
import '../common/step_flow.dart';
import '../retail/sale_flow.dart';
import '../../core/retail/models.dart';
import '../../core/nav/router.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// Ignace's home screen.
///
/// The church home screen shows money because money is what a church records.
/// This one shows eggs, birds and feed first, and money underneath, because
/// that is the order the farm is actually run in: the eggs tell you today, the
/// mortality tells you next week, and the money tells you last month.
///
/// Everything above the fold is computed from this device. That is not a
/// fallback, it is the design — Ignace is the user the offline architecture
/// was built for, and a home screen whose figures go blank at the farm gate is
/// a home screen that teaches him the app is unreliable. The server's version
/// of the same day is fetched when it can be and used to fill in what this
/// phone could not know: how much feed is left across everyone's devices, and
/// how many birds are alive.
class FarmHomeScreen extends StatefulWidget {
  const FarmHomeScreen({
    super.key,
    this.invoicing,
    required this.db,
    required this.org,
    this.farm,
    this.capture,
    this.staff,
    this.accountAction,
    this.access = OrgAccess.allEdit,
    this.retail,
  });

  /// The owner's dial from 031: which tools this person is shown here.
  final OrgAccess access;

  final LocalDb db;
  final OrgSummary org;

  /// Null in a build with no server. The recording sheets still work; the
  /// stock and flock counts cannot be computed from one device.
  final FarmRepository? farm;

  /// Photographs — a feed delivery note, a vet's prescription. Null in a
  /// build with no server or no upload Worker.
  final CaptureRepository? capture;

  /// Staff. Every business has people; 012 built the payroll behind a shop's
  /// home screen and 018 made the records general enough for a church's
  /// volunteers and a farm's seasonal hands. Null in a build with no server,
  /// and every screen behind it is refused by RLS for anyone who is not an
  /// org admin.
  final StaffRepository? staff;

  /// Invoicing. Every business bills somebody — a shop bills a
  /// wholesaler, a church bills a hall hire — and until 020 this was
  /// reachable from the farm alone. Null in a build with no server:
  /// invoicing is the one thing here that cannot work offline.
  final InvoicingRepository? invoicing;

  final Widget? accountAction;

  /// The vitrine's orders (083): what rings the doorbell on this home
  /// (100). Null in a build with no server.
  final RetailRepository? retail;

  @override
  State<FarmHomeScreen> createState() => _FarmHomeScreenState();
}

class _FarmHomeScreenState extends State<FarmHomeScreen>
    with HomeDoorbell<FarmHomeScreen>, HomeCounts<FarmHomeScreen> {
  @override
  String get countsOrgId => widget.org.id;

  @override
  bool get countsShown => !widget.org.isObserverOnly;

  // The doorbell (100): a new order on the farm's vitrine rings here, as
  // on a shop's home, for whoever sees the orders.
  @override
  OrgSummary get doorbellOrg => widget.org;

  @override
  RetailRepository? get doorbellRetail =>
      widget.access.canSee('orders') ? widget.retail : null;

  NumberFormat get _currency => moneyFormat(widget.org.currency);

  ({int eggs, double deaths, double feedUsed}) _today =
      (eggs: 0, deaths: 0, feedUsed: 0);
  double _moneyIn = 0;
  double _moneyOut = 0;
  int _pending = 0;

  /// Feed or sales kept offline that the server refused (101), until read.
  List<RefusedAction> _refused = const [];

  List<Map<String, Object?>> _events = const [];
  List<Map<String, Object?>> _lowStock = const [];

  bool _loading = true;

  /// Set when the server could not be reached. The counts on screen are then
  /// this device's share of the truth, which is worth saying out loud rather
  /// than presenting as the whole of it.
  bool _stale = false;

  /// What kind of farm this is. Read before the panels are drawn so a goat
  /// farmer is not shown an empty poultry section, and a poultry farm still
  /// opens on birds and eggs exactly as it did.
  FarmShape _shape = const FarmShape();

  /// Le Chemin (097), for an admin: the card with the next step. Null
  /// hides it.
  PathState? _path;

  /// The server has no path yet (before 097): the fallback card.
  bool _pathMissing = false;

  Future<void> _openLivestock({int tab = 0}) async {
    final farm = widget.farm;
    if (farm == null) return;
    // The tab rides in the query string, so a link to the goats is a link to
    // the goats rather than to whichever tab happens to be first.
    await context.push(Routes.inside(widget.org.id, 'troupeau?onglet=$tab'));
    if (mounted) await _refresh();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    armDoorbell();
  }

  Future<void> _openExpense() async {
    final saved = await StepFlow.push(
      context,
      ExpenseFlow(
        db: widget.db,
        orgId: widget.org.id,
        profile: widget.org.profile,
        currency: widget.org.currency,
        capture: widget.capture,
      ),
    );
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _refresh() async {
    final today = DateTime.now();

    // The device first and always. Whatever the network does after this, the
    // screen has numbers on it.
    final day = await widget.db.farmDay(widget.org.id, today);
    final totals = await widget.db.dayTotals(widget.org.id, today);
    final events = await widget.db.farmEventsForDay(widget.org.id, today);
    final pending = await widget.db.pendingCount();
    final refused = [
      for (final r in await widget.db.refusedActions(widget.org.id))
        RefusedAction.fromRow(r),
    ];

    if (!mounted) return;
    setState(() {
      _today = day;
      _moneyIn = totals.moneyIn;
      _moneyOut = totals.moneyOut;
      _events = events;
      _pending = pending;
      _refused = refused;
      _loading = false;
    });

    await _refreshFromServer();
    await _readPath();

    if (!mounted) return;
    final items = await widget.db.cachedFarmItems(widget.org.id);
    if (!mounted) return;
    setState(() {
      _lowStock =
          items.where((i) => (i['below_reorder'] as int? ?? 0) == 1).toList();
    });
  }

  /// The next step on the path: best-effort, and only with signal.
  Future<void> _readPath() async {
    if (!mounted) return;
    final client = AppScope.read(context)?.auth.client;
    if (!widget.org.isAdmin || client == null) return;
    try {
      var missing = false;
      final path = await CaurisRepository(client)
          .pathState(widget.org.id, onMissing: () => missing = true);
      if (mounted) {
        setState(() {
          _path = path;
          _pathMissing = missing;
        });
      }
    } catch (_) {}
  }

  /// Pulls the counts only this device cannot compute, and writes them to the
  /// cache so the recording sheets keep offering real names when the signal
  /// goes again.
  Future<void> _refreshFromServer() async {
    final farm = widget.farm;
    if (farm == null || !farm.isConfigured) return;

    try {
      final items = await farm.stockOnHand(widget.org.id);
      final flocks = await farm.flocks(widget.org.id);
      // 019: what this farm actually keeps and grows. Best-effort — a
      // database without it yet leaves the shape empty, and the screen then
      // behaves exactly as it did before.
      try {
        final shape = await farm.shape(widget.org.id);
        if (mounted) setState(() => _shape = shape);
      } catch (_) {}
      await widget.db.cacheFarmItems(
        widget.org.id,
        items.map((i) => i.toCache()).toList(),
      );
      await widget.db.cacheFlocks(
        widget.org.id,
        flocks.map((f) => f.toCache()).toList(),
      );
      if (mounted) setState(() => _stale = false);
    } catch (_) {
      // No signal, or no entitlement. Either way the device's own figures
      // stand and the banner says they are only half the picture.
      if (mounted) setState(() => _stale = true);
    }
  }

  /// The day's four, one entry at a time (115). Each saves on this phone
  /// first where it did before; the home is read again once one is saved.
  Future<void> _record(Future<bool?> flow) async {
    if (await flow == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final nav = _nav();
    return nav.frame(context, Scaffold(
      // The name, the sync count, the bell and the account. Every tool has
      // its place, with its word, on the bar at the foot (HomeNav).
      bottomNavigationBar: nav.bar(context),
      appBar: AppBar(
        title: Text(widget.org.name),
        actions: [
          if (_pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Tooltip(
                  message: Strings.of(context).pendingCount(_pending),
                  child: Chip(
                    avatar: const Icon(Icons.cloud_upload_outlined, size: 16),
                    // Beside Mara's « Admin » on a phone (104): the number
                    // alone, so the bar keeps the farm's name.
                    label: Text(AdminPill.crowds(context)
                        ? '$_pending'
                        : Strings.of(context).pendingCount(_pending)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
          if (widget.accountAction != null) widget.accountAction!,
          bellRoom,
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Le Chemin (097): the one next thing to do. Gone once
                  // the path is walked.
                  if (PathCard.shows(widget.org, _path)) ...[
                    PathCard(org: widget.org, state: _path!, onChanged: _refresh),
                    const SizedBox(height: 16),
                  ] else if (_pathMissing && PathFallbackCard.shows(widget.org)) ...[
                    PathFallbackCard(org: widget.org, onBack: _refresh),
                    const SizedBox(height: 16),
                  ],
                  // The ring with the app closed (115), until this device
                  // rings — for every member but an observer.
                  if (!widget.org.isObserverOnly)
                    PushOfferCard(
                      notify: AppScope.maybeOf(context)?.notify,
                      doorbell: true,
                      message: context.tr('Soyez prévenu des commandes et du stock, même l\'application fermée.'),
                    ),
                  _TodayCard(
                    day: _today,
                    moneyIn: _moneyIn,
                    moneyOut: _moneyOut,
                    currency: _currency,
                  ),

                  if (_refused.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    RefusedNotice(
                      actions: _refused,
                      onDismiss: (a) async {
                        await widget.db.dismissRefused(a.clientUuid);
                        await _refresh();
                      },
                    ),
                  ],

                  if (_lowStock.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _LowStockBanner(items: _lowStock),
                  ],

                  // What this farm keeps and grows, shown only where there is
                  // something to show. 009 assumed poultry; a farm with goats
                  // and onions was expected to record its animals as a flock
                  // and its harvest as "other income".
                  if (widget.farm != null) ...[
                    const SizedBox(height: 12),
                    _FarmShapeCard(
                      shape: _shape,
                      onAnimals: () => _openLivestock(),
                      onCrops: () => _openLivestock(tab: 1),
                    ),
                  ],

                  if (_stale) ...[
                    const SizedBox(height: 12),
                    _StaleBanner(theme: theme),
                  ],

                  const SizedBox(height: 24),
                  Text(Strings.of(context).today, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_events.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          Strings.of(context).nothingCountedToday,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._events.map((e) => _EventTile(event: e)),

                  const SizedBox(height: 120),
                ],
              ),
            ),

      // Récolte is the large one: it happens every morning, it is the thing
      // that has to become a habit, and it is the number that warns earliest.
      // The rest are smaller because they happen when they happen.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // « Vente » (115): what the farm sells, one entry at a time.
              if (widget.retail != null && !widget.org.isObserverOnly) ...[
                FloatingActionButton.small(
                  key: const Key('farm-sell'),
                  heroTag: 'farm-sell',
                  tooltip: context.tr('Vente'),
                  onPressed: _sell,
                  backgroundColor: Colors.green.shade100,
                  foregroundColor: Colors.green.shade900,
                  child: const Icon(Icons.point_of_sale_outlined),
                ),
                const SizedBox(width: 12),
              ],
              FloatingActionButton.small(
                heroTag: 'farm-receive',
                tooltip: Strings.of(context).stockReceipt,
                onPressed: () => _record(FarmStockFlow.receive(context,
                    db: widget.db, org: widget.org)),
                backgroundColor: Colors.orange.shade100,
                foregroundColor: Colors.orange.shade900,
                child: const Icon(Icons.local_shipping_outlined),
              ),
              const SizedBox(width: 12),
              FloatingActionButton.small(
                heroTag: 'farm-consume',
                tooltip: Strings.of(context).feedGiven,
                onPressed: () => _record(FarmStockFlow.use(context,
                    db: widget.db, org: widget.org, farm: widget.farm)),
                backgroundColor: Colors.brown.shade100,
                foregroundColor: Colors.brown.shade800,
                child: const Icon(Icons.restaurant_outlined),
              ),
              const SizedBox(width: 12),
              FloatingActionButton.small(
                heroTag: 'farm-mortality',
                tooltip: Strings.of(context).mortality,
                onPressed: () => _record(FarmAnimalFlow.event(context,
                    db: widget.db, org: widget.org, farm: widget.farm)),
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
                child: const Icon(Icons.pets_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'farm-harvest',
            onPressed: () => _record(FarmCropFlow.harvest(context,
                org: widget.org,
                farm: widget.farm,
                retail: widget.retail,
                onSell: widget.retail == null || widget.org.isObserverOnly
                    ? null
                    : _sell)),
            backgroundColor: KajTheme.of(context).ink,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.agriculture_outlined, size: 28),
            label: Text(
              Strings.of(context).harvest,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            extendedPadding: const EdgeInsets.symmetric(horizontal: 28),
          ),
        ],
      ),
    ));
  }

  /// The farm's « Vente » (115): the same flow as the shop's till, over
  /// what it has for sale (« À vendre »). No signal: the list it last had
  /// is not kept, so the produce is typed by name — and the sale waits on
  /// the phone, as the shop's does.
  Future<void> _sell() async {
    final retail = widget.retail;
    if (retail == null) return;
    List<Product> products = const [];
    try {
      products = await retail.products(widget.org.id);
    } catch (_) {}
    if (!mounted) return;
    final sold = await StepFlow.push(
      context,
      SaleFlow(
        orgId: widget.org.id,
        orgName: widget.org.name,
        retail: retail,
        currency: widget.org.currency,
        products: products,
        farm: true,
        canCredit: widget.access.canEdit('credits') &&
            !PathGate.locks(context, widget.org, 'credits'),
        // The last answer the device heard when offline (batch 115).
        allowWave: AppScope.read(context)?.session.waveAllowedFor(widget.org.id) ?? false,
      ),
    );
    if (sold == true && mounted) await _refresh();
  }

  Future<void> _push(String location) async {
    await context.push(location);
    if (mounted) await _refresh();
  }

  /// The farm's five: Accueil (this screen), Stock, Bandes, Factures,
  /// and Plus. Stock, Bandes and Factures were tiles in the middle of the
  /// page; they are on the bar now, where they are always in reach.
  HomeNav _nav() {
    final s = Strings.of(context);
    final id = widget.org.id;
    return HomeNav(
      home: HomeDestination(
        icon: Icons.agriculture_outlined,
        selectedIcon: Icons.agriculture,
        // Not "Aujourd'hui": that is already the heading of the day's list
        // on this page, and one word twice on a screen reads as two places.
        label: context.tr('Accueil'),
        onTap: () {},
        route: '',
      ),
      primary: [
        HomeDestination(
          icon: Icons.inventory_2_outlined,
          label: s.stock,
          // Supplies under their reorder level (115).
          badge: homeCount('supplies'),
          route: 'stock',
          onTap: () => _push(Routes.inside(id, 'stock')),
        ),
        HomeDestination(
          icon: Icons.pets_outlined,
          label: s.flocks,
          // Open batches with nothing written today (115).
          badge: homeCount('livestock'),
          route: 'bandes',
          onTap: () => _push(Routes.inside(id, 'bandes')),
        ),
        if (widget.invoicing != null && widget.access.canSee('invoices'))
          HomeDestination(
            icon: Icons.receipt_long_outlined,
            label: s.invoices,
            // Invoices past their due date and not paid (115).
            badge: homeCount('invoices'),
            route: 'factures',
            onTap: () => PathGate.open(context, widget.org, 'invoices',
                () => _push(Routes.inside(id, 'factures'))),
          ),
      ],
      more: [
        // Money out (115): the vet, a day's labour, transport — one question
        // a screen, kept on the phone like everything the farm records.
        if (!widget.org.isObserverOnly)
          HomeDestination(
            icon: Icons.north_east,
            label: context.tr('Dépense'),
            onTap: _openExpense,
          ),
        // The farm's vitrine (083): what it sells, and the orders for it.
        HomeDestination(
          icon: Icons.storefront_outlined,
          label: context.tr('À vendre'),
          // Articles at zero or under their alert level (115).
          badge: homeCount('articles'),
          route: 'a-vendre',
          onTap: () => _push(Routes.inside(id, 'a-vendre')),
        ),
        // What the farm does for others (098): ploughing, a stud, a visit —
        // unless Mara's switchboard hid the services (110).
        if (!widget.access.isHidden('services'))
          HomeDestination(
            icon: Icons.event_available_outlined,
            label: context.tr('Mes services'),
            route: 'services',
            onTap: () => _push(Routes.inside(id, 'services')),
          ),
        HomeDestination(
          icon: Icons.shopping_bag_outlined,
          label: context.tr('Commandes'),
          // Orders and bookings not answered yet (115).
          badge: homeCount('orders') + homeCount('bookings'),
          route: 'commandes',
          onTap: () => _push(Routes.inside(id, 'commandes')),
        ),
        if (widget.org.isAdmin)
          HomeDestination(
            icon: Icons.route_outlined,
            label: context.tr('Mon chemin'),
            route: 'chemin',
            onTap: () => _push(Routes.inside(id, 'chemin')),
          ),
        if (widget.access.canSee('credits'))
          HomeDestination(
            icon: Icons.handshake_outlined,
            label: s.creditBook,
            // Credits past their due date (115, 117).
            badge: homeCount('credit'),
            route: 'credits',
            onTap: () => PathGate.open(context, widget.org, 'credits',
                () => context.push(Routes.inside(id, 'credits'))),
          ),
        if (widget.access.canSee('production'))
          HomeDestination(
            icon: Icons.precision_manufacturing_outlined,
            label: s.production,
            route: 'production',
            onTap: () => PathGate.open(context, widget.org, 'production',
                () => context.push(Routes.inside(id, 'production'))),
          ),
        if (widget.capture != null &&
            widget.capture!.isConfigured &&
            widget.access.canSee('photos'))
          HomeDestination(
            icon: Icons.photo_library_outlined,
            label: s.photos,
            route: 'photos',
            onTap: () => context.push(Routes.inside(id, 'photos')),
          ),
        if (widget.staff != null && widget.org.isAdmin)
          HomeDestination(
            icon: Icons.groups_outlined,
            label: context.tr('Équipe'),
            // Invitations not claimed yet (115).
            badge: homeCount('invitations'),
            route: 'equipe',
            onTap: () => context.push(Routes.inside(id, 'equipe')),
          ),
        // The administration's hub (108), for whoever runs the farm.
        if (widget.org.isAdmin)
          HomeDestination(
            icon: Icons.admin_panel_settings_outlined,
            label: context.tr('Administration'),
            route: 'administration',
            onTap: () => _push(Routes.inside(id, 'administration')),
          ),
        HomeDestination(
          icon: Icons.account_circle_outlined,
          label: s.account,
          route: 'compte',
          onTap: () => context.push(Routes.inside(id, 'compte')),
        ),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.day,
    required this.moneyIn,
    required this.moneyOut,
    required this.currency,
  });

  final ({int eggs, double deaths, double feedUsed}) day;
  final double moneyIn;
  final double moneyOut;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The palette's ink, not white. The gradient is a pale wash now, and
    // white measured at 2.54:1 on the light end of it — unreadable. Ink on
    // the same wash measures 4.99 or better.
    final on = KajTheme.of(context).ink;

    return KajCard(
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(gradient: kajGradient(KajTheme.of(context))),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE d MMMM',
                      Localizations.localeOf(context).toString())
                  .format(DateTime.now()),
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: on.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: Strings.of(context).mortality,
                    value: trimQuantity(day.deaths),
                    tint: day.deaths > 0 ? theme.colorScheme.error : on,
                    on: on,
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: Strings.of(context).feedOut,
                    value: trimQuantity(day.feedUsed),
                    on: on,
                  ),
                ),
              ],
            ),
            if (moneyIn > 0 || moneyOut > 0) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _Figure(
                      label: Strings.of(context).received,
                      value: currency.format(moneyIn),
                      on: on,
                    ),
                  ),
                  Expanded(
                    child: _Figure(
                      label: Strings.of(context).spent,
                      value: currency.format(moneyOut),
                      on: on,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.on,
    this.tint,
  });

  final String label;
  final String value;
  final Color on;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold, color: tint ?? on),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: on.withValues(alpha: 0.8)),
        ),
      ],
    );
  }
}

/// The warning that makes counting sacks worth doing.
class _LowStockBanner extends StatelessWidget {
  const _LowStockBanner({required this.items});

  final List<Map<String, Object?>> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = items.map((i) => i['name'] as String).join(', ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              items.length == 1
                  ? Strings.of(context).lowStockOf(names)
                  : context.tr('{length} articles presque épuisés : {names}.', {'length': items.length, 'names': names}),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.tr('Chiffres de cet appareil seulement. Le stock et l\'effectif des bandes se calculent sur tous les appareils et seront à jour au retour du réseau.'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final Map<String, Object?> event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final kind = event['kind'] as String;
    final quantity = (event['quantity'] as num).toDouble();
    final unit = event['unit'] as String?;
    final note = event['note'] as String?;
    final time = DateTime.parse(event['occurred_at'] as String).toLocal();

    final (icon, tint, label) = switch (kind) {
      'eggs' => (Icons.egg_outlined, Colors.amber.shade800, 'Récolte'),
      'stock_in' => (
          Icons.local_shipping_outlined,
          Colors.orange.shade800,
          'Réception'
        ),
      'stock_out' => (
          Icons.restaurant_outlined,
          Colors.brown.shade600,
          'Distribué'
        ),
      'wasted' => (Icons.delete_outline, theme.colorScheme.error, 'Perte'),
      'mortality' => (
          Icons.pets_outlined,
          theme.colorScheme.error,
          'Mortalité'
        ),
      'adjusted' => (Icons.tune, Colors.blueGrey.shade600, 'Ajustement'),
      _ => (
          Icons.check_circle_outline,
          theme.colorScheme.primary,
          flockEventLabel(kind)
        ),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: tint.withValues(alpha: 0.12),
        child: Icon(icon, color: tint, size: 20),
      ),
      title: Text('$label · ${event['subject']}'),
      subtitle: Text(
        [
          DateFormat.Hm().format(time),
          if (note != null && note.isNotEmpty) note,
        ].join(' · '),
      ),
      trailing: Text(
        [trimQuantity(quantity), ?unit].join(' '),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    );
  }
}

/// Livestock and crops, offered in proportion to what this farm has.
///
/// An empty farm gets both as invitations; a farm that keeps goats and grows
/// nothing sees its animals and a quiet way in to crops. The one thing this
/// avoids is showing a market gardener a poultry panel with zeros in it,
/// which is what a fixed layout does to everybody who is not Ignace.
class _FarmShapeCard extends StatelessWidget {
  const _FarmShapeCard({
    required this.shape,
    required this.onAnimals,
    required this.onCrops,
  });

  final FarmShape shape;
  final VoidCallback onAnimals;
  final VoidCallback onCrops;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return KajCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('Élevage et cultures'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              shape.isEmpty
                  ? context.tr('Enregistrez vos animaux et vos parcelles.')
                  : [
                      if (shape.hasLivestock)
                        '${shape.animals} animaux en ${shape.herds} groupe'
                            '${shape.herds > 1 ? 's' : ''}',
                      if (shape.hasCrops)
                        '${shape.cropCycles} culture'
                            '${shape.cropCycles > 1 ? 's' : ''} en cours',
                      if (shape.harvestWeek > 0)
                        '${shape.harvestWeek.toStringAsFixed(0)} kg récoltés cette semaine',
                    ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAnimals,
                    icon: const Icon(Icons.pets, size: 18),
                    label: Text(shape.hasLivestock
                        ? context.tr('{animals} animaux', {'animals': shape.animals})
                        : context.tr('Animaux')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCrops,
                    icon: const Icon(Icons.grass, size: 18),
                    label: Text(shape.hasCrops
                        ? context.tr('{cropCycles} cultures', {'cropCycles': shape.cropCycles})
                        : context.tr('Cultures')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
