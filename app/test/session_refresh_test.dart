import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An open app keeps up (SessionController.refresh).
///
/// The audit: what the server says about a person was read at launch and
/// never again, so on an Android phone that stays open for days a Pro
/// upgrade, an owner's new dial or a removal arrived only after a restart.
/// Each case below is one of those, reaching an app that never restarted —
/// and the two quiet ones: no signal changes nothing, and an unchanged
/// answer does not rebuild a single screen.
class _Server extends AuthRepository {
  _Server(this.orgs) : super(null);

  List<OrgSummary> orgs;
  bool offline = false;
  int asked = 0;

  @override
  bool get hasLiveSession => true;

  @override
  Future<List<OrgSummary>> fetchOrgs() async {
    asked++;
    if (offline) throw Exception('no signal');
    return orgs;
  }
}

class _Admin extends AdminRepository {
  _Admin() : super(null);

  Map<String, String> rules = const {};

  @override
  Future<bool> isPlatformAdmin() async => false;

  @override
  Future<int> claimMyInvitations() async => 0;

  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;

  @override
  Future<Map<String, String>> featureRulesForTier(
          String orgId, String tier) async =>
      rules;
}

const _owner = OrgSummary(
    id: 'o1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);
const _clerk = OrgSummary(
    id: 'o1', name: 'Boutique Awa', profile: 'retail', roles: ['employee']);

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

  Future<(SessionController, _Server, _Admin)> resolved(
      List<OrgSummary> orgs) async {
    final server = _Server(orgs);
    final admin = _Admin();
    final session = SessionController(
      db: db,
      auth: server,
      admin: admin,
      accounting: AccountingRepository(null),
    );
    await session.resolveOrgs();
    // Let the background dial load of the auto-opened business settle.
    await Future<void>.delayed(Duration.zero);
    return (session, server, admin);
  }

  test('a Pro upgrade reaches the open app', () async {
    final (session, server, _) = await resolved(const [_owner]);
    expect(session.phase, SessionPhase.ready);
    expect(session.accessFor('o1').isProLocked('payroll'), isTrue);

    server.orgs = const [
      OrgSummary(
          id: 'o1',
          name: 'Boutique Awa',
          profile: 'retail',
          roles: ['owner'],
          plan: 'pro'),
    ];
    var emits = 0;
    session.addListener(() => emits++);
    await session.refresh(force: true);

    expect(session.orgById('o1')!.isPro, isTrue);
    expect(session.accessFor('o1').isProLocked('payroll'), isFalse);
    expect(emits, greaterThan(0));
    expect(session.phase, SessionPhase.ready,
        reason: 'nobody is moved off the page they are on');
  });

  test('an owner\'s new dial reaches an employee without a restart',
      () async {
    final (session, _, admin) = await resolved(const [_clerk]);
    expect(session.accessFor('o1').canSee('invoices'), isTrue);

    // The org list does not change at all: only the dial does.
    admin.rules = const {'invoices': 'hidden'};
    await session.refresh(force: true);

    expect(session.accessFor('o1').canSee('invoices'), isFalse);
  });

  test('removed from the open business: sent to the picker', () async {
    const other = OrgSummary(
        id: 'o2', name: 'Ferme', profile: 'farm', roles: ['owner']);
    const third = OrgSummary(
        id: 'o3', name: 'Assemblée', profile: 'association', roles: ['owner']);
    final (session, server, _) = await resolved(const [_owner, other, third]);
    session.openOrg('o1');
    expect(session.lastOrgId, 'o1');

    server.orgs = const [other, third];
    await session.refresh(force: true);

    expect(session.phase, SessionPhase.picking);
    expect(session.lastOrgId, isNull);
    expect(session.orgById('o1'), isNull);
  });

  test('no signal changes nothing', () async {
    final (session, server, _) = await resolved(const [_owner]);
    server.offline = true;
    var emits = 0;
    session.addListener(() => emits++);
    await session.refresh(force: true);
    expect(emits, 0);
    expect(session.orgs.single.id, 'o1');
    expect(session.phase, SessionPhase.ready);
  });

  test('an unchanged answer rebuilds nothing, and a burst asks once',
      () async {
    final (session, server, _) = await resolved(const [_owner]);
    var emits = 0;
    session.addListener(() => emits++);
    await session.refresh(force: true);
    expect(emits, 0, reason: 'the same answer must not re-run the router');

    final before = server.asked;
    await session.refresh(); // within 30 s of the last one
    await session.refresh();
    expect(server.asked, before, reason: 'switching apps back and forth');
  });

  test('a locked or signed-out app is left to its gate', () async {
    final server = _Server(const [_owner]);
    final session = SessionController(
      db: db,
      auth: server,
      admin: _Admin(),
      accounting: AccountingRepository(null),
    );
    // Still booting: no resolve has happened, nothing to refresh.
    await session.refresh(force: true);
    expect(server.asked, 0);
    expect(session.phase, SessionPhase.booting);
  });
}
