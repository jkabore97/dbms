import '../../core/money/money_types.dart' show canWriteTypes;
import 'package:flutter/material.dart';
import '../../core/help/help_repository.dart';
import '../help/help_button.dart';
import '../home/vitrine_button.dart';
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
import '../events/events_access.dart';
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
import 'farm_till.dart';
import '../money/expense_flow.dart';
import '../common/step_flow.dart';
import '../retail/till_close_sheet.dart';
import '../../core/nav/router.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/theme/app_bar_title.dart';

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
    this.help,
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

  /// « Besoin d'aide » / « Aide » (136): the app's server unless a test
  /// gives one.
  final HelpRepository? help;

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

  /// How long a question to the server may stall before the farm stops
  /// waiting for it. At the farm gate the connection more often stalls than
  /// fails: without a bound « Vente » did nothing at all when tapped (it was
  /// waiting for the list of produce), and the banner saying the counts are
  /// this device's alone never showed.
  static const _askFor = Duration(seconds: 12);

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
        types: AppScope.read(context)?.reports,
        canEditTypes: canWriteTypes(widget.org),
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

    // The server's counts and the path do not wait for each other: one
    // round trip on a slow line, not four in turn.
    await Future.wait([_refreshFromServer(), _readPath()]);

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
          .pathState(widget.org.id, onMissing: () => missing = true)
          .timeout(_askFor);
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
      // Asked at once; awaited in turn, so a failure is heard here and
      // never as an error nobody caught. Each gives up in time: a stalled
      // line says the counts are this device's rather than spinning.
      final askedItems = farm.stockOnHand(widget.org.id).timeout(_askFor)..ignore();
      final askedFlocks = farm.flocks(widget.org.id).timeout(_askFor)..ignore();
      // 019: what this farm actually keeps and grows. Best-effort — a
      // database without it yet leaves the shape empty, and the screen then
      // behaves exactly as it did before.
      final askedShape = farm
          .shape(widget.org.id)
          .timeout(_askFor)
          .then<FarmShape?>((s) => s, onError: (Object _) => null);
      final items = await askedItems;
      final flocks = await askedFlocks;
      final shape = await askedShape;
      if (shape != null && mounted) setState(() => _shape = shape);
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
        title: AppBarTitle(widget.org.name),
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
                    label: Text(AdminPill.crowds(context) || HelpButton.crowds(context)
                        ? '$_pending'
                        : Strings.of(context).pendingCount(_pending)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
          // « Besoin d'aide » (Pro) or « Aide » (136), after the name.
          // « Ma vitrine » (140), one tap from the home.
          VitrineButton(org: widget.org, onChanged: _refresh),
          HelpButton(org: widget.org, help: widget.help, screen: context.tr('Accueil')),
          if (widget.accountAction != null) widget.accountAction!,
          bellRoom,
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                // Room under the last card for the row of round buttons and
                // « Récolte » floating over the list (UI audit S-4).
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
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

                  // Money out (115) — the vet, a day's labour, transport —
                  // a button here since 134, not a line under Plus: an
                  // act, not a place. Kept on the phone like everything
                  // the farm records.
                  if (!widget.org.isObserverOnly) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        key: const Key('home-expense'),
                        onPressed: _openExpense,
                        // The lighter button: « Récolte » stays the farm's
                        // headline act.
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          foregroundColor: theme.colorScheme.onSurface,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.remove),
                        label: Text(context.tr('Dépense'),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],

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

                  // « Clôturer la caisse » (batch 151): the farm sells at
                  // the same till as a shop (« Vente »), so it closes it
                  // the same way — at the foot of the day, as the
                  // association closes its own.
                  if (widget.retail != null && !widget.org.isObserverOnly) ...[
                    const SizedBox(height: 24),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 52),
                      child: OutlinedButton.icon(
                        key: const Key('home-close-till'),
                        onPressed: () =>
                            TillCloseSheet.open(context, widget.org, widget.retail!.guards),
                        icon: const Icon(Icons.lock_clock_outlined),
                        label: Text(context.tr('Clôturer la caisse'),
                            style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],

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
  /// what it has for sale (« À vendre »). No signal, or a stalled one: the
  /// list this phone last read, its stock less the sales it already made
  /// (the till says the list is the phone's) — typed by name only when it
  /// never read one. The sale waits on the phone, as the shop's does.
  /// Its animals beside its products (150): one sale lowers the batch.
  Future<void> _sell() async {
    final retail = widget.retail;
    if (retail == null) return;
    final sold = await FarmTill.open(context,
        org: widget.org, retail: retail, access: widget.access);
    if (sold == true && mounted) await _refresh();
  }

  Future<void> _push(String location) async {
    await context.push(location);
    if (mounted) await _refresh();
  }

  /// The farm's five (134): Accueil (this screen), Bandes, Stock, Ventes —
  /// always in that order — and Plus, under its headings. « À vendre »,
  /// « Commandes », the invoices and the carnet left Plus and the bar for
  /// Ventes, all the farm's selling in one tab; « Dépense » is a button on
  /// this screen.
  HomeNav _nav() {
    final s = Strings.of(context);
    final id = widget.org.id;
    final slug = widget.org.slug;
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
          icon: Icons.pets_outlined,
          label: s.flocks,
          // Open batches with nothing written today (115).
          badge: homeCount('livestock'),
          route: 'bandes',
          onTap: () => _push(Routes.inside(id, 'bandes')),
        ),
        HomeDestination(
          icon: Icons.inventory_2_outlined,
          label: s.stock,
          // Supplies under their reorder level (115).
          badge: homeCount('supplies'),
          route: 'stock',
          onTap: () => _push(Routes.inside(id, 'stock')),
        ),
        // The farm's vitrine (083) and its money in: À vendre, Commandes,
        // Factures, and the carnet below them.
        HomeDestination(
            icon: Icons.shopping_basket_outlined,
            selectedIcon: Icons.shopping_basket,
            label: context.tr('Ventes'),
            // What waits there: orders and bookings not answered (115),
            // articles running out, invoices past their date.
            badge: (widget.access.canSee('orders')
                    ? homeCount('orders') + homeCount('bookings')
                    : 0) +
                homeCount('articles') +
                (widget.access.canSee('invoices') ? homeCount('invoices') : 0) +
                // The carnet's credits past their date (115, 117): the
                // carnet opens from Ventes.
                (widget.access.canSee('credits') ? homeCount('credit') : 0),
            route: 'ventes',
            alsoRoutes: HomeNav.farmSalesAlso,
            onTap: () => _push(Routes.inside(id, 'ventes')),
          ),
      ],
      more: [
        // MA VITRINE.
        if (slug != null && slug.isNotEmpty)
          HomeDestination(
            icon: Icons.visibility_outlined,
            label: context.tr('Voir ma vitrine'),
            group: PlusGroup.vitrine,
            onTap: () => context.go(Routes.storefront(slug)),
          ),
        // What the farm does for others (098): ploughing, a stud, a visit —
        // unless Mara's switchboard hid the services (110).
        if (!widget.access.isHidden('services'))
          HomeDestination(
            icon: Icons.event_available_outlined,
            label: context.tr('Mes services'),
            route: 'services',
            group: PlusGroup.vitrine,
            onTap: () => _push(Routes.inside(id, 'services')),
          ),
        if (widget.capture != null &&
            widget.capture!.isConfigured &&
            widget.access.canSee('photos'))
          HomeDestination(
            icon: Icons.photo_library_outlined,
            label: s.photos,
            route: 'photos',
            group: PlusGroup.vitrine,
            // Back from the photos, the path reads its photo step again.
            onTap: () => _push(Routes.inside(id, 'photos')),
          ),
        if (widget.org.isAdmin)
          HomeDestination(
            icon: Icons.route_outlined,
            label: context.tr('Mon chemin'),
            route: 'chemin',
            group: PlusGroup.vitrine,
            onTap: () => _push(Routes.inside(id, 'chemin')),
          ),
        if (widget.access.canSee('production'))
          HomeDestination(
            icon: Icons.precision_manufacturing_outlined,
            label: s.production,
            route: 'production',
            group: PlusGroup.vitrine,
            onTap: () => PathGate.open(context, widget.org, 'production',
                () => _push(Routes.inside(id, 'production')),
                afterPath: _refresh),
          ),
        // MON ÉQUIPE.
        if (widget.staff != null && widget.org.isAdmin)
          HomeDestination(
            icon: Icons.groups_outlined,
            label: context.tr('Équipe'),
            // Invitations not claimed yet (115).
            badge: homeCount('invitations'),
            route: 'equipe',
            group: PlusGroup.team,
            onTap: () => context.push(Routes.inside(id, 'equipe')),
          ),
        // The administration's hub (108), for whoever runs the farm.
        if (widget.org.isAdmin)
          HomeDestination(
            icon: Icons.admin_panel_settings_outlined,
            label: context.tr('Administration'),
            route: 'administration',
            group: PlusGroup.team,
            onTap: () => _push(Routes.inside(id, 'administration')),
          ),
        // Événementiel (152): the farm's cards for its guests (an open
        // day, a fair) — Marakaj's own admins' until the platform opens it.
        if (widget.org.isAdmin && eventsShownFor(context))
          HomeDestination(
            icon: Icons.celebration_outlined,
            label: context.tr('Événements'),
            route: 'evenements',
            group: PlusGroup.vitrine,
            onTap: () => _push(Routes.inside(id, 'evenements')),
          ),
        // MOI.
        HomeDestination(
          icon: Icons.account_circle_outlined,
          label: s.account,
          route: 'compte',
          group: PlusGroup.me,
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
      title: Text('${context.tr(label)} · ${event['subject']}'),
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
                        context.tr('{animals} animaux en {herds} groupe(s)', {'animals': shape.animals, 'herds': shape.herds}),
                      if (shape.hasCrops)
                        context.tr('{n} culture(s) en cours', {'n': shape.cropCycles}),
                      if (shape.harvestWeek > 0)
                        context.tr('{n} kg récoltés cette semaine', {'n': shape.harvestWeek.toStringAsFixed(0)}),
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
