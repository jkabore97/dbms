import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/db/local_db.dart';
import '../../core/theme/mara_mark.dart';

/// The WhatsApp status picture's five designs (batch 137). The owner: « the
/// user should have at least 3 to 5 choices of design, and multiple colors
/// to choose. So when they share it, they like what they're sharing, and
/// all the users don't have the same type of image. »
enum StatusDesign {
  /// The shop's photo on top, its name, four articles two by two.
  vitrine('Vitrine'),

  /// A magazine page: the name set like a masthead, a grid of articles on
  /// cards with their prices.
  grille('Grille'),

  /// One article, its big photo, its big price, « Commandez sur Mara ».
  vedette('Vedette'),

  /// A typographic poster: the name huge, the line, the articles as a
  /// price list. No photo needed: a shop with none yet looks finished.
  affiche('Affiche'),

  /// A banner with its ribbon (« Nouveautés », « Disponible »…) and three
  /// articles in rows.
  bandeau('Bandeau');

  const StatusDesign(this.label);

  /// Its name in the picker, French (the key of en.dart).
  final String label;

  static StatusDesign? named(String? name) {
    for (final d in values) {
      if (d.name == name) return d;
    }
    return null;
  }
}

/// One colour theme of the status picture: a curated set, never a free
/// colour picker, every text checked against what it sits on (WCAG AA:
/// 4.5:1 for the text, 3:1 for the big prices) by test/batch137_test.dart.
@immutable
class StatusPalette {
  const StatusPalette({
    required this.id,
    required this.label,
    required this.ground,
    required this.surface,
    required this.onSurface,
    required this.accent,
    required this.onAccent,
    required this.ink,
    required this.soft,
  });

  /// Kept on the device to remember the choice.
  final String id;

  /// Its name, French (the key of en.dart).
  final String label;

  /// The picture's background.
  final Color ground;

  /// Cards and panels on the ground, and [onSurface] the text on them.
  final Color surface;
  final Color onSurface;

  /// Prices, ribbons, rules; [onAccent] the text on it.
  final Color accent;
  final Color onAccent;

  /// The name and every main text on the ground; [soft] the lines under it.
  final Color ink;
  final Color soft;

  /// A dark ground: the light marks of Mara on it.
  bool get dark => ground.computeLuminance() < 0.25;

  /// The price on a card: the accent when it reads there (3:1, a big bold
  /// number), the card's own text otherwise.
  Color get priceOnSurface =>
      contrastRatio(accent, surface) >= 3 ? accent : onSurface;

  /// The accent drawn as text on the ground (a price, a label): itself when
  /// it reads there, the ground's ink otherwise.
  Color get accentOnGround => contrastRatio(accent, ground) >= 3 ? accent : ink;

  /// « Ma couleur »: the vitrine's own colour (068/093), or the business's
  /// app colour, made into a palette whose text stays legible — the colour
  /// is darkened (or, very light, kept with black type) until paper reads
  /// on it at 4.5:1.
  static StatusPalette own(Color colour) {
    final hsl = HSLColor.fromColor(colour.withValues(alpha: 1));
    Color ground = hsl.toColor();
    final onLight = contrastRatio(maraBlack, ground) >= 7 &&
        contrastRatio(maraPaper, ground) < 4.5;
    if (!onLight) {
      var l = hsl.lightness;
      while (contrastRatio(maraPaper, ground) < 5 && l > 0.05) {
        l -= 0.02;
        ground = hsl.withLightness(l).toColor();
      }
    }
    final g = HSLColor.fromColor(ground);
    final ink = onLight ? maraBlack : maraPaper;
    // The cards: a step lighter than the ground (whiter on a light one),
    // never so far that the ground's ink stops reading on them.
    var surface = ground;
    for (var step = 0.07; step > 0.005; step -= 0.01) {
      final s = onLight
          ? Color.lerp(ground, Colors.white, step * 8)!
          : g.withLightness(math.min(1.0, g.lightness + step)).toColor();
      if (contrastRatio(ink, s) >= 4.5) {
        surface = s;
        break;
      }
    }
    final onSurface = ink;
    // The accent: the colour's own hue, light on a dark ground and deep on
    // a light one; Mara's caramel or brown when the hue cannot read.
    var accent = onLight
        ? g.withLightness(0.28).withSaturation(math.min(g.saturation, 0.7)).toColor()
        : g.withLightness(0.80).withSaturation(math.min(g.saturation, 0.65)).toColor();
    if (contrastRatio(accent, ground) < 3) accent = onLight ? maraBrown : maraCaramel;
    if (contrastRatio(accent, ground) < 3) accent = ink;
    final onAccent = contrastRatio(maraBlack, accent) >= contrastRatio(maraPaper, accent)
        ? maraBlack
        : maraPaper;
    var soft = Color.lerp(ink, ground, 0.22)!;
    if (contrastRatio(soft, ground) < 4.5) soft = ink;
    return StatusPalette(
      id: ownId,
      label: 'Ma couleur',
      ground: ground,
      surface: surface,
      onSurface: onSurface,
      accent: accent,
      onAccent: onAccent,
      ink: ink,
      soft: soft,
    );
  }

  static const ownId = 'own';

  /// The curated themes, in the picker's order: Mara's own kit first, then
  /// a light one, then the colours of the street.
  static const curated = <StatusPalette>[
    StatusPalette(
      id: 'graphite',
      label: 'Graphite',
      ground: maraDeep,
      surface: Color(0xFF4C4A47),
      onSurface: maraPaper,
      accent: maraCaramel,
      onAccent: maraBlack,
      ink: maraPaper,
      soft: Color(0xFFD9D4CC),
    ),
    StatusPalette(
      id: 'nuit',
      label: 'Nuit',
      ground: maraBlack,
      surface: Color(0xFF221F1C),
      onSurface: maraPaper,
      accent: Color(0xFFD8B48A),
      onAccent: maraBlack,
      ink: maraPaper,
      soft: Color(0xFFBDB7AE),
    ),
    StatusPalette(
      id: 'papier',
      label: 'Papier',
      ground: maraPaper,
      surface: Color(0xFFFFFFFF),
      onSurface: maraBlack,
      accent: maraBrown,
      onAccent: maraPaper,
      ink: maraBlack,
      soft: Color(0xFF5E574F),
    ),
    StatusPalette(
      id: 'espresso',
      label: 'Espresso',
      ground: Color(0xFF2E1E15),
      surface: maraEspresso,
      onSurface: maraPaper,
      accent: Color(0xFFE2BF8F),
      onAccent: maraBlack,
      ink: maraPaper,
      soft: Color(0xFFE0CDB8),
    ),
    StatusPalette(
      id: 'caramel',
      label: 'Caramel',
      ground: maraCaramel,
      surface: maraPaper,
      onSurface: maraBlack,
      accent: maraEspresso,
      onAccent: maraPaper,
      ink: maraBlack,
      soft: Color(0xFF3A2A1E),
    ),
    StatusPalette(
      id: 'savane',
      label: 'Savane',
      ground: Color(0xFF23412E),
      surface: Color(0xFF2F5640),
      onSurface: maraPaper,
      accent: Color(0xFFE3C27A),
      onAccent: maraBlack,
      ink: maraPaper,
      soft: Color(0xFFCFE0D2),
    ),
    StatusPalette(
      id: 'terre',
      label: 'Terre cuite',
      ground: Color(0xFF9C4429),
      surface: Color(0xFF7E3520),
      onSurface: maraPaper,
      accent: Color(0xFFF6DDB0),
      onAccent: maraBlack,
      ink: maraPaper,
      soft: Color(0xFFF7E6D6),
    ),
  ];

  /// Every theme a business can pick: the curated ones, and « Ma couleur »
  /// first when it has a colour of its own.
  static List<StatusPalette> forShop(Color? own) => [
        if (own != null) StatusPalette.own(own),
        ...curated,
      ];
}

/// The WCAG contrast ratio of two opaque colours, 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// A design and a colour.
@immutable
class StatusChoice {
  const StatusChoice(this.design, this.paletteId);

  final StatusDesign design;
  final String paletteId;

  /// What a business gets before it chooses anything: a design and a
  /// colour from its id, so two shops that share without touching anything
  /// still post different pictures. A business with its own colour starts
  /// in it.
  factory StatusChoice.defaultFor(String orgId, {bool hasOwn = false}) {
    final h = stableHash(orgId);
    final design = StatusDesign.values[h % StatusDesign.values.length];
    final palette = hasOwn
        ? StatusPalette.ownId
        : StatusPalette.curated[(h ~/ StatusDesign.values.length) %
                StatusPalette.curated.length]
            .id;
    return StatusChoice(design, palette);
  }

  /// Another design and another colour, at random: never the one showing.
  StatusChoice surprise(List<StatusPalette> palettes, [math.Random? random]) {
    final r = random ?? math.Random();
    final designs = [for (final d in StatusDesign.values) if (d != design) d];
    final colours = [for (final p in palettes) if (p.id != paletteId) p.id];
    return StatusChoice(
      designs[r.nextInt(designs.length)],
      colours.isEmpty ? paletteId : colours[r.nextInt(colours.length)],
    );
  }

  /// The palette this choice names among [palettes]; the first one when it
  /// names one no longer there (« Ma couleur » after the colour was taken off).
  StatusPalette paletteIn(List<StatusPalette> palettes) =>
      palettes.firstWhere((p) => p.id == paletteId, orElse: () => palettes.first);

  String encode() => '${design.name}:$paletteId';

  static StatusChoice? decode(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final d = StatusDesign.named(parts[0]);
    if (d == null || parts[1].isEmpty) return null;
    return StatusChoice(d, parts[1]);
  }

  @override
  bool operator ==(Object other) =>
      other is StatusChoice && other.design == design && other.paletteId == paletteId;

  @override
  int get hashCode => Object.hash(design, paletteId);

  @override
  String toString() => encode();
}

/// FNV-1a over the id's code units: the same number on every phone, on the
/// web, and on every run (String.hashCode promises none of that). The
/// prime is 2^24 + 0x193, multiplied in two parts so no product passes
/// 2^53: on the web an int is a JavaScript double, and h * 0x01000193
/// (up to 2^56) would lose its low bits there — a business would get
/// another default picture in the browser than on its phone.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = (h ^ c) & 0xFFFFFFFF;
    h = (((h & 0xFF) << 24) + h * 0x193) & 0xFFFFFFFF;
  }
  return h;
}

/// Where the last choice is kept, per business, on this device.
abstract class StatusMemory {
  Future<String?> read(String key);
  Future<void> write(String key, String value);

  static String keyFor(String orgId) => 'status_design.$orgId';

  /// The last choice for [orgId], or null.
  static Future<StatusChoice?> recall(StatusMemory? memory, String orgId) async {
    if (memory == null) return null;
    try {
      return StatusChoice.decode(await memory.read(keyFor(orgId)));
    } catch (_) {
      return null;
    }
  }

  static Future<void> remember(StatusMemory? memory, String orgId, StatusChoice c) async {
    if (memory == null) return;
    try {
      await memory.write(keyFor(orgId), c.encode());
    } catch (_) {}
  }
}

/// The device's own preferences (LocalDb's device_prefs), as everything
/// else this device remembers.
class DbStatusMemory implements StatusMemory {
  const DbStatusMemory(this.db);

  final LocalDb db;

  @override
  Future<String?> read(String key) => db.readPref(key);

  @override
  Future<void> write(String key, String value) => db.writePref(key, value);
}
