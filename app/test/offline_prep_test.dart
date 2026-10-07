import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/offline/offline_prep.dart';
import 'package:kaj_app/features/offline/offline_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Offline on request (the owner: « ask the user after a business creation
/// if they want to be able to use the app offline, then show them a button
/// that will download components »): asked once of a business's admin,
/// never of anybody else; the button prepares each step and says so.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const owner = OrgSummary(
      id: 'o1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);
  const clerk = OrgSummary(
      id: 'o1', name: 'Boutique Awa', profile: 'retail', roles: ['employee']);

  test('asked once, of an admin only', () async {
    final db = await LocalDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    final prep = OfflinePrep(db: db);
    expect(await prep.shouldAsk(clerk), isFalse);
    expect(await prep.shouldAsk(owner), isTrue);
    await prep.markAsked(owner);
    expect(await prep.shouldAsk(owner), isFalse);
  });

  testWidgets('« Oui », then the button, then every step ticked',
      (tester) async {
    late LocalDb db;
    await tester.runAsync(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });
    addTearDown(db.close);
    var charts = 0;
    final prep = OfflinePrep(
        db: db, cacheChart: (_) async => charts++);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: OfflineSheet(org: owner, prep: prep)),
    ));
    expect(find.text('Utiliser Mara sans connexion ?'), findsOneWidget);
    expect(find.byKey(const Key('offline-download')), findsNothing,
        reason: 'the question comes before the button');
    await tester.tap(find.byKey(const Key('offline-yes')));
    await tester.pump();
    // On Android (and here) the app is installed: one step, the accounts.
    expect(find.byKey(const Key('offline-step-accounts')), findsOneWidget);
    expect(find.byKey(const Key('offline-step-app')), findsNothing);
    await tester.tap(find.byKey(const Key('offline-download')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(charts, 1);
    expect(find.text('Prêt : Mara fonctionne sans connexion'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.runAsync(() async {
      expect(await prep.readyAt(), isNotNull);
      expect(await prep.shouldAsk(owner), isFalse);
    });
  });

  testWidgets('a step without signal says « Presque prêt » and offers again',
      (tester) async {
    late LocalDb db;
    await tester.runAsync(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });
    addTearDown(db.close);
    final prep = OfflinePrep(
        db: db, cacheChart: (_) async => throw Exception('no signal'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: OfflineSheet(org: owner, prep: prep, askFirst: false)),
    ));
    await tester.tap(find.byKey(const Key('offline-download')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text('Presque prêt'), findsOneWidget);
    expect(find.byKey(const Key('offline-retry')), findsOneWidget);
  });
}
