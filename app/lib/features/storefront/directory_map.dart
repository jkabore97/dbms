import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/storefront/storefront_repository.dart';
import 'shop_style.dart';

/// Pins that sit on top of each other, grouped.
///
/// The audit: two shops 20 m apart drew one pin over the other, and only
/// one name could be read. Here every pin is placed in screen pixels at the
/// current zoom and pins closer than [radius] share one bubble with a
/// count; zooming in splits them. Pure, so it is tested on its own.
List<List<int>> groupNearby(List<Offset> points, {double radius = 44}) {
  final groups = <List<int>>[];
  final centres = <Offset>[];
  for (var i = 0; i < points.length; i++) {
    var placed = false;
    for (var g = 0; g < groups.length; g++) {
      if ((points[i] - centres[g]).distance <= radius) {
        groups[g].add(i);
        final n = groups[g].length;
        centres[g] = centres[g] + (points[i] - centres[g]) / n.toDouble();
        placed = true;
        break;
      }
    }
    if (!placed) {
      groups.add([i]);
      centres.add(points[i]);
    }
  }
  return groups;
}

/// "What is near me", answered full screen.
///
/// The audit: the map was a 340 px block pushed under a 480 px band, so a
/// shopper who tapped "Voir la carte" on a phone saw a map and no shops, and
/// it centred on the first shop rather than on them. Now the map is the
/// whole page, centred on the shopper (or fitted to every shop when they
/// have not said where they are), with a strip of shop cards along the
/// bottom: swipe a card and the map flies to its pin; tap a pin and the
/// strip turns to its card.
class DirectoryMapPage extends StatefulWidget {
  const DirectoryMapPage({
    super.key,
    required this.entries,
    required this.fallback,
    required this.onOpen,
    required this.onDirections,
    this.previews = const {},
    this.here,
    this.tiles = true,
  });

  final List<DirectoryEntry> entries;
  final Map<String, List<ShopPreview>> previews;
  final LatLng? here;
  final LatLng fallback;
  final void Function(DirectoryEntry) onOpen;
  final void Function(DirectoryEntry) onDirections;

  /// Draw the tile layer. Off in widget tests, which have no network.
  final bool tiles;

  @override
  State<DirectoryMapPage> createState() => _DirectoryMapPageState();
}

class _DirectoryMapPageState extends State<DirectoryMapPage> {
  final _map = MapController();
  late final PageController _strip =
      PageController(viewportFraction: 0.86);
  late final List<DirectoryEntry> _placed =
      widget.entries.where((e) => e.hasLocation).toList();
  int _selected = 0;
  bool _ready = false;

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  LatLng _at(DirectoryEntry e) => LatLng(e.lat!, e.lng!);

  MapOptions get _options {
    final here = widget.here;
    if (here != null) {
      return MapOptions(
        initialCenter: here,
        initialZoom: 14,
        onMapReady: () => setState(() => _ready = true),
        onPositionChanged: (_, _) => setState(() {}),
      );
    }
    if (_placed.length > 1) {
      return MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: [for (final e in _placed) _at(e)],
          padding: const EdgeInsets.fromLTRB(48, 96, 48, 200),
          maxZoom: 16,
        ),
        onMapReady: () => setState(() => _ready = true),
        onPositionChanged: (_, _) => setState(() {}),
      );
    }
    return MapOptions(
      initialCenter: _placed.isEmpty ? widget.fallback : _at(_placed.first),
      initialZoom: _placed.isEmpty ? 12 : 15,
      onMapReady: () => setState(() => _ready = true),
      onPositionChanged: (_, _) => setState(() {}),
    );
  }

  void _select(int index, {bool fromStrip = false}) {
    if (index < 0 || index >= _placed.length) return;
    setState(() => _selected = index);
    if (fromStrip) {
      _map.move(_at(_placed[index]), math.max(_map.camera.zoom, 14));
    } else if (_strip.hasClients) {
      _strip.animateToPage(index,
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    }
  }

  List<Marker> _markers() {
    final markers = <Marker>[];
    if (_placed.isEmpty) return markers;
    final groups = _ready
        ? groupNearby([
            for (final e in _placed) _map.camera.projectAtZoom(_at(e)),
          ])
        : [
            for (var i = 0; i < _placed.length; i++) [i]
          ];
    for (final g in groups) {
      if (g.length == 1) {
        final i = g.single;
        final e = _placed[i];
        final on = i == _selected;
        markers.add(Marker(
          point: _at(e),
          width: 160,
          height: 72,
          child: Semantics(
            button: true,
            label: e.name,
            hint: 'Voir la boutique',
            excludeSemantics: true,
            onTap: () => _select(i),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _select(i),
              child: Column(
                children: [
                  Icon(Icons.location_on,
                      size: on ? 40 : 32,
                      color: on ? ShopStyle.ink : ShopStyle.mist),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: on ? ShopStyle.ink : ShopStyle.paper,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: ShopStyle.line),
                    ),
                    child: Text(e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: on ? ShopStyle.paper : ShopStyle.ink)),
                  ),
                ],
              ),
            ),
          ),
        ));
      } else {
        final points = [for (final i in g) _at(_placed[i])];
        final lat = points.map((p) => p.latitude).reduce((a, b) => a + b) /
            points.length;
        final lng = points.map((p) => p.longitude).reduce((a, b) => a + b) /
            points.length;
        markers.add(Marker(
          point: LatLng(lat, lng),
          width: 48,
          height: 48,
          child: Semantics(
            button: true,
            label: '${g.length} boutiques ici',
            hint: 'Rapprocher la carte',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => _map.fitCamera(CameraFit.coordinates(
                coordinates: points,
                padding: const EdgeInsets.all(80),
                maxZoom: 19,
              )),
              child: Container(
                decoration: BoxDecoration(
                  color: ShopStyle.ink,
                  shape: BoxShape.circle,
                  border: Border.all(color: ShopStyle.paper, width: 3),
                ),
                alignment: Alignment.center,
                child: Text('${g.length}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ShopStyle.paper)),
              ),
            ),
          ),
        ));
      }
    }
    final here = widget.here;
    if (here != null) {
      markers.add(Marker(
        point: here,
        width: 22,
        height: 22,
        child: Semantics(
          label: 'Ma position',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF1F5FA8),
              shape: BoxShape.circle,
              border: Border.all(color: ShopStyle.paper, width: 3),
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final unplaced = widget.entries.length - _placed.length;
    return Theme(
      data: ShopStyle.theme(context),
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                mapController: _map,
                options: _options,
                children: [
                  if (widget.tiles)
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.kaj.app',
                    ),
                  MarkerLayer(markers: _markers()),
                ],
              ),
            ),
            // The way back, and what this is.
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Material(
                      color: ShopStyle.paper,
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: IconButton(
                        tooltip: 'Retour à la liste',
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Material(
                        color: ShopStyle.paper,
                        elevation: 2,
                        borderRadius: BorderRadius.circular(99),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Text(
                            _placed.isEmpty
                                ? "Aucune vitrine n'a indiqué sa position"
                                : unplaced == 0
                                    ? '${_placed.length} vitrine${_placed.length > 1 ? 's' : ''} sur la carte'
                                    : '${_placed.length} sur la carte · $unplaced sans position',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: ShopStyle.ink),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // The strip: one card per placed shop, in step with the pins.
            if (_placed.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 148,
                    child: PageView.builder(
                      controller: _strip,
                      itemCount: _placed.length,
                      onPageChanged: (i) => _select(i, fromStrip: true),
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 16),
                        child: _MapCard(
                          entry: _placed[i],
                          previews: widget.previews[_placed[i].slug] ?? const [],
                          onOpen: () => widget.onOpen(_placed[i]),
                          onDirections: () => widget.onDirections(_placed[i]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One shop on the strip: name, where, how far, a taste of its shelf, and
/// the two things to do — open the window, or go there.
class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.entry,
    required this.previews,
    required this.onOpen,
    required this.onDirections,
  });

  final DirectoryEntry entry;
  final List<ShopPreview> previews;
  final VoidCallback onOpen;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    final line = [
      if ((entry.address ?? '').trim().isNotEmpty) entry.address!.trim(),
      if (distanceLabel(entry.distanceKm) != null)
        distanceLabel(entry.distanceKm)!,
    ].join(' · ');
    final goods = previews.map((p) => p.name).join(' · ');
    return Material(
      color: ShopStyle.paper,
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ShopStyle.ink)),
              if (line.isNotEmpty)
                Text(line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
              if (goods.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(goods,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 13, color: ShopStyle.ink)),
                ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10)),
                      child: const Text('Voir la vitrine',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Itinéraire',
                    onPressed: onDirections,
                    icon: const Icon(Icons.directions_outlined, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
