import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Recording money, driven through the screen rather than the method.
///
/// Two things are under test and the second is what this file was rewritten
/// for.
///
///   1. The buttons reach the storage and the day's totals move. That was the
///      original point: LocalDb could always record an expense and, for a
///      while, nothing on screen ever called it, so the "X dépensé" line could
///      not be anything but zero however correct the storage was.
///
///   2. The name a person types is the name that gets saved, and it survives
///      all the way to the row in the day's list. The whole free-text change
///      is worthless if the label is dropped between the sheet and the
///      database, and that is exactly the kind of break that no analyzer and
///      no SQL test would catch.
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
    tester.view.physicalSize = const Size(480, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ChurchHomeScreen(db: db, orgId: orgId, orgName: 'Grace Chapel'),
      ),
    );
    await flush(tester);
  }

  /// Types an amount on the drawn keypad. `000` is one key because these are
  /// CFA francs and the zeros are most of the typing.
  Future<void> tapKeys(WidgetTester tester, List<String> keys) async {
    for (final key in keys) {
      await tester.tap(find.widgetWithText(InkWell, key));
      await tester.pump();
    }
  }

  testWidgets('money in, money out and a transfer are three separate buttons',
      (tester) async {
    await pumpHome(tester);

    // Not one button with a mode: the acts are reachable without a decision
    // hidden inside a sheet.
    expect(find.widgetWithText(FloatingActionButton, 'Recette'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Dépense'), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
  });

  testWidgets('an expense recorded on screen moves the "dépensé" total',
      (tester) async {
    await pumpHome(tester);

    // Nothing spent yet, so the line is not drawn at all.
    expect(find.textContaining('dépensé'), findsNothing);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Dépense'));
    await flush(tester);

    await tapKeys(tester, ['5', '000']);

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
  });

  testWidgets('the name typed on the sheet is the name that is saved',
      (tester) async {
    await pumpHome(tester);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Dépense'));
    await flush(tester);

    // The thing the old sheet could not do at all: there was no field, and
    // the entry could only ever be one of seven compiled-in categories.
    await tester.enterText(
      find.widgetWithText(TextField, "Nom de l'entrée"),
      'Réparation du toit',
    );
    await tester.pump();

    await tapKeys(tester, ['4', '5', '000']);
    await tester.tap(find.text('Enregistrer la dépense'));
    await flush(tester);

    final entries = await tester.runAsync(
      () => db.entriesForDay(orgId, DateTime.now()),
    );
    expect(entries!.single['label'], 'Réparation du toit');
    expect(entries.single['amount'], 45000);
    expect(entries.single['direction'], 'out');

    // And it reads back on the day's list in the words it was written in.
    expect(find.text('Réparation du toit'), findsOneWidget);
  });

  testWidgets('the details typed with an entry are kept', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Dépense'));
    await flush(tester);

    await tester.enterText(
      find.widgetWithText(TextField, "Nom de l'entrée"),
      'Ciment',
    );
    await tester.pump();

    // Folded away by default, so the fast path never sees it.
    expect(find.widgetWithText(TextField, 'Note'), findsNothing);
    await tester.tap(find.text('Détails'));
    await flush(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Note'),
      'Huit sacs, livrés lundi',
    );
    await tester.pump();

    await tester.tap(find.text('Ajouter une caractéristique'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quoi'),
      'Fournisseur',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Détail'),
      'Kaboré',
    );
    await tester.pump();

    await tapKeys(tester, ['3', '000']);
    await tester.tap(find.text('Enregistrer la dépense'));
    await flush(tester);

    final entries = await tester.runAsync(
      () => db.entriesForDay(orgId, DateTime.now()),
    );
    expect(entries!.single['memo'], 'Huit sacs, livrés lundi');
    expect(
      jsonDecode(entries.single['details'] as String),
      {'Fournisseur': 'Kaboré'},
    );
  });

  testWidgets('the entry is queued for the server, not just drawn locally',
      (tester) async {
    await pumpHome(tester);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Recette'));
    await flush(tester);

    await tester.enterText(
      find.widgetWithText(TextField, "Nom de l'entrée"),
      'Offrande du dimanche',
    );
    await tester.pump();

    await tapKeys(tester, ['2', '000']);
    await tester.tap(find.text('Enregistrer la recette'));
    await flush(tester);

    final pending = await tester.runAsync(() => db.pendingActions());
    expect(pending!.length, 1);
    expect(pending.first['action'], 'record_entry');

    // The payload has to be exactly what record_entry() in 007_accounting.sql
    // takes, since SyncService posts it verbatim under that name. A key
    // renamed on one side and not the other fails at the server, on a phone,
    // days later — which is why it is asserted here rather than trusted.
    final payload =
        jsonDecode(pending.first['payload'] as String) as Map<String, dynamic>;
    expect(payload['p_org_id'], orgId);
    expect(payload['p_amount'], 2000);
    expect(payload['p_direction'], 'in');
    expect(payload['p_label'], 'Offrande du dimanche');
    expect(payload['p_method'], 'cash');
    expect(payload.containsKey('p_client_uuid'), isTrue);
    expect(payload.containsKey('p_occurred_at'), isTrue);
  });

  testWidgets('a transfer moves money without becoming income or expense',
      (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byIcon(Icons.swap_horiz));
    await flush(tester);

    await tapKeys(tester, ['2', '0', '000']);
    await tester.tap(find.text('Enregistrer le transfert'));
    await flush(tester);

    // Listed, because somebody looking for "where did the 20,000 go" needs to
    // see it. Added to neither total, because moving money between two of your
    // own accounts is not a day's takings and not a day's spending.
    final totals = await tester.runAsync(
      () => db.dayTotals(orgId, DateTime.now()),
    );
    expect(totals!.moneyIn, 0);
    expect(totals.moneyOut, 0);

    final entries = await tester.runAsync(
      () => db.entriesForDay(orgId, DateTime.now()),
    );
    expect(entries!.single['direction'], 'transfer');
    expect(entries.single['amount'], 20000);

    final pending = await tester.runAsync(() => db.pendingActions());
    expect(pending!.first['action'], 'record_transfer');
  });
}
