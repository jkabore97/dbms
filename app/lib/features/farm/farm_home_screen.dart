import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/db/local_db.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../capture/gallery_screen.dart';
import 'farm_sheets.dart';
import 'flocks_screen.dart';
import 'invoices_screen.dart';
import 'stock_screen.dart';

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
    required this.db,
    required this.org,
    this.farm,
    this.capture,
    this.accountAction,
  });

  final LocalDb db;
  final OrgSummary org;

  /// Null in a build with no server. The recording sheets still work; the
  /// stock and flock counts cannot be computed from one device.
  final FarmRepository? farm;

  /// Photographs — a feed delivery note, a vet's prescription. Null in a
  /// build with no server or no upload Worker.
  final CaptureRepository? capture;

  final Widget? accountAction;

  @override
  State<FarmHomeScreen> createState() => _FarmHomeScreenState();
}

class _FarmHomeScreenState extends State<FarmHomeScreen> {
  late final NumberFormat _currency = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: widget.org.currency == 'XOF' ? 'FCFA' : widget.org.currency,
    decimalDigits: 0,
  );

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
      _lowStock = items.where((i) => (i['below_reorder'] as int? ?? 0) == 1).toList();
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
                  label: Text('$_pending en attente'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          if (widget.capture != null && widget.capture!.isConfigured)
            IconButton(
              icon: const Icon(Icons.photo_camera_outlined),
              tooltip: 'Photos',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GalleryScreen(
                    org: widget.org,
                    capture: widget.capture!,
                  ),
                ),
              ),
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

                  if (_stale) ...[
                    const SizedBox(height: 12),
                    _StaleBanner(theme: theme),
                  ],

                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _NavCard(
                          icon: Icons.inventory_2_outlined,
                          label: 'Stock',
                          onTap: () => _push(StockScreen(
                            db: widget.db,
                            org: widget.org,
                            farm: widget.farm,
                          )),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NavCard(
                          icon: Icons.pets_outlined,
                          label: 'Bandes',
                          onTap: () => _push(FlocksScreen(
                            db: widget.db,
                            org: widget.org,
                            farm: widget.farm,
                          )),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NavCard(
                          icon: Icons.receipt_long_outlined,
                          label: 'Factures',
                          onTap: () => _push(InvoicesScreen(
                            org: widget.org,
                            farm: widget.farm,
                          )),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  Text("Aujourd'hui", style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_events.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          "Rien compté aujourd'hui.\n"
                          'Commencez par le ramassage.',
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

      // Ramassage is the large one: it happens every morning, it is the thing
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
                tooltip: 'Réception de stock',
                onPressed: () => _open(ReceiveStockSheet(
                  db: widget.db,
                  orgId: widget.org.id,
                  currencySymbol: widget.org.currency == 'XOF'
                      ? 'FCFA'
                      : widget.org.currency,
                )),
                backgroundColor: Colors.orange.shade100,
                foregroundColor: Colors.orange.shade900,
                child: const Icon(Icons.local_shipping_outlined),
              ),
              const SizedBox(width: 12),
              FloatingActionButton.small(
                heroTag: 'farm-consume',
                tooltip: 'Aliment distribué',
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
                tooltip: 'Mortalité',
                onPressed: _recordFlockEvent,
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
                child: const Icon(Icons.pets_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'farm-eggs',
            onPressed: () => _open(RecordEggsSheet(
              db: widget.db,
              orgId: widget.org.id,
              flocks: _flocks,
            )),
            backgroundColor: Colors.amber.shade700,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.egg_outlined, size: 28),
            label: const Text(
              'Ramassage',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            extendedPadding: const EdgeInsets.symmetric(horizontal: 28),
          ),
        ],
      ),
    );
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
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
    final on = theme.colorScheme.onPrimaryContainer;

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now()),
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: on.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 12),
            Text(
              '${day.eggs}',
              style: theme.textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: on),
            ),
            Text('œufs ramassés', style: theme.textTheme.bodyMedium?.copyWith(color: on)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: 'Mortalité',
                    value: trimQuantity(day.deaths),
                    tint: day.deaths > 0 ? theme.colorScheme.error : on,
                    on: on,
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Aliment sorti',
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
                      label: 'Reçu',
                      value: currency.format(moneyIn),
                      on: on,
                    ),
                  ),
                  Expanded(
                    child: _Figure(
                      label: 'Dépensé',
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
                  ? 'Il reste peu de $names.'
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

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, size: 26),
              const SizedBox(height: 6),
              Text(label, style: theme.textTheme.bodySmall),
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
      'eggs' => (Icons.egg_outlined, Colors.amber.shade800, 'Ramassage'),
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
      'mortality' => (Icons.pets_outlined, theme.colorScheme.error, 'Mortalité'),
      'adjusted' => (Icons.tune, Colors.blueGrey.shade600, 'Ajustement'),
      _ => (Icons.check_circle_outline, theme.colorScheme.primary, flockEventLabel(kind)),
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
          Text('Quelle bande ?', style: Theme.of(context).textTheme.titleMedium),
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
