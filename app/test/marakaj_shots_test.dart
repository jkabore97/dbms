// The product's new name, seen (147): the sign-in, the street's header
// with the wordmark, a shop's home, the Pro page, the conditions and the
// bell, in French and in English, at 390 px — the real app (KajApp) with
// no server, as routing_test runs it.
//
// MARAKAJ_SHOTS=<dir> writes the screenshots; without it every case skips.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/pin_codec.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/features/notify/notifications_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:kaj_app/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _realFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6 && !Directory('${dir.path}/material_fonts').existsSync(); i++) {
    dir = dir.parent;
  }
  final fonts = Directory('${dir.path}/material_fonts');
  if (!fonts.existsSync()) return;
  final loader = FontLoader('Roboto');
  for (final f in const ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    final file = File('${fonts.path}/$f');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
  final icons = File('${fonts.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer))))
        .load();
  }
}

/// A bell with three rows: two the app words itself, one an older
/// server's own sentence (« Mara … »), read with the new name.
class _Bell extends NotificationsRepository {
  _Bell() : super(null);

  @override
  Future<List<NotificationRow>> inScope(NotifyScope scope, {int limit = 50}) async => [
        NotificationRow.fromRow({
          'id': 'n1', 'kind': 'pro_active', 'message': 'Mara Pro est actif jusqu\'au 14/11/2026.',
          'created_at': '2026-10-15T09:00:00Z', 'org_id': 'org-1', 'scope': 'shop',
          'params': {'until': '2026-11-14T00:00:00Z'},
        }),
        NotificationRow.fromRow({
          'id': 'n2', 'kind': 'spot_stopped', 'message': 'Mara a arrêté votre mise en avant.',
          'created_at': '2026-10-15T08:00:00Z', 'org_id': 'org-1', 'scope': 'shop',
          'params': {'to': 'shop'},
        }),
        NotificationRow.fromRow({
          'id': 'n3', 'kind': 'platform_note_from_before', 'read_at': '2026-10-15T08:00:00Z',
          'message': 'Mara : ceci est une notification test. Si elle s\'affiche sur votre téléphone, tout marche.',
          'created_at': '2026-10-14T18:00:00Z', 'org_id': 'org-1', 'scope': 'shop',
        }),
      ];

  @override
  Future<void> markRead(Iterable<String> ids) async {}
}

void main() {
  final shots = Platform.environment['MARAKAJ_SHOTS'];

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
    await _realFonts();
  });

  late LocalDb db;
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() => db.close());

  Future<void> flush(WidgetTester tester, {int rounds = 10}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump();
    await tester.runAsync(() async {
      final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('screen')).first);
      final img = await ro.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ImageByteFormat.png);
      File('$shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  Future<GoRouter> pumpApp(WidgetTester tester, Locale locale) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final capture = CaptureRepository(null, db: db);
    await tester.pumpWidget(RepaintBoundary(
      key: const Key('screen'),
      child: KajApp(
        db: db,
        auth: AuthRepository(null),
        admin: AdminRepository(null),
        reports: ReportsRepository(null),
        accounting: AccountingRepository(null),
        console: ConsoleRepository(null),
        farm: FarmRepository(null),
        invoicing: InvoicingRepository(null),
        retail: RetailRepository(null),
        staff: StaffRepository(null),
        capture: capture,
        onboarding: OnboardingRepository(null),
      ),
    ));
    await flush(tester);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    return app.routerConfig as GoRouter;
  }

  for (final locale in const [Locale('fr'), Locale('en')]) {
    final tag = '${locale.languageCode}_390';

    testWidgets('the street, the sign-in and the conditions — $tag', (tester) async {
      Directory(shots!).createSync(recursive: true);
      final router = await pumpApp(tester, locale);
      await capture(tester, '1_street_header_$tag');
      router.go('/connexion');
      await flush(tester);
      await capture(tester, '2_sign_in_$tag');
      router.go('/conditions');
      await flush(tester);
      await capture(tester, '5_conditions_$tag');
    }, skip: shots == null);

    testWidgets('a shop\'s home and the Pro page — $tag', (tester) async {
      Directory(shots!).createSync(recursive: true);
      await tester.runAsync(() async {
        final salt = PinCodec.newSalt();
        await db.saveIdentity(LocalIdentity(
          userId: 'user-awa',
          displayName: 'Awa',
          phone: '+22670000001',
          pinSalt: salt,
          pinHash: PinCodec.hash('1379', salt),
          orgsRefreshedAt: DateTime.now(),
        ));
        await db.cacheOrgs(const [
          OrgSummary(id: 'org-1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']),
        ]);
      });
      final router = await pumpApp(tester, locale);
      for (final d in '1379'.split('')) {
        await tester.tap(find.widgetWithText(TextButton, d));
        await tester.pump();
      }
      await flush(tester);
      router.go('/o/org-1');
      await flush(tester, rounds: 16);
      await capture(tester, '3_shop_home_$tag');
      router.go('/o/org-1/kaj-pro');
      await flush(tester, rounds: 16);
      await capture(tester, '4_pro_page_$tag');
    }, skip: shots == null);

    testWidgets('the bell — $tag', (tester) async {
      Directory(shots!).createSync(recursive: true);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(
        key: const Key('screen'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          home: NotificationsScreen(notify: _Bell(), scope: const NotifyScope.org('org-1')),
        ),
      ));
      await flush(tester);
      await capture(tester, '6_notifications_$tag');
    }, skip: shots == null);
  }
}
