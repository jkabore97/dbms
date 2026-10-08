import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/pin_codec.dart';
import 'package:kaj_app/core/auth/two_step.dart';
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

  /// A market connection that stalls: the list's reply never comes.
  Completer<List<OrgSummary>>? hang;
  int asked = 0;

  @override
  bool get isConfigured => true;

  @override
  bool get hasLiveSession => live;

  @override
  Future<List<OrgSummary>> fetchOrgs() async {
    asked++;
    final h = hang;
    return h == null ? orgs : h.future;
  }
}

class _Admin extends AdminRepository {
  _Admin({this.platform = false}) : super(null);
  bool platform;
  @override
  Future<bool> isPlatformAdmin() async => platform;
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

  SessionController on(_Server server, {_Admin? admin, TwoStep? step, Duration? timeout}) =>
      SessionController(
        db: db,
        auth: server,
        admin: admin ?? _Admin(),
        accounting: AccountingRepository(null),
        twoStep: step,
        resolveTimeout: timeout ?? const Duration(seconds: 12),
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

  // A1: a platform admin with no business keeps the device code — the
  // console is the platform's books — after the second step, as before.
  group('a platform admin with no business', () {
    test('chooses the code once; the lock delay applies; a stale-token cold start locks', () async {
      final admin = _Admin(platform: true);
      final session = on(_Server(), admin: admin);
      await session.handleSignedIn(_person);
      expect(session.phase, SessionPhase.choosingPin);
      await session.setPin('7391');
      expect(session.phase, SessionPhase.noOrg);
      // Asked once.
      await session.resolveOrgs();
      expect(session.phase, SessionPhase.noOrg);
      expect(session.lockNow(), isTrue, reason: 'the console: the lock delay applies');
      session.dispose();

      // The next morning: the token is stale and there is no signal. The
      // device knows it is an admin's phone, so it locks.
      final cold = on(_Server()..live = false, admin: _Admin());
      await cold.boot();
      expect(cold.phase, SessionPhase.locked);
      cold.dispose();
    });

    test('the second step still comes first, the code after it', () async {
      final step = _Step();
      final session = on(_Server(), admin: _Admin(platform: true), step: step);
      await session.handleSignedIn(_person);
      expect(session.phase, SessionPhase.twoStep);
      step.passed = true;
      await session.twoStepPassed();
      expect(session.phase, SessionPhase.choosingPin);
      session.dispose();
    });

    test('signed out, the device forgets it was an admin\'s phone', () async {
      final session = on(_Server(), admin: _Admin(platform: true));
      await session.handleSignedIn(_person);
      await session.setPin('7391');
      await session.signOut();
      // Back as a shopper (the server says no): no code asked, nothing to
      // lock — the flag went with the sign-out.
      final again = on(_Server(), admin: _Admin());
      await oldCode();
      await again.boot();
      expect(again.phase, SessionPhase.noOrg);
      expect(again.lockNow(), isFalse);
      session.dispose();
      again.dispose();
    });
  });

  // A2: a cold start on a network that hangs, the businesses on the device.
  group('a cold start on a stalled network', () {
    test('an owner with the list on the device sees the home at once; the server is asked behind it', () async {
      await oldCode();
      await db.cacheOrgs(const [_shop]);
      final server = _Server()..hang = Completer<List<OrgSummary>>();
      final session = on(server, timeout: const Duration(seconds: 30));
      final clock = Stopwatch()..start();
      await session.boot();
      clock.stop();
      expect(session.phase, SessionPhase.ready);
      expect(session.lastOrgId, _shop.id);
      expect(session.orgsFromCache, isTrue);
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)),
          reason: 'no splash for the timeouts of a hanging network');
      // Behind the screen the list is asked; when it comes, the session is
      // current again.
      await Future<void>.delayed(Duration.zero);
      expect(server.asked, 1);
      server.hang!.complete(const [_shop, _farm]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.orgs.map((o) => o.id), containsAll([_shop.id, _farm.id]));
      expect(session.orgsFromCache, isFalse);
      session.dispose();
    });

    test('a platform admin below the second step: the home, then the code screen', () async {
      await oldCode();
      await db.cacheOrgs(const [_shop]);
      final step = _Step();
      final session = on(_Server(), step: step);
      await session.boot();
      // Settled first, then the background question moves it.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.phase, SessionPhase.twoStep);
      session.dispose();
    });

    test('with nothing on the device, the list is asked with the other questions, not after', () async {
      final server = _Server()..orgs = const [_shop];
      final step = _SlowStep(const Duration(milliseconds: 300));
      final session = on(server, step: step, timeout: const Duration(seconds: 5));
      await oldCode();
      final clock = Stopwatch()..start();
      final booting = session.boot();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // The second step is still being asked, and the list already was.
      expect(server.asked, 1);
      await booting;
      clock.stop();
      expect(session.phase, SessionPhase.ready);
      session.dispose();
    });
  });
}

/// The second step (077): required for this account until [passed].
class _Step extends TwoStep {
  _Step() : super(null);
  bool passed = false;
  @override
  Future<TwoStepStatus> status() async =>
      TwoStepStatus(required: true, enrolled: true, passed: passed);
}

/// A second step not required, answered slowly.
class _SlowStep extends TwoStep {
  _SlowStep(this.delay) : super(null);
  final Duration delay;
  @override
  Future<TwoStepStatus> status() async {
    await Future<void>.delayed(delay);
    return TwoStepStatus.none;
  }
}
