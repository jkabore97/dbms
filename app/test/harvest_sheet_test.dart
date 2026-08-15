import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/features/farm/farm_sheets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The sheet that used to be "Ramassage" and only knew about eggs.
///
/// The rename to "Récolte" is not a string change. The screen previously had
/// one hardcoded subject, so a market gardener lifting tomatoes and a goat
/// keeper opened the app every morning and were asked how many eggs they had
/// collected. What is being gathered is now a question, and these are the
/// cases that question has to survive.
///
/// No `FarmRepository` anywhere in this file, on purpose — same reason as
/// `farm_offline_test.dart`. This is a phone at the farm gate: the crop list
/// lives on the server and cannot be fetched, and the egg path must still work
/// exactly as it always did.
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

  Future<void> pumpSheet(
    WidgetTester tester, {
    bool hasPoultry = true,
    List<Map<String, Object?>> flocks = const [],
  }) async {
    tester.view.physicalSize = const Size(480, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Scaffold(
        body: RecordHarvestSheet(
          db: db,
          orgId: 'org-farm',
          hasPoultry: hasPoultry,
          flocks: flocks,
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> tapKeys(WidgetTester tester, List<String> keys) async {
    for (final key in keys) {
      await tester.tap(find.widgetWithText(InkWell, key));
      await tester.pump();
    }
  }

  group('what is being gathered', () {
    testWidgets('the sheet is called Récolte, not Ramassage', (tester) async {
      await pumpSheet(tester);
      expect(find.text('Récolte'), findsOneWidget);
      expect(find.text('Ramassage'), findsNothing);
    });

    testWidgets('a poultry farm is not asked a question it has one answer to',
        (tester) async {
      // One thing to gather means nothing to choose. Making Ignace confirm
      // "eggs" every morning would be a step added, not a choice offered.
      await pumpSheet(tester);
      expect(find.text('Que récoltez-vous ?'), findsNothing);
      expect(find.text('œufs'), findsOneWidget);
    });

    testWidgets('a farm with no birds and no signal is told what to do',
        (tester) async {
      // The case the old sheet could not express at all: nothing to collect
      // yet. Better than a keypad wired to nothing.
      await pumpSheet(tester, hasPoultry: false);
      expect(find.textContaining('Rien à récolter'), findsOneWidget);
      expect(find.text('Enregistrer la récolte'), findsNothing);
    });
  });

  group('the egg path is unchanged by the rename', () {
    testWidgets('records through the outbox with no server', (tester) async {
      await pumpSheet(tester);

      await tapKeys(tester, ['4', '0', '4']);
      await tester.tap(find.text('Enregistrer la récolte'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final day = await tester.runAsync(
        () => db.farmDay('org-farm', DateTime.now()),
      );
      expect(day!.eggs, 404);

      final pending = await tester.runAsync(() => db.pendingActions());
      expect(pending!.single['action'], 'record_eggs');
    });

    testWidgets('production is not revenue', (tester) async {
      await pumpSheet(tester);

      await tapKeys(tester, ['1', '2', '0']);
      await tester.tap(find.text('Enregistrer la récolte'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Harvesting is not earning. The money arrives at the sale, and
      // counting it here would be the oldest bookkeeping mistake there is.
      final totals = await tester.runAsync(
        () => db.dayTotals('org-farm', DateTime.now()),
      );
      expect(totals!.moneyIn, 0);
    });

    testWidgets('the grades offered are egg grades', (tester) async {
      await pumpSheet(tester);
      expect(find.text('Fêlé'), findsOneWidget);
      // Crop grades belong to a crop, and must not appear against eggs.
      expect(find.text('Premier choix'), findsNothing);
    });

    testWidgets('nothing saves until a number is entered', (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.text('Enregistrer la récolte'));
      await tester.pump();

      final pending = await tester.runAsync(() => db.pendingActions());
      expect(pending, isEmpty);
    });
  });
}
