import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../orders/orders.dart';
import '../site/site.dart';
import '../theme/kaj_theme.dart' show paletteNamed;
import 'street_cache.dart';

/// The shop window, read by anyone (052).
///
/// A shopper has no account, so every call here is one of the SECURITY
/// DEFINER functions the database grants to `anon`: they name their columns
/// and return only what a shop window shows — name, price, in stock or not, a
/// photo. Nothing behind the counter ever comes through this door.
class StorefrontRepository {
  StorefrontRepository(this._client, {this.keep});

  final SupabaseClient? _client;

  /// The street's last look on this device (street_cache.dart): written on
  /// every answer, read when there is none. Null keeps nothing.
  final StreetCache? keep;

  /// When the last answer had to come from [keep] — the network failed —
  /// the time it was kept; null when it was fresh.
  DateTime? keptAt;

  /// [fetch]'s rows, kept under [key]; with no answer from the network,
  /// the rows kept last time (and [keptAt] says when), else the failure.
  Future<List<dynamic>> _rows(String key, Future<List<dynamic>> Function() fetch) async {
    try {
      final rows = await fetch();
      keptAt = null;
      final keep = this.keep;
      if (keep != null) unawaited(keep.put(key, rows));
      return rows;
    } catch (_) {
      final kept = await keep?.get(key);
      if (kept == null) rethrow;
      keptAt = kept.at ?? DateTime.now();
      return kept.list;
    }
  }

  /// A vitrine as this phone last saw it, at once, before the network
  /// answers: the shop, its shelf, whether it is a vitrine d'exemple, and
  /// when. Null when it was never opened here (or nothing is kept).
  Future<KeptVitrine?> keptVitrine(String slug) async {
    final keep = this.keep;
    if (keep == null) return null;
    final shop = await keep.get('storefront:$slug');
    final items = await keep.get('items:$slug');
    if (shop == null || items == null || shop.list.isEmpty) return null;
    final showcases = await keep.get('showcases');
    try {
      return KeptVitrine(
        shop: PublicShop.fromRow(Map<String, dynamic>.from(shop.list.first as Map)),
        items: [
          for (final r in items.list)
            PublicItem.fromRow(Map<String, dynamic>.from(r as Map)),
        ],
        showcase: showcases?.list.map((s) => '$s').contains(slug) ?? false,
        at: shop.at,
      );
    } catch (_) {
      return null;
    }
  }

  /// The street as this phone last saw it: every open vitrine and the
  /// three articles on each card. Null when nothing is kept.
  Future<KeptStreet?> keptStreet() async {
    final keep = this.keep;
    if (keep == null) return null;
    final entries = await keep.get('directory');
    if (entries == null || entries.list.isEmpty) return null;
    final previews = await keep.get('previews');
    try {
      final byShop = <String, List<ShopPreview>>{};
      for (final r in previews?.list ?? const []) {
        final p = ShopPreview.fromRow(Map<String, dynamic>.from(r as Map));
        byShop.putIfAbsent(p.slug, () => []).add(p);
      }
      return KeptStreet(
        entries: [
          for (final r in entries.list)
            DirectoryEntry.fromRow(Map<String, dynamic>.from(r as Map)),
        ],
        previews: byShop,
        at: entries.at,
      );
    } catch (_) {
      return null;
    }
  }

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
    final rows = await _rows('storefront:$slug', () async => await _requireClient()
        .rpc('storefront', params: {'p_slug': slug}) as List<dynamic>);
    if (rows.isEmpty) return null;
    return PublicShop.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  /// The articles the shop chose to show, alphabetical, each with how many
  /// a basket may hold (101's storefront_stock). A database before 101 has
  /// no such count: the basket is then uncapped, and the server decides.
  Future<List<PublicItem>> items(String slug) async {
    final rows = await _rows('items:$slug', () async {
      final client = _requireClient();
      // Both at once: on 3G each question is a round trip of half a second
      // or more, and the shelf waited for the two one after the other.
      final products = client
          .rpc('storefront_products', params: {'p_slug': slug})
          .then((v) => v as List<dynamic>);
      final stock = client
          .rpc('storefront_stock', params: {'p_slug': slug})
          .then((v) => v as List<dynamic>, onError: (Object _) => const <dynamic>[]);
      final shelf = await products;
      final left = <String, Object?>{};
      for (final r in await stock) {
        final m = r as Map;
        left['${m['id']}'] = m['stock_left'];
      }
      return [
        for (final r in shelf)
          {
            ...Map<String, dynamic>.from(r as Map),
            if (left.containsKey('${r['id']}')) 'stock_left': left['${r['id']}'],
          },
      ];
    });
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

  /// « Réserver » (125): one service, its day and time (Ouagadougou's
  /// clock, sent as UTC), how many when it is by the person or the hour,
  /// and the customer's words. Returns the booking's order id. A database
  /// before 125 has no such door: [BookingUnavailable].
  Future<String> bookService(
    String slug, {
    required String productId,
    required DateTime at,
    int quantity = 1,
    String? note,
    String? phone,
  }) async {
    try {
      final id = await _requireClient().rpc('book_service', params: {
        'p_slug': slug,
        'p_product_id': productId,
        'p_booked_for': at.toUtc().toIso8601String(),
        'p_quantity': quantity,
        'p_note': note,
        'p_phone': phone,
      });
      return id as String;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') throw const BookingUnavailable();
      rethrow;
    }
  }

  /// The business proposed another time (125): the customer takes it, and
  /// the booking is confirmed at it.
  Future<void> acceptBookingTime(String orderId) async {
    await _requireClient()
        .rpc('accept_booking_time', params: {'p_order_id': orderId});
  }

  /// This customer's orders, newest first.
  Future<List<CustomerOrder>> myOrders() async {
    final rows = await _requireClient().rpc('my_orders') as List<dynamic>;
    return rows
        .map((r) => CustomerOrder.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Where an order is (073): the timeline, the courier once on the road,
  /// the shop's phone and, for its shopper, the handover code. Null on a
  /// database before 073 or for somebody the order is not about.
  Future<OrderTracking?> tracking(String orderId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final v = await client
          .rpc('order_tracking', params: {'p_order_id': orderId});
      if (v is! Map) return null;
      return OrderTracking.fromJson(Map<String, dynamic>.from(v));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  /// Calls [onChange] whenever one of this shopper's orders moves (074).
  /// Returns the way to stop listening; a no-op when signed out.
  void Function() watchMyOrders(void Function() onChange) {
    final client = _client;
    final me = client?.auth.currentUser?.id;
    if (client == null || me == null) return () {};
    final channel = client
        .channel('my-orders-$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: me,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return () => client.removeChannel(channel);
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

  /// The basket's question about a pinned door, in numbers (069): the fee
  /// (null when none can be fixed), how far the door is, how far this shop
  /// delivers, and whether it is too far. Null when the shop has no pin.
  /// A database from before 069 has no delivery_check(); the old quote then
  /// answers, with no distance and never "too far".
  Future<DeliveryCheck?> deliveryCheck(String slug,
      {required double lat, required double lng}) async {
    try {
      final rows = await _requireClient().rpc('delivery_check', params: {
        'p_slug': slug,
        'p_lat': lat,
        'p_lng': lng,
      }) as List<dynamic>;
      if (rows.isEmpty) return null;
      return DeliveryCheck.fromRow(Map<String, dynamic>.from(rows.first as Map));
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
      final fee = await deliveryQuote(slug, lat: lat, lng: lng);
      return DeliveryCheck(fee: fee);
    }
  }

  /// Three articles per shop for the directory's cards (070), photographed
  /// first. Keyed by slug; a shop with nothing to preview is simply absent.
  /// A database before 070 has no previews: the cards fall back quietly.
  Future<Map<String, List<ShopPreview>>> previews(List<String> slugs) async {
    if (slugs.isEmpty) return const {};
    try {
      final rows = await _rows('previews', () async => await _requireClient()
          .rpc('storefront_previews', params: {'p_slugs': slugs}) as List<dynamic>);
      final out = <String, List<ShopPreview>>{};
      for (final r in rows) {
        final p = ShopPreview.fromRow(Map<String, dynamic>.from(r as Map));
        out.putIfAbsent(p.slug, () => []).add(p);
      }
      return out;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return const {};
      rethrow;
    }
  }

  /// The shops paying for the top of the directory right now (071). Empty
  /// on a database before 071, or with no signal: the list is still the list.
  Future<Set<String>> spotlights() async {
    try {
      final rows =
          await _requireClient().rpc('storefront_spotlights') as List<dynamic>;
      return {for (final r in rows) '${(r as Map)['slug']}'};
    } catch (_) {
      return const {};
    }
  }

  /// Counts a look at the street (071): 'opened' (a window, or with
  /// [productId] an article's sheet), 'seen', or 'added' to a basket. Never
  /// awaited by a screen and never fails one: the numbers are indicative.
  Future<void> recordVisit(String slug, String kind, {String? productId}) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.rpc('record_visit', params: {
        'p_slug': slug,
        'p_kind': kind,
        'p_product_id': productId,
      });
    } catch (_) {}
  }

  /// One distinct visitor of this vitrine today (084): the device's own
  /// random id, so the shop's cauris count people, not reloads. Never
  /// awaited by a screen and never fails one.
  Future<void> recordVisitor(String slug, String visitorId) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.rpc('record_visitor',
          params: {'p_slug': slug, 'p_visitor': visitorId});
    } catch (_) {}
  }

  /// This device opened the vitrine (123): counted once a day, never for
  /// the business's own people. Answers the vitrine's unique visitors of
  /// all time, or null — a database before 123, no network, a vitrine the
  /// street cannot open. Never awaited by the page and never fails it.
  Future<int?> recordVitrineVisit(String slug, String visitorId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final n = await client.rpc('record_vitrine_visit',
          params: {'p_slug': slug, 'p_visitor': visitorId});
      return n is num ? n.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  /// Counts the articles of a strip as seen, in one call (071).
  Future<void> recordSeen(List<String> productIds) async {
    final client = _client;
    if (client == null || productIds.isEmpty) return;
    try {
      await client.rpc('record_seen', params: {'p_product_ids': productIds});
    } catch (_) {}
  }

  /// Every open vitrine (053). With a position, the placed shops come first,
  /// nearest first, each with its distance; the unplaced follow by name.
  /// Without one, all by name and no distance.
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) async {
    final here = lat != null && lng != null;
    final rows = await _rows('directory', () async => await _requireClient()
        .rpc('storefront_directory', params: {
          if (here) 'p_lat': lat,
          if (here) 'p_lng': lng,
        }) as List<dynamic>);
    return rows
        .map((r) =>
            DirectoryEntry.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<Set<String>>? _showcases;

  /// The vitrines d'exemple on the street (094), by slug: « Pas à
  /// proximité », and no order. Asked once per app run; a failure is no
  /// showcase, never an error on the page.
  Future<Set<String>> showcaseSlugs() {
    final client = _client;
    if (client == null) return Future.value(const {});
    return _showcases ??= () async {
      try {
        final rows = await client.rpc('showcase_slugs') as List<dynamic>;
        final slugs = {for (final r in rows) r is Map ? '${r.values.first}' : '$r'};
        final keep = this.keep;
        if (keep != null) unawaited(keep.put('showcases', slugs.toList()));
        return slugs;
      } catch (_) {
        _showcases = null;
        final kept = await keep?.get('showcases');
        return {for (final s in kept?.list ?? const []) '$s'};
      }
    }();
  }
}

/// The server has no booking yet (a database before 125): « Réservation
/// indisponible pour le moment », and the goods are ordered as ever.
class BookingUnavailable implements Exception {
  const BookingUnavailable();
}

/// One shop's window: who they are and how to reach them.
/// The Pro dressing of a window (068): what a paying shop may change
/// within the street's one design. Read from `storefront()`, which sends
/// `{}` for a Free or lapsed business, and written through
/// `set_storefront_style()`, which validates every key.
class StorefrontStyle {
  const StorefrontStyle({
    this.tagline,
    this.hours,
    this.accent,
    this.coverKey,
    this.pinned = const [],
    this.hideOutOfStock = false,
    this.logoKey,
    this.delivers = false,
    this.topWeekRank,
    this.topWeekLeague,
    this.layout = VitrineLayout.grid,
    this.schedule,
    this.openNow,
    this.ordersClosed = false,
  });

  static const none = StorefrontStyle();

  /// How the shelf is drawn (093, Pro): grille, grandes photos, liste, menu.
  final VitrineLayout layout;

  /// The days and times the shop is open (093, every plan); [hours] is the
  /// line written from it.
  final VitrineSchedule? schedule;

  /// « Ouvert maintenant » / « Fermé », said by the server from [schedule]
  /// in Ouagadougou's time (093, Pro). Null: no banner.
  final bool? openNow;

  /// « Commandes en ligne » hidden by Mara's switchboard (110): the vitrine
  /// is a showcase — its shelf, no basket. Said by storefront() only then;
  /// like the logo, no dressing.
  final bool ordersClosed;

  /// One line under the name, 80 characters at most.
  final String? tagline;

  /// "Lun–Sam 8h–19h", 120 characters at most.
  final String? hours;

  /// The buttons' colour.
  final Color? accent;

  /// One of the shop's own photographs, over the band.
  final String? coverKey;

  /// Up to six article ids held at the top of the shelf, in this order.
  final List<String> pinned;

  /// Out-of-stock articles left off the shelf rather than greyed.
  final bool hideOutOfStock;

  /// The shop's own logo (080), for every plan — not a Pro dressing, so it
  /// counts for neither [isEmpty] nor [toJson]: set_org_logo() sets it.
  final String? logoKey;

  /// Whether the shop delivers (081): Kaj Pro and pinned on the map, said
  /// by storefront() for every plan. Like the logo, no dressing.
  final bool delivers;

  /// Last week's top 3 of its league (086): the rank and the league, for
  /// the badge on the window. Null when it was not on the podium.
  final int? topWeekRank;
  final String? topWeekLeague;

  bool get isEmpty =>
      tagline == null &&
      hours == null &&
      accent == null &&
      coverKey == null &&
      pinned.isEmpty &&
      !hideOutOfStock &&
      layout == VitrineLayout.grid &&
      schedule == null;

  factory StorefrontStyle.fromJson(Map<String, dynamic>? json) {
    if (json == null) return none;
    String? s(String key) {
      final v = json[key];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    final pinned = json['pinned'];
    return StorefrontStyle(
      tagline: s('tagline'),
      hours: s('hours'),
      accent: colorFromHex(s('accent')),
      coverKey: s('cover_key'),
      pinned: pinned is List ? pinned.map((e) => e.toString()).toList() : const [],
      hideOutOfStock: json['hide_out_of_stock'] == true,
      logoKey: s('logo_key'),
      delivers: json['delivers'] == true,
      topWeekRank: json['top_week'] is Map
          ? ((json['top_week'] as Map)['rank'] as num?)?.toInt()
          : null,
      topWeekLeague: json['top_week'] is Map
          ? (json['top_week'] as Map)['league'] as String?
          : null,
      layout: VitrineLayout.parse(s('layout')),
      schedule: VitrineSchedule.fromJson(json['schedule']),
      openNow: json['open_now'] is bool ? json['open_now'] as bool : null,
      ordersClosed: json['orders_closed'] == true,
    );
  }

  StorefrontStyle copyWith({
    VitrineLayout? layout,
    List<String>? pinned,
    bool? hideOutOfStock,
  }) =>
      StorefrontStyle(
        tagline: tagline,
        hours: hours,
        accent: accent,
        coverKey: coverKey,
        pinned: pinned ?? this.pinned,
        hideOutOfStock: hideOutOfStock ?? this.hideOutOfStock,
        logoKey: logoKey,
        delivers: delivers,
        topWeekRank: topWeekRank,
        topWeekLeague: topWeekLeague,
        layout: layout ?? this.layout,
        schedule: schedule,
        openNow: openNow,
        ordersClosed: ordersClosed,
      );

  Map<String, Object?> toJson() => {
        if (tagline != null) 'tagline': tagline,
        if (hours != null) 'hours': hours,
        if (accent != null) 'accent': hexOf(accent!),
        if (coverKey != null) 'cover_key': coverKey,
        if (pinned.isNotEmpty) 'pinned': pinned,
        if (hideOutOfStock) 'hide_out_of_stock': true,
        if (layout != VitrineLayout.grid) 'layout': layout.name,
        if (schedule != null) 'schedule': schedule!.toJson(),
      };

  /// '#RRGGBB' → a colour; anything else → null.
  static Color? colorFromHex(String? hex) {
    if (hex == null) return null;
    final m = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(hex.trim());
    if (m == null) return null;
    return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
  }

  static String hexOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// The shelf as the style orders it: pinned articles first, in their
  /// order, then the rest as they came; out-of-stock left off when asked.
  List<PublicItem> arrange(List<PublicItem> items) {
    final kept = hideOutOfStock ? items.where((i) => i.inStock).toList() : items;
    if (pinned.isEmpty) return kept;
    final rank = {for (var i = 0; i < pinned.length; i++) pinned[i]: i};
    final first = <PublicItem>[];
    final rest = <PublicItem>[];
    for (final item in kept) {
      (rank.containsKey(item.id) ? first : rest).add(item);
    }
    first.sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
    return [...first, ...rest];
  }
}

/// How a vitrine's shelf is drawn (093). Grille is the street's common
/// design; the others are Mara Pro.
enum VitrineLayout {
  grid,
  large,
  list,
  menu;

  static VitrineLayout parse(String? name) => VitrineLayout.values
      .firstWhere((l) => l.name == name, orElse: () => VitrineLayout.grid);
}

/// The days and hours a shop is open (093): ISO days (1 = lundi) and two
/// « HH:MM » times. A close before the open is a night shop.
class VitrineSchedule {
  const VitrineSchedule(
      {required this.days, required this.open, required this.close});

  final List<int> days;
  final String open;
  final String close;

  static final _time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  bool get isValid =>
      days.isNotEmpty &&
      _time.hasMatch(open) &&
      _time.hasMatch(close) &&
      open != close;

  static VitrineSchedule? fromJson(Object? json) {
    if (json is! Map) return null;
    final days = json['days'];
    final open = json['open'];
    final close = json['close'];
    if (days is! List || open is! String || close is! String) return null;
    final s = VitrineSchedule(
      days: (days.whereType<num>().map((d) => d.toInt()).toList()..sort()),
      open: open,
      close: close,
    );
    return s.isValid ? s : null;
  }

  Map<String, Object?> toJson() =>
      {'days': [...days]..sort(), 'open': open, 'close': close};

  static const _fr = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  static const _en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// « 8h », « 8h30 » — or « 8:30 » in English.
  static String clock(String hhmm, [String lang = 'fr']) {
    final h = int.parse(hhmm.substring(0, 2));
    final m = hhmm.substring(3);
    if (lang == 'en') return m == '00' ? '$h:00' : '$h:$m';
    return m == '00' ? '${h}h' : '${h}h$m';
  }

  /// « Lun–Sam 8h–19h », « Lun, Mer–Ven 7h30–18h », « Tous les jours … ».
  String label([String lang = 'fr']) {
    final names = lang == 'en' ? _en : _fr;
    final sorted = [...days]..sort();
    final String when;
    if (sorted.length == 7) {
      when = lang == 'en' ? 'Every day' : 'Tous les jours';
    } else {
      final runs = <String>[];
      var i = 0;
      while (i < sorted.length) {
        var j = i;
        while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
          j++;
        }
        runs.add(j == i
            ? names[sorted[i] - 1]
            : j == i + 1
                ? '${names[sorted[i] - 1]}, ${names[sorted[j] - 1]}'
                : '${names[sorted[i] - 1]}–${names[sorted[j] - 1]}');
        i = j + 1;
      }
      when = runs.join(', ');
    }
    return '$when ${clock(open, lang)}–${clock(close, lang)}';
  }
}

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
    this.style = StorefrontStyle.none,
    this.visitors,
  });

  /// The Pro dressing (068); [StorefrontStyle.none] for everyone else.
  final StorefrontStyle style;

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

  /// The vitrine's unique visitors of all time (123), from its first one;
  /// null before then, or on a database before 123.
  final int? visitors;

  bool get hasLocation => lat != null && lng != null;

  /// Delivery is offered (081): the shop is Pro and on the map.
  bool get delivers => hasLocation && style.delivers;

  /// The vitrine's colour: the one its owner chose for it (068/093), else
  /// the colour the business chose for its own app (022, Paramètres ›
  /// Couleurs) — the business's own design on its window too (122). Null
  /// when it chose neither: the street's black, Mara's own look.
  Color? get accent => style.accent ?? paletteNamed(theme)?.ink;

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
        // Absent before 068, or a Free shop: the common design.
        style: row['style'] is Map
            ? StorefrontStyle.fromJson(
                Map<String, dynamic>.from(row['style'] as Map))
            : StorefrontStyle.none,
        // 123 says it in the style, and only from the first visitor.
        visitors: row['style'] is Map && (row['style'] as Map)['visitors'] is num
            ? ((row['style'] as Map)['visitors'] as num).toInt()
            : null,
      );
}

double? _num(Object? v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// An article à la une (054): one of the paid spots on the welcome page,
/// with the shop it belongs to so a tap can open that shop's window.
/// One article on a directory card (070).
class ShopPreview {
  const ShopPreview({
    required this.slug,
    required this.productId,
    required this.name,
    required this.price,
    this.photoKey,
  });

  factory ShopPreview.fromRow(Map<String, dynamic> row) => ShopPreview(
        slug: row['slug'] as String,
        productId: row['product_id'] as String,
        name: row['name'] as String,
        price: _num(row['sale_price']) ?? 0.0,
        photoKey: row['photo_key'] as String?,
      );

  final String slug;
  final String productId;
  final String name;
  final double price;
  final String? photoKey;
}

/// What delivery_check() says about one pinned door (069).
class DeliveryCheck {
  const DeliveryCheck({
    this.fee,
    this.distanceKm,
    this.maxKm,
    this.tooFar = false,
  });

  factory DeliveryCheck.fromRow(Map<String, dynamic> row) => DeliveryCheck(
        fee: _num(row['fee']),
        distanceKm: _num(row['distance_km']),
        maxKm: _num(row['max_km']),
        tooFar: row['too_far'] == true,
      );

  /// The price of the run; null when none can be fixed ("à discuter").
  final double? fee;
  final double? distanceKm;

  /// How far this shop delivers; null on a database before 069.
  final double? maxKm;

  /// Beyond the shop's reach: the order would be refused.
  final bool tooFar;
}

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

/// One article in the window. `inStock` is what the window shows: a shopper
/// is told whether to come, not a count. [stockLeft] only stops the basket's
/// stepper at what is on the shelf (101: no order for more than is left).
class PublicItem {
  const PublicItem({
    required this.id,
    required this.name,
    required this.price,
    required this.inStock,
    this.photoKey,
    this.description,
    this.unit,
    this.availableFrom,
    this.isService = false,
    this.priceFrom = false,
    this.stockLeft,
  });

  final String id;
  final String name;
  final double price;
  final bool inStock;

  /// How many a basket may hold; null when there is no count to keep (a
  /// service, a pre-order, a database before 101).
  final double? stockLeft;

  /// A service (098): its own section, « Réserver », never « épuisé ».
  final bool isService;

  /// « à partir de 5 000 F » (098): the price is where it starts.
  final bool priceFrom;

  /// « plateau », « kg », « tête » (083): shown after the price. Null is a
  /// plain price, the way a shop's article reads.
  final String? unit;

  /// A pre-order (083): the day it will be there. Null when it is there now.
  final DateTime? availableFrom;

  bool get isPreorder => availableFrom != null;

  /// The R2 key of the newest photo the shop took of it, served publicly by
  /// the uploads Worker; null when there is none.
  final String? photoKey;

  /// What the shop wrote about it for the street (064); null when nothing.
  final String? description;

  bool get hasDescription => description != null && description!.isNotEmpty;

  factory PublicItem.fromRow(Map<String, dynamic> row) {
    final raw = row['sale_price'];
    final price = raw == null
        ? 0.0
        : (raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0);
    // Absent before 098: goods, at their plain price.
    final service = row['is_service'] == true;
    return PublicItem(
      id: row['id'] as String,
      name: row['name'] as String,
      price: price,
      // A service has no stock to run out of.
      inStock: service || row['in_stock'] == true,
      isService: service,
      priceFrom: row['price_from'] == true,
      photoKey: row['photo_key'] as String?,
      // Absent from a database before 064: no description, not an error.
      description: (row['description'] as String?)?.trim().isEmpty == true
          ? null
          : row['description'] as String?,
      // Absent before 083: a plain price, there now.
      unit: (row['unit'] as String?)?.trim().isEmpty == true
          ? null
          : row['unit'] as String?,
      availableFrom: row['available_from'] == null
          ? null
          : DateTime.tryParse('${row['available_from']}'),
      stockLeft: service ? null : (row['stock_left'] as num?)?.toDouble(),
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

/// The public address of a vitrine, fit to be sent to anyone: always the
/// site's own name (marakaj.com), whatever address the app was opened at —
/// a link sent from the old workers.dev address kept that address alive.
/// Only a build running on this machine (localhost) shares its own origin,
/// so a test link stays a test link.
String publicShopUrl(String slug) {
  final here = Uri.base;
  final local = here.scheme.startsWith('http') &&
      (here.host == 'localhost' || here.host == '127.0.0.1');
  return '${local ? here.origin : siteOrigin}/s/$slug';
}

/// A WhatsApp link that opens the "send to…" picker with [text] already
/// typed — how a vitrine travels from one phone to the next here.
String whatsappShareUrl(String text) =>
    'https://wa.me/?text=${Uri.encodeComponent(text)}';

/// The WhatsApp link for a phone number, or null when there is none to link.
/// Numbers are stored as E.164 (+226 70 00 00 00); wa.me wants only digits.
/// With [text], the message is typed already (an article's question, 070).
String? whatsappUrl(String? phone, {String? text}) {
  if (phone == null) return null;
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  final base = 'https://wa.me/$digits';
  return text == null ? base : '$base?text=${Uri.encodeComponent(text)}';
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

/// A vitrine as this phone last saw it (StorefrontRepository.keptVitrine).
class KeptVitrine {
  const KeptVitrine({
    required this.shop,
    required this.items,
    required this.showcase,
    this.at,
  });

  final PublicShop shop;
  final List<PublicItem> items;
  final bool showcase;
  final DateTime? at;
}

/// The street as this phone last saw it (StorefrontRepository.keptStreet).
class KeptStreet {
  const KeptStreet({required this.entries, required this.previews, this.at});

  final List<DirectoryEntry> entries;
  final Map<String, List<ShopPreview>> previews;
  final DateTime? at;
}
