import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The bug this proves shut: a business the resolve auto-opens — a single-org
/// employee, or the one remembered across a reload — had its id set in
/// _lastOrgId before the router's openOrg() ran, so openOrg early-returned and
/// the owner's dial was never fetched. `accessFor` then stayed on its
/// permissive default and the employee saw every tool the owner had hidden.
///
/// The dial is fetched through AdminRepository now, so a fake can stand in for
/// the server here without a live client.
class _FakeAdmin extends AdminRepository {
  _FakeAdmin(this.rules) : super(null);

  final Map<String, String> rules;
  int calls = 0;

  @override
  Future<Map<String, String>> featureRulesForTier(
      String orgId, String tier) async {
    calls++;
    return rules;
  }

  @override
  Future<bool> isPlatformAdmin() async => false;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  test("an auto-opened employee's dial is loaded, not left permissive",
      () async {
    await db.cacheOrgs([
      const OrgSummary(
          id: 'o1', name: 'Boutique', profile: 'retail', roles: ['employee']),
    ]);
    final admin = _FakeAdmin({'tontines': 'hidden', 'credits': 'view'});
    final session = SessionController(
      db: db,
      auth: AuthRepository(null),
      admin: admin,
      accounting: AccountingRepository(null),
    );

    await session.resolveOrgs();
    // resolveOrgs kicks _loadAccess off unawaited; let the microtask land.
    await Future<void>.delayed(Duration.zero);

    final access = session.accessFor('o1');
    expect(admin.calls, greaterThan(0),
        reason: 'the dial must be fetched for the auto-opened business');
    expect(access.canSee('tontines'), isFalse, reason: 'hidden must hide');
    expect(access.canSee('credits'), isTrue);
    expect(access.canEdit('credits'), isFalse, reason: 'view is not edit');
    expect(access.canEdit('products'), isTrue,
        reason: 'a feature the owner never dialled stays editable');
  });

  test('an admin is never dialled down, and needs no fetch', () async {
    // On Pro: the dial never lowers an owner, and neither does the plan.
    // A Free owner is a different case — see the test below.
    await db.cacheOrgs([
      const OrgSummary(
          id: 'o1',
          name: 'Boutique',
          profile: 'retail',
          roles: ['owner'],
          plan: 'pro'),
    ]);
    final admin = _FakeAdmin({'tontines': 'hidden'});
    final session = SessionController(
      db: db,
      auth: AuthRepository(null),
      admin: admin,
      accounting: AccountingRepository(null),
    );

    await session.resolveOrgs();
    await Future<void>.delayed(Duration.zero);

    final access = session.accessFor('o1');
    expect(access.canSee('tontines'), isTrue);
    expect(access.canEdit('tontines'), isTrue);
    expect(admin.calls, 0, reason: 'an admin needs no rules fetched');
  });

  test('an owner on Free reads a Pro tool at view, badged, before any fetch',
      () async {
    // The plan layer (066): the owner keeps seeing tontines — never hidden —
    // but cannot edit, and the badge says why. Known from the cached org row
    // and the default terms, so it is right before the network answers, and
    // the load then confirms it without a second emit.
    await db.cacheOrgs([
      const OrgSummary(
          id: 'o1', name: 'Boutique', profile: 'retail', roles: ['owner']),
    ]);
    final admin = _FakeAdmin({});
    final session = SessionController(
      db: db,
      auth: AuthRepository(null),
      admin: admin,
      accounting: AccountingRepository(null),
    );
    var emits = 0;
    session.addListener(() => emits++);

    await session.resolveOrgs();
    final before = session.accessFor('o1');
    final emitsAfterResolve = emits;
    await Future<void>.delayed(Duration.zero);
    final after = session.accessFor('o1');

    expect(before.canSee('tontines'), isTrue);
    expect(before.canEdit('tontines'), isFalse);
    expect(before.isProLocked('tontines'), isTrue);
    expect(before.canEdit('products'), isTrue);
    expect(after, equals(before));
    expect(emits, emitsAfterResolve,
        reason: 'the load confirmed what was already shown: no emit');
  });
}
