// 171c: a button's words are never cut (the owner's screenshot: « Voir le
// modèle en vrai » in the designs' gallery, its line sliced through).
//
// The theme puts 16 pixels above and below a button's label, and a line of
// it is 19 pixels in Roboto: a button needs 51. Seventy-nine buttons sat in
// boxes of a FIXED height — 46, 48 and 50 cut the words at any text size, 52
// and 54 as soon as the phone's text is set larger, and any of them once a
// label goes onto two lines. Their heights are minimums now: the same button
// whenever the words fit, a taller one instead of cut words.
//
//   * the gallery's two buttons keep 46 and 52 at the usual size, their
//     words whole at 1.0 and at 1.3, the long Premium label on two lines;
//   * « C'est fait » (every flow: a sale, an article, a harvest, a
//     contribution) shows its actions whole at 1.3 on a 360 phone — even
//     the short « Nouvelle vente » needed more than the old fixed 56;
//   * nowhere in lib/ does a fixed-height box hold a themed button again.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/events/events_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/events/templates_gallery_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Real letters (as batch133_ui_test): flutter_test's own font is a full em
/// wide and as tall as its size, which would say nothing about Roboto's 19.
Future<bool> _realFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6 && !Directory('${dir.path}/material_fonts').existsSync(); i++) {
    dir = dir.parent;
  }
  final fonts = Directory('${dir.path}/material_fonts');
  if (!fonts.existsSync()) return false;
  ByteData bytes(String name) => ByteData.view(File('${fonts.path}/$name').readAsBytesSync().buffer);
  final loader = FontLoader('Roboto');
  for (final f in const ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    if (File('${fonts.path}/$f').existsSync()) loader.addFont(Future.value(bytes(f)));
  }
  await loader.load();
  return true;
}

var _fonts = false;

/// The templates are the app's own list: no server.
class _Events extends EventsRepository {
  _Events() : super(null);
}

const _org = OrgSummary(id: 'o1', name: 'Awa Événements', slug: 'awa-evenements', profile: 'events', roles: ['owner']);

Future<void> _pump(WidgetTester tester, Widget home, {double scale = 1.0}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    theme: kajTheme(kajPalette),
    home: home,
  ));
  await tester.pumpAndSettle();
}

/// The button as it is drawn (its Material), not its tap area.
Finder _material(Finder button) => find.descendant(of: button, matching: find.byType(Material)).first;

/// Every line of [button]'s words drawn whole, inside the button.
void _whole(WidgetTester tester, Finder button, String what) {
  final box = tester.getRect(_material(button));
  final lines = find.descendant(of: button, matching: find.byType(RichText));
  var words = 0;
  for (final e in lines.evaluate()) {
    // An icon is a letter of its own font, in a box of its own size.
    if (e.findAncestorWidgetOfExactType<Icon>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    if (p.text.toPlainText().trim().isEmpty) continue;
    words++;
    final need = p.getMaxIntrinsicHeight(p.size.width);
    expect(p.size.height, greaterThanOrEqualTo(need - 0.5),
        reason: '$what: « ${p.text.toPlainText()} » needs $need pixels, has ${p.size.height}');
    final r = p.localToGlobal(Offset.zero) & p.size;
    expect(r.top, greaterThanOrEqualTo(box.top - 0.5), reason: '$what: words above the button');
    expect(r.bottom, lessThanOrEqualTo(box.bottom + 0.5), reason: '$what: words below the button');
  }
  expect(words, greaterThan(0), reason: '$what has words');
}

Size _drawn(WidgetTester tester, Finder button) => tester.getSize(_material(button));

void main() {
  setUpAll(() async {
    _fonts = await _realFonts();
  });

  group('the designs\' gallery', () {
    testWidgets('a design shown large: both buttons whole, at the heights they had', (tester) async {
      expect(_fonts, isTrue, reason: 'the SDK\'s Roboto, for real line heights');
      await _pump(tester, TemplatesGalleryScreen(events: _Events(), org: _org, open: (_) async {}));
      await tester.tap(find.byKey(const Key('template-come')));
      await tester.pumpAndSettle();
      expect(find.text('Voir le modèle en vrai'), findsOneWidget);
      _whole(tester, find.byKey(const Key('template-demo')), '« Voir le modèle en vrai »');
      _whole(tester, find.byKey(const Key('template-use')), '« Utiliser ce modèle »');
      // The look kept: the same two heights as before, when the words fit.
      expect(_drawn(tester, find.byKey(const Key('template-demo'))).height, 46);
      expect(_drawn(tester, find.byKey(const Key('template-use'))).height, 52);
    });

    testWidgets('the phone\'s text at 1.3, a Premium design: taller buttons, every word whole', (tester) async {
      await _pump(tester, TemplatesGalleryScreen(events: _Events(), org: _org, open: (_) async {}), scale: 1.3);
      await tester.tap(find.byKey(const Key('family-anime')));
      await tester.pumpAndSettle();
      final premium = find.byKey(const Key('template-anime_lotus_p'));
      await tester.dragUntilVisible(premium, find.byType(GridView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(premium);
      await tester.pumpAndSettle();
      expect(find.text('Modèle Premium : passer à Marakaj Pro'), findsOneWidget);
      _whole(tester, find.byKey(const Key('template-demo')), '« Voir le modèle en vrai » at 1.3');
      _whole(tester, find.byKey(const Key('template-use')), 'the Premium label at 1.3');
      // Two lines at 1.3 on a 360 phone: the button grew, the words stayed.
      expect(_drawn(tester, find.byKey(const Key('template-use'))).height, greaterThan(52));
    });
  });

  testWidgets('« C\'est fait »: a long action whole at 1.3 on a 360 phone', (tester) async {
    await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: FlowDone(message: 'Vente enregistrée', actions: [
              FlowAction(
                key: const Key('done-share'),
                label: 'Partager le reçu sur WhatsApp avec le client',
                icon: Icons.share,
                onPressed: () {},
                primary: true,
              ),
              FlowAction(key: const Key('done-again'), label: 'Nouvelle vente', icon: Icons.add, onPressed: () {}),
            ]),
          ),
        ),
        scale: 1.3);
    _whole(tester, find.byKey(const Key('done-share')), 'the long action');
    _whole(tester, find.byKey(const Key('done-again')), 'the short action');
    // Even the short one needs more than the old fixed 56 at 1.3 (16 + a
    // 26-pixel line + 16): it was cut too.
    expect(_drawn(tester, find.byKey(const Key('done-again'))).height, greaterThan(56));
    expect(_drawn(tester, find.byKey(const Key('done-share'))).height,
        greaterThan(_drawn(tester, find.byKey(const Key('done-again'))).height),
        reason: 'the long action on two lines');
  });

  test('no fixed-height box holds a themed button anywhere in lib/', () {
    // A fixed SizedBox (or Container) height straight around a Filled-,
    // Outlined- or ElevatedButton, the child maybe chosen by a condition.
    // A minimum (ConstrainedBox(minHeight: …)) is the way.
    final fixed = RegExp(
        r'(?:SizedBox|Container)\(\s*(?:\w+:\s*[^,()]+,\s*)*?height:\s*[^,()]+,\s*(?:\w+:\s*[^,()]+,\s*)*'
        r'child:\s*(?:[\w.!= ]+\?\s*)?(?:FilledButton|OutlinedButton|ElevatedButton)\b');
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in fixed.allMatches(src)) {
        // The one exception says so just above it: the vitrine's « Continuer
        // avec Google », as tall as Apple's, its one line shrunk to fit.
        final above = src.substring(0, m.start).split('\n');
        final before = above.sublist(above.length < 6 ? 0 : above.length - 6).join('\n');
        if (before.contains('A fixed height on purpose (171c)')) continue;
        found.add('${f.path}:${'\n'.allMatches(src.substring(0, m.start)).length + 1}');
      }
    }
    expect(found, isEmpty, reason: 'a fixed height cuts the words: ${found.join(', ')}');
  });
}
