import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The report, with a screenshot: the picker sat on "Chargement de vos
/// entreprises…" forever. A resolve's network calls had no timeout, so a
/// request that stalled — the socket open, the reply never coming, no error
/// ever raised — left the future pending and the app hung at `resolving`. Each
/// step is bounded now, and a stall is treated as a dead connection: fall back
/// to the list the device already cached rather than spinning without end.
class _HangingAuth extends AuthRepository {
  _HangingAuth() : super(null);

  @override
  bool get hasLiveSession => true;

  /// Never completes — the stalled socket the timeout exists for.
  @override
  Future<List<OrgSummary>> fetchOrgs() => Completer<List<OrgSummary>>().future;
}

class _FastAdmin extends AdminRepository {
  _FastAdmin() : super(null);

  @override
  Future<bool> isPlatformAdmin() async => false;

  @override
  Future<int> claimMyInvitations() async => 0;
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

  test('a stalled org fetch times out and falls back to the cached list',
      () async {
    await db.cacheOrgs(const [
      OrgSummary(
          id: 'o1', name: 'Boutique Sanou', profile: 'retail', roles: ['owner']),
    ]);

    final session = SessionController(
      db: db,
      auth: _HangingAuth(),
      admin: _FastAdmin(),
      accounting: AccountingRepository(null),
      // Tiny, so the test proves the fallback in milliseconds rather than
      // waiting out the real 12 seconds.
      resolveTimeout: const Duration(milliseconds: 50),
    );

    await session.resolveOrgs().timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              fail('resolveOrgs hung despite the per-call timeout'),
        );

    expect(session.phase, isNot(SessionPhase.resolving),
        reason: 'the resolve must settle, not hang on the spinner');
    expect(session.orgs.map((o) => o.id).toList(), ['o1'],
        reason: 'a stalled fetch should fall back to the cached businesses');
    expect(session.orgsFromCache, isTrue);
  });
}
