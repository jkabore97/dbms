// Throwaway (builder J, 112): screenshots of the changed screens. Deleted after.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/courier/courier_dossier.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/account/legal_screens.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/admin/courier_review_screen.dart';
import 'package:kaj_app/features/admin/couriers_screen.dart';
import 'package:kaj_app/features/courier/become_courier_screen.dart';
import 'package:kaj_app/features/courier/courier_screen.dart';
import 'package:kaj_app/features/storefront/shop_style.dart';
import 'package:kaj_app/l10n/strings.dart';

const out = '/tmp/claude-0/-home-user-dbms/6b841e07-559f-5c6e-8be9-8db87f01d3f1/scratchpad/shots';

Future<void> loadFonts() async {
  const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons');
  icons.addFont(Future.value(ByteData.sublistView(File('$dir/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

final shotKey = GlobalKey();

Future<void> shot(WidgetTester tester, String name) async {
  // Pictures decode off the test clock: give them a moment.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await tester.pump();
  await expectLater(find.byKey(shotKey), matchesGoldenFile(Uri.file('$out/b111_J_$name.png')));
}

Uint8List? _face;
Uint8List? _card;
Uint8List picture() => _face!;

Future<Uint8List> draw(bool face) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const w = 300.0, h = 400.0;
  c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = face ? const Color(0xFFC49A6C) : const Color(0xFFF4F2EE));
  if (face) {
    c.drawOval(const Rect.fromLTWH(80, 70, 140, 180), Paint()..color = const Color(0xFF4A3122));
    c.drawRect(const Rect.fromLTWH(40, 270, 220, 130), Paint()..color = const Color(0xFF3B3A38));
  } else {
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, 110, 260, 170), const Radius.circular(14)),
        Paint()..color = const Color(0xFF3F7A52));
    c.drawRect(const Rect.fromLTWH(40, 140, 70, 90), Paint()..color = const Color(0xFFC49A6C));
    for (var i = 0; i < 4; i++) {
      c.drawRect(Rect.fromLTWH(130, 150.0 + i * 22, 130, 8), Paint()..color = const Color(0xFFF4F2EE));
    }
  }
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class _Server extends CourierDossierRepository {
  _Server(this.row) : super(null);
  Map<String, dynamic> row;

  Map<String, dynamic> get _json => {
        ...row,
        'files': {for (final p in ['selfie', 'id_front', 'id_back', 'licence']) p: (row['files'] ?? {})[p] == true},
        'open_steps': row['status'] == null || row['status'] == 'draft'
            ? ['zone', 'hours', 'vehicle', 'selfie', 'id', 'phone', 'charter']
            : row['status'] == 'refused'
                ? row['reopened']
                : <String>[],
        'refusal': row['status'] == 'refused'
            ? {'reason': row['reason'], 'note': row['note'], 'steps': row['reopened']}
            : null,
        'rules': {'licence_required': false, 'phone_verified': false, 'mobile_money': false, 'charter_version': 1},
      };

  @override
  bool get isConfigured => true;
  @override
  Future<CourierDossier> mine() async => CourierDossier.fromJson(_json);
  @override
  Future<CourierDossier> save(String step, Map<String, Object?> answers) async {
    row.addAll(answers);
    return mine();
  }

  @override
  Future<CourierDossier> send() async => mine();

  @override
  Future<List<CourierApplicationRow>> applications() async => [
        CourierApplicationRow.fromRow({'user_id': 'u-awa', 'name': 'Awa Ouédraogo', 'status': 'pending',
            'city': 'Ouagadougou', 'vehicle': 'moto', 'sent_at': '2026-10-08T09:00:00Z'}),
        CourierApplicationRow.fromRow({'user_id': 'u-moussa', 'name': 'Moussa Sawadogo', 'status': 'pending',
            'city': 'Ouagadougou', 'vehicle': 'velo', 'sent_at': '2026-10-08T11:20:00Z'}),
        CourierApplicationRow.fromRow({'user_id': 'u-ali', 'name': 'Ali Traoré', 'status': 'refused',
            'city': 'Bobo-Dioulasso', 'vehicle': 'velo', 'decided_at': '2026-10-07T09:00:00Z',
            'refusal_reason': 'blurry'}),
      ];

  @override
  Future<CourierDossier> dossier(String userId) async => CourierDossier.fromJson({
        'user_id': userId, 'name': 'Awa Ouédraogo', 'status': 'pending', 'courier_status': 'pending',
        'city': 'Ouagadougou', 'zones': ['Gounghin', 'Pissy', 'Dassasgho'], 'days': ['lun', 'mar', 'mer', 'sam'],
        'hours_from': '07:30', 'hours_to': '19:00', 'vehicle': 'moto', 'vehicle_make': 'Yamaha',
        'vehicle_model': 'Crypton', 'vehicle_colour': 'Rouge', 'vehicle_plate': '11 KK 2233', 'id_kind': 'cnib',
        'phone': '+22670112002', 'phone_verified': true, 'charter_version': 1,
        'charter_at': '2026-10-08T08:40:00Z', 'sent_at': '2026-10-08T09:00:00Z',
        'photos': {'selfie': 's', 'id_front': 'f', 'id_back': 'b', 'licence': null},
        'timeline': [{'at': '2026-10-08T09:00:00Z', 'kind': 'sent'}],
        'rules': {'licence_required': false, 'phone_verified': false, 'mobile_money': false, 'charter_version': 1},
      });
}

class _Files extends CourierFiles {
  _Files(this.server) : super(null, url: 'https://up.example');
  final _Server server;
  @override
  bool get isConfigured => true;
  @override
  Future<void> upload(String part, Uint8List bytes, String contentType) async {
    (server.row['files'] ??= <String, bool>{})[part] = true;
  }

  @override
  Future<Uint8List> photo(String key) async => key == 's' ? _face! : _card!;
  @override
  Future<void> purge() async {}
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<List<PlatformCourier>> platformCouriers() async => [
        PlatformCourier.fromRow({'user_id': 'u-awa', 'name': 'Awa Ouédraogo', 'phone': '+22670112002',
            'status': 'pending', 'created_at': '2026-10-08T09:00:00Z'}),
        PlatformCourier.fromRow({'user_id': 'u-moussa', 'name': 'Moussa Sawadogo', 'phone': '+22670112003',
            'status': 'pending', 'created_at': '2026-10-08T11:20:00Z'}),
        PlatformCourier.fromRow({'user_id': 'u-old', 'name': 'Oumar Kaboré', 'phone': '+22611200007',
            'status': 'pending', 'created_at': '2026-09-01T09:00:00Z'}),
        PlatformCourier.fromRow({'user_id': 'u-ok', 'name': 'Issa Zongo', 'phone': '+22611200009',
            'status': 'approved', 'created_at': '2026-08-01T09:00:00Z'}),
      ];
}

class _Center extends CommandCenterRepository {
  _Center() : super(null);
  @override
  Future<Map<String, SettingValue>> settings() async => {
        for (final d in platformSettingDefs)
          d.key: SettingValue(
              value: switch (d.type) {
                SettingType.flag => false,
                SettingType.flag01 => 0,
                SettingType.list => <String>[],
                SettingType.text || SettingType.currency => 'XOF',
                _ => 10,
              }),
      };
}

class _NoCourier extends CourierRepository {
  _NoCourier() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<String?> status() async => null;
}

Widget app(Widget home) {
  final router = GoRouter(initialLocation: '/x', routes: [
    GoRoute(path: '/x', builder: (_, _) => home),
    GoRoute(path: '/console/livreurs/dossier/:id', builder: (_, _) => const SizedBox()),
  ]);
  return RepaintBoundary(
    key: shotKey,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: kajTheme(kajPalette),
      routerConfig: router,
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
    ),
  );
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> size(WidgetTester tester, double w, double h) async {
  _face ??= await tester.runAsync(() => draw(true));
  _card ??= await tester.runAsync(() => draw(false));
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
}

Future<CourierShot?> camera({required bool selfie, bool gallery = false}) async =>
    (bytes: selfie ? _face! : _card!, type: 'image/png');

Future<void> next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('courier-next')));
  await settle(tester);
}

void main() {
  setUpAll(() async {
    await loadFonts();
    await initializeDateFormatting('fr_FR', null);
  });

  testWidgets('the flow', (tester) async {
    await size(tester, 390, 844);
    addTearDown(tester.view.reset);
    final server = _Server({});
    await tester.pumpWidget(app(BecomeCourierScreen(dossier: server, files: _Files(server), camera: camera)));
    await settle(tester);
    await shot(tester, 'intro_390');
    await tester.tap(find.byKey(const Key('courier-start')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('courier-city')), 'Ouagadougou');
    for (final z in ['Gounghin', 'Pissy', 'Dassasgho']) {
      await tester.enterText(find.byKey(const Key('courier-zone')), z);
      await tester.tap(find.byKey(const Key('courier-zone-add')));
    }
    await settle(tester);
    await shot(tester, 'zone_390');
    await next(tester);
    for (final d in ['lun', 'mar', 'mer', 'sam']) {
      await tester.tap(find.byKey(Key('courier-day-$d')));
    }
    await settle(tester);
    await shot(tester, 'hours_390');
    await next(tester);
    await tester.tap(find.byKey(const Key('courier-vehicle-moto')));
    await settle(tester);
    await shot(tester, 'vehicle_390');
    await next(tester);
    await tester.enterText(find.byKey(const Key('courier-make')), 'Yamaha');
    await tester.enterText(find.byKey(const Key('courier-model')), 'Crypton');
    await tester.enterText(find.byKey(const Key('courier-colour')), 'Rouge');
    await tester.enterText(find.byKey(const Key('courier-plate')), '11 KK 2233');
    await settle(tester);
    await shot(tester, 'vehicle_details_390');
    await next(tester);
    await shot(tester, 'selfie_before_390');
    await tester.tap(find.text('Prendre la photo'));
    await settle(tester);
    await shot(tester, 'selfie_390');
    await next(tester);
    await tester.tap(find.byKey(const Key('courier-id-cnib')));
    await tester.tap(find.descendant(of: find.byKey(const Key('courier-photo-id_front')), matching: find.text('Prendre la photo')));
    await settle(tester);
    await shot(tester, 'id_390');
    await tester.tap(find.descendant(of: find.byKey(const Key('courier-photo-id_back')), matching: find.text('Prendre la photo')));
    await settle(tester);
    await next(tester);
    await tester.enterText(find.byType(TextField).first, '70112002');
    await settle(tester);
    await shot(tester, 'phone_390');
    await next(tester);
    await tester.tap(find.byKey(const Key('courier-charter')));
    await settle(tester);
    await shot(tester, 'charter_390');
    await next(tester);
    await shot(tester, 'summary_390');
  });

  testWidgets('the wait, sent back, approved', (tester) async {
    await size(tester, 390, 844);
    addTearDown(tester.view.reset);
    var server = _Server({
      'status': 'pending', 'courier_status': 'pending',
      'timeline': [{'at': '2026-10-08T09:00:00Z', 'kind': 'sent'}],
    });
    await tester.pumpWidget(app(BecomeCourierScreen(dossier: server, files: _Files(server), camera: camera)));
    await settle(tester);
    await shot(tester, 'pending_390');
    server = _Server({
      'status': 'refused', 'reason': 'blurry', 'note': 'Le visage est flou, reprenez-la à la lumière.',
      'reopened': ['selfie'], 'files': {'selfie': true, 'id_front': true, 'id_back': true},
      'timeline': [
        {'at': '2026-10-08T09:00:00Z', 'kind': 'sent'},
        {'at': '2026-10-08T15:10:00Z', 'kind': 'refused', 'reason': 'blurry'},
      ],
    });
    await tester.pumpWidget(app(BecomeCourierScreen(key: UniqueKey(), dossier: server, files: _Files(server), camera: camera)));
    await settle(tester);
    await shot(tester, 'refused_390');
    server = _Server({
      'status': 'approved', 'courier_status': 'approved',
      'timeline': [
        {'at': '2026-10-08T09:00:00Z', 'kind': 'sent'},
        {'at': '2026-10-09T10:00:00Z', 'kind': 'approved'},
      ],
    });
    await tester.pumpWidget(app(BecomeCourierScreen(key: UniqueKey(), dossier: server, files: _Files(server), camera: camera)));
    await settle(tester);
    await shot(tester, 'approved_390');
    await tester.pumpWidget(app(CourierScreen(courier: _NoCourier())));
    await settle(tester);
    await shot(tester, 'courier_pitch_390');
    await tester.pumpWidget(app(Scaffold(body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ShopFooter(onBecomeCourier: () {})))));
    await settle(tester);
    await shot(tester, 'street_footer_390');
    await tester.pumpWidget(app(const PrivacyScreen()));
    await settle(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await settle(tester);
    await shot(tester, 'privacy_390');
  });

  for (final w in [390.0, 1280.0]) {
    testWidgets('the platform at $w', (tester) async {
      await size(tester, w, w > 400 ? 900 : 1100);
      addTearDown(tester.view.reset);
      final server = _Server({});
      await tester.pumpWidget(app(CouriersScreen(admin: _Admin(), dossier: server, files: _Files(server))));
      await settle(tester);
      await shot(tester, 'couriers_${w.toInt()}');
      await tester.pumpWidget(app(CourierReviewScreen(userId: 'u-awa', dossier: server, files: _Files(server))));
      await settle(tester);
      await shot(tester, 'review_${w.toInt()}');
      if (w < 400) {
        await tester.tap(find.byKey(const Key('review-refuse')));
        await settle(tester);
        await tester.tap(find.byKey(const Key('refuse-blurry')));
        await settle(tester);
        await shot(tester, 'refuse_sheet_390');
      }
      await tester.pumpWidget(app(SettingsSection(center: _Center())));
      await settle(tester);
      final row = find.byKey(const Key('setting-courier_licence_required'));
      await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
      await settle(tester);
      await shot(tester, 'reglages_${w.toInt()}');
    });
  }
}
