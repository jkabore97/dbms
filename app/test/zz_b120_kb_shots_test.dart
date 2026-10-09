import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/console/kind_models_repository.dart';
import 'package:kaj_app/core/console/fiche_repository.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/onboarding/application_form.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/admin/center/command_center_shell.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/admin/kind_models_screen.dart';
import 'package:kaj_app/features/admin/request_form_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

const _dir = '/tmp/claude-0/-home-user-dbms/6b841e07-559f-5c6e-8be9-8db87f01d3f1/scratchpad/shots';

class _Center extends CommandCenterRepository {
  _Center() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<PlatformTodo> todo() async => const PlatformTodo({});
  @override
  Future<Map<String, SettingValue>> settings() async => const {};
}

class _Onboarding extends OnboardingRepository {
  _Onboarding() : super(null);
  @override
  Future<ApplicationForm?> applicationForm({bool strict = false}) async => null;
}

class _Kinds extends KindModelsRepository {
  _Kinds() : super(null);
  @override
  Future<KindModels> models(String kind) async => KindModels.fromJson({
        'kind': kind, 'orgs': 12, 'free': 9, 'never_dressed': 7,
        'settings': [
          {'key': 'free_photo_items', 'label': 'x', 'global': 10, 'value': 12, 'min': 0, 'max': 1000},
        ],
        'vitrine_default': null,
        'setup': [
          {'key': 'identity', 'label': 'Le nom', 'required': true, 'on': true},
        ],
      });
  @override
  Future<List<FeatureBoardRow>> board(String kind) async => [];
}

final _shot = GlobalKey();

Future<void> _save(WidgetTester tester, String name) async {
  final boundary = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/b120_$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    final font = File('/opt/flutter/bin/cache/dart-sdk/bin/resources/devtools/assets/packages/devtools_app_shared/fonts/Roboto_Mono/RobotoMono-Regular.ttf')
        .readAsBytesSync();
    final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.view(font.buffer)));
    await loader.load();
  });

  final pages = <String, Widget Function()>{
    'settings': () => SettingsSection(center: _Center()),
    'kinds': () => KindModelsScreen(repository: _Kinds(), undo: (_) async {}),
    'form': () => RequestFormScreen(onboarding: _Onboarding(), undo: (_) async {}),
  };
  final routes = {
    'settings': Routes.consoleSettings,
    'kinds': Routes.consoleKinds,
    'form': Routes.consoleRequestForm,
  };

  for (final size in const [Size(390, 800), Size(360, 640)]) {
    for (final name in pages.keys) {
      testWidgets('$name ${size.width}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final router = GoRouter(initialLocation: routes[name], routes: [
          ShellRoute(
            builder: (_, _, child) => CommandCenterShell(center: _Center(), platformAdmin: true, child: child),
            routes: [GoRoute(path: routes[name]!, builder: (_, _) => pages[name]!())],
          ),
        ]);
        await tester.pumpWidget(RepaintBoundary(
          key: _shot,
          child: MaterialApp.router(
            theme: kajTheme(kajPalette),
            locale: const Locale('fr'),
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
            routerConfig: router,
          ),
        ));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _save(tester, '${name}_${size.width.toInt()}_before');
        final fields = find.byType(EditableText);
        debugPrint('$name: ${fields.evaluate().length} fields');
        if (fields.evaluate().isNotEmpty) {
          await tester.showKeyboard(fields.first);
        }
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _save(tester, '${name}_${size.width.toInt()}_kb');
        for (final e in find.byType(Scaffold).evaluate()) {
          debugPrint('$name ${size.width}: scaffold ${tester.getRect(find.byWidget(e.widget))}');
        }
        debugPrint('exception ${tester.takeException()}');
      });
    }
  }
}
