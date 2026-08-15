import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/features/admin/businesses_screen.dart';

/// The one screen in this app that destroys something.
///
/// Everything else is append-only by design — undo is a reversing entry, a
/// photograph cannot be deleted, the audit log has no delete policy. So the
/// cases below are not about whether the button works; they are about whether
/// it is hard enough to press.
///
/// The server makes every one of these checks itself, in `delete_org()`, and
/// is the thing that actually decides. These are here because a dialog that
/// lets somebody destroy a year of books with two taps is a bug even when the
/// server would have stopped a *different* mistake.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  PlatformOrg org({
    String name = 'Boutique Espérance',
    int entries = 0,
    int members = 1,
    bool archived = false,
  }) =>
      PlatformOrg(
        id: '00000000-0000-0000-0000-000000000001',
        name: name,
        slug: 'boutique-esperance',
        profile: 'retail',
        entryCount: entries,
        memberCount: members,
        archivedAt: archived ? DateTime(2026, 8, 1) : null,
      );

  Future<void> openDialog(WidgetTester tester, PlatformOrg target) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => DeleteBusinessDialog(org: target),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The delete button, whatever else is on screen.
  Finder confirmButton() => find.widgetWithText(FilledButton, 'Supprimer');

  bool isEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(confirmButton()).onPressed != null;

  testWidgets('the button is dead until the name is typed back',
      (tester) async {
    await openDialog(tester, org());

    expect(isEnabled(tester), isFalse,
        reason: 'a dialog that opens with a live delete button is two taps '
            'from destroying a business');

    // Most of the name is not the name.
    await tester.enterText(find.byType(TextField), 'Boutique');
    await tester.pump();
    expect(isEnabled(tester), isFalse);

    await tester.enterText(find.byType(TextField), 'Boutique Espérance');
    await tester.pump();
    expect(isEnabled(tester), isTrue);
  });

  testWidgets('a name typed in a different case still counts', (tester) async {
    // The server compares case-insensitively on trimmed text, because that is
    // how a name arrives from a phone keyboard. The dialog agrees, otherwise
    // it refuses something the server would accept.
    await openDialog(tester, org());

    await tester.enterText(find.byType(TextField), '  boutique espérance  ');
    await tester.pump();
    expect(isEnabled(tester), isTrue);
  });

  testWidgets('a wrong name says so rather than failing silently',
      (tester) async {
    await openDialog(tester, org());

    await tester.enterText(find.byType(TextField), 'Boutique Rivale');
    await tester.pump();

    expect(find.text('Le nom ne correspond pas.'), findsOneWidget);
    expect(isEnabled(tester), isFalse);
  });

  testWidgets('a business with books is described in what is lost, not in rows',
      (tester) async {
    await openDialog(tester, org(entries: 42, members: 3));

    // "42 écritures" is a number. What it means is the whole of this shop's
    // accounts, and the dialog has to say so before anybody types anything.
    expect(find.textContaining('Toute la comptabilité'), findsOneWidget);
    expect(find.textContaining('42 écritures'), findsOneWidget);
    expect(find.textContaining('irréversible'), findsOneWidget);
  });

  testWidgets('an empty business says it is empty rather than crying wolf',
      (tester) async {
    await openDialog(tester, org(entries: 0));

    expect(find.textContaining('aucune écriture'), findsOneWidget);
    expect(find.textContaining('Toute la comptabilité'), findsNothing);
  });

  testWidgets('cancelling returns nothing and destroys nothing',
      (tester) async {
    await openDialog(tester, org());

    await tester.enterText(find.byType(TextField), 'Boutique Espérance');
    await tester.pump();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });
}
