import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The shopper's own page (113): who they are, their choices, the vitrines
/// they follow, where they are delivered, « Recommander », a report, their
/// data. Everything goes through 113's functions, each about the signed-in
/// caller only; nothing here is cached or offline — the page says when the
/// network is missing.
///
/// The client is nullable like the street's: a build with no server, or a
/// test, has a repository that answers nothing and offers nothing.
class ShopperRepository {
  ShopperRepository(this._client);

  final SupabaseClient? _client;

  /// A server to ask, and somebody signed in to ask it for.
  bool get isConfigured => _client != null && _client.auth.currentUser != null;

  SupabaseClient get _c {
    final c = _client;
    if (c == null) throw StateError('Pas de serveur.');
    return c;
  }

  /// The photo Google gave the account, when it signed in with Google
  /// (the privacy page says so); null otherwise.
  String? get picture {
    final meta = _client?.auth.currentUser?.userMetadata;
    final url = meta?['avatar_url'] ?? meta?['picture'];
    return url is String && url.startsWith('https://') ? url : null;
  }

  Future<ShopperProfile> profile() async {
    final v = await _c.rpc('my_shopper_profile');
    return ShopperProfile.fromJson(Map<String, dynamic>.from(v as Map));
  }

  /// One or more of the choices: the city, the payment, the news switch.
  Future<void> setSettings({String? city, String? payment, bool? news}) async {
    await _c.rpc('set_my_shopper_settings', params: {
      'p_patch': {
        'city': ?city,
        'payment': ?payment,
        'news': ?news,
      },
    });
  }

  // ----------------------------------------------------------------
  // Following
  // ----------------------------------------------------------------

  Future<List<FollowedVitrine>> follows() async {
    final v = await _c.rpc('my_follows');
    return [
      for (final r in (v as List? ?? const []))
        FollowedVitrine.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// The addresses of the vitrines followed, for the hearts on the street.
  Future<Set<String>> followedSlugs() async =>
      {for (final f in await follows()) f.slug};

  /// Follows an open vitrine; answers the business's id.
  Future<String> follow(String slug) async =>
      '${await _c.rpc('follow_vitrine', params: {'p_slug': slug})}';

  Future<void> unfollow(String orgId) async {
    await _c.rpc('unfollow_vitrine', params: {'p_org_id': orgId});
  }

  /// Lets go of a vitrine known by its address (the street's ♥).
  Future<void> unfollowSlug(String slug) async {
    for (final f in await follows()) {
      if (f.slug == slug) await unfollow(f.orgId);
    }
  }

  Future<void> setFollowNews(String orgId, bool on) async {
    await _c.rpc('set_follow_news', params: {'p_org_id': orgId, 'p_on': on});
  }

  // ----------------------------------------------------------------
  // Where to deliver
  // ----------------------------------------------------------------

  Future<List<SavedAddress>> addresses() async => (await profile()).addresses;

  Future<String> saveAddress(SavedAddress a) async => '${await _c.rpc('save_my_address', params: {
        'p_id': a.id,
        'p_kind': a.kind,
        'p_label': a.label,
        'p_address': a.address,
        'p_note': a.note,
        'p_lat': a.lat,
        'p_lng': a.lng,
      })}';

  Future<void> deleteAddress(String id) async {
    await _c.rpc('delete_my_address', params: {'p_id': id});
  }

  // ----------------------------------------------------------------
  // « Recommander », a report, the data
  // ----------------------------------------------------------------

  Future<ReorderBasket> reorder(String orderId) async {
    final v = await _c.rpc('my_order_basket', params: {'p_order_id': orderId});
    return ReorderBasket.fromJson(Map<String, dynamic>.from(v as Map));
  }

  Future<void> report({
    required String topic,
    required String message,
    String? slug,
    String? orderId,
  }) async {
    await _c.rpc('report_problem', params: {
      'p_topic': topic,
      'p_message': message,
      'p_slug': slug,
      'p_order_id': orderId,
    });
  }

  /// « Mes données »: the caller's own, as a JSON file's text.
  Future<String> exportData() async {
    final v = await _c.rpc('my_data_export');
    return const JsonEncoder.withIndent('  ').convert(v);
  }
}

/// What the page draws (113's my_shopper_profile).
class ShopperProfile {
  const ShopperProfile({
    this.name,
    this.phone,
    this.verifiedPhone,
    this.verifyOn = false,
    this.city,
    this.waveAllowed = false,
    this.payment = 'cash',
    this.news = true,
    this.supportWhatsApp,
    this.courier,
    this.member = false,
    this.addresses = const [],
    this.follows = 0,
    this.ordersOpen = 0,
  });

  final String? name;

  /// The number typed on the profile (sign-up, « Mes informations »).
  final String? phone;

  /// The number WhatsApp proved (109), « +226… », or null.
  final String? verifiedPhone;

  /// The platform asks for a proved number (109's switch): the WhatsApp
  /// code is set up, so « Vérifier » can be offered.
  final bool verifyOn;
  final String? city;

  /// RULE M: the platform allows Wave (076's wave_checkout).
  final bool waveAllowed;

  /// 'cash' or 'wave' — 'cash' whenever Wave is not allowed.
  final String payment;

  /// The news of every followed vitrine, on or off.
  final bool news;

  /// Mara's help number, digits only; null until the platform sets it.
  final String? supportWhatsApp;

  /// The courier file's status (056), when there is one.
  final String? courier;

  /// Belongs to a business: their Compte is the business's.
  final bool member;
  final List<SavedAddress> addresses;
  final int follows;
  final int ordersOpen;

  factory ShopperProfile.fromJson(Map<String, dynamic> j) => ShopperProfile(
        name: _text(j['name']),
        phone: _text(j['phone']),
        verifiedPhone: _text(j['verified_phone']),
        verifyOn: j['verify_on'] == true,
        city: _text(j['city']),
        waveAllowed: j['wave'] == true,
        payment: j['wave'] == true && j['payment'] == 'wave' ? 'wave' : 'cash',
        news: j['news'] != false,
        supportWhatsApp: _text(j['support_whatsapp']),
        courier: _text(j['courier']),
        member: j['member'] == true,
        addresses: [
          for (final a in (j['addresses'] as List? ?? const []))
            SavedAddress.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
        follows: (j['follows'] as num?)?.toInt() ?? 0,
        ordersOpen: (j['orders_open'] as num?)?.toInt() ?? 0,
      );
}

/// A place the shopper is delivered: Maison, Travail or Autre.
class SavedAddress {
  const SavedAddress({
    this.id,
    required this.kind,
    this.label,
    required this.address,
    this.note,
    this.lat,
    this.lng,
  });

  final String? id;

  /// 'home', 'work' or 'other'.
  final String kind;

  /// The name of an « Autre » place (« Chez maman »).
  final String? label;

  /// The words a courier reads first.
  final String address;

  /// « Portail bleu, 2e maison ».
  final String? note;
  final double? lat;
  final double? lng;

  bool get hasPin => lat != null && lng != null;

  /// What travels with an order: the words, then the note.
  String get forOrder =>
      [address, if ((note ?? '').isNotEmpty) note!].join(' — ');

  factory SavedAddress.fromJson(Map<String, dynamic> j) => SavedAddress(
        id: j['id'] as String?,
        kind: (j['kind'] as String?) ?? 'other',
        label: _text(j['label']),
        address: (j['address'] as String?) ?? '',
        note: _text(j['note']),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
      );
}

/// A vitrine the shopper follows (113's my_follows).
class FollowedVitrine {
  const FollowedVitrine({
    required this.orgId,
    required this.slug,
    required this.name,
    required this.profile,
    this.logoKey,
    this.news = true,
    this.open = true,
  });

  final String orgId;
  final String slug;
  final String name;
  final String profile;
  final String? logoKey;
  final bool news;

  /// Open to the street today.
  final bool open;

  factory FollowedVitrine.fromJson(Map<String, dynamic> j) => FollowedVitrine(
        orgId: j['org_id'] as String,
        slug: (j['slug'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        profile: (j['profile'] as String?) ?? 'retail',
        logoKey: _text(j['logo_key']),
        news: j['news'] != false,
        open: j['open'] != false,
      );
}

/// What of an order the vitrine still has (113's my_order_basket).
class ReorderBasket {
  const ReorderBasket({
    required this.slug,
    this.closed = false,
    this.lines = const {},
    this.missing = 0,
  });

  final String slug;

  /// The vitrine takes no orders now.
  final bool closed;

  /// Product id → quantity, as the street's basket keeps it.
  final Map<String, double> lines;

  /// Lines of the order the vitrine no longer has.
  final int missing;

  factory ReorderBasket.fromJson(Map<String, dynamic> j) => ReorderBasket(
        slug: (j['slug'] as String?) ?? '',
        closed: j['closed'] == true,
        lines: {
          for (final l in (j['lines'] as List? ?? const []))
            if (l is Map && l['product_id'] is String)
              l['product_id'] as String: ((l['quantity'] as num?) ?? 0).toDouble(),
        },
        missing: (j['missing'] as num?)?.toInt() ?? 0,
      );
}

String? _text(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}
