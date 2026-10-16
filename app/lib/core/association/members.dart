import 'dart:async';
import 'dart:convert';

import '../db/local_db.dart';
import '../errors.dart';
import '../reports/models.dart' show ChurchMember;

/// An association's « Membres » (148): the people on its list — records,
/// not app users (they take no seat and need no Pro) — and what they gave.
///
/// The list is read through `association_members` (148, SECURITY INVOKER:
/// the amounts are line detail, so only a caller with full visibility is
/// given them). On a database before 148 the app reads the table itself
/// (002's policy lets every member of the business read it) and shows the
/// names, phones and dates without amounts — and keeps working.

/// Where a member stands on the usual cotisation (134), as 148 counts it.
enum DuesStatus { upToDate, due, late }

class MemberDues {
  const MemberDues({required this.status, this.lateSince, this.paidThrough});

  final DuesStatus status;

  /// The first period not covered, when [status] is late.
  final DateTime? lateSince;

  /// The last day the cotisations paid so far cover.
  final DateTime? paidThrough;

  static MemberDues? fromRow(Map<String, dynamic> row) {
    final status = switch (row['dues_status']) {
      'up_to_date' => DuesStatus.upToDate,
      'due' => DuesStatus.due,
      'late' => DuesStatus.late,
      _ => null,
    };
    if (status == null) return null;
    return MemberDues(
      status: status,
      lateSince: _date(row['late_since']),
      paidThrough: _date(row['paid_through']),
    );
  }
}

/// One member of the list.
class AssociationMember {
  const AssociationMember({
    required this.id,
    required this.fullName,
    this.phone,
    this.note,
    this.joinedOn,
    this.createdAt,
    this.givenYear,
    this.cotisationsYear,
    this.donsYear,
    this.lastGivenOn,
    this.dues,
  });

  final String id;
  final String fullName;
  final String? phone;

  /// « Trésorier », « Section jeunes » (148). Null before 148.
  final String? note;
  final DateTime? joinedOn;
  final DateTime? createdAt;

  /// This year's total given — every income attributed to the member
  /// (record_entry's p_member_id). Null when the caller may not see
  /// amounts, or before 148.
  final double? givenYear;
  final double? cotisationsYear;
  final double? donsYear;
  final DateTime? lastGivenOn;

  /// Null without a usual cotisation, without full visibility, before 148.
  final MemberDues? dues;

  /// « Membre depuis » — the date typed, else the day it was entered.
  DateTime? get since => joinedOn ?? createdAt;

  ChurchMember get asChurchMember =>
      ChurchMember(id: id, fullName: fullName, phone: phone);

  factory AssociationMember.fromRow(Map<String, dynamic> row) =>
      AssociationMember(
        id: '${row['id']}',
        fullName: (row['full_name'] as String?)?.trim().isNotEmpty == true
            ? (row['full_name'] as String).trim()
            : '—',
        phone: _text(row['phone']),
        note: _text(row['note']),
        joinedOn: _date(row['joined_on']),
        createdAt: _date(row['created_at']),
        givenYear: _num(row['given_year']),
        cotisationsYear: _num(row['cotisations_year']),
        donsYear: _num(row['dons_year']),
        lastGivenOn: _date(row['last_given_on']),
        dues: MemberDues.fromRow(row),
      );

  /// The row as the server shapes it, for the phone's copy.
  Map<String, Object?> toRow() => {
        'id': id,
        'full_name': fullName,
        'phone': phone,
        'note': note,
        'joined_on': _iso(joinedOn),
        'created_at': createdAt?.toIso8601String(),
        'given_year': givenYear,
        'cotisations_year': cotisationsYear,
        'dons_year': donsYear,
        'last_given_on': _iso(lastGivenOn),
        'dues_status': switch (dues?.status) {
          DuesStatus.upToDate => 'up_to_date',
          DuesStatus.due => 'due',
          DuesStatus.late => 'late',
          null => null,
        },
        'late_since': _iso(dues?.lateSince),
        'paid_through': _iso(dues?.paidThrough),
      };

  /// Whether [query] finds this member: a name's words (accents and case
  /// aside) or a phone's digits.
  bool matches(String query) {
    final q = query.trim();
    if (q.isEmpty) return true;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 2 &&
        (phone ?? '').replaceAll(RegExp(r'\D'), '').contains(digits)) {
      return true;
    }
    final hay = foldText('$fullName ${note ?? ''}');
    return foldText(q).split(RegExp(r'\s+')).every(hay.contains);
  }
}

/// The list as last read, and what it can say.
class MembersList {
  const MembersList({
    required this.members,
    this.withAmounts = false,
    this.serverReady = true,
    this.readAt,
    this.fromPhone = false,
  });

  final List<AssociationMember> members;

  /// The amounts and the cotisation status were given (148, full
  /// visibility).
  final bool withAmounts;

  /// The server has 148 (notes, the list's amounts, the analyses).
  final bool serverReady;

  /// When the server last gave this list.
  final DateTime? readAt;

  /// Read from the phone's copy: no signal.
  final bool fromPhone;
}

/// One gift in a member's history (148's association_member_history).
class MemberGift {
  const MemberGift({
    required this.entryId,
    required this.date,
    required this.accountName,
    required this.kind,
    required this.amount,
    this.reversed = false,
  });

  final String entryId;
  final DateTime date;
  final String accountName;

  /// 'cotisation' | 'don' | 'autre'.
  final String kind;
  final double amount;

  /// Undone (« Annuler »): shown struck through, never counted.
  final bool reversed;

  factory MemberGift.fromRow(Map<String, dynamic> row) => MemberGift(
        entryId: '${row['entry_id']}',
        date: _date(row['occurred_on']) ?? DateTime.now(),
        accountName: '${row['account_name'] ?? ''}',
        kind: '${row['kind'] ?? 'autre'}',
        amount: _num(row['amount']) ?? 0,
        reversed: row['reversed'] == true,
      );
}

/// The same phone as another member (148's MA148): the app asks before
/// adding anyway.
class SamePhoneException implements Exception {
  const SamePhoneException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the members' screens need from the server, apart so a test can
/// stand in for it. [ReportsRepository] is the app's.
abstract class MembersApi {
  bool get isConfigured;

  /// The active members, with this year's amounts when the caller may see
  /// them. Throws when there is no signal (the [MembersBook] then reads the
  /// phone's copy).
  Future<MembersList> listMembers(String orgId, {int? year});

  /// Adds ([id] null) or edits a member; its id. Throws
  /// [SamePhoneException] when the phone is another member's and
  /// [allowSamePhone] is false.
  Future<String> saveMember(
    String orgId, {
    String? id,
    required String name,
    String? phone,
    String? note,
    DateTime? joinedOn,
    bool allowSamePhone = false,
  });

  /// Takes the member off the list; their entries stay theirs.
  Future<void> removeMember(String orgId, String memberId);

  /// Every gift of one member, newest first.
  Future<List<MemberGift>> memberHistory(String memberId);
}

/// The list with the phone's copy behind it: the server's answer when there
/// is signal (kept on the phone, for this person only — cleared at
/// sign-out with the rest of [LocalDb.personalPrefPrefix]), the last one
/// known when there is none.
///
/// Adding, editing and removing need the network, as a credit and an
/// invoice do: a member's id comes from the server, and a gift recorded
/// offline is attributed by that id.
class MembersBook {
  MembersBook(this.api, this.db);

  final MembersApi api;
  final LocalDb? db;

  static String _key(String orgId) =>
      '${LocalDb.personalPrefPrefix}members:$orgId';

  Future<MembersList> load(String orgId, {int? year}) async {
    try {
      final list = await api.listMembers(orgId, year: year);
      unawaited(_keep(orgId, list));
      return list;
    } catch (e) {
      final kept = await cached(orgId);
      if (kept != null && (isOffline(e) || !api.isConfigured)) return kept;
      rethrow;
    }
  }

  /// The phone's copy, or null.
  Future<MembersList?> cached(String orgId) async {
    final db = this.db;
    if (db == null) return null;
    try {
      final raw = await db.readPref(_key(orgId));
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return MembersList(
        members: [
          for (final r in (json['members'] as List? ?? const []))
            AssociationMember.fromRow(Map<String, dynamic>.from(r as Map)),
        ],
        withAmounts: json['amounts'] == true,
        serverReady: json['ready'] != false,
        readAt: _date(json['at']),
        fromPhone: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _keep(String orgId, MembersList list) async {
    final db = this.db;
    if (db == null) return;
    try {
      await db.writePref(
          _key(orgId),
          jsonEncode({
            'at': DateTime.now().toIso8601String(),
            'amounts': list.withAmounts,
            'ready': list.serverReady,
            'members': [for (final m in list.members) m.toRow()],
          }));
    } catch (_) {
      // The copy is a convenience: the list on screen is the server's.
    }
  }
}

/// Lower case, accents taken off: « Élodie » finds « elodie ».
String foldText(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString();
}

String? _text(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

double? _num(Object? v) =>
    v is num ? v.toDouble() : (v == null ? null : double.tryParse('$v'));

DateTime? _date(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse('$v');
}

String? _iso(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
