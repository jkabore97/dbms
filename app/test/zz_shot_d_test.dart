// Throwaway: screenshots of builder D's screens (batch 104). Deleted after.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/admin/models.dart';
import 'package:kaj_app/core/admin/team.dart';
import 'package:kaj_app/core/analytics/analytics_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/console/fiche_repository.dart';
import 'package:kaj_app/core/credit/credit_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/l10n/locale_controller.dart';
import 'package:kaj_app/core/nav/app_scope.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/core/tontine/tontine_repository.dart';
import 'package:kaj_app/features/admin/fiche/business_fiche_screen.dart';
import 'package:kaj_app/features/admin/fiche/fiche_vitrine_tab.dart';
import 'package:kaj_app/features/admin/fiche/merchant_preview_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'batch106_fiche_test.dart' show overviewJson;

const _out = '/tmp/claude-0/-home-user-dbms/6b841e07-559f-5c6e-8be9-8db87f01d3f1/scratchpad/shots';

class _Fiche extends FicheRepository {
  _Fiche(this.profile) : super(null);
  final String profile;
  @override
  bool get isConfigured => true;
  @override
  Future<OrgOverview> overview(String orgId) async => OrgOverview.fromJson(overviewJson(profile));
  @override
  Future<List<FeatureBoardRow>> board(String orgId) async => [
        for (final r in [
          {'key': 'invoices', 'label': 'Factures', 'grp': 'Ventes et clients', 'state': 'hidden', 'effective': 'hidden', 'source': 'org', 'until': '2026-11-30T00:00:00Z', 'note': 'Essai'},
          {'key': 'credits', 'label': 'Carnet de crédit', 'grp': 'Ventes et clients', 'state': 'default', 'effective': 'visible', 'source': 'catalog'},
          {'key': 'corrections', 'label': 'Corrections des ventes et livraisons', 'grp': 'Ventes et clients', 'state': 'default', 'effective': 'hidden', 'source': 'kind'},
          {'key': 'production', 'label': 'Production', 'grp': 'Fabrication', 'state': 'default', 'effective': 'visible', 'source': 'catalog'},
          {'key': 'tontines', 'label': 'Tontines', 'grp': 'Épargne', 'state': 'default', 'effective': 'visible', 'source': 'catalog', 'paid': true},
          {'key': 'analytics', 'label': 'Analyses', 'grp': 'Rapports', 'state': 'visible', 'effective': 'visible', 'source': 'org'},
        ])
          FeatureBoardRow.fromJson(r),
      ];
}

class _Center extends CommandCenterRepository {
  _Center() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<List<JournalEntry>> journal({String? orgId, int limit = 50, DateTime? before}) async => [
        JournalEntry(id: 'j1', at: DateTime(2026, 10, 7, 9, 30), kind: 'vitrine',
            summary: 'Vitrine : ouverture, présentation, couleurs', actor: 'Mara Une', orgId: orgId, undoable: true),
        JournalEntry(id: 'j2', at: DateTime(2026, 10, 6, 17, 2), kind: 'feature_rule',
            summary: '« Factures » masqué — Boutique Awa (jusqu\'au 30/11/2026)', actor: 'Mara Une', orgId: orgId, undoable: true),
        JournalEntry(id: 'j3', at: DateTime(2026, 10, 5, 11, 40), kind: 'identity',
            summary: 'Identité : nom, téléphone', actor: 'Mara Une', orgId: orgId,
            undoneAt: DateTime(2026, 10, 5, 12), undoneBy: 'Mara Une'),
        JournalEntry(id: 'j4', at: DateTime(2026, 10, 2, 8, 15), kind: 'cauris_gift',
            summary: 'Cauris offerts à Boutique Awa : 200', actor: 'Mara Une', orgId: orgId, undoable: true),
      ];
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<Map<String, dynamic>> fetchOrg(String orgId) async =>
      {'name': 'Boutique Awa', 'slug': 'org-retail', 'profile': 'retail', 'default_currency': 'XOF'};
  @override
  Future<String?> waveMerchant(String orgId) async => null;
  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) async => const [];
  @override
  Future<({bool enabled, String? blurb, double? lat, double? lng, double? deliveryBase, double? deliveryPerKm})>
      storefront(String orgId) async => (enabled: true, blurb: 'Tissus et pagnes du marché central.', lat: 12.37, lng: -1.52, deliveryBase: null, deliveryPerKm: null);
  @override
  Future<double?> deliveryReach(String orgId) async => null;
  @override
  Future<double?> deliveryIncludedKm(String orgId) async => null;
  @override
  Future<({String? phone, String? address})> orgContact(String orgId) async =>
      (phone: '+22670000106', address: 'Marché central');
  @override
  Future<VitrineChecklist?> vitrineChecklist(String orgId) async =>
      VitrineChecklist.fromJson({'published': 7, 'with_photo': 5, 'min_items': 3});
  @override
  Future<String?> orgLogoKey(String orgId) async => null;
  @override
  Future<FeatureStates?> featureStates(String orgId) async => FeatureStates.fromJson({
        'plan': 'free', 'balance': 420,
        'tools': [{'feature': 'accounting', 'cost': 500, 'until': '2026-11-01T00:00:00Z', 'gift': true}],
        'hidden': ['invoices'],
      });
  @override
  Future<TeamOverview?> teamOverview(String orgId) async => TeamOverview.fromJson({
        'seats': {'free': 1, 'used': 1, 'setup_done': true, 'open': false},
        'members': [
          {'user_id': 'u1', 'name': 'Awa Sanou', 'phone': '+22610600001', 'roles': ['owner'], 'owner': true},
          {'user_id': 'u2', 'name': 'Issa Kaboré', 'phone': '+22610600004', 'roles': ['admin']},
          {'user_id': 'u3', 'name': 'Mariam Ouédraogo', 'roles': ['employee'], 'salary': 45000, 'period': 'month'},
        ],
        'invitations': [],
      });
  @override
  Future<List<Member>> fetchMembers(String orgId) async => const [];
  @override
  Future<List<Entity>> fetchStructure(String orgId) async => const [];
  @override
  Future<List<String>> unseenUnlocks(String orgId) async => const [];
}

void main() {
  late LocalDb db;
  late AppScope Function(Widget child) scoped;
  const org = OrgSummary(
    id: 'o-retail', name: 'Boutique Awa', profile: 'retail', slug: 'org-retail',
    roles: ['platform_admin'], ownerName: 'Awa Sanou',
  );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    final dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
      roboto.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
    }
    await roboto.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(File('$dir/MaterialIcons-Regular.otf').readAsBytesSync())));
    await icons.load();
  });

  Future<void> boot(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });
    final admin = _Admin();
    final session = SessionController(
      db: db,
      auth: AuthRepository(null),
      admin: admin,
      accounting: AccountingRepository(null),
    );
    scoped = (child) => AppScope(
          session: session,
          localeController: LocaleController(db),
          db: db,
          auth: AuthRepository(null),
          admin: admin,
          reports: ReportsRepository(null),
          accounting: AccountingRepository(null),
          console: ConsoleRepository(null),
          farm: FarmRepository(null),
          invoicing: InvoicingRepository(null),
          retail: RetailRepository(null),
          staff: StaffRepository(null),
          capture: CaptureRepository(null, db: db),
          onboarding: OnboardingRepository(null),
          credit: CreditRepository(null),
          tontine: TontineRepository(null),
          production: ProductionRepository(null),
          notify: NotificationsRepository(null),
          analytics: AnalyticsRepository(null),
          child: child,
        );
  }

  Future<void> shoot(WidgetTester tester, String name, double width, Widget home,
      {double height = 900}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(scoped(MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: kajTheme(kajPalette),
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => home)]),
    )));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byType(Router<Object>), matchesGoldenFile('$_out/b104_d_${name}_${width.toInt()}.png'));
  }

  for (final width in [390.0, 1280.0]) {
    for (final tab in ['apercu', 'identite', 'vitrine', 'fonctions', 'equipe', 'pro', 'journal']) {
      testWidgets('fiche $tab $width', (tester) async {
        await boot(tester);
        await shoot(tester, 'fiche_$tab', width,
            BusinessFicheScreen(orgId: org.id, fiche: _Fiche('retail'), center: _Center(), initialTab: tab),
            height: tab == 'apercu' && width < 500 ? 1500 : 900);
        await tester.runAsync(db.close);
      });
    }
    testWidgets('preview $width', (tester) async {
      await boot(tester);
      await shoot(tester, 'preview', width, const MerchantPreviewScreen(org: org), height: 900);
      await tester.runAsync(db.close);
    });
    testWidgets('editor $width', (tester) async {
      await boot(tester);
      await shoot(tester, 'vitrine_editor', width, const MaraVitrineEditor(org: org, slug: 'org-retail'));
      await tester.runAsync(db.close);
    });
  }
  testWidgets('fiche apercu farm and association 390', (tester) async {
    for (final p in ['farm', 'association']) {
      await boot(tester);
      await shoot(tester, 'fiche_apercu_$p', 390,
          BusinessFicheScreen(orgId: 'o-$p', fiche: _Fiche(p), center: _Center()), height: 1500);
      await tester.runAsync(db.close);
    }
  });
}
