import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/org_access.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/errors.dart';
import 'package:kaj_app/features/account/pro_sheet.dart';
import 'package:kaj_app/features/admin/pro_console_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The line between Kaj and Kaj Pro on the phone (066, M10 block 2): the
/// plan layer on the dial, the terms the paywall reads, the sheet itself and
/// the platform's queue.
class _Admin extends AdminRepository {
  _Admin({this.terms = PlanTerms.defaults, this.requests = const []})
      : super(null);

  final PlanTerms terms;
  final List<PlanRequest> requests;

  final requested = <Map<String, Object?>>[];
  final handled = <String>[];
  final settings = <String, Object?>{};

  @override
  Future<PlanTerms> planTerms() async => terms;

  @override
  Future<void> requestPro(String orgId, {double? amount, String? note}) async {
    requested.add({'org': orgId, 'amount': amount, 'note': note});
  }

  @override
  Future<List<PlanRequest>> planRequestsOpen() async =>
      requests.where((r) => !handled.contains(r.id)).toList();

  @override
  Future<void> handlePlanRequest(String id) async {
    handled.add(id);
  }

  @override
  Future<void> setPlatformSetting(String key, Object? value) async {
    settings[key] = value;
  }
}

const _free = OrgSummary(
    id: 'org-1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);
const _pro = OrgSummary(
    id: 'org-2',
    name: 'Boutique Pro',
    profile: 'retail',
    roles: ['owner'],
    plan: 'pro');

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  group('the plan layer on the dial', () {
    const locked = {'analytics', 'payroll', 'tontines', 'team_access'};

    test('an owner on Free reads view on a Pro tool and edit elsewhere', () {
      const access = OrgAccess.admin(proLocked: locked);
      expect(access.accessTo('analytics'), 'view');
      expect(access.canEdit('analytics'), isFalse);
      expect(access.canSee('analytics'), isTrue);
      expect(access.isProLocked('analytics'), isTrue);
      expect(access.accessTo('products'), 'edit');
      expect(access.isProLocked('products'), isFalse);
    });

    test('an owner on Pro, or the platform, is not locked at all', () {
      expect(OrgAccess.allEdit.accessTo('analytics'), 'edit');
      expect(OrgAccess.allEdit.isProLocked('analytics'), isFalse);
      expect(const OrgAccess.admin().isProLocked('payroll'), isFalse);
    });

    test('the dial still wins below the plan: hidden stays hidden, no badge',
        () {
      const clerk = OrgAccess.forTier({'tontines': 'hidden'}, proLocked: locked);
      expect(clerk.accessTo('tontines'), 'hidden');
      expect(clerk.isProLocked('tontines'), isFalse);
      // A tool the dial left at edit is lowered to view by the plan.
      expect(clerk.accessTo('payroll'), 'view');
      expect(clerk.isProLocked('payroll'), isTrue);
    });

    test('equality sees the lock, so a loaded plan triggers one rebuild', () {
      expect(const OrgAccess.admin(proLocked: locked),
          isNot(equals(OrgAccess.allEdit)));
      expect(const OrgAccess.admin(proLocked: locked),
          equals(const OrgAccess.admin(proLocked: locked)));
    });
  });

  group('the terms', () {
    test('read what plan_terms() sends and default to what 066 seeds', () {
      final terms = PlanTerms.fromJson({
        'pro_features': ['analytics', 'payroll'],
        'free_max_staff': 5,
        'pro_price_month': 3000,
        'pro_price_year': '30000',
        'platform_wave': '+226 70 00 00 00',
        'platform_wave_name': 'Kaj',
      });
      expect(terms.proFeatures, ['analytics', 'payroll']);
      expect(terms.freeMaxStaff, 5);
      expect(terms.priceMonth, 3000);
      expect(terms.priceYear, 30000);
      expect(terms.hasWave, isTrue);
      // Unsaid: the seeded defaults.
      expect(terms.freeMaxPhotos, 50);
      expect(terms.currency, 'XOF');

      const before = PlanTerms.defaults;
      expect(before.proFeatures, contains('accounting'));
      expect(before.hasWave, isFalse);
      expect(before.priceMonth, 2500);
    });

    test('a refusal for the plan is recognised by its first words', () {
      expect(
          isProRefusal(const PostgrestException(
              message: 'Kaj Pro : la formule gratuite garde 50 photos.',
              code: 'P0001')),
          isTrue);
      expect(
          isProRefusal(const PostgrestException(
              message: 'Le carnet de crédit vous est fermé.', code: 'P0001')),
          isFalse);
    });
  });

  group('the paywall sheet', () {
    Future<void> open(WidgetTester tester, _Admin admin,
        {required OrgSummary org, required bool canRequest}) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => ProSheet.open(context,
                    org: org,
                    terms: admin.terms,
                    admin: admin,
                    canRequest: canRequest),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('says the price and the number, and "J\'ai payé" lands',
        (tester) async {
      final admin = _Admin(
          terms: const PlanTerms(
              wave: '+226 70 00 00 00', waveName: 'Kaj Consulting'));
      await open(tester, admin, org: _free, canRequest: true);

      expect(find.text('Kaj Pro'), findsOneWidget);
      // intl's French thousands separator is a narrow no-break space, so
      // the digits are matched around it rather than through it.
      expect(find.textContaining(RegExp(r'2.500 F CFA par mois')),
          findsOneWidget);
      expect(find.textContaining(RegExp(r'25.000 F CFA par an')),
          findsOneWidget);
      expect(find.text('+226 70 00 00 00'), findsOneWidget);
      expect(find.text('Wave · Kaj Consulting'), findsOneWidget);
      expect(find.textContaining('Pointages et paie'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Précision (facultatif)'),
          'Awa Wave 12/09');
      await tester.tap(find.text("J'ai payé"));
      await tester.pump();
      await tester.pump();

      expect(admin.requested, hasLength(1));
      expect(admin.requested.single['org'], 'org-1');
      expect(admin.requested.single['amount'], 25000);
      expect(admin.requested.single['note'], 'Awa Wave 12/09');
      expect(find.text("Merci, c'est noté."), findsOneWidget);
    });

    testWidgets('without a number it says to contact Kaj', (tester) async {
      final admin = _Admin();
      await open(tester, admin, org: _free, canRequest: true);
      expect(find.textContaining('contactez Kaj'), findsOneWidget);
    });

    testWidgets('an employee is told whom to ask, and has no button',
        (tester) async {
      final admin = _Admin();
      await open(tester, admin, org: _free, canRequest: false);
      expect(find.text("J'ai payé"), findsNothing);
      expect(find.textContaining('Demandez au propriétaire'), findsOneWidget);
    });

    testWidgets('on a Pro business it says so and asks for nothing',
        (tester) async {
      final admin = _Admin();
      await open(tester, admin, org: _pro, canRequest: true);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text("J'ai payé"), findsNothing);
      expect(find.textContaining('F CFA par mois'), findsNothing);
      expect(find.textContaining('Cette entreprise est sur Kaj Pro'),
          findsOneWidget);
    });
  });

  group('the platform\'s Kaj Pro page', () {
    testWidgets('lists the requests, closes one, and saves the number and prices',
        (tester) async {
      final admin = _Admin(
        terms: const PlanTerms(wave: '+226 70 00 00 00'),
        requests: [
          PlanRequest(
            id: 'r1',
            orgId: 'org-1',
            orgName: 'Boutique Awa',
            orgPlan: 'free',
            requestedBy: 'Awa',
            amount: 25000,
            note: 'Wave fait',
            createdAt: DateTime(2026, 9, 6, 10, 30),
          ),
          PlanRequest(
            id: 'r2',
            orgId: 'org-2',
            orgName: 'Boutique Pro',
            orgPlan: 'pro',
            requestedBy: 'Moussa',
            createdAt: DateTime(2026, 9, 6, 11, 0),
          ),
        ],
      );
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp(home: ProConsoleScreen(admin: admin)));
      await tester.pump();
      await tester.pump();

      expect(find.text('Demandes en attente (2)'), findsOneWidget);
      expect(find.text('Boutique Awa'), findsOneWidget);
      expect(find.textContaining(RegExp(r'25.000 F CFA')), findsOneWidget);
      expect(find.text('déjà Pro'), findsOneWidget);

      await tester.tap(find.text('Traitée').first);
      await tester.pump();
      await tester.pump();
      expect(admin.handled, ['r1']);
      expect(find.text('Demandes en attente (1)'), findsOneWidget);
      expect(find.text('Boutique Awa'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextField, 'Nom affiché sur Wave'), 'Kaj');
      await tester.enterText(
          find.widgetWithText(TextField, 'Prix par mois (XOF)'), '3000');
      final save = find.text('Enregistrer le numéro et les prix');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump();

      expect(admin.settings['platform_wave'], '+226 70 00 00 00');
      expect(admin.settings['platform_wave_name'], 'Kaj');
      expect(admin.settings['pro_price_month'], 3000);
      expect(admin.settings['pro_price_year'], 25000);
      expect(find.textContaining('Enregistré.'), findsOneWidget);
    });
  });
}
