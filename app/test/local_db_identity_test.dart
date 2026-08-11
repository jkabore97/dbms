import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The offline half of authentication: what the device remembers about who is
/// signed in and which businesses they can open with no signal.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;

  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });

  // An in-memory database is keyed by path like any other, so it survives
  // until every connection to it closes. Each test starts empty because of
  // this line.
  tearDown(() => db.close());

  test('a fresh device knows nobody', () async {
    expect(await db.loadIdentity(), isNull);
    expect(await db.cachedOrgs(), isEmpty);
  });

  test('an identity survives being written and read back', () async {
    await db.saveIdentity(const LocalIdentity(
      userId: 'user-1',
      displayName: 'Israel',
      phone: '+22670000001',
      pinSalt: 'salt',
      pinHash: 'hash',
    ));

    final loaded = await db.loadIdentity();
    expect(loaded!.userId, 'user-1');
    expect(loaded.displayName, 'Israel');
    expect(loaded.phone, '+22670000001');
    expect(loaded.hasPin, isTrue);
  });

  test('only one identity is ever stored', () async {
    await db.saveIdentity(const LocalIdentity(userId: 'user-1'));
    await db.saveIdentity(const LocalIdentity(userId: 'user-2'));

    final loaded = await db.loadIdentity();
    expect(loaded!.userId, 'user-2');
  });

  test('the org cache round-trips every field the router needs', () async {
    await db.cacheOrgs(const [
      OrgSummary(
        id: 'org-1',
        name: 'Grace Chapel',
        profile: 'church',
        slug: 'grace',
        currency: 'XOF',
        roles: ['owner'],
        visibility: 'full',
      ),
    ]);

    final orgs = await db.cachedOrgs();
    expect(orgs, hasLength(1));
    expect(orgs.single.id, 'org-1');
    expect(orgs.single.name, 'Grace Chapel');
    expect(orgs.single.profile, 'church');
    expect(orgs.single.slug, 'grace');
    expect(orgs.single.roles, ['owner']);
    expect(orgs.single.visibility, 'full');
  });

  test('a revoked membership disappears from the cache', () async {
    await db.cacheOrgs(const [
      OrgSummary(id: 'org-1', name: 'Grace Chapel', profile: 'church'),
      OrgSummary(id: 'org-2', name: 'Ferme Ignace', profile: 'farm'),
    ]);
    expect(await db.cachedOrgs(), hasLength(2));

    // The next refresh comes back with only one org.
    await db.cacheOrgs(const [
      OrgSummary(id: 'org-1', name: 'Grace Chapel', profile: 'church'),
    ]);

    final orgs = await db.cachedOrgs();
    expect(orgs, hasLength(1));
    expect(orgs.single.id, 'org-1');
  });

  test('signing out forgets the person but never their unsent work', () async {
    await db.saveIdentity(const LocalIdentity(userId: 'user-1'));
    await db.cacheOrgs(const [
      OrgSummary(id: 'org-1', name: 'Grace Chapel', profile: 'church'),
    ]);
    await db.recordContribution(
      orgId: 'org-1',
      amount: 50000,
      kind: 'tithe',
      method: 'cash',
    );

    await db.clearIdentity();

    expect(await db.loadIdentity(), isNull);
    expect(await db.cachedOrgs(), isEmpty);
    // The entry exists nowhere else until it syncs. Losing it here would lose
    // it for good.
    expect(await db.pendingCount(), 1);
  });

  test('upgrading a v1 device keeps its entries and gains identity storage',
      () async {
    // A phone that already has the app on it holds the only copy of whatever
    // was recorded out of signal. The v1 -> v2 migration must not cost a
    // single row of it.
    final dir = await Directory.systemTemp.createTemp('kaj_upgrade_test');
    final path = p.join(dir.path, 'kaj.db');
    addTearDown(() => dir.delete(recursive: true));

    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE outbox (
              client_uuid TEXT PRIMARY KEY, org_id TEXT NOT NULL,
              action TEXT NOT NULL, payload TEXT NOT NULL,
              created_at TEXT NOT NULL, synced_at TEXT,
              attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE entries (
              client_uuid TEXT PRIMARY KEY, server_id TEXT,
              org_id TEXT NOT NULL, kind TEXT NOT NULL, label TEXT NOT NULL,
              amount REAL NOT NULL, direction TEXT NOT NULL, method TEXT,
              member_name TEXT, memo TEXT, occurred_at TEXT NOT NULL,
              reversed INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      ),
    );
    await legacy.insert('entries', {
      'client_uuid': 'abc',
      'org_id': 'org-1',
      'kind': 'tithe',
      'label': 'Dîme',
      'amount': 1000.0,
      'direction': 'in',
      'occurred_at': '2026-01-15T10:00:00.000Z',
    });
    await legacy.close();

    // Opening through LocalDb runs the real migration.
    final upgraded = await LocalDb.open(path: path);

    final totals = await upgraded.dayTotals('org-1', DateTime.utc(2026, 1, 15));
    expect(totals.moneyIn, 1000.0, reason: 'the old entry survived');

    expect(await upgraded.loadIdentity(), isNull);
    await upgraded.saveIdentity(const LocalIdentity(userId: 'user-1'));
    expect((await upgraded.loadIdentity())!.userId, 'user-1');
  });
}
