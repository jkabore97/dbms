import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/nav/router.dart';
import '../../core/storefront/storefront_repository.dart';

/// Every open vitrine, as a list or on a map — for anyone, no account.
///
/// Ouagadougou has no street addresses a stranger can follow, which is why
/// the pin matters: "près de moi" asks the phone where it is once, and the
/// directory comes back nearest first with a distance on each row. The map
/// is OpenStreetMap through flutter_map — no key, no bill, and a tile that
/// loads on a cheap phone. Tapping a shop, in either view, opens its window.
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
  /// list is still there in name order, so nothing is lost by refusing.
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
    final theme = Theme.of(context);
    final placed = _entries.where((e) => e.hasLocation).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Les vitrines'),
        actions: [
          IconButton(
            tooltip: _map ? 'Voir la liste' : 'Voir la carte',
            icon: Icon(_map ? Icons.list_alt_outlined : Icons.map_outlined),
            onPressed: _loading ? null : () => setState(() => _map = !_map),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_loading || _locating) ? null : _nearMe,
        icon: _locating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(_here == null ? Icons.my_location : Icons.near_me),
        label: Text(_here == null ? 'Près de moi' : 'Actualiser'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _Notice(
                  text: _error!,
                  action: TextButton(
                      onPressed: _load, child: const Text('Réessayer')),
                )
              : _entries.isEmpty
                  ? const _Notice(text: 'Aucune vitrine ouverte pour le moment.')
                  : _map
                      ? _MapView(
                          entries: placed,
                          here: _here,
                          fallback: _ouaga,
                          onOpen: _open,
                        )
                      : _ListView(
                          entries: _entries,
                          located: _here != null,
                          onOpen: _open,
                          theme: theme,
                        ),
    );
  }
}

class _ListView extends StatelessWidget {
  const _ListView({
    required this.entries,
    required this.located,
    required this.onOpen,
    required this.theme,
  });

  final List<DirectoryEntry> entries;
  final bool located;
  final void Function(DirectoryEntry) onOpen;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = entries[i];
        final line = (e.address ?? '').trim().isNotEmpty
            ? e.address!.trim()
            : (e.blurb ?? '').trim();
        final distance = distanceLabel(e.distanceKm);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: Icon(_iconFor(e.profile)),
          ),
          title: Text(e.name),
          subtitle: line.isEmpty ? null : Text(line, maxLines: 1,
              overflow: TextOverflow.ellipsis),
          trailing: distance != null
              ? Text(distance,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.primary))
              : (located && !e.hasLocation
                  ? Icon(Icons.location_off_outlined,
                      size: 18, color: theme.colorScheme.onSurfaceVariant)
                  : const Icon(Icons.chevron_right)),
          onTap: () => onOpen(e),
        );
      },
    );
  }

  static IconData _iconFor(String profile) => switch (profile) {
        'farm' => Icons.agriculture_outlined,
        'association' || 'church' => Icons.groups_outlined,
        _ => Icons.storefront_outlined,
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
    final theme = Theme.of(context);
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
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
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
                    child: Icon(Icons.location_on,
                        size: 40, color: theme.colorScheme.error),
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

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined,
                size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
