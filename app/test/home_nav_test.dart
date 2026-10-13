import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/org_access.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/home/home_nav.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every home screen leads with words, not pictures.
///
/// The owner's report: the row of icons in the top bar was not intuitive —
/// eight pictures, no words, the door out to the street first among them.
/// Each home screen now has one labelled bar at its foot: the home screen,
/// three everyday tools, and Plus for the rest, by name.
class _Shop extends RetailRepository {
  _Shop(super.client, {this.pending = 0});

  final int pending;

  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();

  @override
  Future<List<ExpiringProduct>> expiring(String orgId,
          {int within = 14}) async =>
      const [];

  @override
  Future<List<Product>> products(String orgId,
          {bool activeOnly = true}) async =>
      const [];

  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) async => 0;

  @override
  Future<int> pendingOrders(String orgId) async => pending;
}

const _shop = OrgSummary(
  id: 'org-1',
  name: 'Boutique Awa',
  slug: 'boutique-awa',
  profile: 'retail',
  roles: ['owner'],
  currency: 'XOF',
);

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

List<String> _barLabels(WidgetTester tester) => tester
    .widgetList<NavigationDestination>(find.byType(NavigationDestination))
    .map((d) => d.label)
    .toList();

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

  group('the shop', () {
    testWidgets('five labelled places, and a top bar with no tools in it',
        (tester) async {
      await tester.pumpWidget(_app(StoreHomeScreen(
        org: _shop,
        retail: _Shop(client, pending: 3),
        invoicing: InvoicingRepository(client),
      )));
      await tester.pump();
      await tester.pump();

      // 134: Vente · Catalogue · Commandes · Argent · Plus.
      expect(_barLabels(tester),
          ['Vente', 'Catalogue', 'Commandes', 'Argent', 'Plus']);
      // The orders waiting ride on Commandes.
      expect(
          find.descendant(
              of: find.byType(NavigationBar), matching: find.text('3')),
          findsOneWidget);
      // No bare icons left in the top bar.
      expect(
          find.descendant(
              of: find.byType(AppBar), matching: find.byType(IconButton)),
          findsNothing);
    });

    testWidgets('Plus lists the rest by name, the street doors in words',
        (tester) async {
      // Tall enough for the whole sheet: a lazy list builds only what shows.
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(StoreHomeScreen(
        org: _shop,
        retail: _Shop(client),
        invoicing: InvoicingRepository(client),
      )));
      await tester.pump();
      await tester.tap(find.text('Plus'));
      await tester.pumpAndSettle();

      final sheet = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.title as Text).data)
          .toList();
      // 134: under its headings — MA VITRINE, MON ÉQUIPE, MOI. « Dépense »
      // is a button on the home, « Mes services » in Catalogue.
      expect(sheet, [
        'Voir ma vitrine',
        'Mon chemin',
        'Production',
        'Équipe',
        'Administration',
        'Compte',
        'Voir le marché',
      ]);
      for (final g in ['vitrine', 'team', 'me']) {
        expect(find.byKey(Key('plus-heading-$g')), findsOneWidget, reason: g);
      }
      expect(find.text('MA VITRINE'), findsOneWidget);
      expect(find.text('MON ÉQUIPE'), findsOneWidget);
      expect(find.text('MOI'), findsOneWidget);
    });

    testWidgets('a tool the owner hid is not on the bar, and it closes up',
        (tester) async {
      await tester.pumpWidget(_app(StoreHomeScreen(
        org: _shop,
        retail: _Shop(client),
        invoicing: InvoicingRepository(client),
        access: const OrgAccess.forTier({
          'products': 'edit',
          'orders': 'hidden',
          'invoices': 'hidden',
          'production': 'hidden',
          'photos': 'hidden',
        }),
      )));
      await tester.pump();

      // Argent stays for the expenses and the carnet; Catalogue for the
      // articles.
      expect(_barLabels(tester), ['Vente', 'Catalogue', 'Argent', 'Plus']);
    });

    testWidgets('the alerts question is a card on the page, not a bar icon',
        (tester) async {
      // OrderAlert.supported is false off the web, so the card is not drawn
      // here at all — and neither is the old bell-with-a-plus in the bar.
      await tester.pumpWidget(_app(StoreHomeScreen(
        org: _shop,
        retail: _Shop(client),
      )));
      await tester.pump();
      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
      expect(find.text('Activer'), findsNothing);
    });
  });

  testWidgets('the farm: Bandes, Stock, Ventes on the bar', (tester) async {
    // Tall enough for the whole Plus sheet.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(FarmHomeScreen(
      db: db,
      org: const OrgSummary(
          id: 'farm-1', name: 'Ferme Ignace', profile: 'farm', roles: ['owner']),
      invoicing: InvoicingRepository(client),
    )));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    expect(_barLabels(tester),
        ['Accueil', 'Bandes', 'Stock', 'Ventes', 'Plus']);
    // The three tiles that used to sit mid-page are the bar now.
    expect(find.text('Stock'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.byType(IconButton)),
        findsNothing);

    await tester.tap(find.text('Plus'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Production'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Compte'), findsOneWidget);
  });

  testWidgets('the association: Journal, Rapports, Catalogue on the bar',
      (tester) async {
    const org = OrgSummary(
        id: 'ch-1', name: 'Grace Chapel', profile: 'church', roles: ['owner']);
    await tester.pumpWidget(_app(ChurchHomeScreen(
      db: db,
      orgId: org.id,
      orgName: org.name,
      org: org,
      reports: ReportsRepository(client),
      invoicing: InvoicingRepository(client),
      retail: _Shop(client),
      onHistory: () {},
    )));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    expect(_barLabels(tester),
        ['Accueil', 'Journal', 'Rapports', 'Catalogue', 'Plus']);
  });

  group('the rule', () {
    HomeDestination d(String l) =>
        HomeDestination(icon: Icons.circle, label: l, onTap: () {});

    testWidgets('four tools and nothing else: all four fit, no Plus',
        (tester) async {
      late List<String> labels;
      await tester.pumpWidget(_app(Builder(builder: (context) {
        labels = HomeNav(
                home: d('Home'), primary: [d('A'), d('B'), d('C'), d('D')])
            .slots(context)
            .map((s) => s.label)
            .toList();
        return const SizedBox();
      })));
      expect(labels, ['Home', 'A', 'B', 'C', 'D']);
    });

    testWidgets('anything more: three tools, then Plus with the rest',
        (tester) async {
      late HomeNav nav;
      late List<String> labels;
      await tester.pumpWidget(_app(Builder(builder: (context) {
        nav = HomeNav(
            home: d('Home'),
            primary: [d('A'), d('B'), d('C'), d('D')],
            more: [d('E')]);
        labels = nav.slots(context).map((s) => s.label).toList();
        return const SizedBox();
      })));
      expect(labels, ['Home', 'A', 'B', 'C', 'Plus']);
      expect(nav.overflow.map((s) => s.label), ['D', 'E']);
    });

    testWidgets('on a wide screen the places stand in a labelled rail',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(StoreHomeScreen(
        org: _shop,
        retail: _Shop(client),
        invoicing: InvoicingRepository(client),
      )));
      await tester.pump();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(NavigationRail), matching: find.text('Catalogue')),
          findsOneWidget);
    });
  });
}
