import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Recording money, driven through the screen rather than the method —
/// since 115 through « Recette » and « Dépense », one question a screen.
///
///   1. The buttons reach the storage and the day's totals move.
///   2. The words a person gives are the words that get saved, and they
///      survive all the way to the row in the day's list.
///   3. What reaches the outbox is exactly record_entry()'s shape (007).
///   4. No church word is offered to an association (the owner's decision).
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
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
        home: ChurchHomeScreen(db: db, orgId: orgId, orgName: 'Grace Chapel'),
      ),
    );
    await flush(tester);
  }

  /// Types an amount on the drawn keypad (the transfer sheet keeps it).
  Future<void> tapKeys(WidgetTester tester, List<String> keys) async {
    for (final key in keys) {
      await tester.tap(find.widgetWithText(InkWell, key));
      await tester.pump();
    }
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('flow-next')));
    await flush(tester, rounds: 2);
  }

  /// « Dépense »: a heading, the amount, the method, a word — saved, closed.
  Future<void> spend(WidgetTester tester,
      {required String heading, required String amount, String? word, String? other, String? memo}) async {
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Dépense'));
    await flush(tester);
    await tester.tap(find.byKey(Key('heading-$heading')));
    await tester.pump();
    await next(tester);
    if (other != null) {
      await tester.enterText(find.byKey(const Key('expense-other')), other);
      await tester.pump();
      await next(tester);
    }
    await tester.enterText(find.byKey(const Key('expense-amount')), amount);
    await tester.pump();
    await next(tester);
    await next(tester); // Espèces
    if (word != null) {
      await tester.enterText(find.byKey(const Key('expense-note')), word);
      await tester.pump();
    }
    await next(tester); // the word, optional
    if (memo != null) {
      await tester.enterText(find.byKey(const Key('expense-memo')), memo);
      await tester.pump();
    }
    await next(tester); // the note, optional; no photo step without uploads
    expect(find.byKey(const Key('flow-summary')), findsOneWidget);
    await tester.tap(find.byKey(const Key('flow-save')));
    await flush(tester);
    expect(find.byKey(const Key('flow-done')), findsOneWidget);
    await tester.tap(find.byKey(const Key('flow-finish')));
    await flush(tester);
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

  testWidgets('an expense recorded through the flow moves the "dépensé" total',
      (tester) async {
    await pumpHome(tester);

    // Nothing spent yet, so the line is not drawn at all.
    expect(find.textContaining('dépensé'), findsNothing);

    await spend(tester, heading: 'Loyer', amount: '5000');

    final totals = await tester.runAsync(
      () => db.dayTotals(orgId, DateTime.now()),
    );
    expect(totals!.moneyOut, 5000);
    expect(totals.moneyIn, 0);

    // The screen: the day's line, back on the home.
    expect(find.textContaining('dépensé'), findsOneWidget);
  });

  testWidgets('the word typed is the name that is saved, the heading its account',
      (tester) async {
    await pumpHome(tester);

    await spend(tester, heading: 'Entretien', amount: '45000', word: 'Réparation du toit',
        memo: 'Payé à Issa le maçon');

    final entries = await tester.runAsync(
      () => db.entriesForDay(orgId, DateTime.now()),
    );
    expect(entries!.single['label'], 'Réparation du toit');
    expect(entries.single['category'], 'Entretien');
    expect(entries.single['amount'], 45000);
    expect(entries.single['direction'], 'out');
    // The note apart from the name (batch 115), as the old sheet kept it.
    expect(entries.single['memo'], 'Payé à Issa le maçon');

    // And it reads back on the day's list in the words it was written in.
    expect(find.text('Réparation du toit'), findsOneWidget);
  });

  testWidgets('« Autre » names a new heading: it is the account and the name',
      (tester) async {
    await pumpHome(tester);

    await spend(tester, heading: '__other__', amount: '3000', other: 'Ciment');

    final pending = await tester.runAsync(() => db.pendingActions());
    final payload =
        jsonDecode(pending!.single['payload'] as String) as Map<String, dynamic>;
    expect(payload['p_label'], 'Ciment');
    expect(payload['p_category'], 'Ciment');
    expect(payload['p_direction'], 'out');
  });

  testWidgets('a contribution is queued for the server, in record_entry\'s words',
      (tester) async {
    await pumpHome(tester);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Recette'));
    await flush(tester);
    await tester.tap(find.byKey(const Key('flow-option-cotisation')));
    await tester.pump();
    await next(tester);
    // Who: typed (no members list in this build).
    await tester.enterText(find.byKey(const Key('income-who')), 'Awa Ouédraogo');
    await tester.pump();
    await next(tester);
    await tester.enterText(find.byKey(const Key('income-amount')), '2000');
    await tester.pump();
    await next(tester);
    await tester.tap(find.byKey(const Key('flow-option-mobile_money')));
    await tester.pump();
    await next(tester);
    // The note, apart from the name (batch 115).
    await tester.enterText(find.byKey(const Key('income-memo')), 'Cotisation d\'octobre');
    await tester.pump();
    await next(tester);
    await tester.tap(find.byKey(const Key('flow-save')));
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
    expect(payload['p_label'], 'Cotisation — Awa Ouédraogo');
    expect(payload['p_category'], 'Cotisations');
    expect(payload['p_method'], 'mobile_money');
    expect(payload['p_member_id'], isNull);
    expect(payload['p_details'], {'De la part de': 'Awa Ouédraogo'});
    expect(payload['p_memo'], 'Cotisation d\'octobre');
    expect(payload.containsKey('p_client_uuid'), isTrue);
    expect(payload.containsKey('p_occurred_at'), isTrue);

    final entries = await tester.runAsync(() => db.entriesForDay(orgId, DateTime.now()));
    expect(entries!.single['member_name'], 'Awa Ouédraogo');
  });

  testWidgets('no church word is offered to an association — even with the seeded chart',
      (tester) async {
    // The chart 002 seeds for an association (and a legacy church).
    await tester.runAsync(() => db.cacheAccounts(orgId, [
          for (final (code, name) in [
            ('4000', 'Tithes'),
            ('4010', 'Offerings'),
            ('4020', 'Special Collections'),
            ('4030', 'Donations'),
            ('4040', 'Location de la salle'),
          ])
            {'account_id': 'a$code', 'code': code, 'name': name, 'type': 'income', 'is_active': true},
        ]));
    await pumpHome(tester);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Recette'));
    await flush(tester);
    for (final word in ['Offrande', 'Offrandes', 'Dîme', 'Dîmes', 'Quête', 'Collectes spéciales']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
    await tester.tap(find.byKey(const Key('flow-option-autre')));
    await tester.pump();
    await next(tester);
    // « Autre »: what the association named itself is offered back; the
    // church headings are not.
    expect(find.widgetWithText(ChoiceChip, 'Location de la salle'), findsOneWidget);
    for (final word in ['Offrandes', 'Dîmes', 'Collectes spéciales', 'Dons']) {
      expect(find.widgetWithText(ChoiceChip, word), findsNothing, reason: word);
    }
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
