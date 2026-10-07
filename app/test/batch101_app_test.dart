import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/admin/models.dart';
import 'package:kaj_app/core/admin/team.dart';
import 'package:kaj_app/core/analytics/analytics_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/invoicing/models.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/analytics/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/errors.dart';
import 'package:kaj_app/core/retail/stock_rule.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/team_access_screen.dart';
import 'package:kaj_app/features/admin/team_screen.dart';
import 'package:kaj_app/features/analytics/farm_analytics_screen.dart';
import 'package:kaj_app/features/invoicing/billing_details_screen.dart';
import 'package:kaj_app/features/farm/farm_sheets.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Batch 101 on the phone: one sentence for stock that is not there, the
/// vitrine's basket capped at what is left, a farm's feed stopped before it
/// leaves the phone, and a farm's analyses.
/// Équipe's people with a grant on one site, totals only; the dial and
/// the invoice's identity read by an admin who is not the owner.
class _Admin extends AdminRepository {
  _Admin() : super(null);

  @override
  String? get currentUserId => 'me';

  @override
  Future<TeamOverview?> teamOverview(String orgId) async => const TeamOverview(
        seats: TeamSeats(free: 1, used: 1, open: true),
        members: [
          TeamMember(userId: 'u1', name: 'Awa', roles: ['employee'],
              membershipIds: ['m1']),
        ],
      );

  @override
  Future<List<Member>> fetchMembers(String orgId) async => const [
        Member(membershipId: 'm1', userId: 'u1', role: 'employee',
            scopeKind: 'entity', scopeId: 'e1', visibility: 'summary',
            fullName: 'Awa'),
      ];

  @override
  Future<List<Entity>> fetchStructure(String orgId) async =>
      const [Entity(id: 'e1', orgId: 'o1', name: 'Marché central')];

  @override
  Future<Map<String, Map<String, String>>> featureRules(String orgId) async =>
      const {};
}

class _Invoicing extends InvoicingRepository {
  _Invoicing() : super(null);

  @override
  Future<BillingDetails> billingDetails(String orgId) async =>
      const BillingDetails(email: 'boutique@exemple.bf', taxId: 'IFU-1', footer: 'Merci');
}

Widget _fr(Widget home) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

final _farmData = FarmAnalytics.fromJson({
  'periods': {
    'month': {'income': 5000, 'expenses': 2000, 'eggs': 80, 'deaths': 3, 'orders': 1, 'orders_total': 5000},
    'last_month': {'income': 3000, 'expenses': 2500, 'eggs': 60, 'deaths': 5},
    'window': {'income': 8000, 'expenses': 4500, 'eggs': 140, 'deaths': 8, 'orders': 1, 'orders_total': 5000},
  },
  'products': [
    {'name': 'Œufs', 'units': 2, 'revenue': 5000},
    {'name': 'Poulets', 'units': 1, 'revenue': 3500},
  ],
  'expenses': [
    {'name': 'Aliment', 'amount': 4000},
    {'name': 'Vétérinaire', 'amount': 500},
  ],
  'income': [
    {'name': 'Ventes d\'œufs', 'amount': 8000},
  ],
  'flocks': [
    {'batch_code': 'B-1', 'started': 100, 'alive': 97, 'died': 3, 'died_window': 3, 'eggs_7d': 560, 'lay_rate': 0.82},
  ],
  'feed': [
    {'name': 'Aliment ponte', 'unit': 'sac', 'month': 4, 'last_month': 6, 'window': 10},
  ],
  'daily': [
    {'day': '2026-10-01', 'income': 2000, 'expenses': 0},
    {'day': '2026-10-02', 'income': 3000, 'expenses': 2000},
  ],
});

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('one sentence for stock that is not there', () {
    test('the app writes it as the server does', () {
      expect(stockShortMessage('fr', 'Savon', 3), 'Il ne reste que 3 Savon');
      expect(stockShortMessage('fr', 'Riz', 2.5), 'Il ne reste que 2.5 Riz');
      expect(stockShortMessage('fr', 'Savon', 0), 'Plus de Savon en stock');
      expect(stockShortMessage('fr', 'Savon', -4), 'Plus de Savon en stock');
      expect(stockShortMessage('en', 'Savon', 3), 'Only 3 Savon left');
    });

    test('the server\'s sentence is read back in the reader\'s language', () {
      expect(stockShortText('en', 'Il ne reste que 3 Gâteau 69'), 'Only 3 Gâteau 69 left');
      expect(stockShortText('en', 'Plus d\'Huile en stock'), 'No Huile left in stock');
      expect(stockShortText('en', 'Autre chose'), isNull);
      expect(isStockRefusal('Plus d\'Huile en stock'), isTrue);
      expect(isStockRefusal('anything', code: stockRefusalCode), isTrue);
      // De elides before a vowel or an h, as the server says it (101).
      expect(stockShortMessage('fr', 'Aliment', 0), 'Plus d\'Aliment en stock');
      expect(stockShortMessage('fr', 'huile', 0), 'Plus d\'huile en stock');
      expect(stockShortMessage('fr', 'Œufs', 0), 'Plus d\'Œufs en stock');
      expect(stockShortMessage('en', 'Aliment', 0), 'No Aliment left in stock');
      expect(stockShortText('fr', 'Plus d\'Aliment 35 en stock'),
          'Plus d\'Aliment 35 en stock');
      expect(stockShortItem('Il ne reste que 3 Gâteau 69'), (name: 'Gâteau 69', left: 3.0));
      expect(stockShortItem('Plus d\'Aliment en stock'), (name: 'Aliment', left: 0.0));
      expect(isStockRefusal('Kaj Pro : les analyses font partie de Kaj Pro.'), isFalse);
      expect(
          describeError(const PostgrestException(
              message: 'Il ne reste que 3 Savon', code: 'P0001')),
          'Il ne reste que 3 Savon');
    });
  });

  test('the vitrine knows how many a basket may hold, and nothing caps a service', () {
    final soap = PublicItem.fromRow({
      'id': 'p1', 'name': 'Savon', 'sale_price': 500, 'in_stock': true, 'stock_left': 3,
    });
    expect(soap.stockLeft, 3);
    final hair = PublicItem.fromRow({
      'id': 'p2', 'name': 'Coiffure', 'sale_price': 2000, 'in_stock': true,
      'is_service': true, 'stock_left': 0,
    });
    expect(hair.stockLeft, isNull);
    final old = PublicItem.fromRow({'id': 'p3', 'name': 'Riz', 'sale_price': 500, 'in_stock': true});
    expect(old.stockLeft, isNull, reason: 'a database before 101: uncapped');
  });

  testWidgets('a farm\'s feed is stopped on the phone past what it has', (tester) async {
    final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => db.cacheFarmItems('f1', [
          {'item_id': 'i1', 'name': 'Aliment', 'unit': 'sac', 'on_hand': 3},
        ]));
    tester.view.physicalSize = const Size(700, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_fr(Scaffold(body: MoveStockSheet(db: db, orgId: 'f1'))));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.enterText(find.widgetWithText(TextField, 'Quantité'), '5');
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('Il ne reste que 3 Aliment'), findsOneWidget);
    expect(await tester.runAsync(db.pendingCount), 0, reason: 'nothing left the phone');
  });

  testWidgets('a farm\'s analyses: the month against the last, what sold, the flocks, the feed',
      (tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_fr(FarmAnalyticsScreen(
      analytics: AnalyticsRepository(null),
      orgId: 'f1',
      orgName: 'Ferme',
      currency: 'XOF',
      load: (_) async => _farmData,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Ce mois-ci'), findsOneWidget);
    expect(find.text('Ce qui se vend'), findsOneWidget);
    expect(find.text('Le plus vendu'), findsOneWidget);
    expect(find.text('Mes bandes'), findsOneWidget);
    expect(find.text('97 vivants sur 100'), findsOneWidget);
    expect(find.text('Aliment ponte'), findsOneWidget);
    expect(find.text('Où va l\'argent'), findsOneWidget);
  });

  testWidgets('a farm without the tool reads the Pro words', (tester) async {
    await tester.pumpWidget(_fr(FarmAnalyticsScreen(
      analytics: AnalyticsRepository(null),
      orgId: 'f1',
      orgName: 'Ferme',
      currency: 'XOF',
      load: (_) async => throw const PostgrestException(
          message:
              'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.',
          code: 'P0001'),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mara Pro : les analyses'), findsOneWidget);
  });

  group('Équipe and the owner\'s settings (101 / 103)', () {
    testWidgets('each grant says what it covers, as « Personnes » did', (tester) async {
      await tester.pumpWidget(_fr(TeamScreen(
        org: const OrgSummary(id: 'o1', name: 'Boutique', profile: 'retail', roles: ['admin']),
        admin: _Admin(),
        onboarding: OnboardingRepository(null),
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('Marché central · totaux seulement'), findsOneWidget);
    });

    testWidgets('the dial is read, not saved, by anybody but the owner', (tester) async {
      await tester.pumpWidget(_fr(TeamAccessScreen(admin: _Admin(), orgId: 'o1', canSave: false)));
      await tester.pumpAndSettle();
      expect(find.text('Réservé au propriétaire'), findsOneWidget);
      expect(find.text('Enregistrer'), findsNothing);
      await tester.pumpWidget(_fr(TeamAccessScreen(admin: _Admin(), orgId: 'o1')));
      await tester.pumpAndSettle();
      expect(find.text('Enregistrer'), findsOneWidget);
    });

    testWidgets('the invoice\'s e-mail, tax number and footer are the owner\'s', (tester) async {
      tester.view.physicalSize = const Size(480, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_fr(BillingDetailsScreen(
        org: const OrgSummary(id: 'o1', name: 'Boutique', profile: 'retail', roles: ['admin']),
        invoicing: _Invoicing(),
      )));
      await tester.pumpAndSettle();
      for (final k in ['billing-email', 'billing-tax-id', 'billing-footer']) {
        expect(tester.widget<TextField>(find.byKey(Key(k))).enabled, isFalse, reason: k);
      }
      expect(find.text('Réservé au propriétaire'), findsNWidgets(3));
      await tester.pumpWidget(_fr(BillingDetailsScreen(
        org: const OrgSummary(id: 'o2', name: 'Boutique', profile: 'retail', roles: ['owner']),
        invoicing: _Invoicing(),
      )));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('billing-email'))).enabled, isTrue);
    });
  });

  test('roles are offered down the ladder', () {
    final ranks = [for (final r in adminGrantableRoles.keys) accountRoleRank(r)];
    expect(ranks, [...ranks]..sort((a, b) => b.compareTo(a)));
  });
}
