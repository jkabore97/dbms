import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/admin/org_colours_screen.dart';

/// The colour picker, from the point of view of the person using it.
///
/// Runs against `AdminRepository(null)`, so nothing reaches the network. What
/// is asserted here is everything that happens before the save: which option
/// is shown as current, whether tapping one actually previews it, and — the
/// one that matters most — whether the save button can be pressed when there
/// is nothing to save.
///
/// That last one is not fussiness. This screen writes a setting every member
/// of the business sees, and a save button that is live on arrival invites
/// somebody to "confirm" a colour they never chose, which on a slow connection
/// is a spinner and a failure for no reason at all.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required String profile,
    String? current,
  }) async {
    // Tall enough that every card is built. A `ListView` only builds what is
    // near the viewport, and a test that scrolls to reach an option would be
    // asserting the scroll as much as the choice.
    tester.view.physicalSize = const Size(480, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: OrgColoursScreen(
        admin: AdminRepository(null),
        orgId: 'org-1',
        profile: profile,
        current: current,
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The save button's own callback rather than its colour: a button painted
  /// as disabled while still firing would pass a pixel check and still write.
  ///
  /// Found by type, not by its label — the label is itself state here
  /// ("Enregistrer" vs "Enregistré"), so matching on the text would make
  /// every assertion below depend on the wording it is not testing.
  VoidCallback? saveCallback(WidgetTester tester) {
    return tester.widget<FilledButton>(find.byType(FilledButton)).onPressed;
  }

  testWidgets('every palette is offered, plus the profile default',
      (tester) async {
    await pump(tester, profile: 'retail');

    expect(find.text('Couleur par défaut'), findsOneWidget);
    // Named by their labels, so somebody can ask a colleague for "Océan" down
    // the phone and be understood.
    for (final palette in allPalettes) {
      expect(find.text(palette.label), findsOneWidget,
          reason: '${palette.name} is not offerable');
    }
  });

  testWidgets('the default is what a business that never chose sees',
      (tester) async {
    await pump(tester, profile: 'farm');

    // Nothing to save on arrival: this business is already the colour the
    // screen is showing.
    expect(saveCallback(tester), isNull);
  });

  testWidgets('arriving with a colour already chosen shows it as chosen',
      (tester) async {
    await pump(tester, profile: 'farm', current: 'ocean');

    // Still nothing to save — the state on screen matches the server.
    expect(saveCallback(tester), isNull);

    // And the screen is wearing it: the app bar takes the chosen palette, not
    // the farm's green, so the preview is the whole frame and not a swatch.
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).colorScheme.primary,
        oceanPalette.ink);
  });

  testWidgets('choosing a different colour arms the save button',
      (tester) async {
    await pump(tester, profile: 'farm');

    await tester.tap(find.text('Prune'));
    await tester.pumpAndSettle();

    expect(saveCallback(tester), isNotNull,
        reason: 'a change was made and cannot be saved');

    // The preview follows immediately, before anything is written: the point
    // of the screen is deciding by looking, not by saving and then judging.
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).colorScheme.primary,
        prunePalette.ink);
  });

  testWidgets('going back to the colour already saved disarms it again',
      (tester) async {
    await pump(tester, profile: 'farm', current: 'ocean');

    await tester.tap(find.text('Savane'));
    await tester.pumpAndSettle();
    expect(saveCallback(tester), isNotNull);

    // Changed their mind. Nothing differs from the server now, so there is
    // nothing to write — and writing it anyway would be a round trip and a
    // possible failure in exchange for no change at all.
    await tester.tap(find.text('Océan'));
    await tester.pumpAndSettle();
    expect(saveCallback(tester), isNull);
  });

  testWidgets('clearing back to the default is itself a change',
      (tester) async {
    // The way back. A business that tried a colour and wants its own back
    // must be able to say so, and that is a save like any other.
    await pump(tester, profile: 'retail', current: 'ardoise');
    expect(saveCallback(tester), isNull);

    await tester.tap(find.text('Couleur par défaut'));
    await tester.pumpAndSettle();

    expect(saveCallback(tester), isNotNull);
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).colorScheme.primary,
        retailPalette.ink);
  });

  testWidgets('a colour this build does not know shows as the default',
      (tester) async {
    // An APK older than the palette its own business chose. It cannot draw
    // that colour, so it must show the truth it can draw rather than an
    // empty selection — and the save button must stay quiet, because the
    // person has changed nothing.
    await pump(tester, profile: 'church', current: 'couleur-de-2030');

    expect(saveCallback(tester), isNull);
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).colorScheme.primary,
        churchPalette.ink);
  });
}
