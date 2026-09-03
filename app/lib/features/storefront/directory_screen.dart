import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/nav/router.dart';
import '../../core/storefront/storefront_repository.dart';
import 'shop_style.dart';

/// Every open vitrine, as tiles and on a map — for anyone, no account.
///
/// Ouagadougou has no street addresses a stranger can follow, which is why
/// the pin matters: "près de moi" asks the phone where it is once, and the
/// directory comes back nearest first with a distance on each tile. The map
/// is OpenStreetMap through flutter_map — no key, no bill, and a tile that
/// loads on a cheap phone. Tapping a shop, on a tile or a pin, opens its
/// window. Same street-side look as the window itself ([ShopStyle]).
class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key, required this.storefront});

  final StorefrontRepository storefront;

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  List<DirectoryEntry> _entries = const [];
  bool _loading = true;
  bool _locating = false;
  bool _map = false;
  String? _error;

  /// Where the shopper is, once they said so. Null until "près de moi".
  LatLng? _here;

  /// Ouagadougou's centre: where the map opens with nothing better to show.
  static const _ouaga = LatLng(12.3714, -1.5197);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!widget.storefront.isConfigured) {
      setState(() {
        _error = "L'annuaire a besoin d'une connexion.";
        _loading = false;
      });
      return;
    }
    try {
      final here = _here;
      final entries = await widget.storefront
          .directory(lat: here?.latitude, lng: here?.longitude);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "L'annuaire n'a pas pu être chargé. Vérifiez le réseau.";
        _loading = false;
      });
    }
  }

  /// Ask the phone where it is, once, then reload nearest first. Every way
  /// this can fail — refused, switched off, no fix — is said in words; the
  /// tiles are still there in name order, so nothing is lost by refusing.
  Future<void> _nearMe() async {
    setState(() => _locating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        messenger.showSnackBar(const SnackBar(
          content: Text("Sans votre position, l'annuaire reste par nom."),
        ));
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      _here = LatLng(position.latitude, position.longitude);
      await _load();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Position introuvable. Vérifiez que le GPS est activé.'),
      ));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _open(DirectoryEntry entry) =>
      context.go(Routes.storefront(entry.slug));

  @override
  Widget build(BuildContext context) {
    return ShopPage(
      title: 'Les vitrines',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ShopNotice(
                  text: _error!,
                  action: OutlinedButton(
                      onPressed: _load, child: const Text('Réessayer')),
                )
              : _Street(
                  entries: _entries,
                  here: _here,
                  fallback: _ouaga,
                  map: _map,
                  locating: _locating,
                  onNearMe: _nearMe,
                  onToggleMap: () => setState(() => _map = !_map),
                  onOpen: _open,
                ),
    );
  }
}

class _Street extends StatelessWidget {
  const _Street({
    required this.entries,
    required this.here,
    required this.fallback,
    required this.map,
    required this.locating,
    required this.onNearMe,
    required this.onToggleMap,
    required this.onOpen,
  });

  final List<DirectoryEntry> entries;
  final LatLng? here;
  final LatLng fallback;
  final bool map;
  final bool locating;
  final VoidCallback onNearMe;
  final VoidCallback onToggleMap;
  final void Function(DirectoryEntry) onOpen;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 560;
    final columns = ShopStyle.columnsFor(width);
    final placed = entries.where((e) => e.hasLocation).toList();
    final located = here != null;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ColoredBox(
          color: ShopStyle.stone,
          child: ShopWidth(
            padding: EdgeInsets.symmetric(
                horizontal: 20, vertical: wide ? 56 : 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Les boutiques,\nprès de vous.',
                  style: TextStyle(
                    fontSize: wide ? 40 : 30,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: ShopStyle.ink,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: const Text(
                    'Chaque vitrine est tenue par la boutique elle-même : '
                    'ses articles, ses prix, son numéro. Dites où vous êtes '
                    'et les plus proches passent en premier.',
                    style: TextStyle(
                        fontSize: 17, height: 1.45, color: ShopStyle.ink),
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: locating ? null : onNearMe,
                      icon: locating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: ShopStyle.paper),
                            )
                          : Icon(located ? Icons.near_me : Icons.my_location,
                              size: 18),
                      label: Text(located ? 'Actualiser' : 'Près de moi'),
                    ),
                    OutlinedButton.icon(
                      onPressed: entries.isEmpty ? null : onToggleMap,
                      icon: Icon(
                          map ? Icons.grid_view_outlined : Icons.map_outlined,
                          size: 18),
                      label: Text(map ? 'Masquer la carte' : 'Voir la carte'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        ShopWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (map) ...[
                const SizedBox(height: 24),
                SizedBox(
                  height: wide ? 460 : 320,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _MapView(
                      entries: placed,
                      here: here,
                      fallback: fallback,
                      onOpen: onOpen,
                    ),
                  ),
                ),
                if (placed.length < entries.length) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${entries.length - placed.length} vitrine'
                    '${entries.length - placed.length > 1 ? 's' : ''} '
                    "sans position n'apparaî"
                    '${entries.length - placed.length > 1 ? 'ssent' : 't'} '
                    'que dans la liste.',
                    style:
                        const TextStyle(fontSize: 13, color: ShopStyle.mist),
                  ),
                ],
              ],
              const SizedBox(height: 32),
              ShopSectionLabel(
                located ? 'Les plus proches' : 'Toutes les vitrines',
                note: entries.isEmpty
                    ? null
                    : '${entries.length} vitrine${entries.length > 1 ? 's' : ''}',
              ),
              const SizedBox(height: 18),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Aucune vitrine ouverte pour le moment.',
                      style: TextStyle(fontSize: 15, color: ShopStyle.mist)),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: wide ? 24 : 14,
                    mainAxisSpacing: wide ? 36 : 26,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _ShopTile(
                    entry: entries[i],
                    located: located,
                    onOpen: () => onOpen(entries[i]),
                  ),
                ),
              const ShopFooter(),
            ],
          ),
        ),
      ],
    );
  }
}

/// One shop: a warm square with its initial, the name, one line about it,
/// and — once the shopper said where they are — how far.
class _ShopTile extends StatelessWidget {
  const _ShopTile({
    required this.entry,
    required this.located,
    required this.onOpen,
  });

  final DirectoryEntry entry;
  final bool located;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final line = (entry.address ?? '').trim().isNotEmpty
        ? entry.address!.trim()
        : (entry.blurb ?? '').trim();
    final distance = distanceLabel(entry.distanceKm);
    final initial =
        entry.name.trim().isEmpty ? '·' : entry.name.trim()[0].toUpperCase();

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.15,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ColoredBox(
                color: ShopStyle.stone,
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w700,
                          color: ShopStyle.line,
                          height: 1,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 10,
                      child: Icon(_iconFor(entry.profile),
                          size: 18, color: ShopStyle.mist),
                    ),
                    if (distance != null)
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: ShopStyle.ink,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(distance,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ShopStyle.paper)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: ShopStyle.ink),
          ),
          const SizedBox(height: 3),
          Text(
            line.isNotEmpty
                ? line
                : (located && !entry.hasLocation
                    ? 'Position non renseignée'
                    : _labelFor(entry.profile)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String profile) => switch (profile) {
        'farm' => Icons.agriculture_outlined,
        'association' || 'church' => Icons.groups_outlined,
        _ => Icons.storefront_outlined,
      };

  static String _labelFor(String profile) => switch (profile) {
        'farm' => 'Ferme',
        'association' || 'church' => 'Association',
        _ => 'Boutique',
      };
}

class _MapView extends StatelessWidget {
  const _MapView({
    required this.entries,
    required this.here,
    required this.fallback,
    required this.onOpen,
  });

  final List<DirectoryEntry> entries;
  final LatLng? here;
  final LatLng fallback;
  final void Function(DirectoryEntry) onOpen;

  @override
  Widget build(BuildContext context) {
    final centre = here ??
        (entries.isNotEmpty
            ? LatLng(entries.first.lat!, entries.first.lng!)
            : fallback);

    return FlutterMap(
      options: MapOptions(initialCenter: centre, initialZoom: 13),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.kaj.app',
        ),
        MarkerLayer(
          markers: [
            if (here != null)
              Marker(
                point: here!,
                width: 22,
                height: 22,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ShopStyle.ink,
                    shape: BoxShape.circle,
                    border: Border.all(color: ShopStyle.paper, width: 3),
                  ),
                ),
              ),
            for (final e in entries)
              Marker(
                point: LatLng(e.lat!, e.lng!),
                width: 44,
                height: 44,
                child: GestureDetector(
                  onTap: () => onOpen(e),
                  child: Tooltip(
                    message: e.name,
                    child: const Icon(Icons.location_on,
                        size: 40, color: ShopStyle.ink),
                  ),
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }
}
