import 'package:flutter/material.dart';
import '../../core/format/money.dart';

import '../../l10n/strings.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/retail/staff.dart';
import '../../core/db/local_db.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/invoicing/invoicing_repository.dart';
import 'farm_sheets.dart';
import '../../core/nav/router.dart';

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

  @override
  State<FarmHomeScreen> createState() => _FarmHomeScreenState();
}

class _FarmHomeScreenState extends State<FarmHomeScreen> {
  late final NumberFormat _currency = moneyFormat(widget.org.currency);

  ({int eggs, double deaths, double feedUsed}) _today =
      (eggs: 0, deaths: 0, feedUsed: 0);
  double _moneyIn = 0;
  double _moneyOut = 0;
  int _pending = 0;

  List<Map<String, Object?>> _events = const [];
  List<Map<String, Object?>> _flocks = const [];
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
  }

  Future<void> _refresh() async {
    final today = DateTime.now();

    // The device first and always. Whatever the network does after this, the
    // screen has numbers on it.
    final day = await widget.db.farmDay(widget.org.id, today);
    final totals = await widget.db.dayTotals(widget.org.id, today);
    final events = await widget.db.farmEventsForDay(widget.org.id, today);
    final pending = await widget.db.pendingCount();

    if (!mounted) return;
    setState(() {
      _today = day;
      _moneyIn = totals.moneyIn;
      _moneyOut = totals.moneyOut;
      _events = events;
      _pending = pending;
      _loading = false;
    });

    await _refreshFromServer();

    if (!mounted) return;
    final flocks = await widget.db.cachedFlocks(widget.org.id);
    final items = await widget.db.cachedFarmItems(widget.org.id);
    if (!mounted) return;
    setState(() {
      _flocks = flocks;
      _lowStock =
          items.where((i) => (i['below_reorder'] as int? ?? 0) == 1).toList();
    });
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

  Future<void> _open(Widget sheet) async {
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => sheet,
    );
    if (recorded == true) await _refresh();
  }

  Future<void> _recordFlockEvent() async {
    if (_flocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Aucune bande enregistrée. Ouvrez-en une dans « Bandes » — "
            'cela demande le réseau.',
          ),
        ),
      );
      return;
    }

    // One flock is the common case and needs no picker.
    final flock = _flocks.length == 1
        ? _flocks.first
        : await showModalBottomSheet<Map<String, Object?>>(
            context: context,
            builder: (_) => _FlockPicker(flocks: _flocks),
          );
    if (flock == null || !mounted) return;

    await _open(FlockEventSheet(
      db: widget.db,
      orgId: widget.org.id,
      flockId: flock['flock_id'] as String,
      batchCode: flock['batch_code'] as String,
      alive: flock['alive'] as int?,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.org.name),
        actions: [
          if (_pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.cloud_upload_outlined, size: 16),
                  label: Text(Strings.of(context).pendingCount(_pending)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          if (widget.access.canSee('credits'))
            IconButton(
              icon: const Icon(Icons.handshake_outlined),
              tooltip: Strings.of(context).creditBook,
              onPressed: () =>
                  context.push(Routes.inside(widget.org.id, 'credits')),
            ),
          if (widget.access.canSee('production'))
            IconButton(
              icon: const Icon(Icons.soup_kitchen_outlined),
              tooltip: Strings.of(context).production,
              onPressed: () =>
                  context.push(Routes.inside(widget.org.id, 'production')),
            ),
          if (widget.capture != null && widget.capture!.isConfigured)
            IconButton(
              icon: const Icon(Icons.photo_camera_outlined),
              tooltip: Strings.of(context).photos,
              onPressed: () =>
                  context.push(Routes.inside(widget.org.id, 'photos')),
            ),
          if (widget.staff != null && widget.org.isAdmin)
            IconButton(
              icon: const Icon(Icons.groups_outlined),
              tooltip: Strings.of(context).staffLabel,
              onPressed: () =>
                  context.push(Routes.inside(widget.org.id, 'personnel')),
            ),
          if (widget.accountAction != null) widget.accountAction!,
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _TodayCard(
                    day: _today,
                    moneyIn: _moneyIn,
                    moneyOut: _moneyOut,
                    currency: _currency,
                  ),

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

                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _NavCard(
                          tint: 0,
                          icon: Icons.inventory_2_outlined,
                          label: Strings.of(context).stock,
                          onTap: () =>
                              _push(Routes.inside(widget.org.id, 'stock')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NavCard(
                          tint: 1,
                          icon: Icons.pets_outlined,
                          label: Strings.of(context).flocks,
                          onTap: () =>
                              _push(Routes.inside(widget.org.id, 'bandes')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NavCard(
                          tint: 2,
                          icon: Icons.receipt_long_outlined,
                          label: Strings.of(context).invoices,
                          // The shared screen since 020. The farm-only one was
                          // built on outstanding_invoices(), so an invoice
                          // vanished from the app the moment it was paid and
                          // nobody could re-send a copy.
                          onTap: widget.invoicing == null
                              ? () {}
                              : () => _push(
                                  Routes.inside(widget.org.id, 'factures')),
                        ),
                      ),
                    ],
                  ),

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
              FloatingActionButton.small(
                heroTag: 'farm-receive',
                tooltip: Strings.of(context).stockReceipt,
                onPressed: () => _open(ReceiveStockSheet(
                  db: widget.db,
                  orgId: widget.org.id,
                  currency: widget.org.currency,
                )),
                backgroundColor: Colors.orange.shade100,
                foregroundColor: Colors.orange.shade900,
                child: const Icon(Icons.local_shipping_outlined),
              ),
              const SizedBox(width: 12),
              FloatingActionButton.small(
                heroTag: 'farm-consume',
                tooltip: Strings.of(context).feedGiven,
                onPressed: () => _open(MoveStockSheet(
                  db: widget.db,
                  orgId: widget.org.id,
                )),
                backgroundColor: Colors.brown.shade100,
                foregroundColor: Colors.brown.shade800,
                child: const Icon(Icons.restaurant_outlined),
              ),
              const SizedBox(width: 12),
              FloatingActionButton.small(
                heroTag: 'farm-mortality',
                tooltip: Strings.of(context).mortality,
                onPressed: _recordFlockEvent,
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
                child: const Icon(Icons.pets_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'farm-harvest',
            onPressed: () => _open(RecordHarvestSheet(
              db: widget.db,
              orgId: widget.org.id,
              flocks: _flocks,
              farm: widget.farm,
              // A farm that has never recorded a bird still gets the egg
              // option — the shape is empty on day one and guessing "no
              // poultry" from that would be worse than offering both.
              hasPoultry: _shape.hasPoultry || _shape.isEmpty,
            )),
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
    );
  }

  Future<void> _push(String location) async {
    await context.push(location);
    if (mounted) await _refresh();
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

    return Card(
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
            const SizedBox(height: 12),
            Text(
              '${day.eggs}',
              style: theme.textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: on),
            ),
            Text(Strings.of(context).eggsCollected,
                style: theme.textTheme.bodyMedium?.copyWith(color: on)),
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
                  : '${items.length} articles presque épuisés : $names.',
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
              "Chiffres de cet appareil seulement. Le stock et l'effectif des "
              'bandes se calculent sur tous les appareils et seront à jour au '
              'retour du réseau.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the square shortcuts under the day's figures.
///
/// These were six identical grey rectangles told apart only by a small icon
/// and a smaller word, which on a cheap screen in daylight means reading all
/// six. Each carries its own colour now, fixed by its position in the row, so
/// the one you want is found by where it is and what colour it is before its
/// label is read at all.
class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Position in the grid, not meaning: the point is that neighbours differ.
  final int tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = KajTheme.of(context).tint(tint);

    return Card(
      elevation: 0,
      // A tint of the colour rather than the colour: six saturated blocks
      // would shout over the figures above them, which are the point of the
      // screen.
      color: colour.withValues(alpha: 0.07),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  // A tint of the colour with the icon drawn in the colour
                  // itself. A white icon on a saturated chip failed contrast
                  // on four of the six tile colours.
                  color: colour.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: colour),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
        [trimQuantity(quantity), if (unit != null) unit].join(' '),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    );
  }
}

/// Which batch this event belongs to. Only shown when there is more than one
/// open — a single-house operation never sees it.
class _FlockPicker extends StatelessWidget {
  const _FlockPicker({required this.flocks});

  final List<Map<String, Object?>> flocks;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Text('Quelle bande ?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final flock in flocks)
            ListTile(
              leading: const Icon(Icons.pets_outlined),
              title: Text(flock['batch_code'] as String),
              subtitle: Text('${flock['alive']} oiseaux'),
              onTap: () => Navigator.pop(context, flock),
            ),
          const SizedBox(height: 16),
        ],
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Élevage et cultures', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              shape.isEmpty
                  ? 'Enregistrez vos animaux et vos parcelles.'
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
                        ? '${shape.animals} animaux'
                        : 'Animaux'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCrops,
                    icon: const Icon(Icons.grass, size: 18),
                    label: Text(shape.hasCrops
                        ? '${shape.cropCycles} cultures'
                        : 'Cultures'),
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
