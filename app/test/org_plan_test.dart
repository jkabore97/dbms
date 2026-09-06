import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/console/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/features/admin/org_settings_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The plan flag on the phone (065, M10 block 1): the plan rides the org
/// list and its cache like the suspended flag, the v10 → v11 upgrade adds
/// the column without disturbing a device already in the field, the console
/// reads the Pro count, and the settings screen shows every member which
/// plan they are on while only the platform gets the form to change it.
class _Admin extends AdminRepository {
  _Admin({this.plan = 'free', this.until, this.note}) : super(null);

  final String plan;
  final DateTime? until;
  final String? note;

  /// What the form asked to save, verbatim.
  final saved = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> fetchOrg(String orgId) async => {
        'id': orgId,
        'name': 'Boutique Awa',
        'slug': 'boutique-awa',
        'profile': 'retail',
        'default_currency': 'XOF',
      };

  @override
  Future<String?> waveMerchant(String orgId) async => null;

  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) async => const [];

  @override
  Future<
      ({
        bool enabled,
        String? blurb,
        double? lat,
        double? lng,
        double? deliveryBase,
        double? deliveryPerKm
      })> storefront(String orgId) async => (
        enabled: false,
        blurb: null,
        lat: null,
        lng: null,
        deliveryBase: null,
        deliveryPerKm: null,
      );

  @override
  Future<({String plan, DateTime? until, String? note})> orgPlan(
          String orgId) async =>
      (plan: plan, until: until, note: note);

  @override
  Future<void> setOrgPlan(
    String orgId, {
    required String plan,
    DateTime? until,
    String? note,
  }) async {
    saved.add({'org': orgId, 'plan': plan, 'until': until, 'note': note});
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  Future<String> freshPath(String name) async {
    await databaseFactory.deleteDatabase(name);
    addTearDown(() => databaseFactory.deleteDatabase(name));
    return name;
  }

  group('OrgSummary carries the plan', () {
    test('reads it from my_orgs(), and a database before 065 means free', () {
      final pro = OrgSummary.fromRpc({
        'org_id': 'o1',
        'name': 'Boutique',
        'profile': 'retail',
        'roles': ['owner'],
        'plan': 'pro',
      });
      expect(pro.plan, 'pro');
      expect(pro.isPro, isTrue);

      final free = OrgSummary.fromRpc({
        'org_id': 'o2',
        'name': 'Ferme',
        'profile': 'farm',
        'roles': ['owner'],
        'plan': 'free',
      });
      expect(free.isPro, isFalse);

      // The app can run ahead of the database: no column, no plans, free.
      final before = OrgSummary.fromRpc({
        'org_id': 'o3',
        'name': 'Atelier',
        'profile': 'generic',
        'roles': ['owner'],
      });
      expect(before.plan, 'free');
    });

    test('survives the cache round trip', () async {
      final db = await LocalDb.open(path: await freshPath('plan-cache.db'));
      addTearDown(db.close);

      await db.cacheOrgs(const [
        OrgSummary(
            id: 'o1', name: 'Pro', profile: 'retail', roles: ['owner'], plan: 'pro'),
        OrgSummary(id: 'o2', name: 'Libre', profile: 'farm', roles: ['owner']),
      ]);

      final byId = {for (final o in await db.cachedOrgs()) o.id: o};
      expect(byId['o1']!.isPro, isTrue);
      expect(byId['o2']!.isPro, isFalse);
    });
  });

  test('the v10 -> v11 upgrade adds the column and old rows are free',
      () async {
    final path = await freshPath('plan-upgrade.db');

    // A device sitting at v10: cached_orgs as it shipped then, a business
    // already in it, no `plan` column at all.
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 10),
    );
    await old.execute('''
      CREATE TABLE cached_orgs (
        org_id     TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        slug       TEXT,
        profile    TEXT NOT NULL,
        currency   TEXT,
        roles      TEXT,
        visibility TEXT,
        theme      TEXT,
        suspended  INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await old.insert('cached_orgs', {
      'org_id': 'o-old',
      'name': 'Commerce existant',
      'profile': 'retail',
      'roles': 'owner',
      'visibility': 'full',
      'suspended': 1,
    });
    await old.close();

    final db = await LocalDb.open(path: path);
    addTearDown(db.close);

    final cached = await db.cachedOrgs();
    expect(cached, hasLength(1));
    expect(cached.single.name, 'Commerce existant');
    expect(cached.single.plan, 'free');
    // What was there before is untouched.
    expect(cached.single.suspended, isTrue);

    await db.cacheOrgs(const [
      OrgSummary(
          id: 'o-old',
          name: 'Commerce existant',
          profile: 'retail',
          roles: ['owner'],
          plan: 'pro'),
    ]);
    expect((await db.cachedOrgs()).single.isPro, isTrue);
  });

  test('the console overview reads the Pro count, zero before 065', () {
    expect(PlatformOverview.fromRow({'total': 3, 'pro': 2}).pro, 2);
    expect(PlatformOverview.fromRow({'total': 3}).pro, 0);
  });

  group('the settings screen', () {
    Future<void> pump(
      WidgetTester tester,
      _Admin admin, {
      required bool platform,
      String plan = 'free',
    }) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: OrgSettingsScreen(
          admin: admin,
          orgId: 'org-1',
          canSetPlan: platform,
          canSuspend: platform,
          plan: plan,
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a member reads Kaj Pro and gets no form', (tester) async {
      await pump(tester, _Admin(), platform: false, plan: 'pro');
      expect(find.text('Formule'), findsOneWidget);
      expect(find.text('Kaj Pro'), findsOneWidget);
      expect(find.text('Formule (plateforme)'), findsNothing);
      expect(find.text('Enregistrer la formule'), findsNothing);
    });

    testWidgets('a member on the free plan reads Kaj (gratuit)',
        (tester) async {
      await pump(tester, _Admin(), platform: false);
      expect(find.text('Kaj (gratuit)'), findsOneWidget);
    });

    testWidgets('the platform sees the form prefilled with what it set',
        (tester) async {
      await pump(
        tester,
        _Admin(plan: 'pro', until: DateTime(2027, 9, 12), note: 'partenaire'),
        platform: true,
        plan: 'pro',
      );
      expect(find.text('Formule (plateforme)'), findsOneWidget);
      expect(find.text('Payé jusqu\'au 12 septembre 2027'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'partenaire'), findsOneWidget);
    });

    testWidgets('the platform puts a business on Pro without an end date',
        (tester) async {
      final admin = _Admin();
      await pump(tester, admin, platform: true);

      await tester.ensureVisible(find.text('Kaj Pro'));
      await tester.tap(find.text('Kaj Pro'));
      await tester.pump();
      expect(find.textContaining('Payé jusqu\'au…'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Note (pour la plateforme)'),
          'Wave 25 000 F le 12/09');
      final save = find.text('Enregistrer la formule');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();

      // No date: asked, not assumed.
      expect(find.text('Kaj Pro sans date de fin ?'), findsOneWidget);
      await tester.tap(find.text('Sans date de fin'));
      await tester.pump();
      await tester.pump();

      expect(admin.saved, hasLength(1));
      expect(admin.saved.single['org'], 'org-1');
      expect(admin.saved.single['plan'], 'pro');
      expect(admin.saved.single['until'], isNull);
      expect(admin.saved.single['note'], 'Wave 25 000 F le 12/09');
      expect(find.text('Entreprise passée sur Kaj Pro.'), findsOneWidget);
    });

    testWidgets('back to free sends no date and asks nothing', (tester) async {
      final admin =
          _Admin(plan: 'pro', until: DateTime(2027, 9, 12), note: 'partenaire');
      await pump(tester, admin, platform: true, plan: 'pro');

      await tester.ensureVisible(find.text('Kaj'));
      await tester.tap(find.text('Kaj'));
      await tester.pump();
      final save = find.text('Enregistrer la formule');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump();

      expect(find.text('Kaj Pro sans date de fin ?'), findsNothing);
      expect(admin.saved.single['plan'], 'free');
      expect(admin.saved.single['until'], isNull);
      expect(
          find.text('Entreprise repassée sur Kaj (gratuit).'), findsOneWidget);
    });
  });
}
