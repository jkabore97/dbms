import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/platform_writes.dart';

/// Paying by Wave — or by card on Wave's page — through the kaj-pay Worker
/// (migration 076); and Kaj Pro by card as a Stripe subscription, through
/// the same Worker (082).
///
/// Armed by --dart-define=PAY_URL, the Worker's origin, and by the platform
/// switching `wave_checkout` on. Without either, nothing here is drawn and
/// the old paths stand: the shop's own Wave link, "J'ai payé".
class WavePay {
  WavePay(this._client, {http.Client? httpClient, String? url})
      : _http = httpClient ?? http.Client(),
        _url = url ?? const String.fromEnvironment('PAY_URL');

  final SupabaseClient? _client;
  final http.Client _http;
  final String _url;

  bool get compiledIn => _url.isNotEmpty && _client != null;

  static bool _missing(PostgrestException e) =>
      e.code == 'PGRST202' || e.code == '42883';

  /// Whether to offer Wave, for [orgId]'s orders when given.
  Future<WaveTerms> terms({String? orgId}) async {
    final client = _client;
    if (!compiledIn || client == null) return const WaveTerms();
    try {
      final v = await client.rpc('wave_terms', params: {'p_org_id': orgId});
      if (v is! Map) return const WaveTerms();
      return WaveTerms(
        on: v['on'] == true,
        shopReady: v['shop_ready'] == true,
        card: v['card'] == true,
        commissionPct: (v['commission_pct'] is num)
            ? (v['commission_pct'] as num).toDouble()
            : 0,
      );
    } on PostgrestException catch (e) {
      if (_missing(e)) return const WaveTerms();
      rethrow;
    } catch (_) {
      return const WaveTerms();
    }
  }

  /// Starts a payment and returns where to send the person. [kind] is
  /// 'order' (ref: the order), 'pro' (ref: the business; [period] month or
  /// year) or 'spot' (ref: the promotion). The amount is the server's.
  Future<WaveCheckout> start({
    required String kind,
    required String ref,
    bool card = false,
    String period = 'month',
  }) async {
    final token = _client?.auth.currentSession?.accessToken;
    if (!compiledIn || token == null) {
      throw StateError('Connectez-vous pour payer.');
    }
    final response = await _http.post(
      Uri.parse('${_url.replaceAll(RegExp(r'/$'), '')}/v1/checkout'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'kind': kind,
        'ref': ref,
        'method': card ? 'card' : 'wave',
        'period': period,
      }),
    );
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      body = const {};
    }
    if (response.statusCode != 200 || body['url'] == null) {
      throw StateError('${body['error'] ?? 'Le paiement n\'a pas pu commencer.'}');
    }
    return WaveCheckout(url: '${body['url']}', paymentId: '${body['payment_id']}');
  }

  /// Where a payment stands, read after coming back from Wave.
  Future<String?> status(String paymentId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final v = await client
          .rpc('my_wave_payment', params: {'p_payment_id': paymentId});
      return v is Map ? '${v['status']}' : null;
    } catch (_) {
      return null;
    }
  }

  /// What the shop gave (its payout number) and what the platform set (its
  /// Wave merchant id), to the owner and the platform; nulls for anyone else.
  Future<({String? number, String? merchantRef})> shopWave(String orgId) async {
    final client = _client;
    if (client == null) return (number: null, merchantRef: null);
    try {
      // Through org_private_details (103): the owner's and the platform's.
      final raw =
          await client.rpc('org_private_details', params: {'p_org_id': orgId});
      final row = raw is Map ? raw : null;
      return (
        number: row?['wave_payout_number'] as String?,
        merchantRef: row?['wave_merchant_ref'] as String?,
      );
    } catch (_) {
      return (number: null, merchantRef: null);
    }
  }

  /// The shop's own number, where its sales are sent (the owner's, 103).
  Future<void> setPayoutNumber(String orgId, String? number) async {
    await _client!.rpc('set_wave_payout_number',
        params: {'p_org_id': orgId, 'p_number': number});
  }

  /// The platform's view of every Wave payment, failed payouts first.
  Future<List<WavePaymentRow>> platformPayments() async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client.rpc('platform_wave_payments') as List<dynamic>;
      return rows
          .map((r) => WavePaymentRow.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      if (_missing(e)) return const [];
      rethrow;
    }
  }

  /// The aggregated-merchant id Wave gave a shop (platform only).
  Future<void> setMerchantRef(String orgId, String? ref) async {
    await _client!.rpc('set_wave_merchant_ref',
        params: {'p_org_id': orgId, 'p_ref': ref});
  }

  /// Kaj Pro by card, as a Stripe subscription (082), through the same
  /// Worker: returns Stripe's checkout page for [orgId], monthly or yearly.
  /// The price is the platform's; the Worker reads it from the database.
  Future<String> subscribeByCard({
    required String orgId,
    required String period,
  }) =>
      _postForUrl('/v1/stripe/checkout', {'org_id': orgId, 'period': period});

  /// Stripe's own page where the owner changes the card or cancels.
  Future<String> cardPortal(String orgId) =>
      _postForUrl('/v1/stripe/portal', {'org_id': orgId});

  /// Where the card subscription stands, or null when there is none.
  Future<CardSubscription?> cardSubscription(String orgId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final v = await client
          .rpc('my_stripe_subscription', params: {'p_org_id': orgId});
      if (v is! Map) return null;
      return CardSubscription(
        status: '${v['status'] ?? ''}',
        period: '${v['period'] ?? ''}',
        until: DateTime.tryParse('${v['current_period_end'] ?? ''}'),
        cancelAtEnd: v['cancel_at_period_end'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Mara Pro bought in the App Store or on Google Play (130): the Worker
  /// asks the store itself (/store/verify) and writes it down; the answer
  /// says whether the business is now on Pro. [orgId] is the business the
  /// purchase itself names (StorePurchase.orgId) — never the page open —
  /// or null, and the Worker reads it from the store (review S3). Throws
  /// [StoreVerifyRefused] with the Worker's code when it refuses (another
  /// business's purchase, not Mara Pro, an expired session…), or a
  /// [StateError] when it could not be reached — the purchase is then not
  /// completed, so the store hands it back on the next try.
  Future<StoreVerdict> verifyStore({
    required String platform,
    String? orgId,
    required String productId,
    String? transactionId,
    String? token,
  }) async {
    if (!compiledIn) throw StateError('Pas de connexion au serveur de Marakaj.');
    final session = _client?.auth.currentSession?.accessToken;
    if (session == null) {
      throw const StoreVerifyRefused('Connectez-vous pour vous abonner.', 'session', status: 401);
    }
    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('${_url.replaceAll(RegExp(r'/$'), '')}/store/verify'),
        headers: {
          'Authorization': 'Bearer $session',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'platform': platform,
          'org_id': ?orgId,
          'product_id': productId,
          'transaction_id': ?transactionId,
          'token': ?token,
        }),
      );
    } catch (_) {
      throw StateError('Pas de connexion au serveur de Marakaj.');
    }
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      body = const {};
    }
    if (response.statusCode == 200 && body['ok'] == true) {
      return StoreVerdict(
        pro: body['pro'] == true,
        state: '${body['state'] ?? ''}',
        expiresAt: DateTime.tryParse('${body['expires_at'] ?? ''}'),
        orgId: body['org_id'] is String ? body['org_id'] as String : orgId,
      );
    }
    if (response.statusCode >= 400 && response.statusCode < 500) {
      throw StoreVerifyRefused(
        '${body['error'] ?? 'Achat refusé.'}',
        response.statusCode == 401 ? 'session' : '${body['code'] ?? ''}',
        status: response.statusCode,
      );
    }
    throw StateError('${body['error'] ?? 'La vérification de l\'achat n\'a pas abouti.'}');
  }

  /// A spot (« Mettre en avant », 142) bought in the App Store or on
  /// Google Play: the Worker asks the store itself (/store/spot-verify),
  /// and programs the spot the purchase names once. [promotionId] is the
  /// spot the purchase itself names (StorePurchase.spotId), or null — the
  /// Worker then reads it from the store. No price is sent: the amount
  /// written is the store's own, or Mara's zone price. Throws [StoreVerifyRefused] with
  /// the Worker's code (« pending » too, a 202), or a [StateError] when it
  /// could not be reached — the purchase is then left open.
  Future<SpotVerdict> verifySpot({
    required String platform,
    String? promotionId,
    required String productId,
    String? transactionId,
    String? token,
  }) async {
    if (!compiledIn) throw StateError('Pas de connexion au serveur de Marakaj.');
    final session = _client?.auth.currentSession?.accessToken;
    if (session == null) {
      throw const StoreVerifyRefused('Connectez-vous pour payer.', 'session', status: 401);
    }
    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('${_url.replaceAll(RegExp(r'/$'), '')}/store/spot-verify'),
        headers: {
          'Authorization': 'Bearer $session',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'platform': platform,
          'promotion_id': ?promotionId,
          'product_id': productId,
          'transaction_id': ?transactionId,
          'token': ?token,
        }),
      );
    } catch (_) {
      throw StateError('Pas de connexion au serveur de Marakaj.');
    }
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      body = const {};
    }
    if (response.statusCode == 200 && body['ok'] == true) {
      return SpotVerdict(
        promotionId: body['promotion_id'] is String ? body['promotion_id'] as String : promotionId,
        granted: body['granted'] == true,
        startsAt: DateTime.tryParse('${body['starts_at'] ?? ''}'),
        endsAt: DateTime.tryParse('${body['ends_at'] ?? ''}'),
      );
    }
    if (response.statusCode >= 202 && response.statusCode < 500) {
      throw StoreVerifyRefused(
        '${body['error'] ?? 'Achat refusé.'}',
        response.statusCode == 401 ? 'session' : '${body['code'] ?? ''}',
        status: response.statusCode,
      );
    }
    throw StateError('${body['error'] ?? 'La vérification de l\'achat n\'a pas abouti.'}');
  }

  /// A spot by card on the website (142): Stripe's one-time Checkout page
  /// for [promotionId]. The amount and currency are the database's (the
  /// business's zone price).
  Future<String> spotByCard(String promotionId) =>
      _postForUrl('/v1/stripe/spot', {'promotion_id': promotionId});

  /// Where this business's store subscription stands, and whether the
  /// caller's own store purchase already pays for another business (128).
  Future<StoreStanding?> storeStanding(String orgId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final v = await client.rpc('my_store_subscription', params: {'p_org_id': orgId});
      if (v is! Map) return null;
      final mine = v['this'];
      final elsewhere = v['elsewhere'];
      return StoreStanding(
        platform: mine is Map ? '${mine['platform'] ?? ''}' : null,
        state: mine is Map ? '${mine['state'] ?? ''}' : null,
        expiresAt: mine is Map ? DateTime.tryParse('${mine['expires_at'] ?? ''}') : null,
        autoRenew: mine is Map && mine['auto_renew'] == true,
        elsewhereName: elsewhere is Map ? '${elsewhere['name'] ?? ''}' : null,
        elsewherePlatform: elsewhere is Map && elsewhere['platform'] is String
            ? elsewhere['platform'] as String
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _postForUrl(String path, Map<String, Object?> json) async {
    final token = _client?.auth.currentSession?.accessToken;
    if (!compiledIn || token == null) {
      throw StateError('Connectez-vous pour payer.');
    }
    final response = await _http.post(
      Uri.parse('${_url.replaceAll(RegExp(r'/$'), '')}$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(json),
    );
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      body = const {};
    }
    if (response.statusCode != 200 || body['url'] == null) {
      throw StateError('${body['error'] ?? 'Le paiement n\'a pas pu commencer.'}');
    }
    return '${body['url']}';
  }

  /// The platform's switches, written in the command center's journal
  /// (105) — or through 061's set_platform_setting before it.
  Future<void> setSwitch(String key, Object value) async {
    await writePlatformSetting(_client!, key, value);
  }
}

class WaveTerms {
  const WaveTerms({
    this.on = false,
    this.shopReady = false,
    this.card = false,
    this.commissionPct = 0,
  });

  final bool on;
  final bool shopReady;
  final bool card;

  /// The platform's share of an order paid by Wave, in percent.
  final double commissionPct;
}

/// The payments Worker's word on a store purchase (130).
class StoreVerdict {
  const StoreVerdict({required this.pro, required this.state, this.expiresAt, this.orgId});

  /// The business is on Mara Pro now.
  final bool pro;

  /// active · grace · cancelled · on_hold · paused · pending · expired · revoked
  final String state;
  final DateTime? expiresAt;

  /// The business the purchase was settled for.
  final String? orgId;
}

/// The payments Worker's word on a spot's store purchase (142).
class SpotVerdict {
  const SpotVerdict({this.promotionId, this.granted = true, this.startsAt, this.endsAt});

  /// The spot it programmed.
  final String? promotionId;

  /// False when the same purchase was shown again: already programmed.
  final bool granted;
  final DateTime? startsAt;
  final DateTime? endsAt;
}

/// The Worker refused a purchase, in its own French words; [code] says why
/// (wrong_org, replayed, product, bundle, no_org, sandbox — for good;
/// session, not_admin — for now, see StoreWatcher).
class StoreVerifyRefused implements Exception {
  const StoreVerifyRefused(this.message, this.code, {this.status = 400});

  final String message;
  final String code;
  final int status;

  @override
  String toString() => message;
}

/// my_store_subscription() (128).
class StoreStanding {
  const StoreStanding({
    this.platform,
    this.state,
    this.expiresAt,
    this.autoRenew = false,
    this.elsewhereName,
    this.elsewherePlatform,
  });

  final String? platform;
  final String? state;
  final DateTime? expiresAt;
  final bool autoRenew;

  /// The business the caller's own store purchase already pays for.
  final String? elsewhereName;

  /// Which store that purchase is in ('apple' / 'google').
  final String? elsewherePlatform;
}

/// A business's Kaj Pro paid by card (082), as the owner reads it.
class CardSubscription {
  const CardSubscription({
    required this.status,
    required this.period,
    this.until,
    this.cancelAtEnd = false,
  });

  /// Stripe's word: active, past_due, canceled…
  final String status;
  final String period;
  final DateTime? until;
  final bool cancelAtEnd;

  bool get active => status == 'active' || status == 'trialing';
}

class WaveCheckout {
  const WaveCheckout({required this.url, required this.paymentId});

  final String url;
  final String paymentId;
}

class WavePaymentRow {
  const WavePaymentRow({
    required this.id,
    required this.kind,
    required this.orgName,
    required this.amount,
    required this.status,
    required this.payoutStatus,
    this.commission = 0,
    this.method = 'wave',
    this.payoutTo,
    this.payoutError,
    this.createdAt,
  });

  factory WavePaymentRow.fromRow(Map<String, dynamic> r) => WavePaymentRow(
        id: '${r['id']}',
        kind: '${r['kind']}',
        orgName: '${r['org_name'] ?? ''}',
        amount: _d(r['amount']),
        commission: _d(r['commission']),
        method: '${r['method'] ?? 'wave'}',
        status: '${r['status']}',
        payoutStatus: '${r['payout_status']}',
        payoutTo: r['payout_to'] as String?,
        payoutError: r['payout_error'] as String?,
        createdAt: r['created_at'] == null
            ? null
            : DateTime.tryParse('${r['created_at']}')?.toLocal(),
      );

  final String id;
  final String kind;
  final String orgName;
  final double amount;
  final double commission;
  final String method;
  final String status;
  final String payoutStatus;
  final String? payoutTo;
  final String? payoutError;
  final DateTime? createdAt;

  static double _d(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
}
