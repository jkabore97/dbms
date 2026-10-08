import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/console/fiche_repository.dart';
import 'package:kaj_app/core/console/kind_models_repository.dart';
import 'package:kaj_app/core/onboarding/application_form.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/features/admin/create_business_screen.dart';
import 'package:kaj_app/features/admin/kind_models_screen.dart';
import 'package:kaj_app/features/admin/request_form_screen.dart';
import 'package:kaj_app/features/setup/association_setup_screen.dart';
import 'package:kaj_app/features/setup/setup_screen.dart';

/// 107 in the app: Mara's form — since 111 it shapes the creation of a
/// business (its welcome, kinds and questions in CreateMyBusinessScreen:
/// test/batch111_create_test.dart proves them there, with the answers and
/// « Activités créées »); the editor saving and previewing it; the
/// walkthrough's optional steps by kind (none off = today's), a kind's own
/// free numbers on the paywall, and the types-of-business board saying its
/// impact before it saves.

class _Onboarding extends OnboardingRepository {
  _Onboarding() : super(null);

  Object? savedForm = 'never';

  /// No page set yet: the page of origin.
  @override
  Future<ApplicationForm?> applicationForm({bool strict = false}) async => null;

  @override
  Future<String?> setApplicationForm(ApplicationForm? form) async {
    savedForm = form?.toJson();
    return 'act-1';
  }
}

class _SetupActions implements SetupActions {
  @override
  Future<void> rename(String orgId, String name, String currency) async {}
  @override
  Future<void> addArticle(String orgId,
      {required String name, required double price, required double quantity}) async {}
  @override
  Future<void> saveVitrine(String orgId,
      {required bool open, required String blurb, required String phone, required String address}) async {}
  @override
  Future<void> savePosition(String orgId, double lat, double lng) async {}
  @override
  Future<void> finish(String orgId) async {}
}

class _AssociationActions implements AssociationSetupActions {
  @override
  Future<void> identify(String orgId,
      {required String name, required String currency, required String kind, required String about}) async {}
  @override
  Future<void> addMember(String orgId, {required String name, required String phone}) async {}
  @override
  Future<void> addService(String orgId, {required String name, required double price}) async {}
  @override
  Future<void> saveVitrine(String orgId,
      {required bool open, required String about, required String phone, required String address}) async {}
  @override
  Future<void> finish(String orgId) async {}
}

class _Kinds extends KindModelsRepository {
  _Kinds() : super(null);

  final log = <String>[];

  @override
  Future<KindModels> models(String kind) async => KindModels.fromJson({
        'kind': kind,
        'orgs': 12,
        'free': 9,
        'never_dressed': 7,
        'settings': [
          {'key': 'free_photo_items', 'label': 'x', 'global': 10, 'value': 12, 'min': 0, 'max': 1000},
          {'key': 'free_max_staff', 'label': 'x', 'global': 1, 'value': null, 'min': 0, 'max': 50},
        ],
        'vitrine_default': null,
        'setup': [
          {'key': 'identity', 'label': 'Le nom', 'required': true, 'on': true},
          {'key': 'article', 'label': 'Le premier article', 'required': true, 'on': true},
          {'key': 'vitrine', 'label': 'La vitrine', 'required': false, 'on': true},
          {'key': 'position', 'label': 'La position sur la carte', 'required': false, 'on': false},
        ],
      });

  @override
  Future<List<FeatureBoardRow>> board(String kind) async => [
        FeatureBoardRow.fromJson(const {
          'key': 'invoices', 'label': 'Factures', 'grp': 'Ventes et clients',
          'state': 'default', 'effective': 'visible', 'source': 'catalog',
        }),
      ];

  @override
  Future<FeatureImpact> impact(String kind, String feature, String state) async =>
      const FeatureImpact(orgs: 12, overridden: 2, paid: 1);

  @override
  Future<String?> setFeature(String kind, String feature, String state) async {
    log.add('feature $kind $feature $state');
    return 'act-2';
  }

  @override
  Future<String?> setSetting(String kind, String key, Object? value) async {
    log.add('setting $kind $key $value');
    return 'act-3';
  }
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('P1 — with no form, today\'s pages', () {
    testWidgets('the platform admin\'s own « Nouvelle entreprise » stays as it was', (tester) async {
      tall(tester);
      await tester.pumpWidget(MaterialApp(
          home: CreateBusinessScreen(admin: AdminRepository(null))));
      await settle(tester);
      expect(find.text('Association'), findsOneWidget);
      // Name, address, currency; the platform's create_org behind its button.
      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.text('Créer l\'activité'), findsOneWidget);
    });

    testWidgets('the walkthroughs keep every step when nothing is turned off', (tester) async {
      tall(tester);
      await tester.pumpWidget(MaterialApp(
          home: SetupScreen(
              org: const OrgSummary(id: 'o', name: 'Awa', profile: 'retail', roles: ['owner']),
              actions: _SetupActions(),
              onDone: () {},
              stepsOff: () async => const {})));
      await settle(tester);
      expect(find.text('1 / 4'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(
          home: AssociationSetupScreen(
              org: const OrgSummary(id: 'a', name: 'Entraide', profile: 'association', roles: ['owner']),
              actions: _AssociationActions(),
              onDone: () {},
              stepsOff: () async => const {})));
      await settle(tester);
      expect(find.text('1 / 3'), findsOneWidget);
    });

    test('no kind of its own: the paywall reads the platform\'s numbers', () {
      final t = PlanTerms.fromJson(const {'free_photo_items': 10, 'free_max_staff': 1});
      expect(identical(t.forProfile('farm'), t), isTrue);
      expect(t.forProfile('retail').freePhotoItems, 10);
    });
  });

  group('the creation page Mara sets (107\'s editor, renamed in 111)', () {
    testWidgets('the editor saves what is typed, and previews it', (tester) async {
      tall(tester);
      final onboarding = _Onboarding();
      await tester.pumpWidget(MaterialApp(
          home: RequestFormScreen(onboarding: onboarding, undo: (_) async {})));
      await settle(tester);
      expect(find.text('Le parcours de création est celui d\'origine.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('form-welcome')), 'Bonjour');
      await tester.tap(find.byKey(const Key('form-kind-association')));
      await tester.tap(find.byKey(const Key('form-add')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('form-q-0-label')), 'Votre ville');
      await tester.tap(find.byKey(const Key('form-q-0-required')));
      await settle(tester);
      // The preview beside it is the creation itself, drawn with what is
      // typed: the welcome on its first screen, the association no longer
      // offered, the question a screen of its own (6 + 1).
      expect(find.byKey(const Key('create-welcome')), findsOneWidget);
      expect(find.byKey(const Key('create-kind-association')), findsNothing);
      expect(find.byKey(const Key('create-kind-farm')), findsOneWidget);
      expect(find.text('1 / 7'), findsOneWidget);
      await tester.tap(find.byKey(const Key('form-save')));
      await settle(tester);
      expect(onboarding.savedForm, {
        'welcome': 'Bonjour',
        'kinds': ['farm', 'retail'],
        'questions': [
          {'label': 'Votre ville', 'required': true, 'type': 'text'},
        ],
      });
      expect(find.text('Annuler'), findsOneWidget, reason: 'the journal\'s undo');
    });

    testWidgets('a choice needs two answers before it saves', (tester) async {
      tall(tester);
      await tester.pumpWidget(MaterialApp(
          home: RequestFormScreen(onboarding: _Onboarding(), undo: (_) async {})));
      await settle(tester);
      await tester.tap(find.byKey(const Key('form-add')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('form-q-0-label')), 'Vous vendez');
      await tester.tap(find.byKey(const Key('form-q-0-type')));
      await settle(tester);
      await tester.tap(find.text('Choix dans une liste').last);
      await settle(tester);
      expect(find.text('Une question à choix a de 2 à 12 réponses.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('form-save'))).onPressed, isNull);
    });
  });

  group('a kind\'s own steps and numbers', () {
    testWidgets('a shop without « position », an association without « members »', (tester) async {
      tall(tester);
      await tester.pumpWidget(MaterialApp(
          home: SetupScreen(
              org: const OrgSummary(id: 'o', name: 'Awa', profile: 'retail', roles: ['owner']),
              actions: _SetupActions(),
              onDone: () {},
              stepsOff: () async => {'position'})));
      await settle(tester);
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(
          home: AssociationSetupScreen(
              org: const OrgSummary(id: 'a', name: 'Entraide', profile: 'association', roles: ['owner']),
              actions: _AssociationActions(),
              onDone: () {},
              stepsOff: () async => {'members'})));
      await settle(tester);
      expect(find.text('1 / 2'), findsOneWidget);
    });

    test('the paywall says the kind\'s own number, a church an association\'s', () {
      final t = PlanTerms.fromJson(const {
        'free_photo_items': 10,
        'kinds': {
          'association': {'free_photo_items': 4, 'free_max_invoices_month': 2},
        },
      });
      expect(t.forProfile('church').freePhotoItems, 4);
      expect(t.forProfile('association').freeMaxInvoicesMonth, 2);
      expect(t.forProfile('retail').freePhotoItems, 10);
    });

    testWidgets('a switch for every shop says whom it touches before it saves', (tester) async {
      tall(tester);
      final kinds = _Kinds();
      await tester.pumpWidget(MaterialApp(
          home: KindModelsScreen(repository: kinds, undo: (_) async {})));
      await settle(tester);
      expect(find.text('Boutiques'), findsOneWidget);
      expect(find.text('12'), findsWidgets);
      await tester.tap(find.descendant(
          of: find.byKey(const Key('kinds-switch-invoices')), matching: find.text('Masquée')));
      await settle(tester);
      expect(find.text('Ce changement touche 12 boutique(s) ; 2 ont leur propre réglage ; '
          '1 l\'ont payée et la gardent'), findsOneWidget);
      expect(kinds.log, isEmpty, reason: 'nothing saved before the impact is confirmed');
      await tester.tap(find.byKey(const Key('kinds-impact-ok')));
      await settle(tester);
      expect(kinds.log, ['feature retail invoices hidden']);
      // A number of the kind's own, then back to the platform's.
      await tester.tap(find.byKey(const Key('kinds-setting-free_photo_items')));
      await settle(tester);
      expect(find.text('Touche 9 boutique(s) en formule gratuite.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('kinds-setting-field')), '5000');
      await settle(tester);
      expect(tester.widget<FilledButton>(find.byKey(const Key('kinds-setting-save'))).onPressed,
          isNull, reason: 'out of bounds');
      await tester.enterText(find.byKey(const Key('kinds-setting-field')), '15');
      await settle(tester);
      await tester.tap(find.byKey(const Key('kinds-setting-save')));
      await settle(tester);
      expect(kinds.log.last, 'setting retail free_photo_items 15');
      await tester.tap(find.byKey(const Key('kinds-setting-free_photo_items')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('kinds-setting-default')));
      await settle(tester);
      expect(kinds.log.last, 'setting retail free_photo_items null');
      // The walkthrough: « position » comes back on.
      await tester.tap(find.byKey(const Key('kinds-step-position')));
      await settle(tester);
      expect(kinds.log.last, 'setting retail setup_off null');
    });
  });
}
