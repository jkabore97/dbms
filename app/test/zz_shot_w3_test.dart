import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/orders/orders.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/admin/team_invite_flow.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/orders/order_walkthrough.dart';
import 'package:kaj_app/features/orders/shop_orders_screen.dart';
import 'package:kaj_app/features/production/production_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

Future<void> loadFonts() async {
  const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons');
  icons.addFont(Future.value(ByteData.sublistView(File('$dir/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

final shotKey = GlobalKey();

class _Production extends ProductionRepository {
  _Production() : super(null);
  @override
  Future<List<ProductionRun>> history(String orgId) async => const [];
  @override
  Future<void> record({required String orgId, required String productName, required double quantity, required List<ProductionInputDraft> inputs, String? note}) async {}
}

class _Retail extends RetailRepository {
  _Retail({this.shelf = const [], this.orders = const []}) : super(null);
  List<Product> shelf;
  List<ShopOrder> orders;
  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => shelf;
  @override
  Future<List<ShopOrder>> shopOrders(String orgId) async => orders;
  @override
  Future<Map<String, OrderClock>> orderClocks(String orgId) async => const {};
  @override
  Future<List<CashOwed>> cashOwed(String orgId) async => const [];
  @override
  Future<void> decideOrder(String orderId, String status) async {}
  @override
  Future<void> refuseOrder(String orderId, String reason) async {}
  @override
  Future<void> setOrderPaid(String orderId, bool paid) async {}
}

class _Onboarding extends OnboardingRepository {
  _Onboarding() : super(null);
  @override
  Future<Invitation> invite({required String orgId, String role = 'employee', String? fullName, String? title, String? phone, String visibility = 'full', int validDays = 14, String? note}) async =>
      Invitation(id: 'i', code: 'K7P-4QX', orgName: 'Boutique Awa', expiresAt: DateTime.now().add(const Duration(days: 14)));
  @override
  Future<void> setInvitationSalary(String invitationId, double amount, {String period = 'month'}) async {}
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<Map<String, String>> featureRulesForTier(String orgId, String tier) async =>
      const {'credits': 'hidden', 'invoices': 'view', 'staff': 'hidden'};
}

const _shop = OrgSummary(id: 'org1', name: 'Boutique Awa', profile: 'retail', roles: ['owner'], currency: 'XOF');
const _farm = OrgSummary(id: 'org2', name: 'Ferme Issa', profile: 'farm', roles: ['owner'], currency: 'XOF');

ShopOrder _order(String status, {String fulfilment = 'pickup', List<OrderLine>? lines, String id = 'o1', String name = 'Fati Ouédraogo'}) => ShopOrder(
      id: id,
      customerName: name,
      status: status,
      fulfilment: fulfilment,
      total: 3500,
      currency: 'XOF',
      createdAt: DateTime(2026, 10, 8, 9, 12),
      phone: '+22670112233',
      note: 'Je passe vers 17 h',
      lines: lines ??
          const [
            OrderLine(name: 'Savon Citec', unitPrice: 500, quantity: 3),
            OrderLine(name: 'Riz parfumé 5 kg', unitPrice: 2000, quantity: 1),
          ],
    );

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Future<void> run(WidgetTester tester, Size size, Widget home, Future<void> Function(Future<void> Function(String) shot) steps) async {
    await loadFonts();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: kajTheme(kajPalette),
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: home,
      ),
    ));
    await tester.pumpAndSettle();
    await steps((name) => expectLater(find.byKey(shotKey), matchesGoldenFile('zz_shots/b115_W3_$name.png')));
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();
  }

  testWidgets('production', (tester) async {
    final retail = _Retail(shelf: const [
      Product(id: 'f', name: 'Farine de blé', quantity: 10, costPrice: 400, isIngredient: true, unit: 'kg'),
      Product(id: 'h', name: 'Huile', quantity: 2, costPrice: 1000, isIngredient: true, unit: 'l'),
      Product(id: 's', name: 'Sucre', quantity: 6, costPrice: 700, isIngredient: true, unit: 'kg'),
    ]);
    await run(tester, const Size(390, 844), ProductionScreen(org: _shop, production: _Production(), retail: retail), (shot) async {
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('production-name')), 'Gâteaux');
      await tester.pump();
      await shot('production_made_390');
      await next(tester);
      await tester.tap(find.byKey(const Key('production-pick-f')));
      await tester.tap(find.byKey(const Key('production-pick-h')));
      await tester.pumpAndSettle();
      await shot('production_inputs_390');
      await next(tester);
      await tester.enterText(find.byKey(const Key('production-qty-f')), '2');
      await tester.enterText(find.byKey(const Key('production-qty-h')), '3');
      await tester.pumpAndSettle();
      await shot('production_quantities_390');
      await next(tester);
      await tester.enterText(find.byKey(const Key('production-made')), '20');
      await tester.pumpAndSettle();
      await next(tester);
      await tester.enterText(find.byKey(const Key('production-price')), '150');
      await tester.pumpAndSettle();
      await shot('production_price_390');
      await tester.enterText(find.byKey(const Key('production-price')), '300');
      await next(tester);
      await shot('production_summary_390');
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      await shot('production_done_390');
    });
  });

  testWidgets('production, nothing marked (farm)', (tester) async {
    final retail = _Retail(shelf: const [Product(id: 'o', name: 'Œufs (plateau)', quantity: 12, salePrice: 2500)]);
    await run(tester, const Size(390, 844), ProductionScreen(org: _farm, production: _Production(), retail: retail, addIngredients: (_) async {}), (shot) async {
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('production-name')), 'Aliment volaille');
      await tester.pump();
      await next(tester);
      await shot('production_none_marked_390');
    });
  });

  testWidgets('orders', (tester) async {
    final retail = _Retail(orders: [
      _order('pending'),
      _order('accepted', id: 'o2', name: 'Ali Kaboré', fulfilment: 'delivery'),
      _order('ready', id: 'o3', name: 'Awa Traoré'),
    ]);
    await run(tester, const Size(390, 844), ShopOrdersScreen(org: _shop, retail: retail), (shot) async {
      await shot('orders_list_390');
      await tester.tap(find.byKey(const Key('order-walk-o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-option-accepted')));
      await tester.pumpAndSettle();
      await shot('order_answer_390');
      await tester.tap(find.byKey(const Key('flow-option-refused')));
      await tester.pumpAndSettle();
      await next(tester);
      await tester.tap(find.byKey(const Key('flow-option-Plus en stock')));
      await tester.pumpAndSettle();
      await shot('order_reason_390');
      await tester.tap(find.byKey(const Key('flow-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-option-accepted')));
      await tester.pumpAndSettle();
      await next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      await shot('order_accepted_done_390');
      await tester.tap(find.byKey(const Key('order-next-stage')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-pack-0')));
      await tester.pumpAndSettle();
      await shot('order_pack_390');
      await tester.tap(find.byKey(const Key('order-pack-1')));
      await tester.pumpAndSettle();
      await next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-next-stage')));
      await tester.pumpAndSettle();
      await shot('order_handover_390');
      await next(tester);
      await tester.tap(find.byKey(const Key('flow-option-true')));
      await tester.pumpAndSettle();
      await shot('order_paid_390');
      await next(tester);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      await shot('order_finished_390');
    });
  });

  testWidgets('order wide', (tester) async {
    await run(tester, const Size(1280, 800), Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
      onPressed: () => OrderWalkthrough.open(context, org: _shop, retail: _Retail(), order: _order('pending')),
      child: const Text('Ouvrir'))))), (shot) async {
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await shot('order_answer_1280');
    });
  });

  testWidgets('team', (tester) async {
    await run(tester, const Size(390, 844), Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
      onPressed: () => StepFlow.push(context, TeamInviteFlow(org: _shop, onboarding: _Onboarding(), admin: _Admin(), store: MemoryFlowStore())),
      child: const Text('Ouvrir'))))), (shot) async {
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('team-name')), 'Aïcha Sawadogo');
      await tester.enterText(find.byKey(const Key('team-title')), 'Vendeuse');
      await tester.pumpAndSettle();
      await shot('team_name_390');
      await next(tester);
      await tester.enterText(find.byKey(const Key('team-phone')), '70123456');
      await tester.pumpAndSettle();
      await shot('team_phone_390');
      await next(tester);
      await shot('team_role_390');
      await next(tester);
      await shot('team_sees_390');
      await next(tester);
      await tester.enterText(find.byKey(const Key('team-salary')), '45000');
      await tester.pumpAndSettle();
      await shot('team_salary_390');
      await next(tester);
      await shot('team_summary_390');
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      await shot('team_done_390');
    });
  });

  testWidgets('team wide', (tester) async {
    await run(tester, const Size(1280, 800), Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
      onPressed: () => StepFlow.push(context, TeamInviteFlow(org: _shop, onboarding: _Onboarding(), admin: _Admin(), store: MemoryFlowStore())),
      child: const Text('Ouvrir'))))), (shot) async {
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('team-name')), 'Aïcha');
      await tester.pump();
      await next(tester);
      await next(tester);
      await shot('team_role_1280');
    });
  });
}
