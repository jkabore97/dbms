import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Whether a pin sits far outside where a business using [currency] is.
///
/// The audit: both open shops were pinned in Newark, New Jersey — "Utiliser
/// ma position" saved wherever the phone happened to be, and nothing showed
/// where that was. A franc CFA shop's pin outside West or Central Africa is
/// almost certainly the phone's position somewhere else, so it is said
/// before saving. Other currencies are not judged.
bool pinLooksMisplaced(double lat, double lng, String currency) {
  switch (currency) {
    case 'XOF': // UEMOA, generously boxed
      return !(lat >= 2 && lat <= 26 && lng >= -19 && lng <= 17);
    case 'XAF': // CEMAC
      return !(lat >= -6 && lat <= 24 && lng >= 7 && lng <= 30);
    default:
      return false;
  }
}

/// The shop's pin, seen before it is saved (package 3): a small map with
/// the pin on it, and a tap anywhere moves the pin there.
class PinPreview extends StatelessWidget {
  const PinPreview({
    super.key,
    required this.lat,
    required this.lng,
    required this.currency,
    required this.onMove,
    this.tiles = true,
  });

  final double lat;
  final double lng;
  final String currency;
  final void Function(double lat, double lng) onMove;

  /// Off in widget tests, which have no network.
  final bool tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = LatLng(lat, lng);
    final misplaced = pinLooksMisplaced(lat, lng, currency);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 190,
            child: FlutterMap(
              // A new key per pin: the map recentres when the pin moves
              // from a field, a link or a tap.
              key: ValueKey('$lat,$lng'),
              options: MapOptions(
                initialCenter: at,
                initialZoom: 15,
                onTap: (_, point) => onMove(point.latitude, point.longitude),
              ),
              children: [
                if (tiles)
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.kaj.app',
                  ),
                MarkerLayer(markers: [
                  Marker(
                    point: at,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: Icon(Icons.location_on,
                        size: 40, color: theme.colorScheme.primary),
                  ),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Touchez la carte pour déplacer le repère sur la porte.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (misplaced) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cette position est loin de la zone franc CFA. '
                    "Si le téléphone n'était pas à la boutique, touchez la "
                    'carte au bon endroit ou collez le lien Google Maps.',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
