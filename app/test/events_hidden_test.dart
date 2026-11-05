import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The owner: Apple's reviewer made an Événementiel while the platform's
/// switch was on; switched off, the business opened onto « Réservé aux
/// administrateurs » — its own owner locked out by the server's
/// events_open. With the switch off an Événementiel is not in the list at
/// all; a platform admin keeps it; the switch on, everyone has theirs.
class _Auth extends AuthRepository {
  _Auth() : super(null);

  @override
  bool get hasLiveSession => true;

  @override
  Future<List<OrgSummary>> fetchOrgs() async => const [
        OrgSummary(id: 's1', name: 'Review Shop', profile: 'retail', roles: ['owner']),
        OrgSummary(id: 'e1', name: 'Test Event Gala', profile: 'events', roles: ['owner']),
      ];
}

class _Admin extends AdminRepository {
  _Admin({this.platform = false, this.open = false, this.allowed = const {}}) : super(null);

  final bool platform;
  final bool open;
  final Set<String> allowed;

  @override
  Future<Set<String>> eventsAllowed() async => allowed;

  @override
  Future<bool> isPlatformAdmin() async => platform;

  @override
  Future<bool> eventsPublic() async => open;

  @override
  Future<int> claimMyInvitations() async => 0;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() => db.close());

  Future<SessionController> resolve(_Admin admin) async {
    final s = SessionController(db: db, auth: _Auth(), admin: admin, accounting: AccountingRepository(null));
    await s.resolveOrgs();
    return s;
  }

  test('the switch off: the Événementiel is not in the list; the shop opens straight away', () async {
    final s = await resolve(_Admin());
    expect(s.orgs.map((o) => o.id), ['s1']);
    expect(s.orgById('e1'), isNull, reason: 'a bookmark to it lands on the list, not on a locked page');
    expect(s.phase, SessionPhase.ready, reason: 'one business left: it opens');
  });

  test('the switch on: both', () async {
    final s = await resolve(_Admin(open: true));
    expect(s.orgs.map((o) => o.id), ['s1', 'e1']);
  });

  test('a platform admin keeps the Événementiel whatever the switch', () async {
    final s = await resolve(_Admin(platform: true));
    expect(s.orgs.map((o) => o.id), ['s1', 'e1']);
  });

  // 167: « Mariage Phanuel & Esperance », made while the switch was on, let
  // in by a platform admin while it is off: theirs, and nobody else's.
  test('the switch off, this Événementiel allowed: in the list and its pages open', () async {
    final s = await resolve(_Admin(allowed: {'e1'}));
    expect(s.orgs.map((o) => o.id), ['s1', 'e1']);
    expect(s.eventsOpenFor(s.orgById('e1')!), isTrue);
    expect(s.eventsPublic, isFalse, reason: 'the module stays closed to everyone else');
  });

  test('another business allowed: this one stays hidden', () async {
    final s = await resolve(_Admin(allowed: {'zz'}));
    expect(s.orgs.map((o) => o.id), ['s1']);
  });
}
