import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/offline/offline_app.dart';
import 'package:kaj_app/core/offline/offline_prep.dart';
import 'package:kaj_app/features/offline/offline_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Batch 149: on the web, unsent sales live in IndexedDB, which a browser
/// may clear (Safari after seven days without a visit). The browser is
/// asked to keep it — navigator.storage.persist() — at the opt-in tap, and
/// once at an opening of a prepared device; never more than once a week,
/// never once it said yes, never off the web.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const owner = OrgSummary(
      id: 'o1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);

  test('off the web there is nothing to ask: the storage is already kept', () async {
    expect(await OfflineApp.storageKept, isTrue);
    expect(await OfflineApp.keepStorage(), isTrue);
  });

  testWidgets('« Télécharger pour hors ligne » asks the browser, within the tap',
      (tester) async {
    late LocalDb db;
    await tester.runAsync(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });
    addTearDown(db.close);
    var asked = 0;
    final prep = OfflinePrep(
        db: db, cacheChart: (_) async {}, keepStorage: () async => ++asked > 0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: OfflineSheet(org: owner, prep: prep, askFirst: false)),
    ));
    await tester.tap(find.byKey(const Key('offline-download')));
    // Nothing awaited yet: the browser sees the person's gesture.
    expect(asked, 1);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(asked, 1);
    expect(find.text('Prêt : Mara fonctionne sans connexion'), findsOneWidget);
  });

  test('a browser that never answers does not hold the preparation', () async {
    final db = await LocalDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    var charts = 0;
    final prep = OfflinePrep(
        db: db,
        cacheChart: (_) async => charts++,
        // Firefox's question, left on screen.
        keepStorage: () => Future<bool>.delayed(const Duration(days: 1), () => true));
    final failed = await prep.prepare(owner);
    expect(failed, isEmpty);
    expect(charts, 1);
  });

  group('at an opening', () {
    late LocalDb db;
    var asked = 0;
    var kept = false;
    var clock = DateTime(2026, 10, 1, 9);

    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
      asked = 0;
      kept = false;
      clock = DateTime(2026, 10, 1, 9);
    });
    tearDown(() => db.close());

    OfflinePrep prep() => OfflinePrep(
          db: db,
          cacheChart: (_) async {},
          keepStorage: () async {
            asked++;
            return false;
          },
          storageKept: () async => kept,
          now: () => clock,
        );

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    test('a device that never chose offline is not asked', () async {
      await prep().keepStorageAtStartup();
      await settle();
      expect(asked, 0);
    });

    test('a prepared device is asked once, then not again for a week', () async {
      await prep().prepare(owner); // the opt-in: asked once
      await settle();
      expect(asked, 1);
      clock = clock.add(const Duration(days: 1));
      await prep().keepStorageAtStartup();
      await settle();
      expect(asked, 1, reason: 'asked yesterday: no prompt again');
      clock = clock.add(const Duration(days: 7));
      await prep().keepStorageAtStartup();
      await settle();
      expect(asked, 2, reason: 'a week on, the browser is asked again');
      await prep().keepStorageAtStartup();
      await settle();
      expect(asked, 2, reason: 'and not twice in a row');
    });

    test('once the browser promised, it is never asked again', () async {
      await prep().prepare(owner);
      await settle();
      kept = true;
      clock = clock.add(const Duration(days: 30));
      await prep().keepStorageAtStartup();
      await settle();
      expect(asked, 1);
    });

    test('a browser that throws changes nothing', () async {
      await prep().prepare(owner);
      clock = clock.add(const Duration(days: 30));
      final throwing = OfflinePrep(
          db: db,
          keepStorage: () => throw StateError('no storage manager'),
          storageKept: () async => throw StateError('no storage manager'));
      await throwing.keepStorageAtStartup();
      expect(await throwing.prepare(owner), isEmpty);
    });
  });
}
