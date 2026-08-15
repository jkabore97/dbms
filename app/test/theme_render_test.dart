import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/l10n/strings.dart';
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
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
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
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
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
        MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
        home: Builder(builder: (context) {
          expect(KajTheme.of(context), kajPalette);
          return const SizedBox();
        })),
      );
      await tester.pump();
    });
  });

  group('everything painted on a palette can actually be read', () {
    // These are measured, not eyeballed. The first version of this theme put
    // white text on saturated gradients and shipped four tile colours whose
    // white icon was invisible; nothing caught it because nothing asked.
    double luminance(Color c) {
      double channel(double v) =>
          v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
      return 0.2126 * channel(c.r) +
          0.7152 * channel(c.g) +
          0.0722 * channel(c.b);
    }

    double contrast(Color a, Color b) {
      final la = luminance(a), lb = luminance(b);
      final hi = math.max(la, lb), lo = math.min(la, lb);
      return (hi + 0.05) / (lo + 0.05);
    }

    /// What a colour at [alpha] over a white card actually looks like.
    Color over(Color c, double alpha) => Color.alphaBlend(
        c.withValues(alpha: alpha), const Color(0xFFFFFFFF));

    test('the ink is readable on both ends of its own hero gradient', () {
      // `allPalettes`, not a hand-kept list: a palette added to the app is
      // measured by this the moment it exists. A list repeated here would go
      // stale silently, and the failure it would miss is an unreadable
      // screen somebody chose on purpose.
      for (final palette in allPalettes) {
        for (final stop in palette.hero) {
          final ratio = contrast(palette.ink, stop);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: 'ink on a hero stop measured '
                  '\${ratio.toStringAsFixed(2)}:1 — small labels sit here');
        }
      }
    });

    test('every tile icon is readable on its own tinted chip', () {
      // `allPalettes`, not a hand-kept list: a palette added to the app is
      // measured by this the moment it exists. A list repeated here would go
      // stale silently, and the failure it would miss is an unreadable
      // screen somebody chose on purpose.
      for (final palette in allPalettes) {
        for (final tint in palette.tints) {
          final ratio = contrast(tint, over(tint, 0.14));
          expect(ratio, greaterThanOrEqualTo(3.0),
              reason: 'an icon on its chip measured '
                  '\${ratio.toStringAsFixed(2)}:1');
        }
      }
    });

    test('the ink carries the invoice, which is printed on white paper', () {
      // `allPalettes`, not a hand-kept list: a palette added to the app is
      // measured by this the moment it exists. A list repeated here would go
      // stale silently, and the failure it would miss is an unreadable
      // screen somebody chose on purpose.
      for (final palette in allPalettes) {
        expect(contrast(palette.ink, const Color(0xFFFFFFFF)),
            greaterThanOrEqualTo(4.5));
      }
    });

    test('the hero stops really are pale, not merely different', () {
      // Guards the direction of the fix: somebody re-saturating these would
      // reintroduce the unreadable white text the ink replaced.
      // `allPalettes`, not a hand-kept list: a palette added to the app is
      // measured by this the moment it exists. A list repeated here would go
      // stale silently, and the failure it would miss is an unreadable
      // screen somebody chose on purpose.
      for (final palette in allPalettes) {
        for (final stop in palette.hero) {
          expect(luminance(stop), greaterThan(0.6),
              reason: 'a hero stop is too dark to be a wash');
        }
      }
    });
  });

  group('the palettes themselves', () {
    test('every one has a gradient of at least two stops', () {
      // `allPalettes`, not a hand-kept list: a palette added to the app is
      // measured by this the moment it exists. A list repeated here would go
      // stale silently, and the failure it would miss is an unreadable
      // screen somebody chose on purpose.
      for (final palette in allPalettes) {
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
      for (final palette in allPalettes) {
        for (var i = 0; i < palette.tints.length - 1; i++) {
          expect(palette.tint(i), isNot(palette.tint(i + 1)));
        }
      }
    });

    test('every palette is offerable: named, labelled and unique', () {
      // The name is what goes in the database and what an old build reads
      // back years later, so a duplicate or an empty one is not cosmetic —
      // it is a business that cannot be given back the colour it chose.
      final names = allPalettes.map((p) => p.name).toSet();
      expect(names.length, allPalettes.length,
          reason: 'two palettes share a name');
      for (final palette in allPalettes) {
        expect(palette.name, isNotEmpty);
        expect(palette.label, isNotEmpty);
        // The same slug rule the database enforces in 022. A name this side
        // that the server would refuse is a save button that never works.
        expect(RegExp(r'^[a-z][a-z0-9-]{1,31}$').hasMatch(palette.name), isTrue,
            reason: '"${palette.name}" would be refused by set_org_theme()');
      }
    });
  });

  group('what a business is painted in', () {
    test('a chosen palette beats the profile', () {
      expect(paletteFor('farm', theme: 'ocean'), oceanPalette);
      expect(paletteFor('church', theme: 'savane'), savanePalette);
    });

    test('choosing nothing leaves the profile deciding', () {
      // The old behaviour, and what every business has until somebody opens
      // the colour screen. Both spellings of "nothing" have to work: the
      // server stores null, and a cleared picker can send an empty string.
      expect(paletteFor('farm'), farmPalette);
      expect(paletteFor('farm', theme: null), farmPalette);
      expect(paletteFor('farm', theme: ''), farmPalette);
      expect(paletteFor('retail'), retailPalette);
    });

    test('a palette this build has never heard of falls back, not fails', () {
      // The forward-compatibility 022 was written for: the server accepts any
      // slug so a newer app can offer a new colour, which means an older APK
      // will meet names it does not know. It must land on the profile's
      // colour rather than on no colour at all.
      expect(paletteFor('farm', theme: 'couleur-de-2030'), farmPalette);
      expect(paletteFor('church', theme: 'nonsense'), churchPalette);
      // And an unknown palette on an unknown profile still resolves.
      expect(paletteFor('quarry', theme: 'nonsense'), kajPalette);
    });

    test('paletteNamed answers null rather than guessing', () {
      expect(paletteNamed('ocean'), oceanPalette);
      expect(paletteNamed('nope'), isNull);
      expect(paletteNamed(null), isNull);
      expect(paletteNamed(''), isNull);
    });

    test('every name in the registry round-trips', () {
      // What the picker writes, the app must be able to read back.
      for (final palette in allPalettes) {
        expect(paletteNamed(palette.name), palette);
      }
    });
  });
}
