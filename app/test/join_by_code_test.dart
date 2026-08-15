import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/features/auth/join_by_code_screen.dart';

/// The invited person's only way in, so the one thing that must never happen is
/// a screen they cannot get off.
///
/// This exists because it did happen: the Verify button is enabled from the
/// length of what has been typed, recomputed on build, and `onChanged` only
/// called setState when it had a previous result to clear. Nothing rebuilt as
/// the code was entered, so the button stayed grey however much was typed —
/// invisible to every test in the suite until the flow was driven in a
/// browser.
void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
        // A null client is fine: nothing here reaches the network. Enabling
        // the button is a pure function of what has been typed.
        home: JoinByCodeScreen(admin: AdminRepository(null)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The button's own callback, which is what actually decides whether a tap
  /// does anything — checking for a grey pixel would pass against a button
  /// that is merely styled as disabled.
  VoidCallback? verifyCallback(WidgetTester tester) {
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Vérifier le code'),
        matching: find.byType(FilledButton),
      ),
    );
    return button.onPressed;
  }

  testWidgets('the verify button is dead until a full code has been typed',
      (tester) async {
    await pumpScreen(tester);
    expect(verifyCallback(tester), isNull);

    await tester.enterText(find.byType(TextField), 'ABC');
    await tester.pump();
    expect(
      verifyCallback(tester),
      isNull,
      reason: 'three characters is not a code',
    );
  });

  testWidgets('the verify button wakes up as soon as the code is complete',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'ABCD-2345');
    await tester.pump();

    expect(
      verifyCallback(tester),
      isNotNull,
      reason: 'a complete code must enable Verify — this is the regression',
    );
  });

  testWidgets('punctuation and case are not the user\'s problem',
      (tester) async {
    await pumpScreen(tester);

    // Read aloud down a bad line and written down however it was heard. The
    // server normalises it; the button must not disagree.
    await tester.enterText(find.byType(TextField), 'abcd 2345');
    await tester.pump();

    expect(verifyCallback(tester), isNotNull);
  });
}
