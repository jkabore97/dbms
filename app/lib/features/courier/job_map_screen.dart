import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/courier/courier_repository.dart';
import '../../core/format/money.dart';
import '../../core/nav/router.dart';
import '../../core/storefront/storefront_repository.dart';
import '../storefront/shop_style.dart';

/// One course, on a map: where I am, where the shop is, where the door is.
///
/// What actually guides a courier is three things — their own dot, the
/// pickup, the drop — and one line between them, following as they move.
/// That is all this draws. Turn-by-turn is deliberately *not* built in:
/// the phone's own maps app does it better than any routing provider we
/// could pay for, so the two big buttons hand the next leg to it and the
/// job board stays the dispatch.
///
/// The position follows through Geolocator's stream (the browser's
/// watchPosition on the web). Refused or absent, the map still shows the
/// two pins and says in words that the courier's own dot is missing.
class JobMapScreen extends StatefulWidget {
  const JobMapScreen({
    super.key,
    required this.orderId,
    required this.courier,
  });

  final String orderId;
  final CourierRepository courier;

  @override
  State<JobMapScreen> createState() => _JobMapScreenState();
}

class _JobMapScreenState extends State<JobMapScreen> {
  DeliveryJob? _job;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// The courier's own dot, and why it is missing when it is.
  LatLng? _me;
  String? _gpsNote;
  StreamSubscription<Position>? _watch;
  final _map = MapController();
  bool _framed = false;

  /// Ouagadougou's centre: where the map opens with nothing better to show.
  static const _ouaga = LatLng(12.3714, -1.5197);

  @override
  void initState() {
    super.initState();
    _load();
    _follow();
  }

  @override
  void dispose() {
    _watch?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mine = await widget.courier.mine();
      final job = mine.where((j) => j.orderId == widget.orderId).firstOrNull;
      if (!mounted) return;
      setState(() {
        _job = job;
        _loading = false;
        if (job == null) {
          _error = "Cette course n'est pas, ou plus, la vôtre.";
        }
      });
      _frame();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "La course n'a pas pu être chargée. Vérifiez le réseau.";
        _loading = false;
      });
    }
  }

  /// Follows the phone. Every way this can fail is said once, in words,
  /// and the map keeps its two pins.
  Future<void> _follow() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _gpsNote =
              'Sans votre position, la carte montre la boutique et le client.');
        }
        return;
      }
      _watch = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((position) {
        if (!mounted) return;
        setState(() {
          _me = LatLng(position.latitude, position.longitude);
          _gpsNote = null;
        });
        _frame();
      }, onError: (_) {
        if (mounted) {
          setState(() => _gpsNote =
              'Position introuvable. Vérifiez que le GPS est activé.');
        }
      });
    } catch (_) {
      // No location plugin on this platform (tests, an odd browser): the
      // map is still the two pins.
      if (mounted) {
        setState(() => _gpsNote = 'Position indisponible sur cet appareil.');
      }
    }
  }

  /// Fits everything that has a place on screen, once, when the first of
  /// them arrives — and again only if the courier's dot appears later. A
  /// map that re-frames on every GPS tick cannot be dragged.
  void _frame() {
    final points = [
      ?_me,
      if (_job?.shopHasPin ?? false) LatLng(_job!.shopLat!, _job!.shopLng!),
      if (_job?.hasDropPin ?? false) LatLng(_job!.dropLat!, _job!.dropLng!),
    ];
    if (points.isEmpty) return;
    final withMe = _me != null;
    if (_framed && !withMe) return;
    if (_framed && withMe && _framedWithMe) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (points.length == 1) {
          _map.move(points.first, 15);
        } else {
          _map.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(56),
          ));
        }
        _framed = true;
        _framedWithMe = withMe;
      } catch (_) {
        // The map is not laid out yet; the next tick tries again.
      }
    });
  }

  bool _framedWithMe = false;

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _mark(String status, String failed) async {
    setState(() => _busy = true);
    try {
      await widget.courier.mark(widget.orderId, status);
      if (!mounted) return;
      if (status == 'delivered') {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Livraison enregistrée. Merci !')));
        context.go(Routes.courier);
        return;
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    return ShopPage(
      title: job == null ? 'Course' : job.shopName,
      leading: IconButton(
        tooltip: 'Mes courses',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('${Routes.courier}?onglet=courses'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || job == null
              ? ShopNotice(
                  text: _error ?? "Cette course n'est pas la vôtre.",
                  action: OutlinedButton(
                      onPressed: () => context.go(Routes.courier),
                      child: const Text('Retour aux courses')),
                )
              : Column(
                  children: [
                    Expanded(child: _buildMap(job)),
                    _Panel(
                      job: job,
                      me: _me,
                      gpsNote: _gpsNote,
                      busy: _busy,
                      onOpen: _open,
                      onMark: _mark,
                    ),
                  ],
                ),
    );
  }

  Widget _buildMap(DeliveryJob job) {
    final shop = job.shopHasPin ? LatLng(job.shopLat!, job.shopLng!) : null;
    final drop = job.hasDropPin ? LatLng(job.dropLat!, job.dropLng!) : null;
    final centre = _me ?? drop ?? shop ?? _ouaga;
    // The leg still ahead: to the shop while the parcel is there, to the
    // door once it is on the moto.
    final next = job.status == 'ready' ? shop : drop;

    return FlutterMap(
      mapController: _map,
      options: MapOptions(initialCenter: centre, initialZoom: 14),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'bf.kaj.app',
        ),
        PolylineLayer(polylines: [
          if (shop != null && drop != null)
            Polyline(
                points: [shop, drop], color: ShopStyle.line, strokeWidth: 3),
          if (_me != null && next != null)
            Polyline(
                points: [_me!, next], color: ShopStyle.ink, strokeWidth: 3),
        ]),
        MarkerLayer(markers: [
          if (shop != null)
            _pin(shop, Icons.storefront, job.shopName),
          if (drop != null) _pin(drop, Icons.home, 'Client'),
          if (_me != null)
            Marker(
              point: _me!,
              width: 22,
              height: 22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A73E8),
                  shape: BoxShape.circle,
                  border: Border.all(color: ShopStyle.paper, width: 3),
                ),
              ),
            ),
        ]),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  /// A labelled pin: the icon at the top so the widget's centre — where
  /// flutter_map puts the point — is its tip, the name hanging below.
  static Marker _pin(LatLng point, IconData icon, String label) => Marker(
        point: point,
        width: 150,
        height: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: ShopStyle.ink),
            Container(
              constraints: const BoxConstraints(maxWidth: 146),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ShopStyle.paper,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: ShopStyle.line),
              ),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: ShopStyle.ink)),
            ),
          ],
        ),
      );
}

/// Under the map: the two legs with their distance from the courier's dot,
/// what the run pays, and the one button for the leg ahead.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.job,
    required this.me,
    required this.gpsNote,
    required this.busy,
    required this.onOpen,
    required this.onMark,
  });

  final DeliveryJob job;
  final LatLng? me;
  final String? gpsNote;
  final bool busy;
  final Future<void> Function(String url) onOpen;
  final Future<void> Function(String status, String failed) onMark;

  String? _from(double? lat, double? lng) {
    if (me == null || lat == null || lng == null) return null;
    return distanceLabel(distanceKm(me!.latitude, me!.longitude, lat, lng));
  }

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(job.currency);
    final toShop = _from(job.shopLat, job.shopLng);
    final toDoor = _from(job.dropLat, job.dropLng);
    final atShop = job.status == 'ready';
    final phone = (job.phone ?? '').trim();

    return Material(
      color: ShopStyle.paper,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _leg(Icons.storefront_outlined, 'Boutique',
                  (job.shopAddress ?? '').trim().isEmpty
                      ? job.shopName
                      : job.shopAddress!.trim(),
                  toShop,
                  bold: atShop),
              const SizedBox(height: 6),
              _leg(Icons.home_outlined, 'Client',
                  (job.dropAddress ?? '').trim().isEmpty
                      ? 'Adresse chez le client'
                      : job.dropAddress!.trim(),
                  toDoor,
                  bold: !atShop),
              if (gpsNote != null) ...[
                const SizedBox(height: 6),
                Text(gpsNote!,
                    style: const TextStyle(fontSize: 12, color: ShopStyle.mist)),
              ],
              const SizedBox(height: 10),
              Text(
                  job.deliveryFee == null
                      ? 'Course : prix à convenir'
                      : 'Course : ${money.format(job.deliveryFee!)}'
                          '${job.distanceKm == null ? '' : ' · ${job.distanceKm!.toStringAsFixed(1)} km'}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ShopStyle.ink)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (atShop && job.shopHasPin)
                    FilledButton.icon(
                      onPressed: () =>
                          onOpen(directionsUrl(job.shopLat!, job.shopLng!)),
                      icon: const Icon(Icons.directions_outlined, size: 18),
                      label: const Text('Vers la boutique'),
                    ),
                  if (job.hasDropPin)
                    (atShop ? OutlinedButton.icon : FilledButton.icon)(
                      onPressed: () =>
                          onOpen(directionsUrl(job.dropLat!, job.dropLng!)),
                      icon: const Icon(Icons.directions_outlined, size: 18),
                      label: const Text('Vers le client'),
                    ),
                  if (phone.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => onOpen('tel:$phone'),
                      icon: const Icon(Icons.call_outlined, size: 18),
                      label: const Text('Appeler'),
                    ),
                  if (atShop)
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => onMark('in_transit',
                              "Le retrait n'a pas pu être enregistré."),
                      child: const Text('Colis récupéré'),
                    )
                  else if (job.status == 'in_transit')
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => onMark('delivered',
                              "La livraison n'a pas pu être enregistrée."),
                      child: const Text('Livré'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leg(IconData icon, String label, String place, String? distance,
      {required bool bold}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: bold ? ShopStyle.ink : ShopStyle.mist),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$label · $place',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                  color: bold ? ShopStyle.ink : ShopStyle.mist)),
        ),
        if (distance != null)
          Text(distance,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ShopStyle.ink)),
      ],
    );
  }
}
