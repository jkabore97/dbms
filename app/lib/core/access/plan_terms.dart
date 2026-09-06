/// The line between Kaj and Kaj Pro, as the platform draws it (066).
///
/// Read once per session from `plan_terms()`. Nothing here is a secret: the
/// list says which tools carry the Pro badge, the caps say when a Free
/// business is asked to pay, and the price and the Wave number are what the
/// owner is asked for. A database before 066 — or no signal at all — answers
/// with [defaults], which are the same numbers 066 seeds.
class PlanTerms {
  const PlanTerms({
    this.proFeatures = defaultProFeatures,
    this.freeMaxStaff = 3,
    this.freeMaxInvoicesMonth = 20,
    this.freeMaxPhotos = 50,
    this.freeHistoryMonths = 12,
    this.priceMonth = 2500,
    this.priceYear = 25000,
    this.currency = 'XOF',
    this.wave = '',
    this.waveName = '',
    this.deliverySharePct = 10,
  });

  /// What 066 seeds, so a build ahead of its database badges the same tools.
  static const defaultProFeatures = [
    'payroll',
    'team_access',
    'analytics',
    'accounting',
    'currencies',
    'tontines',
    'vitrine_plus',
  ];

  static const defaults = PlanTerms();

  /// Tool keys behind the plan. Some are the dial's own keys (tontines),
  /// some exist only for the plan (analytics, accounting, payroll,
  /// team_access, currencies).
  final List<String> proFeatures;
  final int freeMaxStaff;
  final int freeMaxInvoicesMonth;
  final int freeMaxPhotos;
  final int freeHistoryMonths;
  final int priceMonth;
  final int priceYear;
  final String currency;

  /// The number the owner pays to. Empty until the platform sets it from
  /// the console; the paywall then says "contact us" rather than inventing
  /// one.
  final String wave;
  final String waveName;

  /// The platform's part of every delivery fee, in percent (067). Fixed
  /// on each order when its fee is; this is the rate for the next one.
  final int deliverySharePct;

  bool get hasWave => wave.trim().isNotEmpty;

  factory PlanTerms.fromJson(Map<String, dynamic> json) {
    int n(String key, int fallback) {
      final v = json[key];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    String s(String key) => (json[key] as String?) ?? '';

    final features = json['pro_features'];
    return PlanTerms(
      proFeatures: features is List
          ? features.map((f) => f.toString()).toList()
          : defaultProFeatures,
      freeMaxStaff: n('free_max_staff', 3),
      freeMaxInvoicesMonth: n('free_max_invoices_month', 20),
      freeMaxPhotos: n('free_max_photos', 50),
      freeHistoryMonths: n('free_history_months', 12),
      priceMonth: n('pro_price_month', 2500),
      priceYear: n('pro_price_year', 25000),
      currency: s('pro_currency').isEmpty ? 'XOF' : s('pro_currency'),
      wave: s('platform_wave'),
      waveName: s('platform_wave_name'),
      deliverySharePct: n('delivery_share_pct', 10),
    );
  }

  /// What a Pro tool is called on the paywall, in the words of the screens
  /// that carry it. An unknown key reads as itself rather than crashing a
  /// sheet because the platform added a tool the build does not know.
  static String labelOf(String feature) => switch (feature) {
        'payroll' => 'Pointages et paie du personnel',
        'team_access' => "Accès de l'équipe : qui voit quoi, qui modifie quoi",
        'analytics' => 'Analyses : ventes par heure, par jour, par article',
        'accounting' => 'Comptabilité : journal, résultat, bilan, grand livre',
        'currencies' => 'Devises : encaisser et compter en plusieurs monnaies',
        'tontines' => 'Tontines',
        'vitrine_plus' =>
          'Vitrine personnalisée : photo de couverture, horaires, couleur, '
              'articles épinglés',
        _ => feature,
      };
}

/// An owner said "J'ai payé" (066). One row per business until the platform
/// handles it.
class PlanRequest {
  const PlanRequest({
    required this.id,
    required this.orgId,
    required this.orgName,
    required this.orgPlan,
    required this.requestedBy,
    required this.createdAt,
    this.amount,
    this.note,
  });

  final String id;
  final String orgId;
  final String orgName;

  /// The business's effective plan right now — 'pro' means somebody already
  /// set it and the request only needs closing.
  final String orgPlan;
  final String requestedBy;
  final double? amount;
  final String? note;
  final DateTime createdAt;

  factory PlanRequest.fromRow(Map<String, dynamic> row) {
    final raw = row['amount'];
    return PlanRequest(
      id: row['id'] as String,
      orgId: row['org_id'] as String,
      orgName: (row['org_name'] as String?) ?? '',
      orgPlan: (row['org_plan'] as String?) ?? 'free',
      requestedBy: (row['requested_by'] as String?) ?? '',
      amount: raw == null
          ? null
          : (raw is num ? raw.toDouble() : double.tryParse('$raw')),
      note: row['note'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
