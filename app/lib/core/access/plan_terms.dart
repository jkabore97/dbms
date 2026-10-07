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
    this.freeMaxStaff = 1,
    this.freeMaxInvoicesMonth = 20,
    this.freeMaxPhotos = 50,
    this.freePhotoItems = 10,
    this.freeHistoryMonths = 12,
    this.priceMonth = 2500,
    this.priceYear = 25000,
    this.currency = 'XOF',
    this.wave = '',
    this.waveName = '',
    this.deliverySharePct = 10,
    this.stripeOn = false,
    this.kinds = const {},
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
    'delivery',
    'online_payment',
  ];

  static const defaults = PlanTerms();

  /// Tool keys behind the plan. Some are the dial's own keys (tontines),
  /// some exist only for the plan (analytics, accounting, payroll,
  /// team_access, currencies).
  final List<String> proFeatures;
  final int freeMaxStaff;
  final int freeMaxInvoicesMonth;
  final int freeMaxPhotos;

  /// The articles a Basic business may photograph (100); one more per
  /// photo slot bought with cauris.
  final int freePhotoItems;
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

  /// Kaj Pro by card, as a Stripe subscription (082): the platform's switch.
  /// The price is [priceMonth] / [priceYear], the same wherever it is paid.
  final bool stripeOn;

  bool get hasWave => wave.trim().isNotEmpty;

  /// A kind's own free numbers, set by Mara (107's kind_settings), keyed
  /// 'retail' | 'farm' | 'association', then by the setting's key. Empty
  /// when no kind has one: every business reads the numbers above.
  final Map<String, Map<String, int>> kinds;

  /// The terms a business of [profile] lives under: its kind's own free
  /// numbers where Mara set them (a legacy church reads as an
  /// association), the platform's otherwise — what the server enforces.
  PlanTerms forProfile(String profile) {
    final own = kinds[profile == 'church' ? 'association' : profile];
    if (own == null || own.isEmpty) return this;
    return PlanTerms(
      proFeatures: proFeatures,
      freeMaxStaff: own['free_max_staff'] ?? freeMaxStaff,
      freeMaxInvoicesMonth: own['free_max_invoices_month'] ?? freeMaxInvoicesMonth,
      freeMaxPhotos: freeMaxPhotos,
      freePhotoItems: own['free_photo_items'] ?? freePhotoItems,
      freeHistoryMonths: freeHistoryMonths,
      priceMonth: priceMonth,
      priceYear: priceYear,
      currency: currency,
      wave: wave,
      waveName: waveName,
      deliverySharePct: deliverySharePct,
      stripeOn: stripeOn,
      kinds: kinds,
    );
  }

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
      freeMaxStaff: n('free_max_staff', 1),
      freeMaxInvoicesMonth: n('free_max_invoices_month', 20),
      freeMaxPhotos: n('free_max_photos', 50),
      freePhotoItems: n('free_photo_items', 10),
      freeHistoryMonths: n('free_history_months', 12),
      priceMonth: n('pro_price_month', 2500),
      priceYear: n('pro_price_year', 25000),
      currency: s('pro_currency').isEmpty ? 'XOF' : s('pro_currency'),
      wave: s('platform_wave'),
      waveName: s('platform_wave_name'),
      deliverySharePct: n('delivery_share_pct', 10),
      stripeOn: json['stripe_on'] == true,
      kinds: {
        if (json['kinds'] is Map)
          for (final e in (json['kinds'] as Map).entries)
            if (e.value is Map)
              '${e.key}': {
                for (final v in (e.value as Map).entries)
                  if (v.value is num) '${v.key}': (v.value as num).toInt(),
              },
      },
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
        'delivery' =>
          'Livraison depuis la vitrine : prix selon la distance, livreurs, suivi',
        'online_payment' =>
          'Paiement en ligne des commandes : Wave ou carte, versé sur votre numéro',
        'photo_slot' => 'Une place photo de plus, pour toujours',
        _ => feature,
      };

  /// Whether a Pro tool means anything to a business of [profile] — what
  /// the cauris screens offer to open. The analyses are a shop's and a
  /// farm's (101: Compte draws them for both); an association keeps to its
  /// own tools (099): no analyses, and no delivery — its services are
  /// booked, not carried.
  static bool fits(String feature, String profile) => switch (feature) {
        'analytics' => profile == 'retail' || profile == 'farm',
        'delivery' => profile != 'association' && profile != 'church',
        _ => true,
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
