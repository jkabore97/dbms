import 'dart:convert';
import 'dart:typed_data';

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
      version: 6,
      onCreate: (db, version) async {
        await _createSchema(db, version);
        await _createIdentitySchema(db);
        await _createClosureSchema(db);
        await _createNamingSchema(db);
        await _createFarmSchema(db);
        await _createCaptureSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 -> v2: who this device belongs to, and which businesses they can
        // open while offline. Nothing already recorded is touched.
        if (oldVersion < 2) await _createIdentitySchema(db);
        // v2 -> v3: the day-closing habit and the streak it earns.
        if (oldVersion < 3) await _createClosureSchema(db);
        // v3 -> v4: entries carry the name and the characteristics the person
        // typed, and the chart of accounts is cached so the categories are
        // still offerable with no signal.
        if (oldVersion < 4) await _upgradeToNaming(db);
        // v4 -> v5: sacks and birds, which are counted on a device that has
        // been out of range since Tuesday.
        if (oldVersion < 5) await _createFarmSchema(db);
        // v5 -> v6: photographs taken before there was any signal to send
        // them with. The bytes wait here rather than in memory, because the
        // app being closed is the normal end of a market day.
        if (oldVersion < 6) await _createCaptureSchema(db);
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
    //
    // `label` is what the person typed and is what every list shows.
    // `category` is the account it was filed under, which is usually the same
    // words the first time and stops being the same words the moment somebody
    // records "Réparation du toit — côté est" against the roof account.
    await db.execute('''
      CREATE TABLE entries (
        client_uuid   TEXT PRIMARY KEY,
        server_id     TEXT,
        org_id        TEXT NOT NULL,
        kind          TEXT NOT NULL,
        label         TEXT NOT NULL,
        category      TEXT,
        amount        REAL NOT NULL,
        direction     TEXT NOT NULL,
        method        TEXT,
        member_name   TEXT,
        memo          TEXT,
        details       TEXT,
        occurred_at   TEXT NOT NULL,
        reversed      INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('CREATE INDEX entries_by_date ON entries (org_id, occurred_at)');
  }

  /// The categories a person can be offered while offline.
  ///
  /// The chart of accounts lives on the server and is the only place that
  /// knows the real name of an account — which matters, because posting to
  /// "Loyer" when the books call it "Rent" would open a second account and
  /// split a year of history in two. So the chart is mirrored here, refreshed
  /// whenever there is signal, and the sheets read it rather than a list
  /// compiled into the app.
  ///
  /// Typing a name that is in neither place still works. That is the point,
  /// and it is why this is a cache and not a constraint.
  static Future<void> _createNamingSchema(Database db) async {
    await db.execute('''
      CREATE TABLE cached_accounts (
        account_id TEXT PRIMARY KEY,
        org_id     TEXT NOT NULL,
        code       TEXT NOT NULL,
        name       TEXT NOT NULL,
        type       TEXT NOT NULL,
        is_active  INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute(
      'CREATE INDEX cached_accounts_by_org ON cached_accounts (org_id, type)',
    );
  }

  /// v3 -> v4 on a device that already holds entries.
  ///
  /// The new columns are added rather than the table rebuilt, so nothing
  /// recorded offline is lost — which on a phone that has never had signal is
  /// the only copy that exists.
  static Future<void> _upgradeToNaming(Database db) async {
    await db.execute('ALTER TABLE entries ADD COLUMN category TEXT');
    await db.execute('ALTER TABLE entries ADD COLUMN details TEXT');
    // Everything recorded before this version was filed under a fixed
    // category and labelled with it, so the two were the same word.
    await db.execute('UPDATE entries SET category = label');
    await _createNamingSchema(db);
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

  /// The day-closing habit.
  ///
  /// Closing the day is a ritual, not a transaction: it records that a human
  /// looked at the day's figures and agreed with them. That belongs on the
  /// device rather than in the ledger, because it says nothing about money —
  /// it says something about the person keeping the books, and a streak that
  /// resets because a phone was offline would be a lie about them.
  static Future<void> _createClosureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE day_closures (
        org_id     TEXT NOT NULL,
        closed_on  TEXT NOT NULL,
        closed_at  TEXT NOT NULL,
        money_in   REAL NOT NULL,
        money_out  REAL NOT NULL,
        PRIMARY KEY (org_id, closed_on)
      )
    ''');
  }

  /// What Ignace counts, on a device that has been out of range since Tuesday.
  ///
  /// The farm's problem is not the church's problem. A church records money
  /// and the money is the record; a farm records sacks and birds and eggs, and
  /// those counts are what the farm is actually run on — the money follows
  /// weeks later. So the counts need the same offline guarantee the ledger
  /// has, and they need it more, because the farm is the place with no signal.
  static Future<void> _createFarmSchema(Database db) async {
    // The physical half of what happened, mirroring the outbox row that will
    // eventually carry it to the server. Money, when there is any, still goes
    // in `entries` under the same client_uuid — one delivery is one thing that
    // happened, and it should be one id whichever ledger you look at it from.
    await db.execute('''
      CREATE TABLE farm_events (
        client_uuid TEXT PRIMARY KEY,
        org_id      TEXT NOT NULL,
        kind        TEXT NOT NULL,
        subject     TEXT NOT NULL,
        quantity    REAL NOT NULL,
        unit        TEXT,
        note        TEXT,
        occurred_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX farm_events_by_date ON farm_events (org_id, occurred_at)',
    );

    // The names and counts the server last reported, so the recording sheets
    // can offer real items and real flocks with no signal — the same bargain
    // `cached_accounts` makes, and for the same reason. A stale count is a
    // small inaccuracy; an empty picker at the farm gate is a notebook.
    await db.execute('''
      CREATE TABLE cached_farm_items (
        item_id       TEXT PRIMARY KEY,
        org_id        TEXT NOT NULL,
        name          TEXT NOT NULL,
        unit          TEXT NOT NULL,
        on_hand       REAL NOT NULL DEFAULT 0,
        reorder_level REAL,
        below_reorder INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE cached_flocks (
        flock_id   TEXT PRIMARY KEY,
        org_id     TEXT NOT NULL,
        batch_code TEXT NOT NULL,
        alive      INTEGER NOT NULL DEFAULT 0,
        closed     INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // ----------------------------------------------------------------
  // Captures waiting for signal
  // ----------------------------------------------------------------

  /// Photographs the phone has taken and not yet managed to upload.
  ///
  /// Kept in its own table rather than as `outbox` rows for one reason: size.
  /// An outbox row is a few hundred bytes of JSON and the sync loop drains
  /// dozens at a time; a photograph is two megabytes and has to be sent one
  /// at a time over a connection that is the reason it is queued at all.
  ///
  /// The bytes are on the device and nowhere else until this row is deleted,
  /// which is why the row is deleted only after the server has confirmed the
  /// document — not after the upload.
  static Future<void> _createCaptureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE pending_captures (
        client_uuid  TEXT PRIMARY KEY,
        org_id       TEXT NOT NULL,
        bytes        BLOB NOT NULL,
        content_type TEXT NOT NULL,
        kind         TEXT,
        caption      TEXT,
        captured_at  TEXT NOT NULL,
        attempts     INTEGER NOT NULL DEFAULT 0,
        last_error   TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX pending_captures_by_org ON pending_captures (org_id, captured_at)',
    );
  }

  /// Takes custody of a photograph. Returns the client_uuid it was filed
  /// under, which is also what makes the upload idempotent server-side.
  Future<String> queueCapture({
    required String orgId,
    required Uint8List bytes,
    required String contentType,
    String? kind,
    String? caption,
    DateTime? capturedAt,
    String? clientUuid,
  }) async {
    final id = clientUuid ?? _uuid.v4();
    await _db.insert(
      'pending_captures',
      {
        'client_uuid': id,
        'org_id': orgId,
        'bytes': bytes,
        'content_type': contentType,
        'kind': kind,
        'caption': caption,
        'captured_at':
            (capturedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'attempts': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  Future<List<Map<String, Object?>>> pendingCaptures({int limit = 5}) {
    return _db.query(
      'pending_captures',
      orderBy: 'captured_at ASC',
      limit: limit,
    );
  }

  /// How many pictures this phone is still holding, and how many of those it
  /// has tried to send and been refused. Same distinction as `outboxHealth`:
  /// never-tried is a signal problem and normal, tried-and-failed is
  /// something a person has to be told about.
  Future<({int waiting, int stuck})> captureQueueHealth([String? orgId]) async {
    final rows = await _db.rawQuery(
      '''
      SELECT
        COUNT(*) AS waiting,
        SUM(CASE WHEN attempts > 0 THEN 1 ELSE 0 END) AS stuck
      FROM pending_captures
      ${orgId == null ? '' : 'WHERE org_id = ?'}
      ''',
      orgId == null ? const [] : [orgId],
    );
    final row = rows.first;
    return (
      waiting: (row['waiting'] as int?) ?? 0,
      stuck: (row['stuck'] as int?) ?? 0,
    );
  }

  /// Only ever called once the server has confirmed the document row exists.
  /// Deleting on a successful upload alone would drop the only copy of a
  /// photograph whose `record_document` call then failed.
  Future<void> captureSent(String clientUuid) async {
    await _db.delete(
      'pending_captures',
      where: 'client_uuid = ?',
      whereArgs: [clientUuid],
    );
  }

  Future<void> captureFailed(String clientUuid, String error) async {
    await _db.rawUpdate(
      'UPDATE pending_captures SET attempts = attempts + 1, last_error = ? '
      'WHERE client_uuid = ?',
      [error, clientUuid],
    );
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

  // ----------------------------------------------------------------
  // Recording
  // ----------------------------------------------------------------

  /// Records anything, by the name the person gave it.
  ///
  /// This is the general form and it is what both sheets now call. The two
  /// methods below it — recordContribution and recordExpense — stay because
  /// devices upgrading from an older build may still hold outbox rows written
  /// by them, and the server functions they name still exist; nothing new
  /// goes through them.
  ///
  /// Returns immediately. There is no loading spinner and no network call —
  /// the entry is saved the moment the button is tapped, connection or not.
  ///
  /// [label] is what the entry IS, in the words of whoever recorded it.
  /// [category] is the account to file it under; null means the label is also
  /// the category, which is the right answer for a one-off and becomes the
  /// wrong one by the third time, at which point the category picker offers it
  /// back and the two diverge on their own.
  /// [details] is anything else that was typed — a supplier, an invoice
  /// number, a beneficiary. It reaches the server as jsonb.
  Future<String> recordEntry({
    required String orgId,
    required double amount,
    required String direction, // 'in' | 'out'
    required String label,
    String? category,
    String method = 'cash',
    String? memberId,
    String? memberName,
    String? memo,
    Map<String, String> details = const {},
    DateTime? occurredAt,
  }) async {
    final clientUuid = _uuid.v4();
    final when = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();
    final trimmedLabel = label.trim();
    final trimmedCategory = category?.trim();
    final filed = (trimmedCategory == null || trimmedCategory.isEmpty)
        ? trimmedLabel
        : trimmedCategory;

    // Keys match record_entry() in 007_accounting.sql exactly: SyncService
    // posts this map verbatim as the RPC's arguments.
    final payload = {
      'p_org_id': orgId,
      'p_amount': amount,
      'p_direction': direction,
      'p_label': trimmedLabel,
      'p_category': filed,
      'p_method': method,
      'p_member_id': memberId,
      'p_memo': memo,
      'p_details': details,
      'p_client_uuid': clientUuid,
      'p_occurred_at': when,
    };

    await _db.transaction((txn) async {
      await txn.insert('outbox', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'action': 'record_entry',
        'payload': jsonEncode(payload),
        'created_at': when,
      });

      await txn.insert('entries', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'kind': direction == 'in' ? 'income' : 'expense',
        'label': trimmedLabel,
        'category': filed,
        'amount': amount,
        'direction': direction,
        'method': method,
        'member_name': memberName,
        'memo': memo,
        'details': details.isEmpty ? null : jsonEncode(details),
        'occurred_at': when,
      });
    });

    return clientUuid;
  }

  /// Money moved between two places it was already held: cash banked, a
  /// withdrawal for the week's purchases, a mobile money top-up.
  ///
  /// Recorded as its own direction because it is neither. Counting a bank
  /// deposit as an expense and an income — which is what happens when the only
  /// two buttons are in and out — inflates both sides of the day by the same
  /// amount and makes the books say the business earned money by moving its
  /// own money.
  Future<String> recordTransfer({
    required String orgId,
    required double amount,
    required String fromMethod,
    required String toMethod,
    String? label,
    String? memo,
    DateTime? occurredAt,
  }) async {
    final clientUuid = _uuid.v4();
    final when = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();
    final trimmed = label?.trim();
    final title = (trimmed == null || trimmed.isEmpty) ? 'Transfert' : trimmed;

    final payload = {
      'p_org_id': orgId,
      'p_amount': amount,
      'p_from_method': fromMethod,
      'p_to_method': toMethod,
      'p_label': title,
      'p_memo': memo,
      'p_client_uuid': clientUuid,
      'p_occurred_at': when,
    };

    await _db.transaction((txn) async {
      await txn.insert('outbox', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'action': 'record_transfer',
        'payload': jsonEncode(payload),
        'created_at': when,
      });

      await txn.insert('entries', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'kind': 'transfer',
        'label': title,
        'category': 'Transfert',
        'amount': amount,
        'direction': 'transfer',
        'method': '$fromMethod>$toMethod',
        'memo': memo,
        'occurred_at': when,
      });
    });

    return clientUuid;
  }

  /// Records a contribution locally and queues it for sync.
  ///
  /// Superseded by [recordEntry] and kept for the outbox rows an upgrading
  /// device may still be holding. Nothing in the app calls it any more.
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

  /// Superseded by [recordEntry], and kept for the same reason.
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
  ///
  /// A transfer counts as neither. It is listed, because a person looking for
  /// "where did the 20,000 go" needs to see it, and it is added to nothing,
  /// because moving money between two of your own accounts is not a day's
  /// takings and not a day's spending.
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
      switch (row['direction']) {
        case 'in':
          moneyIn += amount;
        case 'out':
          moneyOut += amount;
      }
    }

    return (moneyIn: moneyIn, moneyOut: moneyOut);
  }

  // ----------------------------------------------------------------
  // The farm
  // ----------------------------------------------------------------

  /// Feed, medicine or supplies arriving.
  ///
  /// The one recording call in the app that writes to both ledgers at once, so
  /// it writes three rows in one transaction: the outbox action, the money in
  /// `entries` (only when somebody said what it cost), and the count in
  /// `farm_events`. All three carry the same client_uuid, which is what
  /// `receive_stock()` in 009 uses to make a retried sync return the original
  /// delivery instead of doubling twenty sacks of feed.
  Future<String> receiveStock({
    required String orgId,
    required String itemName,
    required double quantity,
    double? unitCost,
    String unit = 'sac',
    String category = 'Aliment',
    String method = 'cash',
    String? memo,
    DateTime? occurredAt,
  }) async {
    final clientUuid = _uuid.v4();
    final when = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();
    final name = itemName.trim();
    final total = quantity * (unitCost ?? 0);

    final payload = {
      'p_org_id': orgId,
      'p_item_name': name,
      'p_quantity': quantity,
      'p_unit_cost': unitCost,
      'p_unit': unit,
      'p_category': category,
      'p_method': method,
      'p_memo': memo,
      'p_client_uuid': clientUuid,
      'p_occurred_at': when,
    };

    await _db.transaction((txn) async {
      await txn.insert('outbox', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'action': 'receive_stock',
        'payload': jsonEncode(payload),
        'created_at': when,
      });

      await txn.insert('farm_events', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'kind': 'stock_in',
        'subject': name,
        'quantity': quantity,
        'unit': unit,
        'note': memo,
        'occurred_at': when,
      });

      // A delivery logged without a price is still a delivery — the invoice is
      // often in the truck — and 009 posts no journal entry for it, so neither
      // does the device.
      if (total > 0) {
        await txn.insert('entries', {
          'client_uuid': clientUuid,
          'org_id': orgId,
          'kind': 'expense',
          'label': '$name — ${_trim(quantity)} $unit',
          'category': category,
          'amount': total,
          'direction': 'out',
          'method': method,
          'memo': memo,
          'details': jsonEncode({
            'quantité': _trim(quantity),
            'unité': unit,
            if (unitCost != null) 'prix unitaire': '$unitCost',
          }),
          'occurred_at': when,
        });
      }
    });

    return clientUuid;
  }

  /// Feed eaten, medicine given, something spoiled, or a physical count that
  /// disagreed with the running total.
  ///
  /// No money and no `entries` row: the money left when the sacks arrived, and
  /// expensing them again as they are eaten would double the single largest
  /// cost on the farm. What this moves is the count.
  Future<String> moveStock({
    required String orgId,
    required String itemName,
    required double quantity,
    String kind = 'consumed', // consumed | wasted | adjusted
    String unit = 'sac',
    String? memo,
    DateTime? occurredAt,
  }) async {
    final clientUuid = _uuid.v4();
    final when = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();
    final name = itemName.trim();

    final payload = {
      'p_org_id': orgId,
      'p_item_name': name,
      'p_quantity': quantity,
      'p_kind': kind,
      'p_unit': unit,
      'p_memo': memo,
      'p_client_uuid': clientUuid,
      'p_occurred_at': when,
    };

    await _db.transaction((txn) async {
      await txn.insert('outbox', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'action': 'move_stock',
        'payload': jsonEncode(payload),
        'created_at': when,
      });

      await txn.insert('farm_events', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'kind': kind == 'consumed' ? 'stock_out' : kind,
        'subject': name,
        'quantity': quantity,
        'unit': unit,
        'note': memo,
        'occurred_at': when,
      });
    });

    return clientUuid;
  }

  /// Birds died, were weighed, were vaccinated, or left alive.
  ///
  /// [flockId] is a server id, which means a flock has to have been seen at
  /// least once before its events can be recorded — unlike stock, where the
  /// item is found or created from the name. That asymmetry is deliberate:
  /// creating an item by typing "Aliment ponte" is harmless, and creating a
  /// flock by typing a batch code would let one mistyped code split a batch of
  /// 500 birds into two flocks that no report could add back together.
  Future<String> recordFlockEvent({
    required String orgId,
    required String flockId,
    required String batchCode,
    required String kind, // mortality | weight | vaccination | sold
    required double quantity,
    String? note,
    DateTime? occurredAt,
  }) async {
    final clientUuid = _uuid.v4();
    final when = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();

    final payload = {
      'p_flock_id': flockId,
      'p_kind': kind,
      'p_quantity': quantity,
      'p_note': note,
      'p_client_uuid': clientUuid,
      'p_occurred_at': when,
    };

    await _db.transaction((txn) async {
      await txn.insert('outbox', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'action': 'record_flock_event',
        'payload': jsonEncode(payload),
        'created_at': when,
      });

      await txn.insert('farm_events', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'kind': kind,
        'subject': batchCode,
        'quantity': quantity,
        'note': note,
        'occurred_at': when,
      });
    });

    return clientUuid;
  }

  /// The morning collection. Production, not income — plenty of these are
  /// eaten, given away or broken before anyone pays for one.
  Future<String> recordEggs({
    required String orgId,
    required int eggCount,
    String? flockId,
    String? batchCode,
    String grade = 'normal',
    DateTime? producedOn,
  }) async {
    final clientUuid = _uuid.v4();
    final day = producedOn ?? DateTime.now();
    final when = day.toUtc().toIso8601String();

    final payload = {
      'p_org_id': orgId,
      'p_egg_count': eggCount,
      'p_flock_id': flockId,
      'p_grade': grade,
      'p_produced_on': _dayKey(day),
      'p_client_uuid': clientUuid,
    };

    await _db.transaction((txn) async {
      await txn.insert('outbox', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'action': 'record_eggs',
        'payload': jsonEncode(payload),
        'created_at': when,
      });

      await txn.insert('farm_events', {
        'client_uuid': clientUuid,
        'org_id': orgId,
        'kind': 'eggs',
        'subject': batchCode ?? 'Ponte',
        'quantity': eggCount.toDouble(),
        'note': grade == 'normal' ? null : grade,
        'occurred_at': when,
      });
    });

    return clientUuid;
  }

  /// The day as this device knows it: eggs collected, birds lost, feed used.
  ///
  /// Computed from what is on the phone, which during a fortnight at the farm
  /// is everything there is. The server's `farm_daily_summary()` says the same
  /// thing once the outbox has drained.
  Future<({int eggs, double deaths, double feedUsed})> farmDay(
    String orgId,
    DateTime day,
  ) async {
    final start = DateTime.utc(day.year, day.month, day.day).toIso8601String();
    final end = DateTime.utc(day.year, day.month, day.day)
        .add(const Duration(days: 1))
        .toIso8601String();

    final rows = await _db.query(
      'farm_events',
      where: 'org_id = ? AND occurred_at >= ? AND occurred_at < ?',
      whereArgs: [orgId, start, end],
    );

    var eggs = 0;
    var deaths = 0.0;
    var feed = 0.0;
    for (final row in rows) {
      final q = (row['quantity'] as num).toDouble();
      switch (row['kind']) {
        case 'eggs':
          eggs += q.round();
        case 'mortality':
          deaths += q;
        case 'stock_out':
          feed += q;
      }
    }

    return (eggs: eggs, deaths: deaths, feedUsed: feed);
  }

  /// Everything counted on a given day, newest first.
  Future<List<Map<String, Object?>>> farmEventsForDay(
    String orgId,
    DateTime day,
  ) async {
    final start = DateTime.utc(day.year, day.month, day.day).toIso8601String();
    final end = DateTime.utc(day.year, day.month, day.day)
        .add(const Duration(days: 1))
        .toIso8601String();

    return _db.query(
      'farm_events',
      where: 'org_id = ? AND occurred_at >= ? AND occurred_at < ?',
      whereArgs: [orgId, start, end],
      orderBy: 'occurred_at DESC',
    );
  }

  /// Replaces this org's cached item list wholesale, the way [cacheOrgs] and
  /// [cacheAccounts] do: an item retired on the server has to stop being
  /// offered here, not linger.
  Future<void> cacheFarmItems(
    String orgId,
    List<Map<String, Object?>> items,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete('cached_farm_items', where: 'org_id = ?', whereArgs: [orgId]);
      for (final item in items) {
        await txn.insert('cached_farm_items', {
          'item_id': item['item_id'],
          'org_id': orgId,
          'name': item['name'],
          'unit': item['unit'] ?? 'sac',
          'on_hand': item['on_hand'] ?? 0,
          'reorder_level': item['reorder_level'],
          'below_reorder': (item['below_reorder'] as bool? ?? false) ? 1 : 0,
        });
      }
    });
  }

  Future<List<Map<String, Object?>>> cachedFarmItems(String orgId) {
    return _db.query(
      'cached_farm_items',
      where: 'org_id = ?',
      whereArgs: [orgId],
      orderBy: 'below_reorder DESC, name ASC',
    );
  }

  Future<void> cacheFlocks(
    String orgId,
    List<Map<String, Object?>> flocks,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete('cached_flocks', where: 'org_id = ?', whereArgs: [orgId]);
      for (final flock in flocks) {
        await txn.insert('cached_flocks', {
          'flock_id': flock['flock_id'],
          'org_id': orgId,
          'batch_code': flock['batch_code'],
          'alive': flock['alive'] ?? 0,
          'closed': (flock['closed'] as bool? ?? false) ? 1 : 0,
        });
      }
    });
  }

  Future<List<Map<String, Object?>>> cachedFlocks(String orgId) {
    return _db.query(
      'cached_flocks',
      where: 'org_id = ? AND closed = 0',
      whereArgs: [orgId],
      orderBy: 'batch_code ASC',
    );
  }

  /// The item names to offer, best first.
  ///
  /// Same three-source fallback as [categoriesFor]: what the server last said,
  /// then what this device has actually recorded against, then nothing — and
  /// nothing is survivable because the field these are chips for is a text
  /// field.
  Future<List<String>> farmItemNames(String orgId) async {
    final cached = await _db.query(
      'cached_farm_items',
      columns: ['name'],
      where: 'org_id = ?',
      whereArgs: [orgId],
      orderBy: 'below_reorder DESC, name ASC',
    );
    if (cached.isNotEmpty) {
      return cached.map((r) => r['name'] as String).toList();
    }

    final used = await _db.rawQuery(
      'SELECT subject, COUNT(*) AS n FROM farm_events '
      "WHERE org_id = ? AND kind IN ('stock_in', 'stock_out', 'wasted') "
      'GROUP BY subject ORDER BY n DESC, subject ASC LIMIT 12',
      [orgId],
    );
    return used.map((r) => r['subject'] as String).toList();
  }

  /// Trims a count for display: 20 rather than 20.0, 2.5 rather than 2.500.
  static String _trim(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }

  // ----------------------------------------------------------------
  // The categories on offer
  // ----------------------------------------------------------------

  /// Replaces this org's cached chart wholesale. An account retired on the
  /// server has to stop being offered here, not linger.
  Future<void> cacheAccounts(
    String orgId,
    List<Map<String, Object?>> accounts,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete('cached_accounts', where: 'org_id = ?', whereArgs: [orgId]);
      for (final account in accounts) {
        await txn.insert('cached_accounts', {
          'account_id': account['account_id'],
          'org_id': orgId,
          'code': account['code'],
          'name': account['name'],
          'type': account['type'],
          'is_active': (account['is_active'] as bool? ?? true) ? 1 : 0,
        });
      }
    });
  }

  /// The names to offer for a direction, best first.
  ///
  /// Three sources, in order of how much they are worth: the chart as the
  /// server last described it, then the categories this device has actually
  /// recorded against, then nothing. The second is what makes a phone that has
  /// never synced still useful — the categories somebody has been using all
  /// week are the categories they are about to use again — and the third is
  /// survivable because the field they are chips for is a text field.
  Future<List<String>> categoriesFor(String orgId, String direction) async {
    final type = direction == 'in' ? 'income' : 'expense';

    final cached = await _db.query(
      'cached_accounts',
      columns: ['name'],
      where: 'org_id = ? AND type = ? AND is_active = 1',
      whereArgs: [orgId, type],
      orderBy: 'code ASC',
    );
    if (cached.isNotEmpty) {
      return cached.map((r) => r['name'] as String).toList();
    }

    final used = await _db.rawQuery(
      'SELECT category, COUNT(*) AS n FROM entries '
      'WHERE org_id = ? AND direction = ? AND category IS NOT NULL '
      'GROUP BY category ORDER BY n DESC, category ASC LIMIT 12',
      [orgId, direction],
    );
    return used.map((r) => r['category'] as String).toList();
  }

  /// The asset accounts money can sit in, for the transfer sheet. Empty until
  /// the chart has been cached at least once, which is why the sheet that uses
  /// it needs signal and says so.
  Future<List<String>> cashAccounts(String orgId) async {
    final rows = await _db.query(
      'cached_accounts',
      columns: ['name'],
      where: 'org_id = ? AND type = ? AND is_active = 1',
      whereArgs: [orgId, 'asset'],
      orderBy: 'code ASC',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  // ----------------------------------------------------------------
  // Closing the day
  // ----------------------------------------------------------------

  static String _dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// Records that someone looked at the day and agreed with it. Idempotent:
  /// closing twice is the same as closing once, and re-closing after a late
  /// entry updates the figures rather than adding a second row.
  Future<void> closeDay(
    String orgId,
    DateTime day, {
    required double moneyIn,
    required double moneyOut,
  }) async {
    await _db.insert(
      'day_closures',
      {
        'org_id': orgId,
        'closed_on': _dayKey(day),
        'closed_at': DateTime.now().toUtc().toIso8601String(),
        'money_in': moneyIn,
        'money_out': moneyOut,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isDayClosed(String orgId, DateTime day) async {
    final rows = await _db.query(
      'day_closures',
      where: 'org_id = ? AND closed_on = ?',
      whereArgs: [orgId, _dayKey(day)],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// How many days in a row have been closed, counting back from today.
  ///
  /// Today not being closed yet does not break the streak — it is not over
  /// until the day is. So the count starts at today when today is closed and
  /// at yesterday otherwise, and a streak is only lost by missing a whole day.
  Future<int> closureStreak(String orgId, {DateTime? asOf}) async {
    final rows = await _db.query(
      'day_closures',
      columns: ['closed_on'],
      where: 'org_id = ?',
      whereArgs: [orgId],
    );
    final closed = rows.map((r) => r['closed_on'] as String).toSet();
    if (closed.isEmpty) return 0;

    final today = asOf ?? DateTime.now();
    var cursor = closed.contains(_dayKey(today))
        ? today
        : today.subtract(const Duration(days: 1));

    var streak = 0;
    while (closed.contains(_dayKey(cursor))) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
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

  /// What the outbox looks like right now, for the console.
  ///
  /// `stuck` is the number that have been attempted and are still here. That
  /// is the one figure worth alarming on: pending-and-never-tried means no
  /// signal, which is normal and expected, while pending-and-tried-four-times
  /// means the server is refusing them and nobody has been told.
  Future<({int pending, int stuck, int sent})> outboxHealth() async {
    final rows = await _db.rawQuery('''
      SELECT
        SUM(CASE WHEN synced_at IS NULL THEN 1 ELSE 0 END) AS pending,
        SUM(CASE WHEN synced_at IS NULL AND attempts > 0 THEN 1 ELSE 0 END) AS stuck,
        SUM(CASE WHEN synced_at IS NOT NULL THEN 1 ELSE 0 END) AS sent
      FROM outbox
    ''');
    final row = rows.first;
    return (
      pending: (row['pending'] as int?) ?? 0,
      stuck: (row['stuck'] as int?) ?? 0,
      sent: (row['sent'] as int?) ?? 0,
    );
  }

  /// The actions the server has refused, newest first, with the reason. An
  /// error kept only in a column nobody reads is an error nobody fixes.
  Future<List<Map<String, Object?>>> failedActions({int limit = 20}) {
    return _db.query(
      'outbox',
      where: 'synced_at IS NULL AND attempts > 0',
      orderBy: 'attempts DESC, created_at DESC',
      limit: limit,
    );
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
