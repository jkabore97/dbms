import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// The three reports the church module already had in SQL and never had a
/// screen for: `church_weekly_summary`, `church_balances` and
/// `member_giving_statement` (002_church_profile.sql).
///
/// None of them is SECURITY DEFINER, and that is the point: they run as the
/// caller with RLS enforced on every table underneath, so a report cannot show
/// a person a number they would not be allowed to compute themselves. The
/// client passes an org id and the server decides whether that means anything.
///
/// Nothing here is cached. A report is a claim about money at a moment; a
/// stale one shown without saying so is worse than no report at all, so these
/// need signal and the screens say when there is none.
class ReportsRepository {
  ReportsRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  /// The Sunday summary. [weekEnding] defaults server-side to today; the
  /// function covers the seven days ending on it.
  Future<WeeklySummary> weeklySummary(
    String orgId, {
    DateTime? weekEnding,
  }) async {
    final client = _requireClient();
    final rows = await client.rpc('church_weekly_summary', params: {
      'p_org_id': orgId,
      if (weekEnding != null)
        'p_week_ending': _dateOnly(weekEnding),
    }) as List<dynamic>;

    return WeeklySummary.fromRows(
      rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
      weekEnding: weekEnding ?? DateTime.now(),
    );
  }

  /// Cash, bank and mobile money, as of now.
  Future<List<AccountBalance>> balances(String orgId) async {
    final client = _requireClient();
    final rows = await client.rpc('church_balances', params: {
      'p_org_id': orgId,
    }) as List<dynamic>;

    return rows
        .map((r) => AccountBalance.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// The people a giving statement can be produced for. Not a report function
  /// — church_members is a plain table, readable to org members under the
  /// policy in 002.
  Future<List<ChurchMember>> members(String orgId) async {
    final client = _requireClient();
    final rows = await client
        .from('church_members')
        .select('id, full_name, phone')
        .eq('org_id', orgId)
        .eq('is_active', true)
        .order('full_name');

    return (rows as List)
        .map((r) => ChurchMember.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// One member's giving for a calendar year — the year-end document they take
  /// to their own records.
  Future<List<GivingLine>> givingStatement(
    String memberId, {
    required int year,
  }) async {
    final client = _requireClient();
    final rows = await client.rpc('member_giving_statement', params: {
      'p_member_id': memberId,
      'p_year': year,
    }) as List<dynamic>;

    return rows
        .map((r) => GivingLine.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  static String _dateOnly(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError(
        "Cette version de l'application a été compilée sans serveur. "
        'Reconstruisez-la avec SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY.',
      );
    }
    return client;
  }
}
