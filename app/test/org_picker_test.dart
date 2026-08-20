import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/features/auth/org_picker_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// The business picker, opened cold.
///
/// The report: "/entreprises is never working properly, sometimes it's empty."
/// A bookmark or a reload lands straight on this screen while the org list is
/// still on its way — and for a platform admin the list is every business
/// there is, a slow query — so it used to draw a blank page for that whole
/// window. An empty list is now a state, never a blank: a spinner while it
/// loads, a message once it is truly empty.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: child,
      );

  testWidgets('a cold, still-loading picker shows a spinner, not a blank',
      (tester) async {
    await tester.pumpWidget(wrap(OrgPickerScreen(
      orgs: const [],
      loading: true,
      onSelected: (_) {},
    )));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Chargement de vos entreprises…'), findsOneWidget);
  });

  testWidgets('a loading picker that never resolves offers a way out',
      (tester) async {
    // The "loading forever" report: if the resolve never returns, the spinner
    // must not be a trap. After a short wait it reveals Réessayer (which fires
    // the retry) and Se déconnecter.
    var retried = false;
    var signedOut = false;
    await tester.pumpWidget(wrap(OrgPickerScreen(
      orgs: const [],
      loading: true,
      onSelected: (_) {},
      onRetry: () => retried = true,
      onSignOut: () => signedOut = true,
    )));
    await tester.pump();

    // Nothing but the spinner at first.
    expect(find.text('Réessayer'), findsNothing);

    // Past the escape threshold, the way out appears.
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text('Se déconnecter'), findsOneWidget);

    // Sign out first: pressing Réessayer restarts the wait and hides both.
    await tester.tap(find.text('Se déconnecter'));
    await tester.pump();
    expect(signedOut, isTrue);

    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(retried, isTrue);
    // Réessayer returns to the plain spinner while the retry runs.
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('an empty picker that has finished loading says so', (tester) async {
    await tester.pumpWidget(wrap(OrgPickerScreen(
      orgs: const [],
      loading: false,
      onSelected: (_) {},
    )));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text("Aucune entreprise pour l'instant."), findsOneWidget);
  });

  testWidgets('a populated picker lists every business and is tappable',
      (tester) async {
    OrgSummary? tapped;
    await tester.pumpWidget(wrap(OrgPickerScreen(
      orgs: const [
        OrgSummary(id: 'a', name: 'Grace Chapel', profile: 'church'),
        OrgSummary(id: 'b', name: 'Boutique Sanou', profile: 'retail'),
      ],
      // Even flagged loading, a non-empty list is shown rather than hidden
      // behind a spinner — a refresh must never blank the list already there.
      loading: true,
      onSelected: (o) => tapped = o,
    )));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Grace Chapel'), findsOneWidget);
    expect(find.text('Boutique Sanou'), findsOneWidget);

    await tester.tap(find.text('Boutique Sanou'));
    expect(tapped?.id, 'b');
  });
}
