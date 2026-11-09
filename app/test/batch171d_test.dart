// 171d: nothing in Marakaj is chosen by a long press (the owner: the Google
// text selection gets in the way of moving a block — « cancel it through the
// whole app »). On the website the pages choose no word (their CSS, the
// Worker's tests and the browser runs); in the app, the few texts that were
// SelectableText — a team code, a link, a number, an error — copy themselves
// on a tap instead, and say so.
//
//   * a tap on a CopyText puts the whole text on the clipboard, « Copié »;
//   * the snack bar can say what was copied (« Code copié »);
//   * no SelectableText is left in lib/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/features/common/copy_text.dart';
import 'package:kaj_app/l10n/strings.dart';

void main() {
  final copied = <String>[];
  setUp(() {
    copied.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ));

  testWidgets('a tap copies the whole text and says « Copié »', (tester) async {
    await pump(tester, const CopyText('MK-7Q2P', key: Key('code')));
    expect(find.byType(SelectableText), findsNothing);
    await tester.tap(find.byKey(const Key('code')));
    await tester.pumpAndSettle();
    expect(copied, ['MK-7Q2P']);
    expect(find.text('Copié'), findsOneWidget);
  });

  testWidgets('it can say what was copied', (tester) async {
    await pump(tester, const CopyText('A1B2C3', key: Key('code'), copied: 'Code copié'));
    await tester.tap(find.byKey(const Key('code')));
    await tester.pumpAndSettle();
    expect(copied, ['A1B2C3']);
    expect(find.text('Code copié'), findsOneWidget);
  });

  testWidgets('a long press chooses nothing', (tester) async {
    await pump(tester, const CopyText('+226 70 00 00 00', key: Key('n')));
    await tester.longPress(find.byKey(const Key('n')));
    await tester.pumpAndSettle();
    expect(find.byType(TextSelectionToolbar), findsNothing);
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
  });

  test('no SelectableText anywhere in lib/', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('copy_text.dart')) continue;
      final src = f.readAsStringSync();
      if (RegExp(r'\bSelectableText\b').hasMatch(src) || src.contains('SelectionArea(')) found.add(f.path);
    }
    expect(found, isEmpty, reason: 'a long press would choose words there: ${found.join(', ')}');
  });
}
