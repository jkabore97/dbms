import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/pin_codec.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/// The owner's words (108): « Only request a code pin to be setup after the
/// user has created a business. The pin code is meant to protect
/// businesses. » The device code is asked of somebody who belongs to a
/// business — owner, member, trainer — never of a shopper or a courier;
/// asked once, the day the first business arrives; a code already on a
/// shopper's phone stops being asked and is not deleted.
class _Server extends AuthRepository {
  _Server() : super(null);

  bool live = true;
  List<OrgSummary> orgs = const [];

  @override
  bool get isConfigured => true;

  @override
  bool get hasLiveSession => live;

  @override
  Future<List<OrgSummary>> fetchOrgs() async => orgs;
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<bool> isPlatformAdmin() async => false;
  @override
  Future<int> claimMyInvitations() async => 0;
  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;
}

const _person = User(
  id: 'u-108',
  appMetadata: {},
  userMetadata: {'full_name': 'Awa'},
  aud: 'authenticated',
  phone: '+22670108108',
  createdAt: '2026-10-08T00:00:00Z',
);

const _shop = OrgSummary(id: 'shop-1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);
const _farm = OrgSummary(id: 'farm-1', name: 'Ferme', profile: 'farm', roles: ['member']);
const _asso = OrgSummary(id: 'asso-1', name: 'Entraide', profile: 'association', roles: ['owner']);
const _trained = OrgSummary(id: 'shop-2', name: 'Suivie', profile: 'retail', roles: ['trainer']);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() => db.close());

  SessionController on(_Server server) => SessionController(
        db: db,
        auth: server,
        admin: _Admin(),
        accounting: AccountingRepository(null),
      );

  Future<void> oldCode() async {
    final salt = PinCodec.newSalt();
    await db.saveIdentity(LocalIdentity(
        userId: _person.id, phone: _person.phone, pinSalt: salt, pinHash: PinCodec.hash('2580', salt)));
  }

  test('a shopper signs in: the street, never a code to choose', () async {
    final session = on(_Server());
    await session.handleSignedIn(_person);
    expect(session.phase, SessionPhase.noOrg);
    expect(session.identity?.hasPin, isFalse);
    // Nothing to lock either, whatever the delay.
    expect(session.lockNow(), isFalse);
  });

  for (final org in [_shop, _farm, _asso, _trained]) {
    test('somebody of a ${org.profile} (${org.roles.first}) chooses the code once, then opens it',
        () async {
      final server = _Server()..orgs = [org];
      final session = on(server);
      await session.handleSignedIn(_person);
      expect(session.phase, SessionPhase.choosingPin);
      await session.setPin('7391');
      expect(session.phase, SessionPhase.ready);
      expect(session.identity?.hasPin, isTrue);
      // Asked once: the next resolve opens the business straight away.
      await session.resolveOrgs();
      expect(session.phase, SessionPhase.ready);
      expect(session.lockNow(), isTrue, reason: 'a business on the phone: the lock delay applies');
    });
  }

  test('a shopper\'s first business: the code is asked then, once', () async {
    final server = _Server();
    final session = on(server);
    await session.handleSignedIn(_person);
    expect(session.phase, SessionPhase.noOrg);
    // Their request was accepted (or a code joined them to a team).
    server.orgs = const [_shop];
    await session.resolveOrgs();
    expect(session.phase, SessionPhase.choosingPin);
    await session.setPin('7391');
    expect(session.phase, SessionPhase.ready);
  });

  test('a code already on a shopper\'s phone: no longer asked, and kept', () async {
    await oldCode();
    // No signal at launch, no business on the device: not locked.
    final offline = on(_Server()..live = false);
    await offline.boot();
    expect(offline.phase, SessionPhase.noOrg);
    expect(offline.lockNow(), isFalse);
    // With signal, the same.
    final online = on(_Server());
    await online.boot();
    expect(online.phase, SessionPhase.noOrg);
    expect(online.lockNow(), isFalse);
    // The code is still on the device, untouched.
    final kept = await db.loadIdentity();
    expect(PinCodec.verify('2580', salt: kept!.pinSalt!, hash: kept.pinHash!), isTrue);
  });

  test('a member\'s phone with a code and no signal: locked as before', () async {
    await oldCode();
    await db.cacheOrgs(const [_shop]);
    final session = on(_Server()..live = false);
    await session.boot();
    expect(session.phase, SessionPhase.locked);
  });
}
