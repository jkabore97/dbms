// « Mettre cet article en avant » on a farm's article (after 150): the
// shop's article had it since 071, the farm's sheet only « Partager ».
// Not on an association's (whole-vitrine spot only), not on the iPhone
// app's switch-off, not on an article off the vitrine.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/access/store_rules.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/analytics/analytics_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
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
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/tontine/tontine_repository.dart';
import 'package:kaj_app/features/farm/for_sale_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _farm = OrgSummary(id: 'f1', name: 'Ferme Kossi', profile: 'farm', roles: ['owner']);
const _association = OrgSummary(id: 'a1', name: 'Les Amis', profile: 'association', roles: ['owner']);
const _eggs = Product(id: 'p1', name: 'Œufs', salePrice: 5, quantity: 6, isPublished: true);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() async {
    debugSellsDigitalInApp = null;
    debugStoreBillingPlatform = null;
    await db.close();
  });

  Future<void> sheet(WidgetTester tester, OrgSummary org, Product product) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = SessionController(
        db: db,
        auth: AuthRepository(null),
        admin: AdminRepository(null),
        accounting: AccountingRepository(null));
    await tester.pumpWidget(AppScope(
      session: session,
      localeController: LocaleController(db),
      db: db,
      auth: session.auth,
      admin: session.admin,
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
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ForSaleSheet(org: org, retail: RetailRepository(null), product: product),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  final spot = find.byKey(const Key('for-sale-spot'));

  testWidgets('a farm\'s article on the vitrine offers its spot', (tester) async {
    debugSellsDigitalInApp = true;
    await sheet(tester, _farm, _eggs);
    expect(spot, findsOneWidget);
    expect(find.text('Mettre cet article en avant'), findsOneWidget);
  });

  testWidgets('the iPhone app sells it too, through Apple', (tester) async {
    debugSellsDigitalInApp = false;
    debugStoreBillingPlatform = 'apple';
    await sheet(tester, _farm, _eggs);
    expect(spot, findsOneWidget);
  });

  testWidgets('off the vitrine, or not yet saved: no spot', (tester) async {
    debugSellsDigitalInApp = true;
    await sheet(tester, _farm, const Product(id: 'p2', name: 'Lait', salePrice: 5, quantity: 6));
    expect(spot, findsNothing);
    await sheet(tester, _farm, const Product(id: '', name: '', salePrice: 0, quantity: 0, isPublished: true));
    expect(spot, findsNothing);
  });

  testWidgets('an association buys the whole-vitrine spot only', (tester) async {
    debugSellsDigitalInApp = true;
    await sheet(tester, _association, _eggs);
    expect(spot, findsNothing);
  });
}
