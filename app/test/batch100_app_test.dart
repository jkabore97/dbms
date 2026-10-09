import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/alert_tone.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/auth/org_picker_screen.dart';
import 'package:kaj_app/features/home/business_shell.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Batch 100, the app's half: the picker that tells kinds apart and names
/// owners, the switch beside the bell, the phone's ring, and the vitrine's
/// number that opens WhatsApp.
class _OneShop extends StorefrontRepository {
  _OneShop(this.profile) : super(null);

  final String profile;

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => PublicShop(
        orgId: 'o1',
        name: 'Ferme Awa',
        slug: 'ferme-awa',
        profile: profile,
        phone: '+226 70 11 22 33',
      );

  @override
  Future<List<PublicItem>> items(String slug) async => const [
        PublicItem(id: 'p1', name: 'Oeufs', price: 100, inStock: true),
      ];
}

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: child,
    );

const _many = [
  OrgSummary(id: 's1', name: 'Boutique Sanou', profile: 'retail', ownerName: 'Awa Sanou'),
  OrgSummary(id: 's2', name: 'Boutique Kaboré', profile: 'retail', ownerName: 'Issa Kaboré'),
  OrgSummary(id: 'f1', name: 'Ferme du Nord', profile: 'farm', ownerName: 'Ignace Ouédraogo'),
  OrgSummary(id: 'a1', name: 'Église Grâce', profile: 'church'),
  OrgSummary(id: 'a2', name: 'Tontine des femmes', profile: 'association', ownerName: 'Mariam Zongo'),
  OrgSummary(id: 'f2', name: 'Ferme Bobo', profile: 'farm'),
];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('owner_name (100) on the org list', () {
    test('is read from my_orgs(); absent or blank is no owner', () {
      Map<String, dynamic> row([Object? owner]) => {
            'org_id': 'o',
            'name': 'N',
            'profile': 'retail',
            'owner_name': ?owner,
          };
      expect(OrgSummary.fromRpc(row('Awa Sanou')).ownerName, 'Awa Sanou');
      expect(OrgSummary.fromRpc(row()).ownerName, isNull);
      expect(OrgSummary.fromRpc(row('  ')).ownerName, isNull);
    });

    test('rides the offline cache, and a v11 phone upgrades', () async {
      const name = 'b100-owner.db';
      await databaseFactory.deleteDatabase(name);
      addTearDown(() => databaseFactory.deleteDatabase(name));
      // A phone at v11: cached_orgs without the column, one business in it.
      final old = await databaseFactory.openDatabase(name,
          options: OpenDatabaseOptions(version: 11));
      await old.execute('''
        CREATE TABLE cached_orgs (
          org_id TEXT PRIMARY KEY, name TEXT NOT NULL, slug TEXT,
          profile TEXT NOT NULL, currency TEXT, roles TEXT, visibility TEXT,
          theme TEXT, suspended INTEGER NOT NULL DEFAULT 0,
          plan TEXT NOT NULL DEFAULT 'free'
        )''');
      await old.insert('cached_orgs',
          {'org_id': 'o1', 'name': 'Ancienne', 'profile': 'farm'});
      await old.close();

      final db = await LocalDb.open(path: name);
      addTearDown(db.close);
      expect((await db.cachedOrgs()).single.ownerName, isNull);
      await db.cacheOrgs(const [
        OrgSummary(id: 'o1', name: 'Ancienne', profile: 'farm', ownerName: 'Ignace'),
      ]);
      expect((await db.cachedOrgs()).single.ownerName, 'Ignace');
    });
  });

  group('« Changer d\'activité »', () {
    testWidgets('names the owner where known, nothing where not',
        (tester) async {
      await tester.pumpWidget(_app(OrgPickerScreen(
        orgs: const [
          OrgSummary(id: 'a', name: 'Boutique Sanou', profile: 'retail', ownerName: 'Awa Sanou'),
          OrgSummary(id: 'b', name: 'Ferme du Nord', profile: 'farm'),
        ],
        onSelected: (_) {},
      )));
      expect(find.text('Awa Sanou'), findsOneWidget);
      expect(find.byKey(const Key('picker-owner-b')), findsNothing);
      // Two activities: no search box, but two kinds, so the chips.
      expect(find.byKey(const Key('picker-search')), findsNothing);
      expect(find.byKey(const Key('picker-kind-retail')), findsOneWidget);
      expect(find.byKey(const Key('picker-kind-farm')), findsOneWidget);
      expect(find.byKey(const Key('picker-kind-association')), findsNothing);
    });

    testWidgets('one kind only: no chips', (tester) async {
      await tester.pumpWidget(_app(OrgPickerScreen(
        orgs: const [
          OrgSummary(id: 'a', name: 'A', profile: 'retail'),
          OrgSummary(id: 'b', name: 'B', profile: 'retail'),
        ],
        onSelected: (_) {},
      )));
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('filters by kind and finds by name or owner, accents aside',
        (tester) async {
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      OrgSummary? picked;
      await tester.pumpWidget(_app(OrgPickerScreen(
        orgs: _many,
        onSelected: (o) => picked = o,
      )));
      expect(find.byKey(const Key('picker-search')), findsOneWidget);

      // Associations: 'church' and 'association' together. The chips are
      // one line that scrolls sideways (100): brought into view first.
      await tester.ensureVisible(find.byKey(const Key('picker-kind-association')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('picker-kind-association')));
      await tester.pump();
      expect(find.text('Église Grâce'), findsOneWidget);
      expect(find.text('Tontine des femmes'), findsOneWidget);
      expect(find.text('Boutique Sanou'), findsNothing);

      // Back to all, then search the owner without his accent.
      await tester.ensureVisible(find.byKey(const Key('picker-kind-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('picker-kind-all')));
      await tester.enterText(find.byKey(const Key('picker-search')), 'ouedraogo');
      await tester.pump();
      expect(find.text('Ferme du Nord'), findsOneWidget);
      expect(find.text('Ferme Bobo'), findsNothing);
      await tester.tap(find.text('Ferme du Nord'));
      expect(picked?.id, 'f1');

      await tester.enterText(find.byKey(const Key('picker-search')), 'zzz');
      await tester.pump();
      expect(find.text('Aucune activité ne correspond.'), findsOneWidget);
    });

    test('each kind has its own colour', () {
      final colours = {
        for (final p in ['retail', 'farm', 'association', 'generic']) kindColour(p),
      };
      expect(colours, hasLength(4));
      expect(kindColour('church'), kindColour('association'));
    });
  });

  group('the switch beside the bell', () {
    Future<void> pump(WidgetTester tester, int activities) async {
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            appBar: AppBar(actions: [
              SwitchActivityButton(activities: activities),
              const Icon(Icons.notifications_outlined),
            ]),
          ),
        ),
        GoRoute(
          path: '/entreprises',
          builder: (_, _) => const Text('le sélecteur'),
        ),
      ]);
      await tester.pumpWidget(MaterialApp.router(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        routerConfig: router,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('one activity: no button', (tester) async {
      await pump(tester, 1);
      expect(find.byKey(const Key('switch-activity')), findsNothing);
    });

    testWidgets('two: left of the bell, opening the picker', (tester) async {
      await pump(tester, 2);
      final button = find.byKey(const Key('switch-activity'));
      expect(button, findsOneWidget);
      expect(tester.getCenter(button).dx,
          lessThan(tester.getCenter(find.byIcon(Icons.notifications_outlined)).dx));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('le sélecteur'), findsOneWidget);
    });
  });

  group('the ring', () {
    test('one original tone, bundled and under 30 KB; no choice of the app\'s own (122)', () async {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final f = File(AlertTone.asset);
      expect(f.existsSync(), isTrue, reason: AlertTone.asset);
      expect(f.lengthSync(), lessThan(30 * 1024));
      expect(String.fromCharCodes(f.readAsBytesSync().take(4)), 'RIFF');
      expect(pubspec, contains('- ${AlertTone.asset}'));
      expect(Directory('assets/sounds').listSync().map((e) => e.path.split('/').last),
          ['carillon.wav'], reason: 'the other tones went with their choice');
      // A ring where nothing can play is quiet, never an error.
      await AlertTone.ring();
    });
  });

  group('the vitrine\'s number', () {
    for (final profile in ['retail', 'farm', 'association']) {
      testWidgets('is shown and is a WhatsApp link ($profile)', (tester) async {
        late LocalDb db;
        await tester.runAsync(() async {
          db = await LocalDb.open(path: inMemoryDatabasePath);
        });
        addTearDown(() => tester.runAsync(db.close));
        tester.view.physicalSize = const Size(420, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: StorefrontScreen(
            slug: 'ferme-awa',
            storefront: _OneShop(profile),
            capture: CaptureRepository(null, db: db),
            session: SessionController(
              db: db,
              auth: AuthRepository(null),
              admin: AdminRepository(null),
              accounting: AccountingRepository(null),
            ),
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.byKey(const Key('shop-phone')), findsOneWidget);
        expect(find.text('+226 70 11 22 33'), findsOneWidget);
        // « Appeler » stays its own button.
        expect(find.text('Appeler'), findsOneWidget);
        expect(whatsappUrl('+226 70 11 22 33'), 'https://wa.me/22670112233');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
