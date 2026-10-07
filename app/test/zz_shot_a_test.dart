import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/access/org_access.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _out = '/tmp/claude-0/-home-user-dbms/6b841e07-559f-5c6e-8be9-8db87f01d3f1/scratchpad/shots';
const _fonts = '/opt/flutter/bin/cache/artifacts/material_fonts';

class _Shop extends RetailRepository {
  _Shop(super.client);
  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();
  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) async => const [];
  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [];
  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) async => 0;
  @override
  Future<int> pendingOrders(String orgId) async => 0;
}

const _org = OrgSummary(id: 'o', name: 'Boutique Awa', slug: 'awa', profile: 'retail', roles: ['owner']);

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: kajTheme(kajPalette),
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: ProfileTheme(profile: 'retail', child: home),
    );

void main() {
  setUpAll(() async {
    final roboto = FontLoader('Roboto');
    for (final w in ['Regular', 'Medium', 'Bold', 'Black', 'Light']) {
      roboto.addFont(Future.value(ByteData.sublistView(File('$_fonts/Roboto-$w.ttf').readAsBytesSync())));
    }
    await roboto.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(File('$_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
    await icons.load();
  });

  Future<void> shot(WidgetTester tester, Widget w, String name, double width) async {
    tester.view.physicalSize = Size(width, width < 600 ? 844 : 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(w));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/b104_a_${name}_${width.toInt()}.png'));
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('pas disponible $width', (tester) async {
      await shot(tester, const FeatureUnavailableScreen(org: _org), 'unavailable', width);
    });
  }
  testWidgets('shop home with invoices and production hidden, Plus open', (tester) async {
    final client = SupabaseClient('https://example.supabase.co', 'sb_publishable_test');
    addTearDown(client.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(StoreHomeScreen(
      org: _org,
      retail: _Shop(client),
      invoicing: InvoicingRepository(client),
      access: const OrgAccess.admin(hidden: {'invoices', 'production'}),
    )));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Plus'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/b104_a_home_hidden_390.png'));
  });
}
