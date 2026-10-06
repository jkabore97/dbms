/// What a business's tools cost in cauris, which are open, and its Basic
/// path (085), read in one call — feature_states().
class FeatureStates {
  const FeatureStates({
    this.plan = 'free',
    this.balance = 0,
    this.tools = const {},
    this.progress = const BasicProgress(),
    this.waveAllowed = false,
  });

  final String plan;
  final int balance;

  /// Tool key → its cauris price and state. 'pro_all' is Mara Pro complet.
  final Map<String, ToolState> tools;
  final BasicProgress progress;

  /// Mara's tick (090): until it is given, every order is paid in cash and
  /// the Wave settings and buttons stay out of sight.
  final bool waveAllowed;

  bool get isPro => plan == 'pro';

  /// The tools a cauris unlock has opened right now.
  Set<String> get unlocked => {
        for (final e in tools.entries)
          if (e.value.until != null) e.key,
      };

  ToolState? toolOf(String feature) => tools[feature];

  factory FeatureStates.fromJson(Map<String, dynamic> j) {
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final tools = <String, ToolState>{};
    for (final t in (j['tools'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(t as Map);
      tools['${m['feature']}'] = ToolState(
        cost: n(m['cost']),
        until: DateTime.tryParse('${m['until'] ?? ''}'),
        waitsDays: m['waits_days'] == null ? null : n(m['waits_days']),
      );
    }
    final p = j['progress'];
    return FeatureStates(
      plan: '${j['plan'] ?? 'free'}',
      balance: n(j['balance']),
      tools: tools,
      progress: p is Map
          ? BasicProgress.fromJson(Map<String, dynamic>.from(p))
          : const BasicProgress(),
      waveAllowed: j['wave_allowed'] == true,
    );
  }
}

class ToolState {
  const ToolState({required this.cost, this.until, this.waitsDays});

  /// Its price in cauris, for 30 days.
  final int cost;

  /// Open until then, by cauris; null when not unlocked.
  final DateTime? until;

  /// Days on Mara still to wait before cauris can open it (accounting,
  /// tontines); null when it can be bought now.
  final int? waitsDays;
}

/// The Basic path (085): a business that starts on Mara opens its tools as
/// its vitrine grows. Businesses already here are not [gated].
class BasicProgress {
  const BasicProgress({
    this.gated = false,
    this.inTrial = false,
    this.trialUntil,
    this.score = 100,
    this.orders = 0,
    this.streetPct = 60,
    this.toolsPct = 90,
    this.invoicesPct = 70,
    this.productionPct = 90,
    this.creditOrders = 3,
    this.ordersNeeded = 3,
    this.onStreet = true,
    this.pro = false,
    this.serverLocks,
  });

  final bool gated;

  /// 085's first days; never true since 089 — kept so an older answer reads.
  final bool inTrial;
  final DateTime? trialUntil;

  /// The vitrine's own score, 0–100.
  final int score;

  /// Orders picked up or delivered, ever.
  final int orders;
  final int streetPct;
  final int toolsPct;
  final int invoicesPct;
  final int productionPct;
  final int creditOrders;
  final int ordersNeeded;
  final bool onStreet;
  final bool pro;

  /// The server's own answer (089), step by step: the rule the database
  /// enforces, so the app never draws a door the server would not open.
  final Map<String, bool>? serverLocks;

  /// The tools a growing vitrine opens.
  static const vitrineTools = {'invoices', 'production', 'credits'};

  /// Whether a Basic tool is still ahead of this business.
  bool locks(String feature) {
    final server = serverLocks;
    if (server != null) return server[feature] ?? false;
    if (!gated || inTrial) return false;
    return switch (feature) {
      'invoices' => score < invoicesPct,
      'production' => score < productionPct,
      'credits' => orders < creditOrders,
      'second_business' => !pro,
      _ => false,
    };
  }

  /// How far along, 0–1, for the bar on the lock.
  double progressFor(String feature) => switch (feature) {
        'invoices' => (score / invoicesPct).clamp(0, 1).toDouble(),
        'production' => (score / productionPct).clamp(0, 1).toDouble(),
        'credits' => creditOrders == 0 ? 1 : (orders / creditOrders).clamp(0, 1).toDouble(),
        _ => pro ? 1 : 0,
      };

  /// The goal, in a few words.
  String goalFor(String feature) => switch (feature) {
        'invoices' => 'Vitrine à $invoicesPct %',
        'production' => 'Vitrine à $productionPct %',
        'credits' => '$creditOrders commandes',
        'second_business' => 'Mara Pro',
        _ => '',
      };

  /// Where it stands, in a few words.
  String needFor(String feature) => switch (feature) {
        'invoices' || 'production' => 'Vitrine : $score %',
        'credits' => 'Commandes : $orders / $creditOrders',
        'second_business' => 'Avec Mara Pro',
        _ => '',
      };

  factory BasicProgress.fromJson(Map<String, dynamic> j) {
    int n(Object? v, int d) => v is num ? v.toInt() : int.tryParse('$v') ?? d;
    final l = j['locks'];
    return BasicProgress(
      gated: j['gated'] == true,
      inTrial: j['in_trial'] == true,
      trialUntil: DateTime.tryParse('${j['trial_until'] ?? ''}'),
      score: n(j['score'], 0),
      orders: n(j['orders'], 0),
      streetPct: n(j['street_pct'], 60),
      toolsPct: n(j['tools_pct'], 90),
      invoicesPct: n(j['invoices_pct'], 70),
      productionPct: n(j['production_pct'], 90),
      creditOrders: n(j['credit_orders'], 3),
      ordersNeeded: n(j['orders_needed'], 3),
      onStreet: j['on_street'] != false,
      pro: j['pro'] == true,
      serverLocks: l is Map
          ? {for (final e in l.entries) '${e.key}': e.value == true}
          : null,
    );
  }
}
