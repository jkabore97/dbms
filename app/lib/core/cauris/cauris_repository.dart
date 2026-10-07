import 'package:supabase_flutter/supabase_flutter.dart';

import 'feature_states.dart';

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

  /// Where the business stands on Le Chemin (097): its four stages, every
  /// step with its count, the tools they open and the wallet — recorded
  /// and paid on the way (path_sync). Null for anyone but a member, for a
  /// profile off the path (an association, a church), or on a database
  /// before 097.
  ///
  /// [onMissing] hears when the database has no path_state at all (before
  /// 097: PGRST202 or 42883) — the home then shows its fallback card
  /// rather than nothing.
  Future<PathState?> pathState(String orgId, {void Function()? onMissing}) async {
    final client = _client;
    if (client == null) return null;
    try {
      final v = await client.rpc('path_state', params: {'p_org': orgId});
      if (v is! Map) return null;
      return PathState.fromJson(Map<String, dynamic>.from(v));
    } on PostgrestException catch (e) {
      if (_missing(e)) {
        onMissing?.call();
        return null;
      }
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

  /// This week's board for the business's league (086); null for a
  /// stranger or before 086.
  Future<LeagueBoard?> board(String orgId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final v = await client.rpc('league_board', params: {'p_org_id': orgId});
      if (v is! Map) return null;
      return LeagueBoard.fromJson(Map<String, dynamic>.from(v));
    } on PostgrestException catch (e) {
      if (_missing(e)) return null;
      rethrow;
    }
  }

  /// Hide the business's name from the board; the four-a-week message.
  Future<void> setBoardPrefs(String orgId, {bool? hidden, bool? notify}) async {
    await _client!.rpc('set_board_prefs', params: {
      'p_org_id': orgId,
      'p_hidden': hidden,
      'p_notify': notify,
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

/// Le Chemin (097): one path from a new business to a busy one, in four
/// stages — Ouvrir, Remplir, Vendre, Grandir. The server is its single
/// truth: it counts each step, records it once reached (for good) and pays
/// its cauris; the app only draws what it is told.
class PathState {
  const PathState({
    required this.stage,
    this.stages = const [],
    this.next,
    this.steps = const [],
    this.tools = const {},
    this.balance,
    this.week,
    this.leagueOpen = false,
  });

  /// The current stage, 1–4; 5 once every step is done.
  final int stage;
  final List<PathStage> stages;

  /// The first step not yet done, in order; null when none is left.
  final String? next;

  /// Every step of every stage, in order (the app hides the stages ahead).
  final List<PathStep> steps;

  /// Tool → open: 'invoices', 'production', 'credits', 'second_business'.
  final Map<String, bool> tools;

  /// The wallet, and what was earned since Monday (the league's score) —
  /// for the business's admins; null for its other members.
  final int? balance;
  final int? week;

  /// From stage 4, once the business's league has three racing.
  final bool leagueOpen;

  bool get finished => stage >= 5;

  PathStep? get nextStep {
    for (final s in steps) {
      if (s.key == next) return s;
    }
    return null;
  }

  /// The step worth proposing now: the next one, in order — but never the
  /// podium while the league is not yet a race (it says « Bientôt »).
  /// Null when nothing can be done today.
  PathStep? get proposed {
    for (final s in steps) {
      if (s.done || soon(s)) continue;
      return s;
    }
    return null;
  }

  /// A step that cannot be done yet: the week's podium, while the
  /// business's league has too few racing.
  bool soon(PathStep s) => s.key == 'podium' && !leagueOpen && !s.done;

  PathStep? step(String key) {
    for (final s in steps) {
      if (s.key == key) return s;
    }
    return null;
  }

  List<PathStep> stepsOf(int n) => [
        for (final s in steps)
          if (s.stage == n) s,
      ];

  /// The stage's name: « Remplir ».
  String titleOf(int n) {
    for (final s in stages) {
      if (s.n == n) return s.title;
    }
    return '';
  }

  factory PathState.fromJson(Map<String, dynamic> j) {
    final t = j['tools'];
    return PathState(
      stage: _int(j['stage']),
      stages: [
        for (final s in (j['stages'] as List? ?? const []))
          if (s is Map)
            PathStage(
              n: _int(s['n']),
              title: '${s['title'] ?? ''}',
              done: s['done'] == true,
            ),
      ],
      next: j['next'] as String?,
      steps: [
        for (final s in (j['steps'] as List? ?? const []))
          if (s is Map) PathStep.fromJson(Map<String, dynamic>.from(s)),
      ],
      tools: t is Map
          ? {for (final e in t.entries) '${e.key}': e.value == true}
          : const {},
      balance: j['balance'] == null ? null : _int(j['balance']),
      week: j['week'] == null ? null : _int(j['week']),
      leagueOpen: j['league_open'] == true,
    );
  }
}

class PathStage {
  const PathStage({required this.n, required this.title, this.done = false});

  final int n;
  final String title;
  final bool done;
}

/// One step on the path: what to do, why, how far, what it pays.
class PathStep {
  const PathStep({
    required this.key,
    required this.stage,
    required this.title,
    this.line = '',
    this.go = '',
    this.progress = 0,
    int? live,
    this.goal = 1,
    this.done = false,
    this.reward = 0,
    this.opens,
  }) : live = live ?? progress;

  final String key;
  final int stage;

  /// Already in the business's own words (a farm's « produit »), with the
  /// numbers filled in.
  final String title;

  /// Why it matters, in one sentence.
  final String line;

  /// Where it is done, under `/o/<id>/` — may carry `?partie=`; empty for
  /// the home itself (the till).
  final String go;

  /// Toward the goal, as remembered: a step reached shows its goal met.
  final int progress;

  /// What the data says right now (capped at the goal) — what the gates
  /// read, so a photo taken off shows here.
  final int live;
  final int goal;
  final bool done;

  /// Its cauris, paid once.
  final int reward;

  /// The tool it opens: 'invoices', 'production', 'credits'; null for none.
  final String? opens;

  factory PathStep.fromJson(Map<String, dynamic> j) => PathStep(
        key: '${j['key']}',
        stage: _int(j['stage']),
        title: '${j['title'] ?? ''}',
        line: '${j['line'] ?? ''}',
        go: '${j['go'] ?? ''}',
        progress: _int(j['progress']),
        live: j['live'] == null ? null : _int(j['live']),
        goal: j['goal'] == null ? 1 : _int(j['goal']),
        done: j['done'] == true,
        reward: _int(j['reward']),
        opens: j['opens'] as String?,
      );
}

/// This week's race in the business's league (086).
class LeagueBoard {
  const LeagueBoard({
    required this.label,
    required this.rank,
    required this.score,
    required this.size,
    this.gap,
    this.top = const [],
    this.hidden = false,
    this.notify = true,
    this.lastWeekRank,
  });

  /// « Boutiques · Ouagadougou · petites »
  final String label;
  final int rank;
  final int score;

  /// How many businesses race in the league.
  final int size;

  /// Cauris still needed to pass the place above; null when first.
  final int? gap;
  final List<({int rank, String name, int score, bool me})> top;
  final bool hidden;
  final bool notify;
  final int? lastWeekRank;

  factory LeagueBoard.fromJson(Map<String, dynamic> j) => LeagueBoard(
        label: '${j['label'] ?? ''}',
        rank: _int(j['rank']),
        score: _int(j['score']),
        size: _int(j['size']),
        gap: j['gap'] == null ? null : _int(j['gap']),
        top: [
          for (final t in (j['top'] as List? ?? const []))
            if (t is Map)
              (
                rank: _int(t['rank']),
                name: '${t['name']}',
                score: _int(t['score']),
                me: t['me'] == true,
              ),
        ],
        hidden: j['hidden'] == true,
        notify: j['notify'] != false,
        lastWeekRank: j['last_week'] is Map
            ? _int((j['last_week'] as Map)['rank'])
            : null,
      );
}

/// A business this one sponsored (092): it pays once its vitrine is
/// complete and it has finished 3 orders.
class Referral {
  const Referral({required this.name, required this.score, required this.orders, required this.paid});

  final String name;
  final int score;
  final int orders;
  final bool paid;
}

class CaurisWallet {
  const CaurisWallet({
    required this.balance,
    required this.week,
    this.expiresOn,
    this.referralCode,
    this.referred = false,
    this.referralPoints = 0,
    this.referrals = const [],
    this.history = const [],
    this.rules = const [],
    this.promo = const [],
  });

  final int balance;

  /// Promotional cauris the platform gave (100), soonest first: part of
  /// [balance], each to spend before its day.
  final List<PromoLot> promo;

  /// Earned since Monday: the league's score (086).
  final int week;

  /// When an idle wallet would empty itself.
  final DateTime? expiresOn;

  /// This business's own code for the businesses it brings in: its vitrine
  /// address.
  final String? referralCode;

  /// Whether it has said who brought it in.
  final bool referred;

  /// What one sponsored business pays once it takes off (092).
  final int referralPoints;

  /// The businesses this one brought in, and how far each is from paying.
  final List<Referral> referrals;
  final List<CaurisLine> history;

  /// How to earn, as the platform set it.
  final List<CaurisRule> rules;

  factory CaurisWallet.fromJson(Map<String, dynamic> j) => CaurisWallet(
        balance: _int(j['balance']),
        week: _int(j['week']),
        expiresOn: DateTime.tryParse('${j['expires_on'] ?? ''}'),
        promo: PromoLot.listOf(j['promo']),
        referralCode: j['referral_code'] as String?,
        referred: j['referred'] == true,
        referralPoints: _int(j['referral_points']),
        referrals: [
          for (final r in (j['referrals'] as List? ?? const []))
            if (r is Map)
              Referral(
                name: '${r['name']}',
                score: _int(r['score']),
                orders: _int(r['orders']),
                paid: r['paid'] == true,
              ),
        ],
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
