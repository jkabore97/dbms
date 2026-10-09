// Throwaway: copied to app/test/zz_shot_r_lib.dart while shooting (builder R).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/l10n/strings.dart';

const shotDir =
    '/tmp/claude-0/-home-user-dbms/6b841e07-559f-5c6e-8be9-8db87f01d3f1/scratchpad/shots';

Future<void> loadFonts() async {
  const base = '/opt/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Light.ttf']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$base/$f').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$base/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

final shotKey = GlobalKey();

Widget app(Widget home, {String lang = 'fr', ThemeData? theme}) => RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? kajTheme(kajPalette),
        locale: Locale(lang),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: home,
      ),
    );

void size(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$shotDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
