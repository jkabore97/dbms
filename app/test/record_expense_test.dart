import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Recording an expense, driven through the screen rather than the method.
///
/// LocalDb.recordExpense() was already written and already tested. What was
/// never true until now is that anything called it — the "X dépensé" line on
/// the home screen had no way of ever being anything but zero. That is what
/// this file is about: not that the storage works, but that the button reaches
/// it and the total moves.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  const orgId = 'org-church';

  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });

  // sqflite keys open databases by path, so an in-memory database outlives the
  // test that opened it unless the connection is closed.
  tearDown(() => db.close());

  /// Widget tests run in a fake-async zone where sqflite's real background I/O
  /// never completes, so fake time and real time have to be alternated.
  Future<void> flush(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
  }

  Future<void> pumpHome(WidgetTester tester) async {
    // The default 800x600 test window is shorter than the sheet, which puts
    // the save button outside the viewport where a tap silently misses. A
    // tall, narrow window is both closer to the real device and hittable.
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ChurchHomeScreen(db: db, orgId: orgId, orgName: 'Grace Chapel'),
      ),
    );
    await flush(tester);
  }

  testWidgets('money in and money out are two separate buttons',
      (tester) async {
    await pumpHome(tester);

    // Not one button with a mode: both acts are reachable without a decision
    // hidden inside a sheet.
    expect(find.widgetWithText(FloatingActionButton, 'Recette'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Dépense'), findsOneWidget);
  });

  testWidgets('an expense recorded on screen moves the "dépensé" total',
      (tester) async {
    await pumpHome(tester);

    // Nothing spent yet, so the line is not drawn at all.
    expect(find.textContaining('dépensé'), findsNothing);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Dépense'));
    await flush(tester);

    // 5 then 000 — the keypad shortcut that exists because these are CFA
    // francs and the zeros are most of the typing.
    await tester.tap(find.widgetWithText(InkWell, '5'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, '000'));
    await tester.pump();

    await tester.tap(find.text('Loyer'));
    await tester.pump();

    await tester.tap(find.text('Enregistrer la dépense'));
    await flush(tester);

    // The books: one outgoing entry, and the day's total to match.
    final totals = await tester.runAsync(
      () => db.dayTotals(orgId, DateTime.now()),
    );
    expect(totals!.moneyOut, 5000);
    expect(totals.moneyIn, 0);

    // The screen: the line that could never appear before.
    expect(find.textContaining('dépensé'), findsOneWidget);

    // And the entry is listed under the category that was chosen, not a
    // free-text spelling of it.
    expect(find.text('Loyer'), findsOneWidget);
  });

  testWidgets('the expense is queued for the server, not just drawn locally',
      (tester) async {
    await pumpHome(tester);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Dépense'));
    await flush(tester);
    await tester.tap(find.widgetWithText(InkWell, '2'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, '000'));
    await tester.pump();
    await tester.tap(find.text('Enregistrer la dépense'));
    await flush(tester);

    final pending = await tester.runAsync(() => db.pendingActions());
    expect(pending!.length, 1);
    expect(pending.first['action'], 'record_expense');

    // The payload has to be what record_expense() in 002_church_profile.sql
    // takes, since SyncService posts it verbatim under that name.
    expect(pending.first['payload'], contains('p_expense_code'));
    expect(pending.first['payload'], contains('5050'));
  });
}
