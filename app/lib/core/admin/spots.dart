/// Spots for sale on the street (071): what they cost, and the ones asked.
library;

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
      );

  final double article7;
  final double article30;
  final double shop7;
  final double shop30;
  final int maxLive;
  final String wave;
  final String waveName;
  final String currency;

  bool get hasWave => wave.isNotEmpty;

  double price({required bool shop, required int days}) => shop
      ? (days == 30 ? shop30 : shop7)
      : (days == 30 ? article30 : article7);
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

  String get label => isShop ? 'Toute la boutique' : (productName ?? 'Article');

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
  String get label =>
      kind == 'shop' ? 'Toute la boutique' : (productName ?? 'Article');
}

/// The platform's day (072): what waits, the month's money, growth, health.
class PlatformToday {
  const PlatformToday({
    this.todo = const {},
    this.money = const {},
    this.growth = const {},
    this.health = const {},
  });

  factory PlatformToday.fromJson(Map<String, dynamic> j) {
    Map<String, num> block(Object? v) => {
          if (v is Map)
            for (final e in v.entries)
              if (e.value is num) '${e.key}': e.value as num
              else if (num.tryParse('${e.value}') != null)
                '${e.key}': num.parse('${e.value}'),
        };
    return PlatformToday(
      todo: block(j['todo']),
      money: block(j['money']),
      growth: block(j['growth']),
      health: block(j['health']),
    );
  }

  final Map<String, num> todo;
  final Map<String, num> money;
  final Map<String, num> growth;
  final Map<String, num> health;

  int count(Map<String, num> block, String key) => (block[key] ?? 0).toInt();

  /// Everything waiting on the platform, added up.
  int get waiting =>
      count(todo, 'applications') +
      count(todo, 'pro_requests') +
      count(todo, 'spots') +
      count(todo, 'couriers') +
      count(todo, 'orders_stuck');

  double get earnedMonth =>
      (money['pro'] ?? 0).toDouble() +
      (money['spots'] ?? 0).toDouble() +
      (money['delivery_cut'] ?? 0).toDouble();
}
