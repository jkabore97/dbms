import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Closing the day, and the streak that makes anyone bother twice.
///
/// The streak rule is the part worth testing carefully. It is a claim about a
/// person's habit, so getting it wrong is not a rounding error — a count that
/// resets while somebody was in fact closing every day tells them their effort
/// did not register, and they stop.
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
  tearDown(() => db.close());

  DateTime daysAgo(int n) => DateTime.now().subtract(Duration(days: n));

  group('the streak', () {
    test('is zero before anything has been closed', () async {
      expect(await db.closureStreak(orgId), 0);
    });

    test('counts consecutive days back from today', () async {
      for (var i = 0; i < 4; i++) {
        await db.closeDay(orgId, daysAgo(i), moneyIn: 0, moneyOut: 0);
      }
      expect(await db.closureStreak(orgId), 4);
    });

    test('survives today not being closed yet', () async {
      // The day is not over. Someone who closed yesterday and the day before
      // is on a streak of two, not zero, until they actually miss a day.
      await db.closeDay(orgId, daysAgo(1), moneyIn: 0, moneyOut: 0);
      await db.closeDay(orgId, daysAgo(2), moneyIn: 0, moneyOut: 0);
      expect(await db.closureStreak(orgId), 2);
    });

    test('breaks on a missed day and counts only what follows it', () async {
      await db.closeDay(orgId, daysAgo(0), moneyIn: 0, moneyOut: 0);
      await db.closeDay(orgId, daysAgo(1), moneyIn: 0, moneyOut: 0);
      // Nothing on day 2.
      await db.closeDay(orgId, daysAgo(3), moneyIn: 0, moneyOut: 0);
      await db.closeDay(orgId, daysAgo(4), moneyIn: 0, moneyOut: 0);
      expect(await db.closureStreak(orgId), 2);
    });

    test('closing the same day twice is still one day', () async {
      await db.closeDay(orgId, daysAgo(0), moneyIn: 100, moneyOut: 0);
      await db.closeDay(orgId, daysAgo(0), moneyIn: 250, moneyOut: 50);
      expect(await db.closureStreak(orgId), 1);
      expect(await db.isDayClosed(orgId, DateTime.now()), isTrue);
    });

    test('belongs to one business, not to the device', () async {
      // Israel keeps two sets of books. Closing the church does not close the
      // farm, and neither streak may borrow from the other.
      await db.closeDay(orgId, daysAgo(0), moneyIn: 0, moneyOut: 0);
      await db.closeDay(orgId, daysAgo(1), moneyIn: 0, moneyOut: 0);

      expect(await db.closureStreak(orgId), 2);
      expect(await db.closureStreak('org-farm'), 0);
      expect(await db.isDayClosed('org-farm', DateTime.now()), isFalse);
    });
  });

  group('the screen', () {
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

    testWidgets('closing the day from the home screen records it and shows '
        'the day as closed', (tester) async {
      await pumpHome(tester);

      expect(find.text('Clôturer la journée'), findsOneWidget);
      expect(find.text('Journée clôturée'), findsNothing);

      await tester.tap(find.text('Clôturer la journée'));
      await flush(tester);

      // The sheet restates the day before anyone agrees to it.
      expect(find.text('Reçu'), findsOneWidget);
      expect(find.text('Dépensé'), findsOneWidget);
      expect(find.text('Solde du jour'), findsOneWidget);
      expect(find.text('Premier jour clôturé'), findsOneWidget);

      await tester.tap(find.text('Clôturer la journée').last);
      await flush(tester);

      final closed = await tester.runAsync(
        () => db.isDayClosed(orgId, DateTime.now()),
      );
      expect(closed, isTrue);

      // And the home screen says so rather than inviting the same tap again.
      //
      // Matched on the button rather than on the words, because the
      // confirmation snackbar says the same thing and is still on screen: two
      // widgets reading "Journée clôturée" is the correct state here, and an
      // assertion that cannot tell them apart is testing the timing of a
      // snackbar rather than the button it means to test.
      expect(
        find.widgetWithText(OutlinedButton, 'Journée clôturée'),
        findsOneWidget,
      );
    });

    testWidgets('the sheet reports the day it is closing', (tester) async {
      await tester.runAsync(() async {
        await db.recordEntry(
          orgId: orgId,
          amount: 20000,
          direction: 'in',
          label: 'Offrande du dimanche',
          category: 'Offerings',
        );
        await db.recordEntry(
          orgId: orgId,
          amount: 5000,
          direction: 'out',
          label: 'Loyer de mars',
          category: 'Rent',
        );
      });

      await pumpHome(tester);
      await tester.tap(find.text('Clôturer la journée'));
      await flush(tester);

      // Two entries, and the two that have not left the device yet.
      expect(find.text('2'), findsWidgets);
      expect(find.text('Tout est envoyé'), findsNothing);
    });
  });
}
