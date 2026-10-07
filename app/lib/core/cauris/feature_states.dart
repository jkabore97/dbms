/// What a business's tools cost in cauris, which are open, and its Basic
/// path (085), read in one call — feature_states().
class FeatureStates {
  const FeatureStates({
    this.plan = 'free',
    this.balance = 0,
    this.tools = const {},
    this.progress = const BasicProgress(),
    this.waveAllowed = false,
    this.setupDone = true,
  });

  final String plan;
  final int balance;

  /// Tool key → its cauris price and state. 'pro_all' is Mara Pro complet.
  final Map<String, ToolState> tools;
  final BasicProgress progress;

  /// Mara's tick (090): until it is given, every order is paid in cash and
  /// the Wave settings and buttons stay out of sight.
  final bool waveAllowed;

  /// The first setup was gone through (091). True when the server does
  /// not say, so an older database never shuts anybody out.
  final bool setupDone;

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
      setupDone: j['setup_done'] != false,
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

/// The tools on Le Chemin (097) — invoices, production, credits, a second
/// business — as the server gates them (path_locked): the steps that open
/// each are counted there, live, so the app never draws a door the server
/// would not open. Mara Pro and the businesses off the path are never
/// locked.
class BasicProgress {
  const BasicProgress({this.serverLocks});

  /// Tool → still locked, as org_progress() said it.
  final Map<String, bool>? serverLocks;

  /// Whether a tool on the path is still ahead of this business.
  bool locks(String feature) => serverLocks?[feature] ?? false;

  factory BasicProgress.fromJson(Map<String, dynamic> j) {
    final l = j['locks'];
    return BasicProgress(
      serverLocks: l is Map
          ? {for (final e in l.entries) '${e.key}': e.value == true}
          : null,
    );
  }
}
