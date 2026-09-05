import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../orders/orders.dart';

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

  // ----------------------------------------------------------------
  // Orders (055): the customer's side. All three need a signed-in caller;
  // the server refuses anyone else.
  // ----------------------------------------------------------------

  /// Sends a réservation to the shop at [slug]. [lines] maps a product id
  /// to a quantity. Returns the new order's id.
  Future<String> placeOrder(
    String slug, {
    required Map<String, double> lines,
    required String fulfilment,
    String? note,
    String? address,
    String? phone,
    String payment = 'cash',
    double? dropLat,
    double? dropLng,
  }) async {
    final id = await _requireClient().rpc('place_order', params: {
      'p_slug': slug,
      'p_lines': [
        for (final e in lines.entries)
          {'product_id': e.key, 'quantity': e.value},
      ],
      'p_fulfilment': fulfilment,
      'p_note': note,
      'p_address': address,
      'p_phone': phone,
      'p_payment': payment,
      'p_drop_lat': dropLat,
      'p_drop_lng': dropLng,
    });
    return id as String;
  }

  /// This customer's orders, newest first.
  Future<List<CustomerOrder>> myOrders() async {
    final rows = await _requireClient().rpc('my_orders') as List<dynamic>;
    return rows
        .map((r) => CustomerOrder.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Withdraws an order that the shop has not yet answered.
  Future<void> cancelOrder(String orderId) async {
    await _requireClient()
        .rpc('cancel_order', params: {'p_order_id': orderId});
  }

  /// The articles à la une (054): the paid spots on the welcome page.
  Future<List<FeaturedItem>> featured() async {
    final rows =
        await _requireClient().rpc('storefront_featured') as List<dynamic>;
    return rows
        .map((r) => FeaturedItem.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// One search across every window (059): the published articles of open
  /// vitrines whose name contains [query], accents and case ignored. With a
  /// position, each hit says how far its shop is and the nearer answer of a
  /// tie comes first. Under two letters the server answers nothing.
  Future<List<ProductHit>> searchProducts(
    String query, {
    double? lat,
    double? lng,
  }) async {
    final here = lat != null && lng != null;
    final rows = await _requireClient().rpc('search_products', params: {
      'p_query': query,
      if (here) 'p_lat': lat,
      if (here) 'p_lng': lng,
    }) as List<dynamic>;
    return rows
        .map((r) => ProductHit.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// What bringing an order from the shop at [slug] to a pin would cost
  /// (061): a number, or null when no price can be fixed — the shop has no
  /// pin, or no rate exists for its currency. Anyone may ask.
  Future<double?> deliveryQuote(String slug,
      {required double lat, required double lng}) async {
    final v = await _requireClient().rpc('delivery_quote', params: {
      'p_slug': slug,
      'p_lat': lat,
      'p_lng': lng,
    });
    return _num(v);
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
    this.lat,
    this.lng,
    this.waveMerchant,
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

  /// Where the shop is (054), when it placed itself; null otherwise.
  final double? lat;
  final double? lng;

  /// The shop's Wave merchant link (057), when it takes Wave.
  final String? waveMerchant;

  bool get hasLocation => lat != null && lng != null;

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
        lat: _num(row['lat']),
        lng: _num(row['lng']),
        waveMerchant: row['wave_merchant'] as String?,
      );
}

double? _num(Object? v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// An article à la une (054): one of the paid spots on the welcome page,
/// with the shop it belongs to so a tap can open that shop's window.
class FeaturedItem {
  const FeaturedItem({
    required this.id,
    required this.name,
    required this.price,
    required this.inStock,
    required this.shopName,
    required this.shopSlug,
    this.photoKey,
    this.currency = 'XOF',
  });

  final String id;
  final String name;
  final double price;
  final bool inStock;
  final String shopName;
  final String shopSlug;
  final String? photoKey;
  final String currency;

  factory FeaturedItem.fromRow(Map<String, dynamic> row) => FeaturedItem(
        id: row['id'] as String,
        name: row['name'] as String,
        price: _num(row['sale_price']) ?? 0.0,
        inStock: row['in_stock'] == true,
        shopName: (row['shop_name'] as String?) ?? '',
        shopSlug: (row['shop_slug'] as String?) ?? '',
        photoKey: row['photo_key'] as String?,
        currency: (row['currency'] as String?) ?? 'XOF',
      );
}

/// One answer of the search across every window (059): an article, the shop
/// whose window it is in, and — when the shopper said where they are — how
/// far that shop is.
class ProductHit {
  const ProductHit({
    required this.id,
    required this.name,
    required this.price,
    required this.inStock,
    required this.shopName,
    required this.shopSlug,
    this.photoKey,
    this.currency = 'XOF',
    this.shopLat,
    this.shopLng,
    this.distanceKm,
  });

  final String id;
  final String name;
  final double price;
  final bool inStock;
  final String shopName;
  final String shopSlug;
  final String? photoKey;
  final String currency;
  final double? shopLat;
  final double? shopLng;
  final double? distanceKm;

  factory ProductHit.fromRow(Map<String, dynamic> row) => ProductHit(
        id: row['id'] as String,
        name: row['name'] as String,
        price: _num(row['sale_price']) ?? 0.0,
        inStock: row['in_stock'] == true,
        shopName: (row['shop_name'] as String?) ?? '',
        shopSlug: (row['shop_slug'] as String?) ?? '',
        photoKey: row['photo_key'] as String?,
        currency: (row['currency'] as String?) ?? 'XOF',
        shopLat: _num(row['shop_lat']),
        shopLng: _num(row['shop_lng']),
        distanceKm: _num(row['distance_km']),
      );
}

/// The link that opens turn-by-turn directions to a pin in whatever maps
/// app the phone has — Google Maps on Android and in every browser. No key,
/// no billing, and the shopper is guided by the app they already trust.
String directionsUrl(double lat, double lng) =>
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';

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

/// Lower-cased and stripped of the accents French names carry — the same
/// folding the server's street search does (059), so filtering inside one
/// shop answers exactly like searching the whole street: "cafe" finds Café.
String foldSearchText(String text) {
  const accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };
  final lower = text.toLowerCase();
  final out = StringBuffer();
  // split('') walks UTF-16 units, which holds for every accent above —
  // all of them live in the basic plane.
  for (final ch in lower.split('')) {
    out.write(accents[ch] ?? ch);
  }
  return out.toString();
}

/// The public address of a vitrine, fit to be sent to anyone. On the web
/// the running origin is the truth (a preview stays a preview); in the
/// Android app there is no origin, so the production site is the address.
String publicShopUrl(String slug) {
  final origin = Uri.base.scheme.startsWith('http')
      ? Uri.base.origin
      : 'https://dbms.kabore-boss.workers.dev';
  return '$origin/s/$slug';
}

/// A WhatsApp link that opens the "send to…" picker with [text] already
/// typed — how a vitrine travels from one phone to the next here.
String whatsappShareUrl(String text) =>
    'https://wa.me/?text=${Uri.encodeComponent(text)}';

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

/// Great-circle distance in km between two points — the same haversine the
/// database uses for the directory and the delivery fee (061), so what a
/// courier reads on the map agrees with what the fee was priced on.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return r * 2 * math.asin(math.sqrt(a));
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
