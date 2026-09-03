import 'package:flutter/material.dart';
import '../../core/format/money.dart';

import '../../l10n/strings.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/retail/staff.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../capture/capture_action.dart';
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

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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

      if (!mounted) return;
      setState(() {
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
        capture: widget.capture,
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
    final canPhotograph =
        widget.capture != null && widget.capture!.isConfigured;
    final atRisk = _expiring.fold<double>(0, (sum, p) => sum + p.valueAtRisk);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.org.name),
        actions: [
          // The bar carries only what a till reaches for many times a day.
          // Analyses, the carnet and the personnel are consulted, not worked
          // in, so they live under Compte instead of crowding this row.
          if (widget.access.canSee('production'))
            IconButton(
              icon: const Icon(Icons.soup_kitchen_outlined),
              tooltip: Strings.of(context).production,
              onPressed: () async {
                await context.push(Routes.inside(widget.org.id, 'production'));
                if (mounted) await _load();
              },
            ),
          if (widget.access.canSee('products'))
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: Strings.of(context).productsLabel,
            onPressed: widget.retail == null
                ? null
                : () async {
                    await context
                        .push(Routes.inside(widget.org.id, 'produits'));
                    if (mounted) await _load();
                  },
          ),
          if (canPhotograph && widget.access.canSee('photos'))
            IconButton(
              icon: const Icon(Icons.photo_library_outlined),
              tooltip: Strings.of(context).photos,
              onPressed: _openGallery,
            ),
          if (widget.invoicing != null && widget.access.canSee('invoices'))
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: Strings.of(context).invoices,
              onPressed: () =>
                  context.push(Routes.inside(widget.org.id, 'factures')),
            ),
          // Orders sent from the vitrine (055), with how many are waiting
          // for an answer. Only shown once the shop has opened its window —
          // before that there is nothing a customer could have ordered from.
          if (widget.retail != null && widget.access.canSee('orders'))
            IconButton(
              icon: Badge(
                isLabelVisible: _pendingOrders > 0,
                label: Text('$_pendingOrders'),
                child: const Icon(Icons.shopping_bag_outlined),
              ),
              tooltip: 'Commandes',
              onPressed: () async {
                await context.push(Routes.inside(widget.org.id, 'commandes'));
                if (mounted) await _load();
              },
            ),
          if (widget.accountAction != null) widget.accountAction!,
        ],
      ),
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
                  Text(
                    _money.format(_day.netSales),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: KajTheme.of(context).ink,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gradient == null ? colour : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
