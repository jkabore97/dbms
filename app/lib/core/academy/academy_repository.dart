import 'package:supabase_flutter/supabase_flutter.dart';

/// Académie Mara (087): the lessons of a business's kind, what this person
/// has done, and the level they climbed to.
class AcademyRepository {
  AcademyRepository(this._client);

  final SupabaseClient? _client;

  Future<Academy?> mine(String orgId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final v = await client.rpc('my_academy', params: {'p_org_id': orgId});
      if (v is! Map) return null;
      return Academy.fromJson(Map<String, dynamic>.from(v));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  /// Done when seen (a guide) or when lived (a mission — the server checks
  /// the business's own data). Returns whether it is done, and the cauris
  /// it earned the business (0 when already paid).
  Future<({bool done, int earned})> complete(String orgId, String lesson) async {
    final v = await _client!.rpc('complete_lesson',
        params: {'p_org_id': orgId, 'p_lesson': lesson});
    if (v is! Map) return (done: false, earned: 0);
    final e = v['earned'];
    return (done: v['done'] == true, earned: e is num ? e.toInt() : 0);
  }
}

class Academy {
  const Academy({
    required this.lessons,
    required this.done,
    required this.total,
    required this.level,
    this.caurisEach = 0,
  });

  final List<AcademyLesson> lessons;
  final int done;
  final int total;

  /// Apprenti, Commerçant, Maître.
  final String level;
  final int caurisEach;

  factory Academy.fromJson(Map<String, dynamic> j) {
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return Academy(
      lessons: [
        for (final l in (j['lessons'] as List? ?? const []))
          if (l is Map)
            AcademyLesson(
              key: '${l['key']}',
              title: '${l['title']}',
              mission: l['kind'] == 'mission',
              minutes: n(l['minutes']),
              done: l['done'] == true,
              ready: l['ready'] == true,
            ),
      ],
      done: n(j['done']),
      total: n(j['total']),
      level: '${j['level'] ?? 'Apprenti'}',
      caurisEach: n(j['cauris_each']),
    );
  }
}

class AcademyLesson {
  const AcademyLesson({
    required this.key,
    required this.title,
    required this.mission,
    required this.minutes,
    required this.done,
    required this.ready,
  });

  final String key;
  final String title;

  /// Lived, not just seen: the server checks it.
  final bool mission;
  final int minutes;
  final bool done;

  /// A mission already lived, waiting to be collected.
  final bool ready;
}
