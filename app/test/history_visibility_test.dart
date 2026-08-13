import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Who is offered the history, and who is not.
///
/// `journal_page` already refuses a summary observer server-side — it filters
/// on has_full_visibility, so they receive no rows however they ask. This is
/// the other half of that rule, and it is worth pinning separately: the server
/// decides what may be read, and the app decides what to offer. Offering a
/// screen that is guaranteed to be empty is not a security hole, but it is a
/// promise the app cannot keep, and the investor who taps it concludes the
/// books are empty rather than that they were never granted the lines.
///
/// The visibility read here is the one that came back from my_orgs() at login
/// and was cached with the org — never a role, and never something the device
/// decided for itself.
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

  /// The same alternation app_root_test uses, and for the same two reasons:
  /// widget tests run in a fake-async zone where sqflite's real background I/O
  /// never completes, and the loading spinner animates forever, so
  /// `pumpAndSettle` never returns.
  Future<void> flush(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    required String visibility,
    bool liveSession = true,
  }) async {
    final org = OrgSummary(
      id: 'org-1',
      name: 'Grace Chapel',
      profile: 'church',
      roles: const ['observer'],
      visibility: visibility,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChurchHomeScreen(
          db: db,
          orgId: org.id,
          orgName: org.name,
          org: org,
          // Null is what app_root passes with no live session; a callback is
          // what it passes with one.
          onHistory: liveSession ? () {} : null,
        ),
      ),
    );
    await flush(tester);
  }

  testWidgets('a member on full visibility is offered the history',
      (tester) async {
    await pumpHome(tester, visibility: 'full');

    expect(find.byTooltip('Historique'), findsOneWidget);
  });

  testWidgets('an observer on summary visibility is not', (tester) async {
    // Not hidden to keep a secret — the totals on the reports screen are still
    // theirs, and this is the same grant said consistently in both places.
    await pumpHome(tester, visibility: 'summary');

    expect(find.byTooltip('Historique'), findsNothing);
  });

  testWidgets('nor is anyone once the session has expired', (tester) async {
    // A null callback is what app_root passes with no live session. The list
    // is paged by the database; there is nothing offline to page through, and
    // an empty history would read as a lost one.
    await pumpHome(tester, visibility: 'full', liveSession: false);

    expect(find.byTooltip('Historique'), findsNothing);
  });
}
