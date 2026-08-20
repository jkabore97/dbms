import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A suspended business is read-only on the phone, not gone.
///
/// The freeze is enforced on the server (049), but the app has to *know* about
/// it without signal — the banner that explains why nothing saves has to be on
/// screen the instant a frozen business opens, and the only thing on the phone
/// that early is the cached org list. So the flag rides `my_orgs()`, survives
/// the cache round trip, and is added to an already-populated device by the
/// v9 → v10 upgrade without disturbing anything else it holds.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<String> freshPath(String name) async {
    await databaseFactory.deleteDatabase(name);
    addTearDown(() => databaseFactory.deleteDatabase(name));
    return name;
  }

  group('OrgSummary carries the suspended flag', () {
    test('reads it from my_orgs()', () {
      final frozen = OrgSummary.fromRpc({
        'org_id': 'o1',
        'name': 'Boutique',
        'profile': 'retail',
        'roles': ['owner'],
        'suspended': true,
      });
      expect(frozen.suspended, isTrue);

      final open = OrgSummary.fromRpc({
        'org_id': 'o2',
        'name': 'Ferme',
        'profile': 'farm',
        'roles': ['owner'],
        'suspended': false,
      });
      expect(open.suspended, isFalse);
    });

    test('a database one migration behind (no column) means not frozen', () {
      // The app can run ahead of the database, so `suspended` can be absent
      // from the RPC row. Absent must read as "not frozen", never crash.
      final org = OrgSummary.fromRpc({
        'org_id': 'o3',
        'name': 'Atelier',
        'profile': 'generic',
        'roles': ['owner'],
      });
      expect(org.suspended, isFalse);
    });

    test('survives the cache round trip', () async {
      final db = await LocalDb.open(path: await freshPath('suspend-cache.db'));
      addTearDown(db.close);

      await db.cacheOrgs(const [
        OrgSummary(
          id: 'o1',
          name: 'Boutique gelée',
          profile: 'retail',
          roles: ['owner'],
          suspended: true,
        ),
        OrgSummary(
          id: 'o2',
          name: 'Ferme active',
          profile: 'farm',
          roles: ['owner'],
        ),
      ]);

      final cached = await db.cachedOrgs();
      final byId = {for (final o in cached) o.id: o};
      expect(byId['o1']!.suspended, isTrue);
      expect(byId['o2']!.suspended, isFalse);
    });
  });

  test('the v9 -> v10 upgrade adds the column and old rows are not frozen',
      () async {
    final path = await freshPath('suspend-upgrade.db');

    // A device sitting at v9: the cached_orgs table as it shipped then, with a
    // business already in it and no `suspended` column at all.
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 9),
    );
    await old.execute('''
      CREATE TABLE cached_orgs (
        org_id     TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        slug       TEXT,
        profile    TEXT NOT NULL,
        currency   TEXT,
        roles      TEXT,
        visibility TEXT,
        theme      TEXT
      )
    ''');
    await old.insert('cached_orgs', {
      'org_id': 'o-old',
      'name': 'Commerce existant',
      'profile': 'retail',
      'roles': 'owner',
      'visibility': 'full',
    });
    await old.close();

    // Opening at the current version runs the upgrade. The row that was there
    // before the column existed reads back as not frozen — the safe default —
    // and the business it belongs to is otherwise untouched.
    final db = await LocalDb.open(path: path);
    addTearDown(db.close);

    final cached = await db.cachedOrgs();
    expect(cached, hasLength(1));
    expect(cached.single.id, 'o-old');
    expect(cached.single.name, 'Commerce existant');
    expect(cached.single.suspended, isFalse);

    // And the upgraded device can store a freeze immediately.
    await db.cacheOrgs(const [
      OrgSummary(
        id: 'o-old',
        name: 'Commerce existant',
        profile: 'retail',
        roles: ['owner'],
        suspended: true,
      ),
    ]);
    final after = await db.cachedOrgs();
    expect(after.single.suspended, isTrue);
  });
}
