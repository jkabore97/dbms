import 'package:supabase_flutter/supabase_flutter.dart';

/// Cauris (084): Mara's points, earned by doing well.
///
/// The database earns them from the events themselves — an order finished,
/// a visitor, the till kept, the farm's log — so the app only reads the
/// wallet, nudges the milestones it can see (a complete vitrine), says who
/// brought the business in, and, for the platform, tunes the rules.
class CaurisRepository {
  CaurisRepository(this._client);

  final SupabaseClient? _client;

  static bool _missing(PostgrestException e) =>
      e.code == 'PGRST202' || e.code == '42883';

  /// The business's wallet, for its admins; null for anyone else, or on a
  /// database before 084.
  Future<CaurisWallet?> wallet(String orgId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final v = await client.rpc('my_cauris', params: {'p_org_id': orgId});
      if (v is! Map) return null;
      return CaurisWallet.fromJson(Map<String, dynamic>.from(v));
    } on PostgrestException catch (e) {
      if (_missing(e)) return null;
      rethrow;
    }
  }

  /// The milestones only a look at the business can see — its vitrine
  /// complete, a business it brought in that took off. Best-effort.
  Future<void> milestones(String orgId) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.rpc('cauris_milestones', params: {'p_org_id': orgId});
    } catch (_) {}
  }

  /// Who brought this business in, by their vitrine address. Returns the
  /// sponsor's name.
  Future<String> setReferral(String orgId, String code) async {
    final v = await _client!.rpc('set_referral',
        params: {'p_org_id': orgId, 'p_code': code.trim()});
    return '$v';
  }

  /// The rules, for the platform's console.
  Future<List<CaurisRule>> rules() async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client.rpc('cauris_rules_list') as List<dynamic>;
      return rows
          .map((r) => CaurisRule.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      if (_missing(e)) return const [];
      rethrow;
    }
  }

  Future<void> setRule(String key, int points, {int? dailyCap}) async {
    await _client!.rpc('set_cauris_rule', params: {
      'p_key': key,
      'p_points': points,
      'p_daily_cap': dailyCap,
    });
  }

  /// What each Pro tool costs in cauris (085), for the console.
  Future<List<({String feature, int cost, int minDays})>> costs() async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client.rpc('cauris_costs_list') as List<dynamic>;
      return [
        for (final r in rows)
          if (r is Map)
            (
              feature: '${r['feature']}',
              cost: _int(r['cost']),
              minDays: _int(r['min_days']),
            ),
      ];
    } on PostgrestException catch (e) {
      if (_missing(e)) return const [];
      rethrow;
    }
  }

  Future<void> setCost(String feature, int cost) async {
    await _client!.rpc('set_cauris_cost',
        params: {'p_feature': feature, 'p_cost': cost});
  }

  /// The week's top earners, with how much of their orders came from one
  /// customer — what an abuse looks like.
  Future<List<CaurisWatchRow>> watch() async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client.rpc('cauris_watch') as List<dynamic>;
      return rows
          .map((r) =>
              CaurisWatchRow.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      if (_missing(e)) return const [];
      rethrow;
    }
  }
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class CaurisWallet {
  const CaurisWallet({
    required this.balance,
    required this.week,
    this.expiresOn,
    this.referralCode,
    this.referred = false,
    this.history = const [],
    this.rules = const [],
  });

  final int balance;

  /// Earned since Monday: the league's score (086).
  final int week;

  /// When an idle wallet would empty itself.
  final DateTime? expiresOn;

  /// This business's own code for the businesses it brings in: its vitrine
  /// address.
  final String? referralCode;

  /// Whether it has said who brought it in.
  final bool referred;
  final List<CaurisLine> history;

  /// How to earn, as the platform set it.
  final List<CaurisRule> rules;

  factory CaurisWallet.fromJson(Map<String, dynamic> j) => CaurisWallet(
        balance: _int(j['balance']),
        week: _int(j['week']),
        expiresOn: DateTime.tryParse('${j['expires_on'] ?? ''}'),
        referralCode: j['referral_code'] as String?,
        referred: j['referred'] == true,
        history: [
          for (final h in (j['history'] as List? ?? const []))
            CaurisLine.fromJson(Map<String, dynamic>.from(h as Map)),
        ],
        rules: [
          for (final r in (j['rules'] as List? ?? const []))
            CaurisRule.fromJson(Map<String, dynamic>.from(r as Map)),
        ],
      );
}

class CaurisLine {
  const CaurisLine({
    required this.delta,
    required this.reason,
    required this.label,
    this.note,
    this.at,
  });

  final int delta;
  final String reason;
  final String label;
  final String? note;
  final DateTime? at;

  factory CaurisLine.fromJson(Map<String, dynamic> j) => CaurisLine(
        delta: _int(j['delta']),
        reason: '${j['reason']}',
        label: '${j['label']}',
        note: j['note'] as String?,
        at: DateTime.tryParse('${j['at'] ?? ''}'),
      );
}

class CaurisRule {
  const CaurisRule({
    required this.key,
    required this.points,
    required this.label,
    this.dailyCap,
  });

  final String key;
  final int points;
  final String label;
  final int? dailyCap;

  factory CaurisRule.fromJson(Map<String, dynamic> j) => CaurisRule(
        key: '${j['key']}',
        points: _int(j['points']),
        label: '${j['label']}',
        dailyCap: j['daily_cap'] == null ? null : _int(j['daily_cap']),
      );
}

class CaurisWatchRow {
  const CaurisWatchRow({
    required this.orgId,
    required this.orgName,
    required this.week,
    required this.balance,
    required this.orders,
    required this.topCustomerShare,
  });

  final String orgId;
  final String orgName;
  final int week;
  final int balance;
  final int orders;

  /// 0–1: the share of the week's counted orders from its biggest customer.
  final double topCustomerShare;

  bool get suspicious => orders >= 5 && topCustomerShare >= 0.5;

  factory CaurisWatchRow.fromJson(Map<String, dynamic> j) => CaurisWatchRow(
        orgId: '${j['org_id']}',
        orgName: '${j['org_name']}',
        week: _int(j['week']),
        balance: _int(j['balance']),
        orders: _int(j['orders']),
        topCustomerShare: (j['top_customer_share'] is num)
            ? (j['top_customer_share'] as num).toDouble()
            : double.tryParse('${j['top_customer_share']}') ?? 0,
      );
}
