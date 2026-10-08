import 'package:supabase_flutter/supabase_flutter.dart';

import 'fiche_repository.dart' show FeatureBoardRow;

/// The types of business, as Mara shapes them (104's switchboard at a
/// kind's level, 107's settings by kind): what every shop, every farm or
/// every association is shown, its free numbers, its vitrine by default
/// and its walkthrough. Every call is refused by the server to anybody but
/// a platform admin; the screen is drawn only for one, as a courtesy.
class KindModelsRepository {
  KindModelsRepository(this._client);

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

  /// A kind's tab: its businesses, numbers, vitrine default, walkthrough.
  Future<KindModels> models(String kind) async {
    final v = await _db.rpc('platform_kind_models', params: {'p_kind': kind});
    return KindModels.fromJson(Map<String, dynamic>.from(v as Map));
  }

  /// The kind's switches (104's board for a kind).
  Future<List<FeatureBoardRow>> board(String kind) async {
    final v = await _db.rpc('platform_feature_board', params: {'p_kind': kind});
    return [
      for (final r in (v is List ? v : const []))
        FeatureBoardRow.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// What a kind's switch would touch, before it is saved (104).
  Future<FeatureImpact> impact(String kind, String feature, String state) async {
    final v = await _db.rpc('platform_feature_impact', params: {
      'p_kind': kind,
      'p_feature': feature,
      'p_state': state,
    });
    return FeatureImpact.fromJson(Map<String, dynamic>.from(v as Map));
  }

  /// One switch for every business of the kind: 'default', 'visible' or
  /// 'hidden'. Returns the journal line, or null when nothing moved.
  Future<String?> setFeature(String kind, String feature, String state) async {
    final v = await _db.rpc('platform_set_feature_rule', params: {
      'p_scope': 'kind',
      'p_kind': kind,
      'p_org': null,
      'p_feature': feature,
      'p_state': state,
    });
    return v as String?;
  }

  /// One of the kind's own settings (107): a number, 'vitrine_default' (a
  /// map) or 'setup_off' (a list). Null is « Par défaut ». Returns the
  /// journal line, or null when nothing moved.
  Future<String?> setSetting(String kind, String key, Object? value) async {
    final v = await _db.rpc('platform_set_kind_setting', params: {
      'p_kind': kind,
      'p_key': key,
      'p_value': value,
    });
    return v as String?;
  }
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// What a kind's switch would touch: its businesses, those that keep a
/// switch of their own, those that paid for it (they keep it).
class FeatureImpact {
  const FeatureImpact({this.orgs = 0, this.overridden = 0, this.paid = 0});

  final int orgs;
  final int overridden;
  final int paid;

  factory FeatureImpact.fromJson(Map<String, dynamic> j) => FeatureImpact(
        orgs: _int(j['orgs']),
        overridden: _int(j['overridden']),
        paid: _int(j['paid']),
      );
}

/// A kind's tab, from platform_kind_models (107).
class KindModels {
  const KindModels({
    required this.kind,
    this.orgs = 0,
    this.free = 0,
    this.neverDressed = 0,
    this.settings = const [],
    this.vitrineDefault,
    this.setup = const [],
  });

  final String kind;

  /// The kind's businesses (not archived, no vitrine d'exemple), those on
  /// the free plan, and those whose vitrine was never dressed.
  final int orgs;
  final int free;
  final int neverDressed;
  final List<KindSettingRow> settings;
  final VitrineDefault? vitrineDefault;
  final List<SetupStepRow> setup;

  Set<String> get stepsOff => {
        for (final s in setup)
          if (!s.on) s.key,
      };

  factory KindModels.fromJson(Map<String, dynamic> j) => KindModels(
        kind: '${j['kind'] ?? ''}',
        orgs: _int(j['orgs']),
        free: _int(j['free']),
        neverDressed: _int(j['never_dressed']),
        settings: [
          for (final r in (j['settings'] is List ? j['settings'] as List : const []))
            if (r is Map) KindSettingRow.fromJson(Map<String, dynamic>.from(r)),
        ],
        vitrineDefault: j['vitrine_default'] is Map
            ? VitrineDefault.fromJson(Map<String, dynamic>.from(j['vitrine_default'] as Map))
            : null,
        setup: [
          for (final r in (j['setup'] is List ? j['setup'] as List : const []))
            if (r is Map) SetupStepRow.fromJson(Map<String, dynamic>.from(r)),
        ],
      );
}

/// One free number: the platform's, and the kind's own when Mara set one.
class KindSettingRow {
  const KindSettingRow({
    required this.key,
    required this.label,
    required this.global,
    this.value,
    this.min = 0,
    this.max = 1000,
  });

  final String key;
  final String label;
  final int global;

  /// The kind's own; null: « Par défaut » (the global one).
  final int? value;
  final int min;
  final int max;

  int get effective => value ?? global;

  factory KindSettingRow.fromJson(Map<String, dynamic> j) => KindSettingRow(
        key: '${j['key']}',
        label: '${j['label'] ?? j['key']}',
        global: _int(j['global']),
        value: j['value'] is num ? (j['value'] as num).toInt() : null,
        min: _int(j['min']),
        max: j['max'] == null ? 1000 : _int(j['max']),
      );
}

/// Mara's vitrine for a kind, for a vitrine never dressed (107): a layout
/// ('grid' | 'large' | 'list' | 'menu'), a colour '#RRGGBB', a cover
/// ('none' | 'first_photo').
class VitrineDefault {
  const VitrineDefault({this.layout = 'grid', this.accent, this.cover = 'none'});

  final String layout;
  final String? accent;
  final String cover;

  bool get isEmpty => layout == 'grid' && accent == null && cover == 'none';

  factory VitrineDefault.fromJson(Map<String, dynamic> j) => VitrineDefault(
        layout: '${j['layout'] ?? 'grid'}',
        accent: j['accent'] as String?,
        cover: '${j['cover'] ?? 'none'}',
      );

  Map<String, Object?> toJson() => {
        if (layout != 'grid') 'layout': layout,
        'accent': ?accent,
        if (cover != 'none') 'cover': cover,
      };
}

/// One step of a kind's walkthrough: on, unless Mara turned it off; a
/// required one is always on.
class SetupStepRow {
  const SetupStepRow({
    required this.key,
    required this.label,
    this.required = false,
    this.on = true,
  });

  final String key;
  final String label;
  final bool required;
  final bool on;

  factory SetupStepRow.fromJson(Map<String, dynamic> j) => SetupStepRow(
        key: '${j['key']}',
        label: '${j['label'] ?? j['key']}',
        required: j['required'] == true,
        on: j['on'] != false,
      );
}
