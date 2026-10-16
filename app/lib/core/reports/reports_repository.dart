import 'package:supabase_flutter/supabase_flutter.dart';

import '../association/association_analytics.dart';
import '../association/books_start.dart';
import '../association/members.dart';
import '../errors.dart' show isSchemaOutOfDate;
import '../money/money_types.dart';
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
class ReportsRepository implements BooksStartApi, MembersApi, MoneyTypesApi {
  ReportsRepository(this._client);

  final SupabaseClient? _client;

  @override
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
      if (weekEnding != null) 'p_week_ending': _dateOnly(weekEnding),
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

  /// The members' list (148's association_members): this year's amounts
  /// for a caller with full visibility. Before 148, the table itself —
  /// names, phones and dates, no amounts — so the screens keep working.
  @override
  Future<MembersList> listMembers(String orgId, {int? year}) async {
    final client = _requireClient();
    try {
      final rows = await client.rpc('association_members', params: {
        'p_org_id': orgId,
        'p_year': ?year,
      }) as List<dynamic>;
      final members = [
        for (final r in rows)
          AssociationMember.fromRow(Map<String, dynamic>.from(r as Map)),
      ];
      return MembersList(
        members: members,
        withAmounts: members.any((m) => m.givenYear != null),
        readAt: DateTime.now(),
      );
    } on PostgrestException catch (e) {
      if (!isSchemaOutOfDate(e) && e.code != '42883') rethrow;
    }
    final rows = await client
        .from('church_members')
        .select('id, full_name, phone, joined_on, created_at')
        .eq('org_id', orgId)
        .eq('is_active', true)
        .order('full_name');
    return MembersList(
      members: [
        for (final r in rows as List)
          AssociationMember.fromRow(Map<String, dynamic>.from(r as Map)),
      ],
      serverReady: false,
      readAt: DateTime.now(),
    );
  }

  /// Adds or edits a member (148's save_association_member, INVOKER: 148's
  /// policies decide). Before 148, the table itself under 002's policy —
  /// without the note, which has no column yet.
  @override
  Future<String> saveMember(
    String orgId, {
    String? id,
    required String name,
    String? phone,
    String? note,
    DateTime? joinedOn,
    bool allowSamePhone = false,
  }) async {
    final client = _requireClient();
    final cleanPhone = (phone ?? '').trim().isEmpty ? null : phone!.trim();
    try {
      final v = await client.rpc('save_association_member', params: {
        'p_org_id': orgId,
        'p_member_id': id,
        'p_full_name': name.trim(),
        'p_phone': cleanPhone,
        'p_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'p_joined_on': joinedOn == null ? null : _dateOnly(joinedOn),
        'p_allow_same_phone': allowSamePhone,
      });
      return '$v';
    } on PostgrestException catch (e) {
      if (e.code == 'MA148') throw SamePhoneException(e.message);
      if (!isSchemaOutOfDate(e) && e.code != '42883') rethrow;
    }
    final row = {
      'full_name': name.trim(),
      'phone': cleanPhone,
      'joined_on': ?(joinedOn == null ? null : _dateOnly(joinedOn)),
    };
    if (id == null) {
      final created = await client
          .from('church_members')
          .insert({
            ...row,
            'org_id': orgId,
            if (joinedOn == null) 'joined_on': _dateOnly(DateTime.now()),
          })
          .select('id')
          .single();
      return '${created['id']}';
    }
    await client.from('church_members').update(row).eq('id', id).eq('org_id', orgId);
    return id;
  }

  /// Takes a member off the list (148's remove_association_member); before
  /// 148 the same soft update under 002's policy. Never a delete.
  @override
  Future<void> removeMember(String orgId, String memberId) async {
    final client = _requireClient();
    try {
      await client.rpc('remove_association_member', params: {'p_member_id': memberId});
      return;
    } on PostgrestException catch (e) {
      if (!isSchemaOutOfDate(e) && e.code != '42883') rethrow;
    }
    await client
        .from('church_members')
        .update({'is_active': false})
        .eq('id', memberId)
        .eq('org_id', orgId);
  }

  /// Every gift of one member (148). Before 148: the giving statement of
  /// this year and the two before it.
  @override
  Future<List<MemberGift>> memberHistory(String memberId) async {
    final client = _requireClient();
    try {
      final rows = await client.rpc('association_member_history',
          params: {'p_member_id': memberId}) as List<dynamic>;
      return [
        for (final r in rows) MemberGift.fromRow(Map<String, dynamic>.from(r as Map)),
      ];
    } on PostgrestException catch (e) {
      if (!isSchemaOutOfDate(e) && e.code != '42883') rethrow;
    }
    final year = DateTime.now().year;
    final out = <MemberGift>[];
    for (var y = year; y >= year - 2; y--) {
      for (final l in await givingStatement(memberId, year: y)) {
        out.add(MemberGift(
          entryId: '$y-${out.length}',
          date: l.date,
          accountName: l.kind,
          kind: switch (l.kind.trim().toLowerCase()) {
            'cotisations' => 'cotisation',
            'donations' => 'don',
            _ => 'autre',
          },
          amount: l.amount,
        ));
      }
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  /// « Analyses » of an association (148). Null on a database before 148.
  Future<AssociationAnalytics?> associationAnalytics(
    String orgId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final client = _requireClient();
    try {
      final v = await client.rpc('association_analytics', params: {
        'p_org_id': orgId,
        'p_from': from == null ? null : _dateOnly(from),
        'p_to': to == null ? null : _dateOnly(to),
      });
      if (v is! Map) return null;
      return AssociationAnalytics.fromJson(Map<String, dynamic>.from(v));
    } on PostgrestException catch (e) {
      if (isSchemaOutOfDate(e) || e.code == '42883') return null;
      rethrow;
    }
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

  /// « La caisse et la cotisation » (134). Null with no server, for no
  /// member, or on a database before 134 (PGRST202).
  @override
  Future<BooksStart?> booksStart(String orgId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final v = await client.rpc('books_start', params: {'p_org_id': orgId});
      if (v is! Map) return null;
      final start = BooksStart.fromJson(Map<String, dynamic>.from(v));
      BooksStart.lastKnown[orgId] = start;
      return start;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  @override
  Future<void> setOpeningBalance(String orgId, double amount, {String? clientUuid}) async {
    await _requireClient().rpc('set_opening_balance', params: {
      'p_org_id': orgId,
      'p_amount': amount,
      'p_method': 'cash',
      'p_client_uuid': ?clientUuid,
    });
  }

  @override
  Future<void> setContributionDefault(
      String orgId, double? amount, ContributionPeriod period) async {
    await _requireClient().rpc('set_contribution_default', params: {
      'p_org_id': orgId,
      'p_amount': amount,
      'p_period': period.name,
    });
  }

  @override
  Future<void> dismissBooksStart(String orgId) async {
    await _requireClient().rpc('dismiss_books_start', params: {'p_org_id': orgId});
  }

  // ----------------------------------------------------------------
  // Recette and dépense types (149)
  // ----------------------------------------------------------------

  /// The business's income and expense accounts (149's money_types,
  /// SECURITY INVOKER: the chart as 004's RLS lets a member read it).
  @override
  Future<List<MoneyType>> moneyTypes(String orgId) async {
    final client = _requireClient();
    try {
      final rows = await client.rpc('money_types', params: {'p_org_id': orgId}) as List<dynamic>;
      return [
        for (final r in rows) MoneyType.fromRow(Map<String, dynamic>.from(r as Map)),
      ];
    } on PostgrestException catch (e) {
      if (isSchemaOutOfDate(e) || e.code == '42883') throw const TypesNotOnServer();
      rethrow;
    }
  }

  @override
  Future<String> addMoneyType(String orgId,
      {required String direction,
      required String name,
      String? description,
      bool adopt = false}) async {
    final client = _requireClient();
    try {
      final v = await client.rpc('save_money_type', params: {
        'p_org_id': orgId,
        'p_direction': direction,
        'p_name': name,
        'p_description': description,
        'p_adopt': adopt,
      });
      return '$v';
    } on PostgrestException catch (e) {
      if (e.code == 'MA149') throw DuplicateTypeException(name);
      if (isSchemaOutOfDate(e) || e.code == '42883') throw const TypesNotOnServer();
      rethrow;
    }
  }

  @override
  Future<void> updateMoneyType(String orgId,
      {required String direction,
      required String id,
      String? name,
      String? description,
      bool? active}) async {
    final client = _requireClient();
    try {
      await client.rpc('save_money_type', params: {
        'p_org_id': orgId,
        'p_direction': direction,
        'p_account_id': id,
        'p_name': name,
        'p_description': description,
        'p_active': active,
      });
    } on PostgrestException catch (e) {
      if (e.code == 'MA149') throw DuplicateTypeException(name ?? '');
      if (isSchemaOutOfDate(e) || e.code == '42883') throw const TypesNotOnServer();
      rethrow;
    }
  }

  @override
  Future<void> reorderMoneyTypes(String orgId,
      {required String direction, required List<String> ids}) async {
    final client = _requireClient();
    try {
      await client.rpc('reorder_money_types', params: {
        'p_org_id': orgId,
        'p_direction': direction,
        'p_account_ids': ids,
      });
    } on PostgrestException catch (e) {
      if (isSchemaOutOfDate(e) || e.code == '42883') throw const TypesNotOnServer();
      rethrow;
    }
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
