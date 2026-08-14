import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/home/home_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// That the colour actually arrives on the screen, and that it is a different
/// colour per business.
///
/// This is asserted rather than eyeballed because the failure mode is silent:
/// a `ProfileTheme` that is not in the tree, or a palette looked up above the
/// widget that provides it, leaves everything compiling, every test passing,
/// and every screen the same grey it was before.
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

  Future<Color> appBarColourFor(WidgetTester tester, String profile) async {
    tester.view.physicalSize = const Size(480, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: kajTheme(kajPalette),
      home: homeScreenFor(
        db: db,
        org: OrgSummary(id: 'org-$profile', name: 'Test', profile: profile),
      ),
    ));
    await tester.pump();

    final context = tester.element(find.byType(Scaffold).first);
    return Theme.of(context).appBarTheme.backgroundColor!;
  }

  group('a business is painted in its own colours', () {
    // One screen per test: each home screen kicks off an async refresh in
    // initState, and replacing the tree underneath a half-finished one is a
    // race, not an assertion.
    testWidgets('the farm is green', (tester) async {
      expect(await appBarColourFor(tester, 'farm'), farmPalette.hero.first);
    });

    testWidgets('the church is indigo', (tester) async {
      expect(await appBarColourFor(tester, 'church'), churchPalette.hero.first);
    });

    testWidgets('the shop is amber', (tester) async {
      expect(await appBarColourFor(tester, 'retail'), retailPalette.hero.first);
    });

    test('and no two of them are the same', () {
      // The whole point: somebody who runs two of these knows which is open
      // before reading a word.
      final heads = {
        farmPalette.hero.first,
        churchPalette.hero.first,
        retailPalette.hero.first,
        kajPalette.hero.first,
      };
      expect(heads.length, 4);
    });

    testWidgets('a profile this build has never heard of still opens',
        (tester) async {
      // Same tolerance homeScreenFor has always had. A profile added
      // server-side must not be able to brick an APK already installed.
      final unknown = await appBarColourFor(tester, 'quarry');
      expect(unknown, kajPalette.hero.first);
    });
  });

  group('the palette reaches the widgets that hand-paint with it', () {
    testWidgets('KajTheme.of finds the profile palette below the router',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: homeScreenFor(
          db: db,
          org: const OrgSummary(id: 'o', name: 'T', profile: 'farm'),
        ),
      ));
      await tester.pump();

      final context = tester.element(find.byType(Scaffold).first);
      expect(KajTheme.of(context), farmPalette);
    });

    testWidgets('outside a business it falls back rather than throwing',
        (tester) async {
      // Sign-in, the business picker and the console live above any
      // ProfileTheme. They must not need one.
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: (context) {
          expect(KajTheme.of(context), kajPalette);
          return const SizedBox();
        })),
      );
      await tester.pump();
    });
  });

  group('the palettes themselves', () {
    test('every one has a gradient of at least two stops', () {
      for (final palette in [
        farmPalette,
        churchPalette,
        retailPalette,
        kajPalette
      ]) {
        expect(palette.hero.length, greaterThanOrEqualTo(2));
        expect(palette.tints, isNotEmpty);
      }
    });

    test('tints rotate rather than running out', () {
      // Called with a position, not a meaning — so it must answer for any
      // index a row of shortcuts can reach.
      expect(farmPalette.tint(0), farmPalette.tints.first);
      expect(farmPalette.tint(farmPalette.tints.length), farmPalette.tints.first);
      expect(farmPalette.tint(99), isNotNull);
    });

    test('adjacent tiles never get the same colour', () {
      for (final palette in [farmPalette, churchPalette, retailPalette]) {
        for (var i = 0; i < palette.tints.length - 1; i++) {
          expect(palette.tint(i), isNot(palette.tint(i + 1)));
        }
      }
    });
  });
}
