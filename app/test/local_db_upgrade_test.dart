import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Upgrading a phone that already has work on it.
///
/// This is the most destructive bug this codebase can have and the least
/// likely to be noticed in testing. Everywhere else, losing the local database
/// costs a round trip; here it can be the only copy that exists. Ignace records
/// three weeks at the farm with no signal, updates the app, and if the v3 → v4
/// migration drops or rebuilds `entries` those three weeks are gone from the
/// only machine that ever held them.
///
/// So the upgrade is exercised against a database built the way v3 built it,
/// with rows in it, rather than against a fresh one.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// A path nothing is left over on.
  ///
  /// The ffi factory writes a named path to a real file under .dart_tool, so
  /// unlike `inMemoryDatabasePath` these outlive the process. Left alone, the
  /// second run of this suite would open a database that is already at v4 and
  /// every assertion below would pass for the wrong reason — which is exactly
  /// the failure mode a migration test exists to catch, so it must not be the
  /// failure mode of the test itself.
  Future<String> freshPath(String name) async {
    await databaseFactory.deleteDatabase(name);
    addTearDown(() => databaseFactory.deleteDatabase(name));
    return name;
  }

  /// Everything LocalDb.open(version: 3) would have created, verbatim from
  /// what shipped. Deliberately a copy rather than a call into LocalDb: the
  /// point is to reproduce what is on somebody's phone, and a helper that
  /// tracked the current schema would make this test pass by definition.
  Future<void> createV3(String path) async {
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 3),
    );

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
    await db.execute(
      'CREATE INDEX entries_by_date ON entries (org_id, occurred_at)',
    );
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

    // Three weeks at the farm: one recorded entry, still unsent.
    await db.insert('entries', {
      'client_uuid': 'offline-1',
      'org_id': 'org-farm',
      'kind': 'offering',
      'label': 'Offrande',
      'amount': 12500.0,
      'direction': 'in',
      'method': 'cash',
      'occurred_at': '2026-07-02T09:00:00.000Z',
    });
    await db.insert('outbox', {
      'client_uuid': 'offline-1',
      'org_id': 'org-farm',
      'action': 'record_contribution',
      'payload': '{"p_amount":12500}',
      'created_at': '2026-07-02T09:00:00.000Z',
    });

    await db.close();
  }

  test('a v3 device keeps everything it recorded', () async {
    // A distinct name per test: sqflite keys open databases by path.
    final path = await freshPath('upgrade-keeps.db');
    await createV3(path);

    final db = await LocalDb.open(path: path);
    addTearDown(db.close);

    final entries =
        await db.entriesForDay('org-farm', DateTime.utc(2026, 7, 2));
    expect(entries, hasLength(1));
    expect(entries.single['label'], 'Offrande');
    expect(entries.single['amount'], 12500.0);

    // And the work that has not left the device is still queued for the
    // server, under the action name the old build wrote. That name still
    // resolves — record_contribution() in 002 was never removed — which is
    // the reason the function survives in LocalDb with nothing calling it.
    final pending = await db.pendingActions();
    expect(pending, hasLength(1));
    expect(pending.single['action'], 'record_contribution');
  });

  test('the new columns exist and old rows get a category', () async {
    final path = await freshPath('upgrade-columns.db');
    await createV3(path);

    final db = await LocalDb.open(path: path);
    addTearDown(db.close);

    final entries =
        await db.entriesForDay('org-farm', DateTime.utc(2026, 7, 2));

    // Everything recorded before v4 was filed under a fixed category and
    // labelled with it, so backfilling category from label is not a guess —
    // it is what was true.
    expect(entries.single['category'], 'Offrande');
    expect(entries.single['details'], isNull);

    // And the upgraded device can record the new way immediately.
    await db.recordEntry(
      orgId: 'org-farm',
      amount: 3000,
      direction: 'out',
      label: 'Sac de maïs',
      details: {'Fournisseur': 'Ouédraogo'},
    );

    final today = await db.entriesForDay('org-farm', DateTime.now());
    expect(today.single['label'], 'Sac de maïs');
  });

  test('the category cache survives the upgrade and can be filled', () async {
    final path = await freshPath('upgrade-cache.db');
    await createV3(path);

    final db = await LocalDb.open(path: path);
    addTearDown(db.close);

    // The table did not exist in v3 at all.
    await db.cacheAccounts('org-farm', [
      {
        'account_id': 'a1',
        'code': '5000',
        'name': 'Aliment volaille',
        'type': 'expense',
        'is_active': true,
      },
      {
        'account_id': 'a2',
        'code': '5010',
        'name': 'Vétérinaire',
        'type': 'expense',
        'is_active': false,
      },
    ]);

    // A retired account is not offered — that is the whole point of retiring
    // one rather than deleting it.
    expect(
      await db.categoriesFor('org-farm', 'out'),
      ['Aliment volaille'],
    );
  });

  test('with no cached chart, the categories are the ones already used',
      () async {
    final db = await LocalDb.open(path: await freshPath('upgrade-fallback.db'));
    addTearDown(db.close);

    await db.recordEntry(
      orgId: 'org-farm',
      amount: 1000,
      direction: 'out',
      label: 'Aliment du lundi',
      category: 'Aliment volaille',
    );
    await db.recordEntry(
      orgId: 'org-farm',
      amount: 1000,
      direction: 'out',
      label: 'Aliment du mardi',
      category: 'Aliment volaille',
    );
    await db.recordEntry(
      orgId: 'org-farm',
      amount: 8000,
      direction: 'out',
      label: 'Vaccin',
    );

    // Most-used first: the categories somebody has been using all week are the
    // ones they are about to use again. A phone that has never synced is still
    // useful, which is the whole reason this fallback exists.
    expect(
      await db.categoriesFor('org-farm', 'out'),
      ['Aliment volaille', 'Vaccin'],
    );

    // An entry with no category typed files itself under its own name.
    expect(await db.categoriesFor('org-farm', 'in'), isEmpty);
  });
}
