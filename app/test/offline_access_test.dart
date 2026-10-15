import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A team member's access kept on the phone (the offline audit).
///
/// Before: the owner's dial (031) was asked each time a business opened and
/// kept nowhere, and an unanswered question read as « the defaults » — so
/// offline a cashier whose owner hid the carnet saw the carnet again.

/// The owner's dial as the server says it: [answer], a failure ([down]), or
/// a request taken and never answered ([stall]).
class _Dial extends AdminRepository {
  _Dial({this.answer = const {}, this.down = false, this.stall = false})
      : super(null);

  final Map<String, String> answer;
  final bool down;
  final bool stall;

  @override
  Future<bool> isPlatformAdmin() async => false;

  @override
  Future<Map<String, String>> featureRulesForTier(String orgId, String tier) {
    if (stall) return Completer<Map<String, String>>().future;
    if (down) return Future.error(const SocketException('Failed host lookup'));
    return Future.value(answer);
  }
}

/// Signed in, with the device code set: the resolve lands in the business.
const _me = LocalIdentity(userId: 'u1', pinSalt: 'salt', pinHash: 'hash');

const _cashier = OrgSummary(
    id: 'o1', name: 'Boutique Sanou', profile: 'retail', roles: ['cashier']);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
    await db.saveIdentity(_me);
  });
  tearDown(() => db.close());

  /// A phone opening with no live token: the device's list of businesses,
  /// as an offline cold start does.
  Future<SessionController> open(AdminRepository admin,
      {OrgSummary org = _cashier,
      Duration timeout = const Duration(milliseconds: 50)}) async {
    await db.cacheOrgs([org]);
    final session = SessionController(
      db: db,
      auth: AuthRepository(null),
      admin: admin,
      accounting: AccountingRepository(null),
      resolveTimeout: timeout,
    );
    addTearDown(session.dispose);
    await session.boot();
    // Unlocked with the code: the resolve the PIN screen starts.
    expect(session.phase, SessionPhase.locked);
    await session.unlock();
    expect(session.phase, SessionPhase.ready);
    return session;
  }

  /// The dial loaded (or given up on) for the auto-opened business.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 150));

  test('kept from the last answer: offline, the hidden tool stays hidden', () async {
    final online = await open(_Dial(answer: {'credits': 'hidden', 'reports': 'edit'}));
    await settle();
    expect(online.accessFor('o1').canSee('credits'), isFalse);

    // The next cold start, no signal.
    final offline = await open(_Dial(down: true));
    await settle();
    final access = offline.accessFor('o1');
    expect(access.canSee('credits'), isFalse,
        reason: 'before: the server\'s defaults, the carnet open again');
    expect(access.canEdit('reports'), isTrue, reason: 'the owner\'s own choice, kept');
    expect(access.canEdit('products'), isTrue);
  });

  test('a stalled server: the kept dial is drawn before the question gives up',
      () async {
    await open(_Dial(answer: {'credits': 'hidden'}));
    await settle();

    final stalled = await open(_Dial(stall: true),
        timeout: const Duration(milliseconds: 600));
    var emits = 0;
    stalled.addListener(() => emits++);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(stalled.accessFor('o1').canSee('credits'), isFalse,
        reason: 'the question is still out; the phone\'s copy is what shows');
    // And it stays so once the question has given up.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(stalled.accessFor('o1').canSee('credits'), isFalse);
    expect(emits, lessThanOrEqualTo(1), reason: 'drawn once, not on every step');
  });

  test('refreshed on every answer: an owner who opens the carnet again is heard',
      () async {
    await open(_Dial(answer: {'credits': 'hidden'}));
    await settle();
    await open(_Dial(answer: {'credits': 'edit'}));
    await settle();
    final offline = await open(_Dial(down: true));
    await settle();
    expect(offline.accessFor('o1').canEdit('credits'), isTrue);
  });

  test('nothing kept: the server\'s defaults — never everything open', () async {
    final offline = await open(_Dial(down: true));
    await settle();
    expect(offline.accessFor('o1').canEdit('reports'), isFalse,
        reason: 'reports default to view for a member');
  });

  test('another role is another dial: the kept one is not used for it', () async {
    await open(_Dial(answer: {'credits': 'hidden'}));
    await settle();
    final promoted = await open(_Dial(down: true),
        org: const OrgSummary(
            id: 'o1', name: 'Boutique Sanou', profile: 'retail', roles: ['manager']));
    await settle();
    expect(promoted.accessFor('o1').canSee('credits'), isTrue);
  });

  test('signing out forgets it, with the person', () async {
    final online = await open(_Dial(answer: {'credits': 'hidden'}));
    await settle();
    await online.signOut();
    final prefs = await db.readPref('${LocalDb.personalPrefPrefix}dial:o1:u1');
    expect(prefs, isNull);

    await db.saveIdentity(_me);
    final again = await open(_Dial(down: true));
    await settle();
    expect(again.accessFor('o1').canSee('credits'), isTrue,
        reason: 'nothing of before is left on the phone');
  });

  test('an unreachable server is a failure, not an untouched dial', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
      httpClient: MockClient((r) async => http.Response(
          jsonEncode({'code': '42P01', 'message': 'relation does not exist'}),
          404,
          headers: {'content-type': 'application/json'},
          request: r)),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    // Before: swallowed and answered {} — which the session could not tell
    // from an owner who never touched the dial.
    await expectLater(AdminRepository(client).featureRulesForTier('o1', 'employee'),
        throwsA(isA<PostgrestException>()));
  });
}
