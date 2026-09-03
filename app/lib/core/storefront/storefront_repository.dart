import 'package:supabase_flutter/supabase_flutter.dart';

/// The shop window, read by anyone (052).
///
/// A shopper has no account, so every call here is one of the SECURITY
/// DEFINER functions the database grants to `anon`: they name their columns
/// and return only what a shop window shows — name, price, in stock or not, a
/// photo. Nothing behind the counter ever comes through this door.
class StorefrontRepository {
  StorefrontRepository(this._client);

  final SupabaseClient? _client;

  /// A build with no backend cannot show a vitrine; the screen says so
  /// rather than spinning forever.
  bool get isConfigured => _client != null;

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('La vitrine a besoin d\'une connexion.');
    }
    return client;
  }

  /// The shop, or null when there is no open vitrine at that address — a
  /// slug nobody owns, a vitrine the shop closed, or a business the platform
  /// has suspended or archived. All three read the same to the street.
  Future<PublicShop?> shop(String slug) async {
    final rows = await _requireClient()
        .rpc('storefront', params: {'p_slug': slug}) as List<dynamic>;
    if (rows.isEmpty) return null;
    return PublicShop.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  /// The articles the shop chose to show, alphabetical.
  Future<List<PublicItem>> items(String slug) async {
    final rows = await _requireClient()
        .rpc('storefront_products', params: {'p_slug': slug}) as List<dynamic>;
    return rows
        .map((r) => PublicItem.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Every open vitrine (053). With a position, the placed shops come first,
  /// nearest first, each with its distance; the unplaced follow by name.
  /// Without one, all by name and no distance.
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) async {
    final here = lat != null && lng != null;
    final rows = await _requireClient().rpc('storefront_directory', params: {
      if (here) 'p_lat': lat,
      if (here) 'p_lng': lng,
    }) as List<dynamic>;
    return rows
        .map((r) =>
            DirectoryEntry.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}

/// One shop's window: who they are and how to reach them.
class PublicShop {
  const PublicShop({
    required this.orgId,
    required this.name,
    required this.slug,
    required this.profile,
    this.blurb,
    this.phone,
    this.address,
    this.theme,
    this.currency = 'XOF',
  });

  final String orgId;
  final String name;
  final String slug;
  final String profile;
  final String? blurb;
  final String? phone;
  final String? address;
  final String? theme;
  final String currency;

  factory PublicShop.fromRow(Map<String, dynamic> row) => PublicShop(
        orgId: row['org_id'] as String,
        name: row['name'] as String,
        slug: row['slug'] as String,
        profile: (row['profile'] as String?) ?? 'generic',
        blurb: row['blurb'] as String?,
        phone: row['phone'] as String?,
        address: row['address'] as String?,
        theme: row['theme'] as String?,
        currency: (row['currency'] as String?) ?? 'XOF',
      );
}

/// One article in the window. `inStock` is a yes/no on purpose: a shopper is
/// told whether to come, never how many are on the shelf.
class PublicItem {
  const PublicItem({
    required this.id,
    required this.name,
    required this.price,
    required this.inStock,
    this.photoKey,
  });

  final String id;
  final String name;
  final double price;
  final bool inStock;

  /// The R2 key of the newest photo the shop took of it, served publicly by
  /// the uploads Worker; null when there is none.
  final String? photoKey;

  factory PublicItem.fromRow(Map<String, dynamic> row) {
    final raw = row['sale_price'];
    final price = raw == null
        ? 0.0
        : (raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0);
    return PublicItem(
      id: row['id'] as String,
      name: row['name'] as String,
      price: price,
      inStock: row['in_stock'] == true,
      photoKey: row['photo_key'] as String?,
    );
  }
}

/// The WhatsApp link for a phone number, or null when there is none to link.
/// Numbers are stored as E.164 (+226 70 00 00 00); wa.me wants only digits.
String? whatsappUrl(String? phone) {
  if (phone == null) return null;
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  return 'https://wa.me/$digits';
}

/// One shop in the directory (053): the window, where it is, and — when the
/// shopper said where they are — how far.
class DirectoryEntry {
  const DirectoryEntry({
    required this.orgId,
    required this.name,
    required this.slug,
    required this.profile,
    this.blurb,
    this.address,
    this.lat,
    this.lng,
    this.distanceKm,
  });

  final String orgId;
  final String name;
  final String slug;
  final String profile;
  final String? blurb;
  final String? address;
  final double? lat;
  final double? lng;

  /// Great-circle distance from the shopper, in km; null when either side
  /// has no position.
  final double? distanceKm;

  bool get hasLocation => lat != null && lng != null;

  factory DirectoryEntry.fromRow(Map<String, dynamic> row) {
    double? num_(Object? v) => v == null
        ? null
        : (v is num ? v.toDouble() : double.tryParse('$v'));
    return DirectoryEntry(
      orgId: row['org_id'] as String,
      name: row['name'] as String,
      slug: row['slug'] as String,
      profile: (row['profile'] as String?) ?? 'generic',
      blurb: row['blurb'] as String?,
      address: row['address'] as String?,
      lat: num_(row['lat']),
      lng: num_(row['lng']),
      distanceKm: num_(row['distance_km']),
    );
  }
}

/// A distance a shopper reads at a glance: metres under a kilometre, one
/// decimal above. Null in, null out.
String? distanceLabel(double? km) {
  if (km == null) return null;
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1)} km';
}

/// The coordinates hidden in a Google Maps link, or typed as "lat, lng".
///
/// A shop that is already on Google Maps can paste its own link rather than
/// hunt for numbers. Full links carry the position in one of three shapes —
/// `@12.37,-1.52,17z`, `?q=12.37,-1.52`, or `!3d12.37!4d-1.52` — and a bare
/// "12.37, -1.52" is accepted too. The short `maps.app.goo.gl` links carry
/// nothing (they redirect), so this returns null for them and the screen says
/// to open the link and copy the full address. Anything off the world is null.
({double lat, double lng})? parseGoogleMapsLink(String text) {
  final s = text.trim();
  if (s.isEmpty) return null;
  const n = r'(-?\d+(?:\.\d+)?)';
  final patterns = [
    RegExp('@$n,$n'),
    RegExp('[?&]q=$n,$n'),
    RegExp('!3d$n!4d$n'),
    RegExp('^$n\\s*,\\s*$n\$'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(s);
    if (m == null) continue;
    final lat = double.tryParse(m.group(1)!);
    final lng = double.tryParse(m.group(2)!);
    if (lat == null || lng == null) continue;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return (lat: lat, lng: lng);
  }
  return null;
}
