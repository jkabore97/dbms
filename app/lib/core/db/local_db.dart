import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../auth/models.dart';

/// The device's own database. This is the source of truth while Ignace is out
/// at the farm with no signal, and while Israel is counting an offering in a
/// building with thick walls.
///
/// Two tables matter:
///   - `outbox`   : actions waiting to be sent to the server. Append-only.
///   - `entries`  : a local, readable view of what has been recorded so the
///                  UI can show totals instantly without waiting for a server.
///
/// Nothing here is ever UPDATEd in a way that loses history. An "undo" writes
/// a new reversing row, exactly as the server-side ledger does.
class LocalDb {
  LocalDb._(this._db);

  final Database _db;
  static const _uuid = Uuid();

  /// [path] overrides where the file lives. Tests pass
  /// `inMemoryDatabasePath`; the app never passes anything.
  static Future<LocalDb> open({String? path}) async {
    // On web there is no filesystem: the wasm factory treats the path as an
    // opaque IndexedDB key, and asking it for a databases directory throws.
    // Everywhere else the file belongs in the platform's databases directory.
    path ??= kIsWeb ? 'kaj.db' : p.join(await getDatabasesPath(), 'kaj.db');

    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createSchema(db, version);
        await _createIdentitySchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 -> v2: who this device belongs to, and which businesses they can
        // open while offline. Nothing already recorded is touched.
        if (oldVersion < 2) await _createIdentitySchema(db);
      },
    );
    return LocalDb._(db);
  }

  /// Releases the file. The app never calls this — the database lives as long
  /// as the process — but tests need each case to start from nothing.
  Future<void> close() => _db.close();

  static Future<void> _createSchema(Database db, int version) async {
    // Actions the device has taken that the server hasn't confirmed yet.
    await db.execute('''
      CREATE TABLE outbox (
        client_uuid   TEXT PRIMARY KEY,
        org_id        TEXT NOT NULL,
        action        TEXT NOT NULL,
        payload       TEXT NOT NULL,
        created_at    TEXT NOT NULL,
        synced_at     TEXT,
        attempts      INTEGER NOT NULL DEFAULT 0,
        last_error    TEXT
      )
    ''');

    await db.execute('CREATE INDEX outbox_pending ON outbox (synced_at)');

    // A readable local mirror so the home screen can show today's total
    // without a round trip. Rebuilt from the outbox plus server pulls.
    await db.execute('''
      CREATE TABLE entries (
        client_uuid   TEXT PRIMARY KEY,
        server_id     TEXT,
        org_id        TEXT NOT NULL,
        kind          TEXT NOT NULL,
        label         TEXT NOT NULL,
        amount        REAL NOT NULL,
        direction     TEXT NOT NULL,
        method        TEXT,
        member_name   TEXT,
        memo          TEXT,
        occurred_at   TEXT NOT NULL,
        reversed      INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('CREATE INDEX entries_by_date ON entries (org_id, occurred_at)');
  }

  /// Who is signed in, and what they can open with no signal.
  ///
  /// This is the offline half of authentication. The access token expires
  /// within the hour and cannot be refreshed at the farm, so without a local
  /// record of the user and their orgs the app would lock its own user out of
  /// data that is sitting on their own phone.
  static Future<void> _createIdentitySchema(Database db) async {
    // Exactly one row, ever. Two identities on one device would mean one
    // person's outbox draining under another person's token.
    await db.execute('''
      CREATE TABLE identity (
        id                INTEGER PRIMARY KEY CHECK (id = 1),
        user_id           TEXT NOT NULL,
        display_name      TEXT,
        phone             TEXT,
        email             TEXT,
        pin_salt          TEXT,
        pin_hash          TEXT,
        orgs_refreshed_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cached_orgs (
        org_id     TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        slug       TEXT,
        profile    TEXT NOT NULL,
        currency   TEXT,
        roles      TEXT,
        visibility TEXT
      )
    ''');
  }

  // ----------------------------------------------------------------
  // Identity
  // ----------------------------------------------------------------

  Future<LocalIdentity?> loadIdentity() async {
    final rows = await _db.query('identity', limit: 1);
    if (rows.isEmpty) return null;
    return LocalIdentity.fromRow(rows.first);
  }

  Future<void> saveIdentity(LocalIdentity identity) async {
    await _db.insert(
      'identity',
      identity.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Signing out forgets the person and their orgs. It deliberately does not
  /// touch `entries` or `outbox`: work already recorded belongs to the org it
  /// was recorded against, and deleting it here would destroy the one copy
  /// that exists when the phone has never had signal.
  Future<void> clearIdentity() async {
    await _db.transaction((txn) async {
      await txn.delete('identity');
      await txn.delete('cached_orgs');
    });
  }

  /// Replaces the cached org list wholesale — a membership that was revoked
  /// server-side has to disappear from the picker, not linger.
  Future<void> cacheOrgs(List<OrgSummary> orgs) async {
    await _db.transaction((txn) async {
      await txn.delete('cached_orgs');
      for (final org in orgs) {
        await txn.insert('cached_orgs', org.toCache());
      }
    });
  }

  Future<List<OrgSummary>> cachedOrgs() async {
    final rows = await _db.query('cached_orgs', orderBy: 'name ASC');
    return rows.map(OrgSummary.fromCache).toList();
  }

  /// Records a contribution locally and queues it for sync.
  ///
  /// Returns immediately. There is no loading spinner and no network call —
  /// the entry is saved the moment the button is tapped, connection or not.
  Future<String> recordContribution({
    required String orgId,
    required double amount,
    required String kind, // tithe | offering | special | donation
    required String method, // cash | bank | mobile_money
    String? memberId,
    String? memberName,
    String? memo,
    DateTime? occurredAt,
  }) async {
    final clientUuid = _uuid.v4();
    final when = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();

    final payload = {
      'p_org_id': orgId,
      'p_amount': amount,
      'p_kind': kind,
      'p_method': method,
      'p_member_id': memberId,
      'p_memo': memo,
      'p_client_uuid': clientUuid,
      'p_occurred_at': when,
    };

    await _db.transaction((txn) async {
      await txn.insert('outbox', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'action': 'record_contribution',
        'payload': jsonEncode(payload),
        'created_at': when,
      });

      await txn.insert('entries', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'kind': kind,
        'label': _labelFor(kind),
        'amount': amount,
        'direction': 'in',
        'method': method,
        'member_name': memberName,
        'memo': memo,
        'occurred_at': when,
      });
    });

    return clientUuid;
  }

  Future<String> recordExpense({
    required String orgId,
    required double amount,
    required String expenseCode,
    required String expenseName,
    required String method,
    String? memo,
    DateTime? occurredAt,
  }) async {
    final clientUuid = _uuid.v4();
    final when = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();

    final payload = {
      'p_org_id': orgId,
      'p_amount': amount,
      'p_expense_code': expenseCode,
      'p_method': method,
      'p_memo': memo,
      'p_client_uuid': clientUuid,
      'p_occurred_at': when,
    };

    await _db.transaction((txn) async {
      await txn.insert('outbox', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'action': 'record_expense',
        'payload': jsonEncode(payload),
        'created_at': when,
      });

      await txn.insert('entries', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'kind': 'expense',
        'label': expenseName,
        'amount': amount,
        'direction': 'out',
        'method': method,
        'memo': memo,
        'occurred_at': when,
      });
    });

    return clientUuid;
  }

  /// Undo. Marks the local row reversed and queues a reversing entry.
  /// The original is never deleted — it stays visible, marked as corrected.
  Future<void> reverse(String clientUuid, {required String reason}) async {
    final rows = await _db.query(
      'entries',
      where: 'client_uuid = ?',
      whereArgs: [clientUuid],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final original = rows.first;
    final reversalUuid = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await _db.transaction((txn) async {
      await txn.update(
        'entries',
        {'reversed': 1},
        where: 'client_uuid = ?',
        whereArgs: [clientUuid],
      );

      await txn.insert('outbox', {
        'client_uuid': reversalUuid,
        'org_id': original['org_id'],
        'action': 'reverse_entry',
        'payload': jsonEncode({
          'p_original_client_uuid': clientUuid,
          'p_reason': reason,
        }),
        'created_at': now,
      });
    });
  }

  /// Everything recorded on a given day, newest first.
  Future<List<Map<String, Object?>>> entriesForDay(
    String orgId,
    DateTime day,
  ) async {
    final start = DateTime.utc(day.year, day.month, day.day).toIso8601String();
    final end = DateTime.utc(day.year, day.month, day.day)
        .add(const Duration(days: 1))
        .toIso8601String();

    return _db.query(
      'entries',
      where: 'org_id = ? AND occurred_at >= ? AND occurred_at < ?',
      whereArgs: [orgId, start, end],
      orderBy: 'occurred_at DESC',
    );
  }

  /// Money in and money out for a day. Reversed rows are excluded from totals
  /// but stay in the list, so a correction is visible rather than hidden.
  Future<({double moneyIn, double moneyOut})> dayTotals(
    String orgId,
    DateTime day,
  ) async {
    final rows = await entriesForDay(orgId, day);
    var moneyIn = 0.0;
    var moneyOut = 0.0;

    for (final row in rows) {
      if ((row['reversed'] as int? ?? 0) == 1) continue;
      final amount = (row['amount'] as num).toDouble();
      if (row['direction'] == 'in') {
        moneyIn += amount;
      } else {
        moneyOut += amount;
      }
    }

    return (moneyIn: moneyIn, moneyOut: moneyOut);
  }

  /// How many actions are still waiting for a connection. Shown in the UI so
  /// the user always knows whether their work has left the device.
  Future<int> pendingCount() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM outbox WHERE synced_at IS NULL',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<List<Map<String, Object?>>> pendingActions({int limit = 50}) {
    return _db.query(
      'outbox',
      where: 'synced_at IS NULL',
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  Future<void> markSynced(String clientUuid, {String? serverId}) async {
    await _db.transaction((txn) async {
      await txn.update(
        'outbox',
        {'synced_at': DateTime.now().toUtc().toIso8601String()},
        where: 'client_uuid = ?',
        whereArgs: [clientUuid],
      );
      if (serverId != null) {
        await txn.update(
          'entries',
          {'server_id': serverId},
          where: 'client_uuid = ?',
          whereArgs: [clientUuid],
        );
      }
    });
  }

  Future<void> markFailed(String clientUuid, String error) async {
    await _db.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE client_uuid = ?',
      [error, clientUuid],
    );
  }

  static String _labelFor(String kind) {
    switch (kind) {
      case 'tithe':
        return 'Dîme';
      case 'offering':
        return 'Offrande';
      case 'special':
        return 'Collecte spéciale';
      case 'donation':
        return 'Don';
      default:
        return kind;
    }
  }
}
