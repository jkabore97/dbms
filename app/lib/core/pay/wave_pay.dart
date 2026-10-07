import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// The platform's switches, through 061's set_platform_setting.
  Future<void> setSwitch(String key, Object value) async {
    await _client!.rpc('set_platform_setting',
        params: {'p_key': key, 'p_value': value});
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
