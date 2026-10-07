import 'package:supabase_flutter/supabase_flutter.dart';

/// The fiche entreprise's window onto the server (106, on 104's journal):
/// one business, seen and changed by the platform. Every call here is
/// refused by the server to anybody but a platform admin — the fiche is
/// drawn only for one, and that is a courtesy, not the lock.
class FicheRepository {
  FicheRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  SupabaseClient get _db {
    final c = _client;
    if (c == null) {
      throw StateError(
        "Cette version de l'application a été compilée sans serveur.",
      );
    }
    return c;
  }

  /// The Aperçu in one call: health, owner, plan, cauris, alerts (106).
  Future<OrgOverview> overview(String orgId) async {
    final v = await _db.rpc('platform_org_overview', params: {'p_org': orgId});
    return OrgOverview.fromJson(Map<String, dynamic>.from(v as Map));
  }

  /// The Identité (106). Null leaves a field; an empty phone or address
  /// clears it. [confirm] is the business's name, typed back to change its
  /// kind. Returns the journal line, or null when nothing moved.
  Future<String?> updateIdentity(
    String orgId, {
    String? name,
    String? profile,
    String? slug,
    String? currency,
    String? phone,
    String? address,
    bool? verified,
    String? confirm,
  }) async {
    final v = await _db.rpc('platform_update_org_identity', params: {
      'p_org': orgId,
      'p_name': ?name,
      'p_profile': ?profile,
      'p_slug': ?slug,
      'p_currency': ?currency,
      'p_phone': ?phone,
      'p_address': ?address,
      'p_verified': ?verified,
      'p_confirm': ?confirm,
    });
    return v as String?;
  }

  /// This business's switches (104's board at the business's level).
  Future<List<FeatureBoardRow>> board(String orgId) async {
    final v = await _db.rpc('platform_feature_board', params: {'p_org': orgId});
    return [
      for (final r in (v is List ? v : const []))
        FeatureBoardRow.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// One switch for this business: 'default', 'visible' or 'hidden' (104).
  /// Refused, in French, for a feature the business paid for. Returns the
  /// journal line, or null when nothing moved.
  Future<String?> setFeature(String orgId, String feature, String state,
      {DateTime? until, String? note}) async {
    final v = await _db.rpc('platform_set_feature_rule', params: {
      'p_scope': 'org',
      'p_kind': null,
      'p_org': orgId,
      'p_feature': feature,
      'p_state': state,
      'p_until': until?.toUtc().toIso8601String(),
      'p_note': note,
    });
    return v as String?;
  }

  /// The journal of what Mara did to this business, newest first (104).
  Future<List<PlatformAction>> actions(String orgId,
      {int limit = 50, DateTime? before}) async {
    final v = await _db.rpc('platform_actions_page', params: {
      'p_org': orgId,
      'p_limit': limit,
      'p_before': before?.toUtc().toIso8601String(),
    });
    return [
      for (final r in (v is List ? v : const []))
        PlatformAction.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// « Annuler » (104): the line's undo, once.
  Future<void> undo(String actionId) async {
    await _db.rpc('platform_undo', params: {'p_action': actionId});
  }

  /// The newest line of one kind for this business — what a save that
  /// returns no id of its own (set_org_plan, logged by 106's trigger)
  /// wrote, for its « Annuler ».
  Future<PlatformAction?> latest(String orgId, String kind) async {
    final page = await actions(orgId, limit: 5);
    for (final a in page) {
      if (a.kind == kind) return a;
    }
    return null;
  }
}

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String? _text(Object? v) {
  final t = v?.toString().trim() ?? '';
  return t.isEmpty ? null : t;
}

/// One business as the platform sees it (106's platform_org_overview).
class OrgOverview {
  const OrgOverview({
    required this.id,
    required this.name,
    required this.slug,
    required this.profile,
    this.associationKind,
    this.currency = 'XOF',
    this.phone,
    this.address,
    this.city,
    this.createdAt,
    this.archivedAt,
    this.suspendedAt,
    this.verifiedAt,
    this.showcase = false,
    this.waveAllowed = false,
    this.setupDone = true,
    this.health = 'never',
    this.lastActivityAt,
    this.daysSilent,
    this.owner,
    this.members = 0,
    this.roles = const {},
    this.plan = 'free',
    this.planRaw = 'free',
    this.planUntil,
    this.planNote,
    this.cauris = 0,
    this.promo = const [],
    this.unlocks = const [],
    this.vitrineOpen = false,
    this.published = 0,
    this.rules = 0,
    this.actions = 0,
    this.lastActionAt,
    this.alerts = const [],
  });

  final String id;
  final String name;
  final String slug;
  final String profile;
  final String? associationKind;
  final String currency;
  final String? phone;
  final String? address;
  final String? city;
  final DateTime? createdAt;
  final DateTime? archivedAt;
  final DateTime? suspendedAt;
  final DateTime? verifiedAt;
  final bool showcase;
  final bool waveAllowed;
  final bool setupDone;

  /// 'healthy' | 'slowing' | 'silent' | 'never' | 'archived'.
  final String health;
  final DateTime? lastActivityAt;
  final int? daysSilent;
  final OrgOwner? owner;
  final int members;

  /// Role → how many people hold it.
  final Map<String, int> roles;

  /// The plan in effect ('pro' or 'free'), and the one the platform set.
  final String plan;
  final String planRaw;
  final DateTime? planUntil;
  final String? planNote;
  final int cauris;

  /// Promotional cauris: so many, to spend before a day.
  final List<({int points, DateTime until})> promo;

  /// The Pro tools open now, until when, and whether Mara gave them.
  final List<({String feature, DateTime until, bool gift, String? note})> unlocks;
  final bool vitrineOpen;
  final int published;

  /// This business's own switches on the board, and Mara's lines on it.
  final int rules;
  final int actions;
  final DateTime? lastActionAt;

  /// What wants attention: {kind, n?, until?, days?, at?}.
  final List<Map<String, dynamic>> alerts;

  bool get isAssociation => profile == 'association' || profile == 'church';
  bool get isArchived => archivedAt != null;
  bool get isPro => plan == 'pro';

  factory OrgOverview.fromJson(Map<String, dynamic> j) {
    final vitrine = j['vitrine'] is Map
        ? Map<String, dynamic>.from(j['vitrine'] as Map)
        : const <String, dynamic>{};
    return OrgOverview(
      id: '${j['id']}',
      name: '${j['name'] ?? ''}',
      slug: '${j['slug'] ?? ''}',
      profile: '${j['profile'] ?? 'generic'}',
      associationKind: _text(j['association_kind']),
      currency: _text(j['currency']) ?? 'XOF',
      phone: _text(j['phone']),
      address: _text(j['address']),
      city: _text(j['city']),
      createdAt: _date(j['created_at']),
      archivedAt: _date(j['archived_at']),
      suspendedAt: _date(j['suspended_at']),
      verifiedAt: _date(j['verified_at']),
      showcase: j['showcase'] == true,
      waveAllowed: j['wave_allowed'] == true,
      setupDone: j['setup_done'] != false,
      health: '${j['health'] ?? 'never'}',
      lastActivityAt: _date(j['last_activity_at']),
      daysSilent: j['days_silent'] == null ? null : _int(j['days_silent']),
      owner: j['owner'] is Map
          ? OrgOwner.fromJson(Map<String, dynamic>.from(j['owner'] as Map))
          : null,
      members: _int(j['members']),
      roles: {
        if (j['roles'] is Map)
          for (final e in (j['roles'] as Map).entries) '${e.key}': _int(e.value),
      },
      plan: '${j['plan'] ?? 'free'}',
      planRaw: '${j['plan_raw'] ?? 'free'}',
      planUntil: _date(j['plan_until']),
      planNote: _text(j['plan_note']),
      cauris: _int(j['cauris']),
      promo: [
        for (final p in (j['promo'] is List ? j['promo'] as List : const []))
          if (p is Map && _date(p['until']) != null)
            (points: _int(p['points']), until: _date(p['until'])!),
      ],
      unlocks: [
        for (final u in (j['unlocks'] is List ? j['unlocks'] as List : const []))
          if (u is Map && _date(u['until']) != null)
            (
              feature: '${u['feature']}',
              until: _date(u['until'])!,
              gift: u['gift'] == true,
              note: _text(u['note']),
            ),
      ],
      vitrineOpen: vitrine['open'] == true,
      published: _int(vitrine['published']),
      rules: _int(j['rules']),
      actions: _int(j['actions']),
      lastActionAt: _date(j['last_action_at']),
      alerts: [
        for (final a in (j['alerts'] is List ? j['alerts'] as List : const []))
          if (a is Map) Map<String, dynamic>.from(a),
      ],
    );
  }
}

class OrgOwner {
  const OrgOwner({this.userId, this.name, this.phone, this.email});

  final String? userId;
  final String? name;
  final String? phone;
  final String? email;

  factory OrgOwner.fromJson(Map<String, dynamic> j) => OrgOwner(
        userId: _text(j['user_id']),
        name: _text(j['name']),
        phone: _text(j['phone']),
        email: _text(j['email']),
      );
}

/// One line of 104's board: a feature, its switch here, what it comes to.
class FeatureBoardRow {
  const FeatureBoardRow({
    required this.key,
    required this.label,
    required this.group,
    this.state = 'default',
    this.effective = 'visible',
    this.source = 'catalog',
    this.until,
    this.note,
    this.paid = false,
    this.proTool,
  });

  final String key;
  final String label;
  final String group;

  /// The switch at this level: 'default' | 'visible' | 'hidden'.
  final String state;

  /// What the business is shown: 'visible' | 'hidden'.
  final String effective;

  /// Where that comes from: 'catalog' | 'kind' | 'org'.
  final String source;
  final DateTime? until;
  final String? note;

  /// The business paid for it (a paid Mara Pro, or its own cauris): it
  /// cannot be hidden.
  final bool paid;
  final String? proTool;

  bool get hidden => effective == 'hidden';

  factory FeatureBoardRow.fromJson(Map<String, dynamic> j) => FeatureBoardRow(
        key: '${j['key']}',
        label: '${j['label'] ?? j['key']}',
        group: '${j['grp'] ?? ''}',
        state: '${j['state'] ?? 'default'}',
        effective: '${j['effective'] ?? 'visible'}',
        source: '${j['source'] ?? 'catalog'}',
        until: _date(j['until']),
        note: _text(j['note']),
        paid: j['paid'] == true,
        proTool: _text(j['pro_tool']),
      );
}

/// One line of the command center's journal (104's platform_actions_page).
class PlatformAction {
  const PlatformAction({
    required this.id,
    required this.at,
    required this.kind,
    required this.summary,
    this.actorLabel = 'Mara',
    this.orgId,
    this.orgName,
    this.before,
    this.after,
    this.undoable = false,
    this.undoneAt,
    this.undoneBy,
  });

  final String id;
  final DateTime at;
  final String kind;

  /// The server's own line, in French: « Vitrine : présentation, logo ».
  final String summary;
  final String actorLabel;
  final String? orgId;
  final String? orgName;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final bool undoable;
  final DateTime? undoneAt;
  final String? undoneBy;

  bool get undone => undoneAt != null;

  factory PlatformAction.fromJson(Map<String, dynamic> j) => PlatformAction(
        id: '${j['id']}',
        at: _date(j['at']) ?? DateTime.now(),
        kind: '${j['kind'] ?? ''}',
        summary: '${j['summary'] ?? ''}',
        actorLabel: _text(j['actor_label']) ?? 'Mara',
        orgId: _text(j['org_id']),
        orgName: _text(j['org_name']),
        before: j['before'] is Map ? Map<String, dynamic>.from(j['before'] as Map) : null,
        after: j['after'] is Map ? Map<String, dynamic>.from(j['after'] as Map) : null,
        undoable: j['undoable'] == true,
        undoneAt: _date(j['undone_at']),
        undoneBy: _text(j['undone_by_label']),
      );
}
