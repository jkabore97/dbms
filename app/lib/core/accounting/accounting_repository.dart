import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// The accounting reports and the chart of accounts, behind one door.
///
/// None of it is offline-first and none of it is cached — with one exception,
/// noted below. A report is a claim about money at a moment, and a stale one
/// shown without saying so is worse than no report at all, so these need
/// signal and the screens say when there is none.
///
/// The exception is [chartOfAccounts]. Its result is written to the device by
/// the caller, because it is not a claim about money — it is the list of names
/// the recording sheets offer, and a phone with no signal still has to be able
/// to record something under the name the books already use. A month-old
/// category list is a small inaccuracy; a category list that vanishes at the
/// farm gate is a person writing in a notebook again.
class AccountingRepository {
  AccountingRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  // ----------------------------------------------------------------
  // The chart
  // ----------------------------------------------------------------

  Future<List<LedgerAccount>> chartOfAccounts(String orgId) async {
    final client = _requireClient();
    final rows = await client.rpc(
      'chart_of_accounts',
      params: {'p_org_id': orgId},
    ) as List<dynamic>;

    return rows
        .map((r) => LedgerAccount.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Adds a category deliberately. `create_account()` is admin-only and mints
  /// the code itself from the type's band, so nothing here invents a number.
  Future<void> createAccount({
    required String orgId,
    required String name,
    required String type,
    String? description,
  }) async {
    final client = _requireClient();
    await client.rpc('create_account', params: {
      'p_org_id': orgId,
      'p_name': name.trim(),
      'p_type': type,
      'p_description': description?.trim(),
    });
  }

  /// Renaming and retiring go straight at the table rather than through an
  /// RPC: 004 already has update policies on `accounts` that admit only an org
  /// admin, and a function wrapping an UPDATE that RLS already governs is one
  /// more place for the rule to be written differently.
  Future<void> updateAccount(
    String accountId, {
    String? name,
    String? description,
    bool? isActive,
  }) async {
    final client = _requireClient();
    await client.from('accounts').update({
      if (name != null) 'name': name.trim(),
      if (description != null) 'description': description.trim(),
      if (isActive != null) 'is_active': isActive,
    }).eq('id', accountId);
  }

  // ----------------------------------------------------------------
  // The four reports
  // ----------------------------------------------------------------

  /// Debits and credits, uninterpreted. The screen's job is to show that the
  /// two totals agree; when they do not, something wrote to the ledger without
  /// going through the recording functions and no other report would say so.
  Future<List<TrialBalanceRow>> trialBalance(
    String orgId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final client = _requireClient();
    final rows = await client.rpc('trial_balance', params: {
      'p_org_id': orgId,
      if (from != null) 'p_from': _date(from),
      if (to != null) 'p_to': _date(to),
    }) as List<dynamic>;

    return rows
        .map((r) => TrialBalanceRow.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Earned, spent, and the difference. Per-account rows arrive only for a
  /// reader with full visibility; a summary observer gets the three totals and
  /// the screen renders what it is given.
  Future<List<StatementLine>> incomeStatement(
    String orgId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final client = _requireClient();
    final rows = await client.rpc('income_statement', params: {
      'p_org_id': orgId,
      if (from != null) 'p_from': _date(from),
      if (to != null) 'p_to': _date(to),
    }) as List<dynamic>;

    return rows
        .map((r) => StatementLine.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<StatementLine>> balanceSheet(
    String orgId, {
    DateTime? asOf,
  }) async {
    final client = _requireClient();
    final rows = await client.rpc('balance_sheet', params: {
      'p_org_id': orgId,
      if (asOf != null) 'p_as_of': _date(asOf),
    }) as List<dynamic>;

    return rows
        .map((r) => StatementLine.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// One account's history with a running balance. Newest first, because the
  /// question is almost always about the recent end of it.
  Future<List<LedgerMovement>> accountLedger(
    String orgId,
    String accountId, {
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async {
    final client = _requireClient();
    final rows = await client.rpc('account_ledger', params: {
      'p_org_id': orgId,
      'p_account_id': accountId,
      if (from != null) 'p_from': _date(from),
      if (to != null) 'p_to': _date(to),
      'p_limit': limit,
    }) as List<dynamic>;

    return rows
        .map((r) => LedgerMovement.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Every entry in a range, both sides named.
  Future<List<JournalRow>> journal(
    String orgId, {
    DateTime? from,
    DateTime? to,
    int limit = 100,
    int offset = 0,
  }) async {
    final client = _requireClient();
    final rows = await client.rpc('journal_page', params: {
      'p_org_id': orgId,
      if (from != null) 'p_from': _date(from),
      if (to != null) 'p_to': _date(to),
      'p_limit': limit,
      'p_offset': offset,
    }) as List<dynamic>;

    return rows
        .map((r) => JournalRow.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  static String _date(DateTime when) =>
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
