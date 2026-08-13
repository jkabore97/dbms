import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/retail/staff.dart';
import '../capture/capture_action.dart';
import '../capture/gallery_screen.dart';
import 'products_screen.dart';
import 'staff_screen.dart';
import 'sale_sheet.dart';

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
    required this.org,
    this.retail,
    this.staff,
    this.capture,
    this.accountAction,
  });

  final OrgSummary org;

  /// Null in a build with no server.
  final RetailRepository? retail;

  /// Wages. Null in a build with no server, and every screen behind it is
  /// refused by RLS for anyone who is not an org admin.
  final StaffRepository? staff;

  /// Photographs. Null in a build with no server, and not configured in a
  /// build made before the upload Worker had a URL — in both cases the camera
  /// button is hidden rather than shown and failing.
  final CaptureRepository? capture;

  final Widget? accountAction;

  @override
  State<StoreHomeScreen> createState() => _StoreHomeScreenState();
}

class _StoreHomeScreenState extends State<StoreHomeScreen> {
  late final NumberFormat _money = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: widget.org.currency,
    decimalDigits: 0,
  );

  StoreDay _day = const StoreDay();
  List<ExpiringProduct> _expiring = const [];
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
        _error = '$error';
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
        retail: retail,
        capture: widget.capture,
        products: _products,
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

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryScreen(
          org: widget.org,
          capture: capture,
          retail: widget.retail,
        ),
      ),
    );
    await _load();
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
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Articles',
            onPressed: widget.retail == null
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProductsScreen(
                          org: widget.org,
                          retail: widget.retail!,
                        ),
                      ),
                    );
                    await _load();
                  },
          ),
          if (canPhotograph)
            IconButton(
              icon: const Icon(Icons.photo_library_outlined),
              tooltip: 'Photos',
              onPressed: _openGallery,
            ),
          if (widget.staff != null)
            IconButton(
              icon: const Icon(Icons.groups_outlined),
              tooltip: 'Personnel',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StaffScreen(
                      org: widget.org,
                      staff: widget.staff!,
                    ),
                  ),
                );
                await _load();
              },
            ),
          if (widget.accountAction != null) widget.accountAction!,
        ],
      ),
      // The camera is the primary action and the sale is the small one above
      // it. That is the wrong way round for a till and the right way round
      // for this shop: what a sale is worth is already known when it happens,
      // and what is lost is lost because nobody wrote the delivery down.
      floatingActionButton: (widget.retail == null && !canPhotograph)
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.retail != null)
                  FloatingActionButton.small(
                    heroTag: 'sell',
                    onPressed: _sell,
                    tooltip: 'Vente',
                    child: const Icon(Icons.point_of_sale),
                  ),
                if (widget.retail != null && canPhotograph)
                  const SizedBox(height: 12),
                if (canPhotograph)
                  FloatingActionButton.extended(
                    heroTag: 'photo',
                    onPressed: _photograph,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Photo'),
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
                      label: const Text('Réessayer'),
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
                      child: const Text('Envoyer'),
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
            _Panel(
              colour: theme.colorScheme.primaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Aujourd'hui", style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    _money.format(_day.netSales),
                    style: theme.textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_day.saleCount} vente${_day.saleCount > 1 ? 's' : ''}'
                    '${_day.returnsTotal > 0 ? ' · ${_money.format(_day.returnsTotal)} rendus' : ''}',
                    style: theme.textTheme.bodyMedium,
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
                          Text('Pertes évitées',
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
  const _Panel({required this.child, required this.colour});

  final Widget child;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}
