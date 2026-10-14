import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// OpenStreetMap's tiles carry its credit, as its tile policy asks: on the
/// map, always, and a tap opens the copyright page. Shared by every map
/// that draws them (PinPicker, PinPreview, the street's map — 145).
class OsmCredit extends StatelessWidget {
  const OsmCredit({
    super.key,
    this.radius = const BorderRadius.only(topLeft: Radius.circular(6)),
  });

  /// The corner it is rounded on: the one facing into the map.
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    child: Material(
      color: Colors.white.withValues(alpha: 0.85),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () => launchUrl(
          Uri.parse('https://www.openstreetmap.org/copyright'),
          mode: LaunchMode.externalApplication,
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            '© OpenStreetMap',
            key: Key('osm-credit'),
            // The credit is the same in every language, and small.
            textScaler: TextScaler.noScaling,
            style: TextStyle(fontSize: 11, color: Color(0xFF333333)),
          ),
        ),
      ),
    ),
  );
}
