import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/features/common/phone_field.dart';
import 'package:kaj_app/l10n/strings.dart';

/// 178: every phone field has its country (the owner: « I thought you …
/// added country code to all the phone number entries »). PhoneInput keeps
/// the country itself; the screen's controller always holds the whole
/// number, as it did before — so the thirteen screens read it unchanged.
Future<void> _pump(WidgetTester tester, TextEditingController c) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    home: Scaffold(body: PhoneInput(controller: c, labelText: 'Numéro')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('typed under Burkina: the screen reads the whole number', (tester) async {
    final c = TextEditingController();
    await _pump(tester, c);
    expect(find.textContaining('+226'), findsWidgets, reason: 'Burkina first');
    await tester.enterText(find.byType(TextField), '70 00 00 01');
    await tester.pump();
    expect(c.text, '+22670000001');
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(c.text, '', reason: 'empty stays empty');
  });

  testWidgets('a stored number opens under its own country, its zero kept (Côte d’Ivoire)', (tester) async {
    final c = TextEditingController(text: '+2250712345678');
    await _pump(tester, c);
    expect(find.textContaining('+225'), findsWidgets);
    expect(find.widgetWithText(TextField, '0712345678'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '0712345679');
    await tester.pump();
    expect(c.text, '+2250712345679');
  });

  testWidgets('a number the screen loads later is shown under its country', (tester) async {
    final c = TextEditingController();
    await _pump(tester, c);
    c.text = '+22370000002';
    await tester.pump();
    expect(find.textContaining('+223'), findsWidgets);
    expect(find.widgetWithText(TextField, '70000002'), findsOneWidget);
  });

  testWidgets('a wrong length for the country is said', (tester) async {
    final c = TextEditingController();
    await _pump(tester, c);
    await tester.enterText(find.byType(TextField), '70 00');
    await tester.pump();
    expect(find.textContaining('8 chiffres'), findsOneWidget);
  });
}
