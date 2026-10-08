// Throwaway (builder E, 108): screenshots of the changed screens. Deleted after.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/nav/business_cover.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/home/business_frame.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  // ignore: avoid_print
  print('shot $name');
  await expectLater(find.byKey(shotKey), matchesGoldenFile('zz_shots/b108_E_$name.png'));
}

class _Shop extends RetailRepository {
  _Shop(super.client);
  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();
  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) async => const [];
  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [
        Product(id: 'p1', name: 'Riz 5 kg', salePrice: 4500, quantity: 12),
        Product(id: 'p2', name: 'Huile 1 L', salePrice: 1200, quantity: 30),
      ];
  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) async => 0;
  @override
  Future<int> pendingOrders(String orgId) async => 2;
}

Widget tool(String name) => Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(name)),
        body: ListView(children: [
          for (var i = 1; i <= 12; i++) ListTile(title: Text('$name — ligne $i')),
        ]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => const SizedBox(height: 220, child: Center(child: Text('Une feuille, comme avant'))),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Ajouter'),
        ),
      ),
    );

GoRouter router(Widget Function() home, OrgSummary org, String at) {
  final cover = BusinessCover();
  return GoRouter(initialLocation: at, routes: [
    ShellRoute(
      observers: [cover],
      builder: (c, s, child) => BusinessFrame(org: org, location: s.uri.path, cover: cover, child: child),
      routes: [
        GoRoute(path: '/o/:orgId', builder: (_, _) => BusinessPage(child: home()), routes: [
          for (final r in const ['produits', 'commandes', 'factures', 'bandes', 'stock', 'rapports', 'administration'])
            GoRoute(path: r, builder: (_, _) => BusinessPage(child: tool(r))),
        ]),
      ],
    ),
  ]);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await loadFonts();
  });

  const shop = OrgSummary(id: 'org-1', name: 'Boutique Awa', slug: 'awa', profile: 'retail', roles: ['owner'], currency: 'XOF');
  const farm = OrgSummary(id: 'farm-1', name: 'Ferme Ignace', profile: 'farm', roles: ['owner']);
  const asso = OrgSummary(id: 'asso-1', name: 'Entraide', profile: 'association', roles: ['owner']);

  Future<void> run(WidgetTester tester, GoRouter r, double w, double h) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: shotKey,
      child: MaterialApp.router(
        theme: kajTheme(kajPalette),
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        routerConfig: r,
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('E1 shots', (tester) async {
    final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
    final client = SupabaseClient('https://example.supabase.co', 'sb_publishable_test');
    Widget shopHome() => StoreHomeScreen(org: shop, retail: _Shop(client), invoicing: InvoicingRepository(client));

    await run(tester, router(shopHome, shop, '/o/org-1'), 390, 844);
    await shot(tester, 'e1_shop_home_390');
    await tester.tap(find.text('Factures'));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 600)); await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, 'e1_shop_factures_390');
    await tester.tap(find.text('Ajouter'));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 600)); await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, 'e1_shop_sheet_390');
    await tester.tapAt(const Offset(200, 100));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 600)); await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Plus'));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 600)); await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, 'e1e2_shop_plus_390');

    await run(tester, router(shopHome, shop, '/o/org-1/commandes'), 1280, 800);
    await shot(tester, 'e1_shop_commandes_1280');

    await run(tester, router(() => FarmHomeScreen(db: db, org: farm, invoicing: InvoicingRepository(client)), farm, '/o/farm-1/bandes'), 390, 844);
    await shot(tester, 'e1_farm_bandes_390');
    await tester.tap(find.text('Plus'));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 600)); await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, 'e1e2_farm_plus_390');

    await run(tester, router(() => ChurchHomeScreen(db: db, orgId: asso.id, orgName: asso.name, org: asso, invoicing: InvoicingRepository(client)), asso, '/o/asso-1/factures'), 390, 844);
    await shot(tester, 'e1_asso_factures_390');
    await tester.tap(find.text('Plus'));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 600)); await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, 'e1e2_asso_plus_390');
    await tester.runAsync(() async {
      await client.dispose();
      await db.close();
    });
  });
}
