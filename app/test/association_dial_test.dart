import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/org_access.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/home/home_nav.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The association screen honours the owner's dial.
///
/// The audit: it was the one home screen never handed the dial, so every
/// member saw every tool the owner hid. The database refuses them too since
/// 069; this is the screen no longer offering them.
const _org = OrgSummary(
    id: 'ch-1', name: 'Assemblée', profile: 'association', roles: ['employee']);

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  late SupabaseClient client;

  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
    client =
        SupabaseClient('https://example.supabase.co', 'sb_publishable_test');
  });

  tearDown(() async {
    await client.dispose();
    await db.close();
  });

  Future<List<String>> barFor(WidgetTester tester, OrgAccess access) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: ChurchHomeScreen(
        db: db,
        orgId: _org.id,
        orgName: _org.name,
        org: _org,
        reports: ReportsRepository(client),
        invoicing: InvoicingRepository(client),
        onHistory: () {},
        access: access,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    return tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => d.label)
        .toList();
  }

  testWidgets('tools the owner hid are not offered', (tester) async {
    expect(
        await barFor(tester,
            const OrgAccess.forTier({'reports': 'hidden', 'invoices': 'hidden'})),
        ['Accueil', HomeNav.moreLabel]);
  });

  testWidgets('with no rule, the member sees the usual five', (tester) async {
    expect(await barFor(tester, const OrgAccess.forTier({})),
        ['Accueil', 'Historique', 'Rapports', 'Factures', HomeNav.moreLabel]);
  });
}
