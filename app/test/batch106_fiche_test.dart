import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/console/fiche_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/look_only.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/features/admin/fiche/business_fiche_screen.dart';
import 'package:kaj_app/features/admin/fiche/look_only_view.dart';
import 'package:kaj_app/features/admin/fiche/merchant_preview_screen.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Batch 104's fiche entreprise (106), the app's half: the Aperçu reads
/// the owner, the plan, the cauris and what waits; the Identité changes the
/// kind only with the name typed back; the Fonctions lock a paid feature;
/// every change offers « Annuler »; « Voir comme le commerçant » draws the
/// owner's role, plan and visibility and lets nothing be touched; the
/// owner's bell says what Mara changed. A shop, a farm and an association.
Map<String, dynamic> overviewJson(String profile) => {
      'id': 'o-$profile',
      'name': switch (profile) {
        'farm' => 'Ferme Issa',
        'association' => 'Entraide Mariam',
        _ => 'Boutique Awa',
      },
      'slug': 'org-$profile',
      'profile': profile,
      'currency': 'XOF',
      'phone': '+22670000106',
      'address': 'Marché central',
      'created_at': '2026-01-05T08:00:00Z',
      'health': 'silent',
      'days_silent': 34,
      'last_activity_at': '2026-09-03T08:00:00Z',
      'owner': {'user_id': 'u1', 'name': 'Awa Sanou', 'phone': '+22610600001', 'email': 'awa@example.com'},
      'members': 3,
      'roles': {'owner': 1, 'admin': 1, 'employee': 1},
      'plan': 'free',
      'plan_raw': 'free',
      'cauris': 420,
      'promo': [
        {'points': 100, 'until': '2026-12-31'},
      ],
      'unlocks': [
        {'feature': 'accounting', 'until': '2026-11-01T00:00:00Z', 'gift': true, 'note': 'Offert par Mara'},
      ],
      'vitrine': {'open': true, 'published': 7},
      'rules': 1,
      'actions': 2,
      'alerts': [
        {'kind': 'paid_claim', 'n': 1},
        {'kind': 'silent', 'days': 34},
        {'kind': 'setup'},
      ],
    };

class _Fiche extends FicheRepository {
  _Fiche(String profile)
      : o = OrgOverview.fromJson(overviewJson(profile)),
        super(null);

  final OrgOverview o;
  final calls = <Map<String, Object?>>[];

  @override
  bool get isConfigured => true;

  @override
  Future<OrgOverview> overview(String orgId) async => o;

  @override
  Future<List<FeatureBoardRow>> board(String orgId) async => [
        FeatureBoardRow.fromJson(const {
          'key': 'invoices', 'label': 'Factures', 'grp': 'Ventes et clients',
          'state': 'default', 'effective': 'visible', 'source': 'catalog', 'paid': false,
        }),
        FeatureBoardRow.fromJson(const {
          'key': 'tontines', 'label': 'Tontines', 'grp': 'Épargne',
          'state': 'default', 'effective': 'visible', 'source': 'catalog', 'paid': true,
          'pro_tool': 'tontines',
        }),
      ];

  @override
  Future<String?> setFeature(String orgId, String feature, String state,
      {DateTime? until, String? note}) async {
    calls.add({'feature': feature, 'state': state, 'note': note});
    return 'action-rule';
  }

  @override
  Future<String?> updateIdentity(String orgId,
      {String? name,
      String? profile,
      String? slug,
      String? currency,
      String? phone,
      String? address,
      bool? verified,
      String? confirm}) async {
    calls.add({'profile': profile, 'confirm': confirm, 'phone': phone, 'name': name});
    return 'action-identity';
  }
}

class _Center extends CommandCenterRepository {
  _Center() : super(null);

  final undone = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<List<JournalEntry>> journal(
      {String? orgId, int limit = 50, DateTime? before, String? beforeId}) async => [
        JournalEntry(
          id: 'j1',
          at: DateTime(2026, 10, 7, 9, 30),
          kind: 'vitrine',
          summary: 'Vitrine : présentation, logo',
          actor: 'Mara Une',
          orgId: orgId,
          undoable: true,
        ),
      ];

  @override
  Future<void> undo(String actionId) async => undone.add(actionId);
}

Future<void> _open(WidgetTester tester, _Fiche fiche, _Center center,
    {String? tab, Size size = const Size(1280, 1000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: BusinessFicheScreen(orgId: fiche.o.id, fiche: fiche, center: center, initialTab: tab),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('the Aperçu', () {
    for (final profile in ['retail', 'farm', 'association']) {
      testWidgets('says the owner, the plan, the cauris and what waits ($profile)', (tester) async {
        final fiche = _Fiche(profile);
        await _open(tester, fiche, _Center());
        expect(find.byKey(const Key('business-fiche')), findsOneWidget);
        for (final t in ['Aperçu', 'Identité', 'Vitrine', 'Fonctions', 'Équipe', 'Pro et cauris', 'Journal']) {
          expect(find.text(t), findsWidgets, reason: t);
        }
        expect(find.byKey(const Key('fiche-owner-name')), findsOneWidget);
        expect(find.text('Awa Sanou'), findsWidgets);
        expect(find.text('420'), findsOneWidget);
        expect(find.text('Gratuit'), findsOneWidget);
        expect(find.text('Formule Mara'), findsOneWidget);
        expect(find.byKey(const Key('fiche-alert-paid_claim')), findsOneWidget);
        expect(find.text('Silencieuse depuis 34 jours'), findsOneWidget);
        expect(find.byKey(const Key('fiche-preview')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    test('parses what the server sends', () {
      final o = OrgOverview.fromJson(overviewJson('association'));
      expect(o.isAssociation, isTrue);
      expect(o.owner?.phone, '+22610600001');
      expect(o.promo.single.points, 100);
      expect(o.unlocks.single.gift, isTrue);
      expect(o.published, 7);
      expect(o.alerts.map((a) => a['kind']), ['paid_claim', 'silent', 'setup']);
    });
  });

  group('the Identité', () {
    testWidgets('changes the kind only with the business\'s name typed back', (tester) async {
      final fiche = _Fiche('retail');
      await _open(tester, fiche, _Center(), tab: 'identite');
      expect(find.byKey(const Key('mara-as-banner')), findsOneWidget);
      // No verification for a shop: it is an association's.
      expect(find.byKey(const Key('identity-verified')), findsNothing);
      await tester.tap(find.text('Ferme').last);
      await tester.pump();
      expect(find.byKey(const Key('identity-kind-warning')), findsOneWidget);
      await tester.tap(find.byKey(const Key('identity-save')));
      await tester.pumpAndSettle();
      final go = find.byKey(const Key('identity-confirm-go'));
      expect(tester.widget<FilledButton>(go).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('identity-confirm-name')), 'boutique awa');
      await tester.pump();
      expect(tester.widget<FilledButton>(go).onPressed, isNotNull);
      await tester.tap(go);
      await tester.pumpAndSettle();
      expect(fiche.calls.single['profile'], 'farm');
      expect(fiche.calls.single['confirm'], 'boutique awa');
      // Nothing else was sent: the name and the phone were left as they were.
      expect(fiche.calls.single['name'], isNull);
      expect(fiche.calls.single['phone'], isNull);
      expect(find.text('Annuler'), findsWidgets);
    });

    testWidgets('an association shows Mara\'s verification', (tester) async {
      await _open(tester, _Fiche('association'), _Center(), tab: 'identite');
      expect(find.byKey(const Key('identity-verified')), findsOneWidget);
    });
  });

  group('the Fonctions', () {
    testWidgets('a paid feature is locked; a switch asks, is saved, and is undone', (tester) async {
      final fiche = _Fiche('farm');
      final center = _Center();
      await _open(tester, fiche, center, tab: 'fonctions');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('feature-paid-tontines')), findsOneWidget);
      expect(find.text('Payée — ne peut pas être masquée'), findsOneWidget);
      // Its « Masquée » does nothing.
      await tester.tap(find.descendant(
          of: find.byKey(const Key('feature-tontines')), matching: find.text('Masquée')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rule-save')), findsNothing);
      // The invoices: asked, then saved, then « Annuler ».
      await tester.tap(find.descendant(
          of: find.byKey(const Key('feature-invoices')), matching: find.text('Masquée')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('rule-note')), 'Essai');
      await tester.tap(find.byKey(const Key('rule-save')));
      await tester.pumpAndSettle();
      expect(fiche.calls.single, {'feature': 'invoices', 'state': 'hidden', 'note': 'Essai'});
      await tester.tap(find.byKey(const Key('undo-bar')));
      await tester.pumpAndSettle();
      expect(center.undone, ['action-rule']);
    });
  });

  testWidgets('the Journal: Mara\'s lines with « Annuler », for this business', (tester) async {
    final center = _Center();
    await _open(tester, _Fiche('retail'), center, tab: 'journal');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Vitrine : présentation, logo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('journal-undo-j1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('journal-undo-confirm')));
    await tester.pumpAndSettle();
    expect(center.undone, ['j1']);
  });

  group('« Voir comme le commerçant »', () {
    const terms = PlanTerms.defaults;
    const shop = OrgSummary(
      id: 'o1',
      name: 'Boutique Awa',
      profile: 'retail',
      roles: ['platform_admin'],
    );

    test('the owner\'s role, the plan\'s locks, what Mara hides', () {
      final owner = ownerOf(shop);
      expect(owner.roles, ['owner']);
      expect(owner.isAdmin, isTrue);
      final states = FeatureStates.fromJson({
        'plan': 'free',
        'tools': [
          {'feature': 'accounting', 'cost': 500, 'until': '2099-01-01T00:00:00Z'},
        ],
        'hidden': ['credits'],
      });
      final access = ownerAccess(owner, states, terms);
      // A platform admin has no lock; the owner of a free business has.
      expect(access.isProLocked('analytics'), terms.proFeatures.contains('analytics'));
      expect(access.isProLocked('accounting'), isFalse);
      expect(access.isHidden('credits'), isTrue);
      final pro = ownerAccess(ownerOf(const OrgSummary(
          id: 'o2', name: 'Pro', profile: 'retail', plan: 'pro')), null, terms);
      expect(pro.isProLocked('analytics'), isFalse);
    });

    test('the session it draws with moves nothing and is not the platform\'s', () async {
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      final real = SessionController(
        db: db,
        auth: AuthRepository(null),
        admin: AdminRepository(null),
        accounting: AccountingRepository(null),
      );
      final view = OwnerViewSession(
        real: real,
        org: ownerOf(shop),
        states: FeatureStates.fromJson({'plan': 'free', 'hidden': ['tontines']}),
      );
      expect(view.isPlatformAdmin, isFalse);
      expect(view.orgs.single.roles, ['owner']);
      expect(view.phase, SessionPhase.ready);
      expect(view.accessFor('o1').isHidden('tontines'), isTrue);
      expect(view.orgById('another'), isNull);
      await view.refresh(force: true);
      await view.signOut();
      expect(view.lockNow(), isFalse);
      view.dispose();
      real.dispose();
      await db.close();
    });

    testWidgets('nothing in it can be touched; it still scrolls', (tester) async {
      var pressed = 0;
      var looked = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LookOnlyView(
            width: 390,
            child: Builder(builder: (context) {
              looked = LookOnly.of(context);
              return ListView(
                children: [
                  ElevatedButton(
                    key: const Key('inside'),
                    onPressed: () => pressed++,
                    child: const Text('Enregistrer'),
                  ),
                  for (var i = 0; i < 60; i++) SizedBox(height: 40, child: Text('ligne $i')),
                ],
              );
            }),
          ),
        ),
      ));
      expect(looked, isTrue);
      await tester.tap(find.byKey(const Key('inside')), warnIfMissed: false);
      await tester.pump();
      expect(pressed, 0);
      await tester.drag(find.byType(LookOnlyView), const Offset(0, -600));
      await tester.pump();
      expect(find.text('ligne 0'), findsNothing);
    });
  });

  group('the owner\'s bell', () {
    NotificationRow row(String kind, Map<String, dynamic> params) => NotificationRow(
          id: 'n',
          kind: kind,
          message: 'Mara a modifié votre vitrine',
          createdAt: DateTime.utc(2026, 10, 7),
          orgId: 'o1',
          params: params,
        );

    Future<String> line(WidgetTester tester, NotificationRow n) async {
      late String said;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: Builder(builder: (context) {
          said = notificationLine(context, n);
          return const SizedBox();
        }),
      ));
      return said;
    }

    testWidgets('says what Mara changed, and opens where it is', (tester) async {
      expect(await line(tester, row('mara_edited', {'what': 'vitrine'})), 'Mara changed your vitrine');
      expect(
          await line(tester, row('mara_edited', {
            'what': 'identity',
            'fields': ['name', 'phone', 'verified_at', 'verified_by'],
          })),
          'Mara changed your business\'s identity: name, phone, verification');
      expect(await line(tester, row('mara_undone', {'what': 'vitrine'})),
          'Mara took back her change to your vitrine');
      expect(notificationTarget(row('mara_edited', {'what': 'vitrine'})),
          Routes.orgSettings('o1', part: 'vitrine'));
      expect(notificationTarget(row('mara_undone', {'what': 'identity'})),
          Routes.orgSettings('o1', part: 'identite'));
    });
  });
}
