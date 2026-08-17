import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/features/farm/farm_sheets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The Récolte sheet, now crops only.
///
/// Egg collection was removed: eggs are kept as ordinary stock (Réception /
/// Stock) like anything else the farm stores, so this sheet no longer offers
/// an "Œufs" subject, egg grades, or the offline outbox path. A crop cycle
/// lives on the server, so with no `FarmRepository` (a phone at the field gate
/// with no signal) there is nothing to list — and the sheet says so rather
/// than showing a keypad wired to nothing.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;

  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Scaffold(
        // No FarmRepository: offline, so no crop list can be fetched.
        body: RecordHarvestSheet(db: db, orgId: 'org-farm'),
      ),
    ));
    await tester.pump();
  }

  testWidgets('the sheet is called Récolte, not Ramassage', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Récolte'), findsOneWidget);
    expect(find.text('Ramassage'), findsNothing);
  });

  testWidgets('egg collection is gone from the sheet', (tester) async {
    await pumpSheet(tester);
    // No egg subject, no egg unit, no egg grade.
    expect(find.text('Œufs'), findsNothing);
    expect(find.text('œufs'), findsNothing);
    expect(find.text('Fêlé'), findsNothing);
  });

  testWidgets('with no signal and no crops, it says there is nothing to gather',
      (tester) async {
    await pumpSheet(tester);
    expect(find.textContaining('Rien à récolter'), findsOneWidget);
    // No keypad wired to nothing, and nothing to save.
    expect(find.text('Enregistrer la récolte'), findsNothing);
  });

  testWidgets('nothing is written to the outbox — eggs no longer record here',
      (tester) async {
    await pumpSheet(tester);
    final pending = await tester.runAsync(() => db.pendingActions());
    expect(pending, isEmpty);
  });
}
