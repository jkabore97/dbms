/// Spots for sale on the street (071): what they cost, and the ones asked.
library;

import 'package:kaj_app/core/l10n/tr.dart';

import '../pay/price_zone.dart';

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// The price list and where to pay, as the platform set it.
class SpotTerms {
  const SpotTerms({
    this.article7 = 1000,
    this.article30 = 3000,
    this.shop7 = 2500,
    this.shop30 = 8000,
    this.maxLive = 8,
    this.wave = '',
    this.waveName = '',
    this.currency = 'XOF',
    this.zones = const {},
    this.stripeOn = false,
    this.version = 0,
  });

  factory SpotTerms.fromJson(Map<String, dynamic> j) => SpotTerms(
        article7: _d(j['article_7']),
        article30: _d(j['article_30']),
        shop7: _d(j['shop_7']),
        shop30: _d(j['shop_30']),
        maxLive: _i(j['max_live']),
        wave: '${j['wave'] ?? ''}'.trim(),
        waveName: '${j['wave_name'] ?? ''}'.trim(),
        currency: '${j['currency'] ?? 'XOF'}',
        zones: {
          if (j['zones'] is Map)
            for (final e in (j['zones'] as Map).entries)
              if (e.value is Map)
                '${e.key}': (
                  article: _d((e.value as Map)['article']),
                  shop: _d((e.value as Map)['shop']),
                ),
        },
        stripeOn: j['stripe_on'] == true,
        version: _i(j['version']),
      );

  final double article7;
  final double article30;
  final double shop7;
  final double shop30;
  final int maxLive;
  final String wave;
  final String waveName;
  final String currency;

  /// The 7-day prices per zone (139): 'XOF', 'EUR', 'USD' → the article's
  /// and the vitrine's. Empty on a database before 139.
  final Map<String, ({double article, double shop})> zones;

  /// A spot may be paid by card on the website (139, the platform's
  /// stripe_on): false on a database before 139.
  final bool stripeOn;

  /// spot_terms()'s version: 139 once the stores and the card may sell a
  /// spot (the Worker's spot_settle is there); 0 before.
  final int version;

  /// The server verifies a store or card payment of a spot (139).
  bool get paidOnline => version >= 139;

  bool get hasWave => wave.isNotEmpty;

  /// A spot lasts 7 days (139): the 30-day prices stay for the spots
  /// asked before, never offered.
  static const days = 7;

  double price({required bool shop, required int days}) => shop
      ? (days == 30 ? shop30 : shop7)
      : (days == 30 ? article30 : article7);

  /// The 7-day price for a business of [currency], in its zone (139) —
  /// the XOF numbers on a database before 139, which asks those.
  double zonePrice(String? currency, {required bool shop}) {
    final z = zones[zoneKey(priceZoneOf(currency))];
    if (z == null) return shop ? shop7 : article7;
    return shop ? z.shop : z.article;
  }

  /// The currency that price is in: the zone's (XAF for an XAF business);
  /// the francs before 139.
  String zoneCurrency(String? currency) =>
      zones.isEmpty ? 'XOF' : zoneCurrencyOf(currency);
}

/// One spot a shop asked for, with what it earned while it ran.
class Promotion {
  const Promotion({
    required this.id,
    required this.kind,
    required this.days,
    required this.status,
    this.productId,
    this.productName,
    this.price = 0,
    this.currency = 'XOF',
    this.free = false,
    this.startsAt,
    this.endsAt,
    this.createdAt,
    this.seen = 0,
    this.opened = 0,
    this.added = 0,
    this.ordered = 0,
  });

  factory Promotion.fromRow(Map<String, dynamic> r) => Promotion(
        id: '${r['id']}',
        kind: '${r['kind']}',
        productId: r['product_id'] as String?,
        productName: r['product_name'] as String?,
        days: _i(r['days']),
        price: _d(r['price']),
        currency: '${r['currency'] ?? 'XOF'}',
        free: r['free'] == true,
        status: '${r['status']}',
        startsAt: _t(r['starts_at']),
        endsAt: _t(r['ends_at']),
        createdAt: _t(r['created_at']),
        seen: _i(r['seen']),
        opened: _i(r['opened']),
        added: _i(r['added']),
        ordered: _i(r['ordered']),
      );

  final String id;

  /// 'article' or 'shop'.
  final String kind;
  final String? productId;
  final String? productName;
  final int days;
  final double price;
  final String currency;
  final bool free;

  /// requested → paid_claimed → approved | refused; cancelled.
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? createdAt;
  final int seen;
  final int opened;
  final int added;
  final int ordered;

  bool get isShop => kind == 'shop';

  String get label => isShop
      ? translate(trCurrent, 'Toute la boutique')
      : (productName ?? translate(trCurrent, 'Article'));

  /// Where the spot is, in the owner's words.
  String stateLabel([DateTime? now]) {
    final at = now ?? DateTime.now();
    switch (status) {
      case 'requested':
        return 'En attente de paiement';
      case 'paid_claimed':
        return 'Paiement en vérification';
      case 'refused':
        return 'Refusée';
      case 'cancelled':
        return 'Annulée';
      case 'approved':
        if (endsAt != null && !endsAt!.isAfter(at)) return 'Terminée';
        if (startsAt != null && startsAt!.isAfter(at)) return 'Programmée';
        return 'En cours';
    }
    return status;
  }

  bool isRunning([DateTime? now]) => stateLabel(now) == 'En cours';
}

/// A spot as the console sees it: whose, and what is asked of the platform.
class PlatformPromotion {
  const PlatformPromotion({
    required this.id,
    required this.orgId,
    required this.orgName,
    required this.kind,
    required this.days,
    required this.status,
    this.productName,
    this.price = 0,
    this.currency = 'XOF',
    this.free = false,
    this.startsAt,
    this.endsAt,
    this.createdAt,
    this.note,
  });

  factory PlatformPromotion.fromRow(Map<String, dynamic> r) => PlatformPromotion(
        id: '${r['id']}',
        orgId: '${r['org_id']}',
        orgName: '${r['org_name'] ?? ''}',
        kind: '${r['kind']}',
        productName: r['product_name'] as String?,
        days: _i(r['days']),
        price: _d(r['price']),
        currency: '${r['currency'] ?? 'XOF'}',
        free: r['free'] == true,
        status: '${r['status']}',
        startsAt: _t(r['starts_at']),
        endsAt: _t(r['ends_at']),
        createdAt: _t(r['created_at']),
        note: r['note'] as String?,
      );

  final String id;
  final String orgId;
  final String orgName;
  final String kind;
  final String? productName;
  final int days;
  final double price;
  final String currency;
  final bool free;
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? createdAt;
  final String? note;

  bool get waiting => status == 'requested' || status == 'paid_claimed';
  String get label => kind == 'shop'
      ? translate(trCurrent, 'Toute la boutique')
      : (productName ?? translate(trCurrent, 'Article'));
}

/// The platform's day (072): the month's money, growth, health. What waits
/// is « À faire »'s own (105's platform_todo).
class PlatformToday {
  const PlatformToday({
    this.money = const {},
    this.growth = const {},
    this.health = const {},
    this.other = const {},
  });

  factory PlatformToday.fromJson(Map<String, dynamic> j) {
    Map<String, num> block(Object? v) => {
          if (v is Map)
            for (final e in v.entries)
              if (e.value is num) '${e.key}': e.value as num
              else if (num.tryParse('${e.value}') != null)
                '${e.key}': num.parse('${e.value}'),
        };
    final other = j['money'] is Map ? (j['money'] as Map)['other'] : null;
    return PlatformToday(
      money: block(j['money']),
      growth: block(j['growth']),
      health: block(j['health']),
      other: {
        if (other is Map)
          for (final e in other.entries) '${e.key}': block(e.value),
      },
    );
  }

  /// The month's delivery parts and vitrine sales in every money but the
  /// franc CFA (140), by money: {'EUR': {'delivery_cut': 0.41,
  /// 'shops_sold': 25}}. [money] is in francs CFA only — one money is
  /// never added to another. Empty before 140.
  final Map<String, Map<String, num>> other;

  /// [key] of [money] (francs CFA, written by [xof]) and of every other
  /// money with some: « 1 200 FCFA + 0,41 EUR ».
  String withOthers(String key, String Function(num) xof, String Function(String, num) format) => [
        xof(money[key] ?? 0),
        for (final e in other.entries)
          if ((e.value[key] ?? 0) != 0) format(e.key, e.value[key]!),
      ].join(' + ');

  final Map<String, num> money;
  final Map<String, num> growth;
  final Map<String, num> health;

  int count(Map<String, num> block, String key) => (block[key] ?? 0).toInt();

  double get earnedMonth =>
      (money['pro'] ?? 0).toDouble() +
      (money['spots'] ?? 0).toDouble() +
      (money['delivery_cut'] ?? 0).toDouble();
}

/// The places around a business (144's spot_area_status): a spot shows
/// only to shoppers within [areaKm] of it, and at most [places] of the
/// same kind run at once in its area. Null from a database before 144.
class SpotArea {
  const SpotArea({
    required this.positioned,
    this.areaKm = 30,
    this.places = 8,
    this.taken = 0,
    this.free = 8,
    this.nextAt,
  });

  factory SpotArea.fromJson(Map<String, dynamic> j) => SpotArea(
        positioned: j['positioned'] == true,
        areaKm: _d(j['area_km']),
        places: _i(j['places']),
        taken: _i(j['taken']),
        free: _i(j['free']),
        nextAt: _t(j['next_at']),
      );

  /// The business is on the map: without it no spot can be bought.
  final bool positioned;
  final double areaKm;
  final int places;
  final int taken;
  final int free;

  /// Full: when the next place frees (the queue's own date).
  final DateTime? nextAt;

  bool get full => positioned && free <= 0;
}

/// What a business may do with one of its spots now (144's
/// promotion_options), and the items it may change to.
class PromotionOptions {
  const PromotionOptions({
    this.canCancel = false,
    this.canChange = false,
    this.canStop = false,
    this.changed = false,
    this.changeUntil,
    this.items = const [],
  });

  factory PromotionOptions.fromJson(Map<String, dynamic> j) => PromotionOptions(
        canCancel: j['can_cancel'] == true,
        canChange: j['can_change'] == true,
        canStop: j['can_stop'] == true,
        changed: j['changed'] == true,
        changeUntil: _t(j['change_until']),
        items: [
          if (j['items'] is List)
            for (final e in j['items'] as List)
              if (e is Map) (id: '${e['id']}', name: '${e['name'] ?? ''}', service: e['service'] == true),
        ],
      );

  final bool canCancel;
  final bool canChange;
  final bool canStop;

  /// Its one change is already made.
  final bool changed;

  /// A running spot's change closes then (24 h after it started).
  final DateTime? changeUntil;
  final List<({String id, String name, bool service})> items;
}

/// Which fixes the card offers for [p] (144). The server decides; this
/// only chooses which buttons show.
({bool cancel, bool change, bool stop}) spotFixes(Promotion p, [DateTime? now]) {
  final at = now ?? DateTime.now();
  final started = p.startsAt != null && !p.startsAt!.isAfter(at);
  final running = p.status == 'approved' && started && p.endsAt != null && p.endsAt!.isAfter(at);
  final queued = p.status == 'approved' && p.startsAt != null && p.startsAt!.isAfter(at);
  final inWindow = running && at.isBefore(p.startsAt!.add(const Duration(hours: 24)));
  return (
    cancel: p.status == 'requested',
    change: !p.isShop &&
        (p.status == 'requested' || p.status == 'paid_claimed' || queued || inWindow),
    stop: running,
  );
}
