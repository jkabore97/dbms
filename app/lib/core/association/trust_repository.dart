import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// An association's trust level (088): read off its own books on the
/// server, never declared. Null where it does not apply (a business) or
/// before the migration.
class TrustRepository {
  TrustRepository(this._client);

  final SupabaseClient? _client;

  Future<TrustLevel?> trust(String orgId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final v = await client.rpc('association_trust', params: {'p_org_id': orgId});
      if (v is! Map) return null;
      return TrustLevel.fromJson(Map<String, dynamic>.from(v));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  /// Mara's tick (platform admins only; the server refuses anyone else).
  Future<void> setVerified(String orgId, bool verified) async {
    await _client!.rpc('set_org_verified',
        params: {'p_org_id': orgId, 'p_verified': verified});
  }
}

class TrustLevel {
  const TrustLevel({
    required this.level,
    required this.met,
    required this.pillars,
    this.verifiedAt,
  });

  /// Nouvelle, Régulière, Fiable, Exemplaire.
  final String level;
  final int met;
  final List<TrustPillar> pillars;
  final DateTime? verifiedAt;

  bool get verified => verifiedAt != null;

  static const levels = ['Nouvelle', 'Régulière', 'Fiable', 'Exemplaire'];

  int get step => levels.indexOf(level).clamp(0, levels.length - 1);

  factory TrustLevel.fromJson(Map<String, dynamic> j) {
    int? n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    return TrustLevel(
      level: '${j['level'] ?? 'Nouvelle'}',
      met: n(j['met']) ?? 0,
      verifiedAt: DateTime.tryParse('${j['verified_at'] ?? ''}'),
      pillars: [
        for (final p in (j['pillars'] as List? ?? const []))
          if (p is Map)
            TrustPillar(
              key: '${p['key']}',
              met: p['met'] == true,
              value: n(p['value']),
              target: n(p['target']),
              of: n(p['of']),
            ),
      ],
    );
  }
}

class TrustPillar {
  const TrustPillar({
    required this.key,
    required this.met,
    this.value,
    this.target,
    this.of,
  });

  /// verified, regular, justified, clean, lasting.
  final String key;
  final bool met;
  final int? value;
  final int? target;
  final int? of;

  String get title => switch (key) {
        'verified' => 'Vérifiée par Mara',
        'regular' => 'Des comptes tenus chaque semaine',
        'justified' => 'Des dépenses justifiées',
        'clean' => 'Peu de corrections',
        'lasting' => 'Six mois sur Mara',
        _ => key,
      };

  /// Where it stands, and — when not met — what to do, in a line.
  String get line {
    final v = value ?? 0;
    final args = {'v': v, 'of': of ?? 0, 'months': (v / 30).floor()};
    return translate(trCurrent, switch (key) {
      'verified' => met
          ? 'Mara a vérifié qui vous êtes.'
          : 'Mara vérifie l\'association (récépissé, responsables). Demandez-le à votre contact Mara.',
      'regular' => met
          ? '{v} semaines sur les 8 dernières ont leurs entrées.'
          : v > 1
              ? '{v} semaines sur 8 : notez les entrées et sorties au moins 6 semaines sur 8.'
              : '{v} semaine sur 8 : notez les entrées et sorties au moins 6 semaines sur 8.',
      'justified' => (of ?? 0) < 3
          ? 'Moins de 3 dépenses en 90 jours : pas encore de quoi juger.'
          : met
              ? '{v} dépenses sur {of} ont leur reçu.'
              : 'Seulement {v} sur {of} ont leur reçu : photographiez chaque reçu (8 sur 10 au moins).',
      'clean' => (of ?? 0) < 5
          ? 'Moins de 5 entrées en 90 jours : pas encore de quoi juger.'
          : met
              ? (v > 1 ? '{v} corrections pour {of} entrées.' : '{v} correction pour {of} entrées.')
              : '{v} corrections pour {of} entrées : vérifiez avant d\'enregistrer (moins d\'une sur 10).',
      'lasting' => met
          ? 'Sur Mara depuis {months} mois.'
          : 'Sur Mara depuis {months} mois : la confiance se gagne avec le temps.',
      _ => '',
    }, args);
  }
}
