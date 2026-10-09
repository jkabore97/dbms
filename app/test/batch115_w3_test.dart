import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/features/admin/team_invite_flow.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/core/orders/orders.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/orders/order_walkthrough.dart';
import 'package:kaj_app/features/orders/shop_orders_screen.dart';
import 'package:kaj_app/features/production/production_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Batch 115, W3: « Production » and « Commandes » one step at a time.

class _Production extends ProductionRepository {
  _Production() : super(null);
  final recorded = <Map<String, Object?>>[];

  @override
  Future<List<ProductionRun>> history(String orgId) async => const [];

  @override
  Future<void> record({
    required String orgId,
    required String productName,
    required double quantity,
    required List<ProductionInputDraft> inputs,
    String? note,
  }) async =>
      recorded.add({
        'name': productName,
        'quantity': quantity,
        'inputs': [for (final i in inputs) i.toJson()],
      });
}

class _Retail extends RetailRepository {
  _Retail({this.shelf = const [], this.orders = const []}) : super(null);
  List<Product> shelf;
  List<ShopOrder> orders;
  final moves = <String>[];
  final paid = <String>[];
  final prices = <String, double>{};
  final self = <String>[];

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async =>
      shelf;

  @override
  Future<void> updateProduct(
    String id, {
    String? name,
    double? salePrice,
    double? costPrice,
    DateTime? expiresOn,
    double? lowStockAt,
    bool? isActive,
    bool? isIngredient,
    bool? isPublished,
    String? description,
    String? unit,
    DateTime? availableFrom,
    bool clearAvailableFrom = false,
    double? quantity,
    bool? isService,
    bool? priceFrom,
  }) async {
    if (salePrice != null) prices[id] = salePrice;
  }

  @override
  Future<List<ShopOrder>> shopOrders(String orgId) async => orders;

  @override
  Future<Map<String, OrderClock>> orderClocks(String orgId) async => const {};

  @override
  Future<List<CashOwed>> cashOwed(String orgId) async => const [];

  @override
  Future<void> decideOrder(String orderId, String status) async =>
      moves.add('$orderId:$status');

  @override
  Future<void> refuseOrder(String orderId, String reason) async =>
      moves.add('$orderId:refused:$reason');

  @override
  Future<void> setOrderPaid(String orderId, bool paid) async =>
      this.paid.add('$orderId:$paid');

  @override
  Future<void> deliverSelf(String orderId) async => self.add(orderId);
}

class _Onboarding extends OnboardingRepository {
  _Onboarding({this.salaryFails = false}) : super(null);
  final bool salaryFails;
  final invites = <Map<String, Object?>>[];
  final salaries = <String>[];

  @override
  Future<Invitation> invite({
    required String orgId,
    String role = 'employee',
    String? fullName,
    String? title,
    String? phone,
    String visibility = 'full',
    int validDays = 14,
    String? note,
  }) async {
    invites.add({
      'org': orgId,
      'role': role,
      'name': fullName,
      'title': title,
      'phone': phone,
      'visibility': visibility,
    });
    return const Invitation(id: 'inv1', code: 'K7P-4QX', orgName: 'Boutique Awa');
  }

  @override
  Future<void> setInvitationSalary(String invitationId, double amount,
      {String period = 'month'}) async {
    if (salaryFails) throw StateError('PGRST202');
    salaries.add('$invitationId:$amount:$period');
  }
}

class _Admin extends AdminRepository {
  _Admin() : super(null);

  @override
  Future<Map<String, String>> featureRulesForTier(String orgId, String tier) async =>
      tier == 'employee' ? const {'credits': 'hidden', 'invoices': 'view'} : const {};
}

Future<void> _openInvite(WidgetTester tester, OrgSummary org, _Onboarding onboarding) async {
  await tester.pumpWidget(_app(Builder(
    builder: (context) => TextButton(
      onPressed: () => StepFlow.push(
          context,
          TeamInviteFlow(
              org: org, onboarding: onboarding, admin: _Admin(), store: MemoryFlowStore())),
      child: const Text('Ouvrir'),
    ),
  )));
  await tester.tap(find.text('Ouvrir'));
  await tester.pumpAndSettle();
}

const _shop = OrgSummary(
    id: 'org1', name: 'Boutique Awa', profile: 'retail', roles: ['owner'], currency: 'XOF');
const _farm = OrgSummary(
    id: 'org2', name: 'Ferme Issa', profile: 'farm', roles: ['owner'], currency: 'XOF');
const _assoc = OrgSummary(
    id: 'org3', name: 'Entraide', profile: 'association', roles: ['owner'], currency: 'XOF');

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

ShopOrder _order(String status,
        {String fulfilment = 'pickup',
        List<OrderLine>? lines,
        String id = 'o1'}) =>
    ShopOrder(
      id: id,
      customerName: 'Fati',
      status: status,
      fulfilment: fulfilment,
      total: 3500,
      currency: 'XOF',
      createdAt: DateTime(2026, 10, 8, 9),
      phone: '+22670000000',
      lines: lines ??
          const [
            OrderLine(name: 'Savon', unitPrice: 500, quantity: 3),
            OrderLine(name: 'Riz 5 kg', unitPrice: 2000, quantity: 1),
          ],
    );

Future<void> _big(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('flow-next')));
  await tester.pumpAndSettle();
}

bool _nextEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('flow-next'))).onPressed != null;

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('Production', () {
    testWidgets('nothing marked: the way to the article flow, and back to the step',
        (tester) async {
      await _big(tester);
      final retail = _Retail(shelf: const [
        Product(id: 'p1', name: 'Savon', quantity: 4, salePrice: 500),
      ]);
      var opened = 0;
      await tester.pumpWidget(_app(ProductionScreen(
        org: _farm,
        production: _Production(),
        retail: retail,
        addIngredients: (_) async {
          opened++;
          // The article flow, pre-ticked, added the flour.
          retail.shelf = [
            ...retail.shelf,
            const Product(id: 'p2', name: 'Farine', quantity: 10, costPrice: 400, isIngredient: true, unit: 'kg'),
          ];
        },
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('production-name')), 'Pain');
      await tester.pump();
      await _next(tester);
      expect(find.byKey(const Key('production-none-marked')), findsOneWidget);
      expect(find.textContaining('cochez « Utilisé en production »'), findsOneWidget);
      expect(_nextEnabled(tester), isFalse);
      await tester.tap(find.byKey(const Key('production-add-ingredient')));
      await tester.pumpAndSettle();
      expect(opened, 1);
      // Back on the same step, the new ingredient there.
      expect(find.byKey(const Key('flow-step-inputs')), findsOneWidget);
      expect(find.byKey(const Key('production-none-marked')), findsNothing);
      expect(find.byKey(const Key('production-pick-p2')), findsOneWidget);
      expect(find.byKey(const Key('production-pick-p1')), findsNothing,
          reason: 'an article not marked waits behind « Voir tous mes articles »');
    });

    testWidgets('made → used → how much → how many → price → cost → saved',
        (tester) async {
      await _big(tester);
      final production = _Production();
      final retail = _Retail(shelf: const [
        Product(id: 'f', name: 'Farine', quantity: 10, costPrice: 400, isIngredient: true, unit: 'kg'),
        Product(id: 'h', name: 'Huile', quantity: 2, costPrice: 1000, isIngredient: true, unit: 'l'),
        Product(id: 'g', name: 'Gâteau', quantity: 0),
      ]);
      await tester.pumpWidget(_app(ProductionScreen(
          org: _shop, production: production, retail: retail)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('flow-step-bar')), findsOneWidget);
      expect(_nextEnabled(tester), isFalse);
      await tester.enterText(find.byKey(const Key('production-name')), 'Gâteau');
      await tester.pump();
      await _next(tester);
      await tester.tap(find.byKey(const Key('production-pick-f')));
      await tester.tap(find.byKey(const Key('production-pick-h')));
      await tester.pump();
      await _next(tester);
      expect(_nextEnabled(tester), isFalse);
      await tester.enterText(find.byKey(const Key('production-qty-f')), '2');
      await tester.enterText(find.byKey(const Key('production-qty-h')), '3');
      await tester.pump();
      expect(find.textContaining('Plus que votre stock'), findsOneWidget);
      await _next(tester);
      await tester.enterText(find.byKey(const Key('production-made')), '20');
      await tester.pump();
      // (2 × 400 + 3 × 1000) / 20 = 190
      expect(find.byKey(const Key('production-unit-cost')), findsOneWidget);
      expect(find.textContaining('190'), findsWidgets);
      await _next(tester);
      await tester.enterText(find.byKey(const Key('production-price')), '150');
      await tester.pump();
      expect(find.byKey(const Key('production-below-cost')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('production-price')), '300');
      await tester.pump();
      expect(find.byKey(const Key('production-below-cost')), findsNothing);
      await _next(tester);
      expect(find.byKey(const Key('flow-summary')), findsOneWidget);
      expect(find.text('20 × Gâteau'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^3.800.FCFA$')), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(production.recorded, [
        {
          'name': 'Gâteau',
          'quantity': 20.0,
          'inputs': [
            {'product_id': 'f', 'quantity': 2.0},
            {'product_id': 'h', 'quantity': 3.0},
          ],
        }
      ]);
      expect(retail.prices, {'g': 300.0});
      expect(find.byKey(const Key('flow-done')), findsOneWidget);
      expect(find.text('20 × Gâteau fabriqués'), findsOneWidget);
    });
  });

  group('Commandes', () {
    testWidgets('shop pickup: answer → prepare (each ticked) → Prête → handed over, paid',
        (tester) async {
      await _big(tester);
      final retail = _Retail(orders: [_order('pending')]);
      await tester.pumpWidget(_app(ShopOrdersScreen(org: _shop, retail: retail)));
      await tester.pumpAndSettle();
      expect(find.text('Répondre'), findsOneWidget);
      // The card's old one-tap buttons are gone: one way, the walkthrough.
      expect(find.text('Refuser'), findsNothing);
      await tester.tap(find.byKey(const Key('order-walk-o1')));
      await tester.pumpAndSettle();
      expect(find.text('Fati commande'), findsOneWidget);
      expect(_nextEnabled(tester), isFalse);
      await tester.tap(find.byKey(const Key('flow-option-accepted')));
      await tester.pump();
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(retail.moves, ['o1:accepted']);
      expect(find.text('Commande acceptée. Fati est prévenu.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-next-stage')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('flow-step-pack')), findsOneWidget);
      expect(_nextEnabled(tester), isFalse);
      await tester.tap(find.byKey(const Key('order-pack-0')));
      await tester.pump();
      expect(_nextEnabled(tester), isFalse, reason: 'every article ticked first');
      await tester.tap(find.byKey(const Key('order-pack-1')));
      await tester.pump();
      expect(find.text('2 sur 2 prêts'), findsOneWidget);
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(retail.moves.last, 'o1:ready');
      expect(find.text('Prête. Fati est prévenu.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-next-stage')));
      await tester.pumpAndSettle();
      expect(find.text('Fati est là ?'), findsOneWidget);
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-option-true')));
      await tester.pump();
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(retail.moves, ['o1:accepted', 'o1:ready', 'o1:picked_up']);
      expect(retail.paid, ['o1:true']);
      expect(find.textContaining('ne la passez pas à la caisse'), findsOneWidget);
      expect(find.byKey(const Key('order-next-stage')), findsNothing);
    });

    testWidgets('a refusal carries its reason', (tester) async {
      await _big(tester);
      final retail = _Retail();
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () => OrderWalkthrough.open(context,
              org: _farm, retail: retail, order: _order('pending')),
          child: const Text('Ouvrir'),
        ),
      )));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-option-refused')));
      await tester.pump();
      await _next(tester);
      expect(find.text('Pourquoi refuser ?'), findsOneWidget);
      expect(_nextEnabled(tester), isFalse);
      await tester.tap(find.byKey(const Key('flow-option-other')));
      await tester.pump();
      expect(_nextEnabled(tester), isFalse);
      await tester.enterText(find.byKey(const Key('order-reason-other')), 'Récolte pas encore prête');
      await tester.pump();
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(retail.moves, ['o1:refused:Récolte pas encore prête']);
      expect(find.text('Commande refusée. Fati est prévenu.'), findsOneWidget);
    });

    testWidgets('an association\'s booking: confirm, then the service done',
        (tester) async {
      await _big(tester);
      final retail = _Retail(orders: [
        _order('pending',
            lines: const [OrderLine(name: 'Salle', unitPrice: 10000, quantity: 1, isService: true)])
      ]);
      await tester.pumpWidget(_app(ShopOrdersScreen(org: _assoc, retail: retail)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-walk-o1')));
      await tester.pumpAndSettle();
      expect(find.text('Fati demande un rendez-vous'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-option-accepted')));
      await tester.pump();
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(find.text('Réservation confirmée. Fati est prévenu.'), findsOneWidget);
      // No packing for a service: straight to « Terminer ».
      expect(find.text('Terminer'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-next-stage')));
      await tester.pumpAndSettle();
      expect(find.text('Le service est rendu'), findsOneWidget);
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-option-false')));
      await tester.pump();
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(retail.moves, ['o1:accepted', 'o1:picked_up']);
      expect(retail.paid, isEmpty);
      expect(find.text('Réservation terminée.'), findsOneWidget);
    });

    testWidgets('a delivery: the shop carries it, then confirms it', (tester) async {
      await _big(tester);
      final retail = _Retail();
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () => OrderWalkthrough.open(context,
              org: _shop,
              retail: retail,
              order: _order('ready', fulfilment: 'delivery')),
          child: const Text('Ouvrir'),
        ),
      )));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(_nextEnabled(tester), isFalse);
      await tester.tap(find.byKey(const Key('flow-option-self')));
      await tester.pump();
      await _next(tester);
      // Delivering oneself asks no payment yet.
      expect(find.byKey(const Key('flow-summary')), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(retail.self, ['o1']);
      expect(find.text('En route : vous livrez Fati.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-next-stage')));
      await tester.pumpAndSettle();
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-option-true')));
      await tester.pump();
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(retail.moves, ['o1:delivered']);
      expect(retail.paid, ['o1:true']);
    });

    test('the stage follows the status, for goods and bookings', () {
      expect(stageOf(_order('pending')), OrderStage.answer);
      expect(stageOf(_order('accepted')), OrderStage.prepare);
      expect(
          stageOf(_order('accepted',
              lines: const [OrderLine(name: 'Coupe', unitPrice: 1, quantity: 1, isService: true)])),
          OrderStage.finish);
      expect(stageOf(_order('in_transit', fulfilment: 'delivery')), OrderStage.finish);
      for (final s in ['picked_up', 'delivered', 'refused', 'cancelled']) {
        expect(stageOf(_order(s)), OrderStage.none, reason: s);
      }
      expect(stageAction(_order('in_transit', fulfilment: 'delivery')),
          'Confirmer la livraison');
    });
  });

  group('Équipe', () {
    testWidgets('the owner: name, number, responsibility, what they see, salary → invitation → WhatsApp',
        (tester) async {
      await _big(tester);
      final onboarding = _Onboarding();
      await _openInvite(tester, _shop, onboarding);
      expect(_nextEnabled(tester), isTrue, reason: 'the name is optional, as before (batch 115)');
      await tester.enterText(find.byKey(const Key('team-name')), 'Aïcha Sawadogo');
      await tester.enterText(find.byKey(const Key('team-title')), 'Vendeuse');
      await tester.pump();
      await _next(tester);
      // A number too short is said, and holds the step.
      await tester.enterText(find.byKey(const Key('team-phone')), '7012');
      await tester.pump();
      expect(_nextEnabled(tester), isFalse);
      await tester.enterText(find.byKey(const Key('team-phone')), '70123456');
      await tester.pump();
      await _next(tester);
      // The owner hands out anything below the owner — never owner itself.
      for (final r in ['admin', 'manager', 'supervisor', 'approver', 'employee', 'observer']) {
        expect(find.byKey(Key('flow-option-$r')), findsOneWidget, reason: r);
      }
      expect(find.byKey(const Key('flow-option-owner')), findsNothing);
      expect(find.text('Vend et enregistre au quotidien'), findsOneWidget);
      await _next(tester);
      // The employee tier's dial, as the owner set it.
      expect(find.text('Ce que Aïcha Sawadogo verra'), findsOneWidget);
      expect(find.byKey(const Key('team-sees')), findsOneWidget);
      expect(find.text('Caché'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-option-summary')));
      await tester.pump();
      await _next(tester);
      await tester.enterText(find.byKey(const Key('team-salary')), '45000');
      await tester.tap(find.byKey(const Key('team-period-week')));
      await tester.pump();
      await _next(tester);
      expect(find.byKey(const Key('flow-summary')), findsOneWidget);
      expect(find.text('+22670123456'), findsOneWidget);
      expect(find.textContaining('par semaine'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(onboarding.invites, [
        {
          'org': 'org1',
          'role': 'employee',
          'name': 'Aïcha Sawadogo',
          'title': 'Vendeuse',
          'phone': '+22670123456',
          'visibility': 'summary',
        }
      ]);
      expect(onboarding.salaries, ['inv1:45000.0:week']);
      expect(find.byKey(const Key('team-code')), findsOneWidget);
      expect(find.byKey(const Key('team-send')), findsOneWidget);
      expect(find.textContaining('Le salaire n\'a pas pu'), findsNothing);
    });

    testWidgets('no name: the invitation is made all the same, its name left to the account (batch 115)',
        (tester) async {
      await _big(tester);
      final onboarding = _Onboarding();
      await _openInvite(tester, _shop, onboarding);
      await _next(tester); // no name
      await _next(tester); // no number
      await tester.tap(find.byKey(const Key('flow-option-employee')));
      await tester.pump();
      await _next(tester);
      await _next(tester); // what they see: as offered
      await _next(tester); // no salary
      expect(find.byKey(const Key('flow-summary')), findsOneWidget);
      expect(find.text('Pas dit'), findsWidgets);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(onboarding.invites.single['name'], isNull);
      expect(find.text('L\'invitation est prête'), findsOneWidget);
      expect(find.byKey(const Key('team-code')), findsOneWidget);
    });

    testWidgets('a manager offers only what is below them; no salary, no number', (tester) async {
      await _big(tester);
      final onboarding = _Onboarding();
      await _openInvite(
          tester,
          const OrgSummary(id: 'org2', name: 'Ferme Issa', profile: 'farm', roles: ['manager']),
          onboarding);
      await tester.enterText(find.byKey(const Key('team-name')), 'Issa');
      await tester.pump();
      await _next(tester);
      await _next(tester);
      expect(find.byKey(const Key('flow-option-admin')), findsNothing);
      expect(find.byKey(const Key('flow-option-manager')), findsNothing);
      expect(find.byKey(const Key('flow-option-supervisor')), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-option-observer')));
      await tester.pump();
      await _next(tester);
      expect(find.text('Tout regarder, sans rien enregistrer.'), findsOneWidget);
      await _next(tester);
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(onboarding.invites.single['role'], 'observer');
      expect(onboarding.invites.single['phone'], '');
      expect(onboarding.salaries, isEmpty);
    });

    testWidgets('an association: the salary refused leaves the invitation, and says so',
        (tester) async {
      await _big(tester);
      final onboarding = _Onboarding(salaryFails: true);
      await _openInvite(tester, _assoc, onboarding);
      await tester.enterText(find.byKey(const Key('team-name')), 'Moussa');
      await tester.pump();
      await _next(tester);
      await _next(tester);
      await _next(tester);
      // No production line for an association.
      expect(find.text('Production'), findsNothing);
      await _next(tester);
      await tester.enterText(find.byKey(const Key('team-salary')), '20000');
      await tester.pump();
      await _next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(onboarding.invites, hasLength(1));
      expect(find.byKey(const Key('team-code')), findsOneWidget);
      expect(find.textContaining('Le salaire n\'a pas pu être noté'), findsOneWidget);
    });
  });
}
