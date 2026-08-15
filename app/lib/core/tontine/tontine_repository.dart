import 'package:supabase_flutter/supabase_flutter.dart';

class TontineSummary {
  const TontineSummary({
    required this.id,
    required this.name,
    required this.amount,
    required this.period,
    required this.currentRound,
  });

  final String id;
  final String name;
  final double amount;
  final String period;
  final int currentRound;

  factory TontineSummary.fromRow(Map<String, dynamic> r) => TontineSummary(
        id: r['id'] as String,
        name: r['name'] as String,
        amount: (r['amount'] as num).toDouble(),
        period: r['period'] as String,
        currentRound: (r['current_round'] as num).toInt(),
      );
}

/// One member's line in the current round: paid or not, and whether the pot
/// is theirs this time.
class TontineMemberStatus {
  const TontineMemberStatus({
    required this.memberId,
    required this.name,
    required this.position,
    required this.hasPaid,
    required this.isTaker,
    this.phone,
  });

  final String memberId;
  final String name;
  final String? phone;
  final int position;
  final bool hasPaid;
  final bool isTaker;

  factory TontineMemberStatus.fromRow(Map<String, dynamic> r) =>
      TontineMemberStatus(
        memberId: r['member_id'] as String,
        name: r['member_name'] as String,
        phone: r['phone'] as String?,
        position: (r['turn_position'] as num).toInt(),
        hasPaid: r['has_paid'] as bool,
        isTaker: r['is_taker'] as bool,
      );
}

/// The tontine tracker. Plain table reads and writes under RLS — unlike the
/// ledger there is no money of the business's in these rows, so the policies
/// are the whole gate and no DEFINER function stands in front of them, except
/// `advance_tontine_round()` which enforces the everyone-has-paid contract.
class TontineRepository {
  TontineRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  SupabaseClient get _c {
    final c = _client;
    if (c == null) {
      throw StateError(
          "Cette version de l'application a été compilée sans serveur.");
    }
    return c;
  }

  Future<List<TontineSummary>> list(String orgId) async {
    final rows = await _c
        .from('tontines')
        .select('id, name, amount, period, current_round')
        .eq('org_id', orgId)
        .eq('is_active', true)
        .order('created_at');
    return (rows as List)
        .map((r) => TontineSummary.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<String> create({
    required String orgId,
    required String name,
    required double amount,
    required String period,
    required List<String> memberNames,
  }) async {
    final row = await _c
        .from('tontines')
        .insert({
          'org_id': orgId,
          'name': name,
          'amount': amount,
          'period': period,
          'created_by': _c.auth.currentUser!.id,
        })
        .select('id')
        .single();
    final id = row['id'] as String;
    // The order of the list is the order of the turns — position is
    // 1-based, and the person first in the list takes the first pot.
    await _c.from('tontine_members').insert([
      for (var i = 0; i < memberNames.length; i++)
        {
          'tontine_id': id,
          'org_id': orgId,
          'name': memberNames[i],
          'position': i + 1,
        }
    ]);
    return id;
  }

  Future<List<TontineMemberStatus>> roundStatus(String tontineId) async {
    final rows = await _c
        .rpc('tontine_round_status', params: {'p_tontine_id': tontineId});
    return (rows as List)
        .map((r) =>
            TontineMemberStatus.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> recordContribution({
    required String orgId,
    required String tontineId,
    required String memberId,
    required int round,
    required double amount,
  }) async {
    await _c.from('tontine_contributions').insert({
      'tontine_id': tontineId,
      'org_id': orgId,
      'member_id': memberId,
      'round': round,
      'amount': amount,
      'created_by': _c.auth.currentUser!.id,
    });
  }

  /// Refused server-side while anyone has not paid — see 025.
  Future<int> advanceRound(String tontineId) async {
    final next = await _c
        .rpc('advance_tontine_round', params: {'p_tontine_id': tontineId});
    return (next as num).toInt();
  }
}
