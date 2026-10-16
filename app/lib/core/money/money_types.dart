import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../association/members.dart' show foldText;
import '../auth/models.dart';
import '../db/local_db.dart';
import '../errors.dart';
import '../l10n/tr.dart';
import '../reports/models.dart' show accountLabel;

/// The recette and dépense types a business adds itself (149).
///
/// A type IS an income or expense account of the business's chart: what is
/// recorded under it lands on that account, so the income statement, the
/// ledgers, the association's analyses (148) and every report count it with
/// no mapping. The chart is the one place it is stored.
///
///   * its name is the account's name — what record_entry() is sent, so an
///     entry posts to it by name (ensure_account, 007), offline included;
///   * [label]: a type renamed after entries were posted to it keeps the
///     account's name (the entries carry it) and shows this instead;
///   * [description]: the short line under the card;
///   * [active] false: hidden — off the cards, the account and its entries
///     untouched (007's is_active, the chart screen's « Retirer »);
///   * [sortOrder]: the cards' order.
///
/// The phone keeps the last list read (device_prefs, « mine: », cleared at
/// sign-out), so step 1 shows the types with no signal. A type added with
/// no signal is shown at once and sent by the outbox (save_money_type with
/// p_adopt): the same rule as « Autre », whose account opens when the entry
/// reaches the server. Renaming, hiding and ordering need the network.
class MoneyType {
  const MoneyType({
    required this.id,
    required this.name,
    required this.direction,
    this.code = '',
    this.label,
    this.description,
    this.active = true,
    this.sortOrder,
    this.entryCount = 0,
    this.pending = false,
  });

  /// The account's id; « local:… » for a type added on this phone and not
  /// on the server yet.
  final String id;

  /// The account's name, as the books hold it: what an entry is filed under.
  final String name;

  /// 'in' | 'out'.
  final String direction;
  final String code;
  final String? label;
  final String? description;
  final bool active;
  final int? sortOrder;
  final int entryCount;

  /// Added here with no signal (or before the server had 149): on the
  /// phone only for now.
  final bool pending;

  bool get isLocal => id.startsWith('local:');

  /// What the card says: the label, else the books' name in the reader's
  /// language (the seeded chart is in English).
  String get display => label ?? accountLabel(name);

  MoneyType copyWith({
    String? label,
    bool clearLabel = false,
    String? name,
    String? description,
    bool? active,
    int? sortOrder,
  }) => MoneyType(
    id: id,
    name: name ?? this.name,
    direction: direction,
    code: code,
    label: clearLabel ? null : (label ?? this.label),
    description: description ?? this.description,
    active: active ?? this.active,
    sortOrder: sortOrder ?? this.sortOrder,
    entryCount: entryCount,
    pending: pending,
  );

  factory MoneyType.fromRow(Map<String, dynamic> row) => MoneyType(
    id: '${row['account_id'] ?? row['id']}',
    name: '${row['name']}',
    direction: row['type'] == 'income' || row['direction'] == 'in'
        ? 'in'
        : 'out',
    code: '${row['code'] ?? ''}',
    label: _text(row['label']),
    description: _text(row['description']),
    active: row['is_active'] != false && row['active'] != false,
    sortOrder: (row['sort_order'] as num?)?.toInt(),
    entryCount:
        (row['entry_count'] as num?)?.toInt() ??
        int.tryParse('${row['entry_count']}') ??
        0,
    pending: row['pending'] == true,
  );

  Map<String, Object?> toRow() => {
    'account_id': id,
    'name': name,
    'direction': direction,
    'code': code,
    'label': label,
    'description': description,
    'is_active': active,
    'sort_order': sortOrder,
    'entry_count': entryCount,
    'pending': pending,
  };
}

/// The name is already a type, a built-in card or an account of the same
/// kind (149's MA149, or the phone's own check before asking).
class DuplicateTypeException implements Exception {
  const DuplicateTypeException(this.name);
  final String name;
  @override
  String toString() => translate(
    trCurrent,
    'Un type porte déjà ce nom : {name}.',
    {'name': name},
  );
}

/// Renaming, hiding and ordering need the network — said, not failed mute.
class TypesNeedNetwork implements Exception {
  const TypesNeedNetwork();
  @override
  String toString() => translate(
    trCurrent,
    'Il faut du réseau pour modifier la liste. Réessayez quand le signal revient.',
  );
}

/// The server has not had 149 yet: only adding works (on the phone).
class TypesNotOnServer implements Exception {
  const TypesNotOnServer();
  @override
  String toString() =>
      translate(trCurrent, 'Arrive avec la prochaine mise à jour du serveur.');
}

/// Who may add, rename, order and hide types: the people who record — a
/// member who is not only an observer or an approver, in a business that
/// is not suspended (149's money_type_writer, the same as 148's writers).
bool canWriteTypes(OrgSummary org) =>
    !org.suspended &&
    org.roles.any(
      (r) => r != 'observer' && r != 'approver' && r != 'platform_admin',
    );

/// The accounts behind Recette's four built-in cards, and the seeded church
/// headings (never offered again, the owner's decision, 115): none is shown
/// as an added type.
const builtInIncomeAccounts = {
  'Cotisations', 'Donations', 'Ventes', 'Sales', //
  'Tithes', 'Offerings', 'Special Collections',
};

/// The words of the built-in cards, in both languages: a type cannot take
/// them (« Don » is already a card).
const _incomeCardWords = [
  'Cotisation',
  'Cotisations',
  'Don',
  'Dons',
  'Vente',
  'Ventes',
  'Autre',
  'Contribution',
  'Contributions',
  'Gift',
  'Gifts',
  'Sale',
  'Sales',
  'Other',
];
const _expenseCardWords = ['Autre', 'Other'];

/// What the server does for the list, apart so a test can stand in for it.
/// [ReportsRepository] is the app's.
abstract class MoneyTypesApi {
  bool get isConfigured;

  /// Every income and expense account of the business (149's money_types).
  /// Throws [TypesNotOnServer] before 149; throws when there is no signal.
  Future<List<MoneyType>> moneyTypes(String orgId);

  /// Adds a type (or with [adopt], takes the account of that name); its id.
  /// Throws [DuplicateTypeException] (MA149).
  Future<String> addMoneyType(
    String orgId, {
    required String direction,
    required String name,
    String? description,
    bool adopt = false,
  });

  /// Renames ([name]), describes ([description], '' clears it), shows or
  /// hides ([active]) one type.
  Future<void> updateMoneyType(
    String orgId, {
    required String direction,
    required String id,
    String? name,
    String? description,
    bool? active,
  });

  Future<void> reorderMoneyTypes(
    String orgId, {
    required String direction,
    required List<String> ids,
  });
}

/// The list as last read.
class MoneyTypesList {
  const MoneyTypesList({
    required this.types,
    this.serverReady = true,
    this.fromPhone = false,
  });

  final List<MoneyType> types;

  /// The server has 149 (renaming, hiding, ordering).
  final bool serverReady;

  /// Read from the phone's copy (or the phone's own entries): no signal.
  final bool fromPhone;

  /// The types of one direction, in their order.
  List<MoneyType> of(String direction) {
    final list = [
      for (final t in types)
        if (t.direction == direction) t,
    ];
    list.sort((a, b) {
      final x = a.sortOrder, y = b.sortOrder;
      if (x != null && y != null && x != y) return x.compareTo(y);
      if (x != null && y == null) return -1;
      if (x == null && y != null) return 1;
      if (a.isLocal != b.isLocal) return a.isLocal ? 1 : -1;
      return a.code.compareTo(b.code);
    });
    return list;
  }

  /// The added types, as step 1 shows them as cards: shown ones, in order.
  /// For income, the built-in cards' accounts and the old church headings
  /// are not repeated.
  List<MoneyType> cards(String direction) => [
    for (final t in manageable(direction))
      if (t.active) t,
  ];

  /// What « Gérer » lists: every type of the direction (hidden too), the
  /// built-in income accounts aside.
  List<MoneyType> manageable(String direction) => [
    for (final t in of(direction))
      if (direction == 'out' || !builtInIncomeAccounts.contains(t.name)) t,
  ];

  /// Whether [name] is already taken for [direction]: an account's name or
  /// label (shown or hidden), what the reader sees it called, or a built-in
  /// card's word — accents, case and spaces aside. [except] is the type
  /// being renamed.
  bool taken(String direction, String name, {String? except}) {
    final key = typeKey(name);
    if (key.isEmpty) return false;
    final words = direction == 'in' ? _incomeCardWords : _expenseCardWords;
    if (words.any((w) => typeKey(w) == key)) {
      return true;
    }
    for (final t in types) {
      if (t.direction != direction || t.id == except) continue;
      if (typeKey(t.name) == key ||
          typeKey(t.label ?? '') == key ||
          typeKey(accountLabel(t.name)) == key) {
        return true;
      }
    }
    return false;
  }
}

/// The fold the duplicate test compares: 149's money_type_key.
String typeKey(String s) => foldText(
  s.trim().toLowerCase().replaceAll('œ', 'oe').replaceAll('æ', 'ae'),
).replaceAll(RegExp(r'\s+'), ' ');

/// The list with the phone's copy behind it, and the types added here.
class MoneyTypesBook {
  MoneyTypesBook({this.api, required this.db});

  final MoneyTypesApi? api;
  final LocalDb db;
  static const _uuid = Uuid();

  static String _key(String orgId) =>
      '${LocalDb.personalPrefPrefix}money_types:$orgId';

  bool get _online => api?.isConfigured ?? false;

  /// The server's list when there is signal (kept on the phone), else the
  /// phone's copy, else the names this phone's own entries were filed
  /// under — with the types added here and not sent yet.
  Future<MoneyTypesList> load(String orgId) async {
    final kept = await _read(orgId);
    if (_online) {
      try {
        final server = await api!.moneyTypes(orgId);
        final pending = [
          for (final p in kept.pending)
            if (!server.any(
              (t) =>
                  t.direction == p.direction &&
                  typeKey(t.name) == typeKey(p.name),
            ))
              p,
        ];
        await _write(orgId, server, pending, ready: true);
        return MoneyTypesList(types: [...server, ...pending]);
      } on TypesNotOnServer {
        return _fallback(orgId, kept, ready: false);
      } catch (e) {
        // No signal: the copy below.
      }
    }
    return _fallback(orgId, kept, ready: kept.ready);
  }

  /// The phone's copy alone — no network — for step 1's first frame.
  Future<MoneyTypesList> cached(String orgId) async =>
      _fallback(orgId, await _read(orgId), ready: (await _read(orgId)).ready);

  Future<MoneyTypesList> _fallback(
    String orgId,
    _Kept kept, {
    required bool ready,
  }) async {
    if (kept.types.isNotEmpty) {
      return MoneyTypesList(
        types: [...kept.types, ...kept.pending],
        serverReady: ready,
        fromPhone: true,
      );
    }
    // Never read from the server: the accounts this phone already filed
    // entries under (or the chart it cached), as « Autre » offered them.
    final names = <MoneyType>[];
    for (final d in const ['in', 'out']) {
      final list = await db.categoriesFor(orgId, d);
      for (var i = 0; i < list.length; i++) {
        names.add(
          MoneyType(
            id: 'name:$d:${list[i]}',
            name: list[i],
            direction: d,
            code: '$i'.padLeft(4, '0'),
          ),
        );
      }
    }
    final pending = [
      for (final p in kept.pending)
        if (!names.any(
          (t) =>
              t.direction == p.direction && typeKey(t.name) == typeKey(p.name),
        ))
          p,
    ];
    return MoneyTypesList(
      types: [...names, ...pending],
      serverReady: ready,
      fromPhone: true,
    );
  }

  /// Adds a type. Online, the server's answer (and its refusal of a name
  /// already used); with no signal, kept on the phone and sent by the
  /// outbox — the account opens then, or with the first entry, as with
  /// « Autre ». Throws [DuplicateTypeException].
  Future<MoneyType> add(
    String orgId,
    MoneyTypesList current, {
    required String direction,
    required String name,
    String? description,
  }) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final desc = (description ?? '').trim();
    if (current.taken(direction, clean)) throw DuplicateTypeException(clean);
    if (_online) {
      try {
        final id = await api!.addMoneyType(
          orgId,
          direction: direction,
          name: clean,
          description: desc.isEmpty ? null : desc,
        );
        final added = MoneyType(
          id: id,
          name: clean,
          direction: direction,
          description: desc.isEmpty ? null : desc,
          code: '9999',
        );
        final kept = await _read(orgId);
        await _write(
          orgId,
          [...kept.types.where((t) => t.id != id), added],
          kept.pending,
          ready: true,
        );
        return added;
      } on DuplicateTypeException {
        rethrow;
      } on TypesNotOnServer {
        return _keepLocal(orgId, direction, clean, desc, queue: false);
      } catch (e) {
        if (!isOffline(e)) rethrow;
      }
    }
    return _keepLocal(orgId, direction, clean, desc, queue: _online);
  }

  Future<MoneyType> _keepLocal(
    String orgId,
    String direction,
    String name,
    String desc, {
    required bool queue,
  }) async {
    final type = MoneyType(
      id: 'local:${_uuid.v4()}',
      name: name,
      direction: direction,
      description: desc.isEmpty ? null : desc,
      pending: true,
    );
    final kept = await _read(orgId);
    await _write(orgId, kept.types, [...kept.pending, type], ready: kept.ready);
    if (queue) {
      await db.queueMoneyType(
        orgId: orgId,
        params: {
          'p_org_id': orgId,
          'p_direction': direction,
          'p_name': name,
          'p_description': desc.isEmpty ? null : desc,
          'p_adopt': true,
        },
      );
    }
    return type;
  }

  /// Renames, describes, shows or hides one type. A type still on the
  /// phone only is changed there; any other needs the network.
  Future<void> update(
    String orgId,
    MoneyTypesList current,
    MoneyType type, {
    String? name,
    String? description,
    bool? active,
  }) async {
    final clean = name?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean != null &&
        clean != type.display &&
        current.taken(type.direction, clean, except: type.id)) {
      throw DuplicateTypeException(clean);
    }
    // On the phone only (not sent yet, or a server before 149): it is
    // changed once it is in the books.
    if (type.isLocal) throw const TypesNeedNetwork();
    if (type.id.startsWith('name:')) throw const TypesNotOnServer();
    if (!_online) throw const TypesNeedNetwork();
    try {
      await api!.updateMoneyType(
        orgId,
        direction: type.direction,
        id: type.id,
        name: clean,
        description: description,
        active: active,
      );
    } on DuplicateTypeException {
      rethrow;
    } catch (e) {
      if (isOffline(e)) throw const TypesNeedNetwork();
      rethrow;
    }
  }

  Future<void> reorder(
    String orgId,
    String direction,
    List<MoneyType> ordered,
  ) async {
    if (!_online) throw const TypesNeedNetwork();
    final ids = [
      for (final t in ordered)
        if (!t.isLocal && !t.id.startsWith('name:')) t.id,
    ];
    try {
      await api!.reorderMoneyTypes(orgId, direction: direction, ids: ids);
    } catch (e) {
      if (isOffline(e)) throw const TypesNeedNetwork();
      rethrow;
    }
  }

  Future<_Kept> _read(String orgId) async {
    try {
      final raw = await db.readPref(_key(orgId));
      if (raw == null) return const _Kept([], [], true);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      List<MoneyType> rows(Object? list) => [
        for (final r in (list as List? ?? const []))
          MoneyType.fromRow(Map<String, dynamic>.from(r as Map)),
      ];
      return _Kept(
        rows(json['types']),
        rows(json['pending']),
        json['ready'] != false,
      );
    } catch (_) {
      return const _Kept([], [], true);
    }
  }

  Future<void> _write(
    String orgId,
    List<MoneyType> types,
    List<MoneyType> pending, {
    required bool ready,
  }) async {
    try {
      await db.writePref(
        _key(orgId),
        jsonEncode({
          'at': DateTime.now().toIso8601String(),
          'ready': ready,
          'types': [for (final t in types) t.toRow()],
          'pending': [for (final t in pending) t.toRow()],
        }),
      );
    } catch (_) {
      // The copy is a convenience: the list on screen is the server's.
    }
  }
}

class _Kept {
  const _Kept(this.types, this.pending, this.ready);
  final List<MoneyType> types;
  final List<MoneyType> pending;
  final bool ready;
}

String? _text(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}
