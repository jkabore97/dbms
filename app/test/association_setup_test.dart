import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/setup/association_setup_screen.dart';

/// An association's first minutes (102): its name and kind, its first
/// members (skippable), one service on the vitrine (or « Plus tard »),
/// then « C'est prêt ! ».
class _Actions implements AssociationSetupActions {
  final log = <String>[];

  @override
  Future<void> identify(String orgId,
          {required String name, required String currency, required String kind, required String about}) async =>
      log.add('identify $name $currency $kind $about');

  @override
  Future<void> addMember(String orgId, {required String name, required String phone}) async =>
      log.add('member $name $phone');

  @override
  Future<void> addService(String orgId, {required String name, required double price}) async =>
      log.add('service $name $price');

  @override
  Future<void> saveVitrine(String orgId,
          {required bool open, required String about, required String phone, required String address}) async =>
      log.add('vitrine $open $about $phone $address');

  @override
  Future<void> finish(String orgId) async => log.add('finish');
}

const _org = OrgSummary(
    id: 'a1', name: 'Entraide', profile: 'association', roles: ['owner'], slug: 'entraide');

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<_Actions> start(WidgetTester tester, {VoidCallback? onDone}) async {
    tester.view.physicalSize = const Size(480, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final a = _Actions();
    await tester.pumpWidget(MaterialApp(
        home: AssociationSetupScreen(org: _org, actions: a, onDone: onDone ?? () {})));
    await settle(tester);
    return a;
  }

  testWidgets('the name and the kind, three members, a service, then ready',
      (tester) async {
    var opened = false;
    final a = await start(tester, onDone: () => opened = true);

    expect(find.text('Votre association'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    // The kind is asked, with its line; no currency question.
    expect(find.text('On cotise, chacun reçoit à son tour.'), findsOneWidget);
    expect(find.textContaining('monnaie'), findsNothing);
    await tester.tap(find.byKey(const Key('asetup-next-0')));
    await settle(tester);
    expect(find.text('Choisissez ce qu\'elle est.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('asetup-kind-tontine')));
    await tester.enterText(find.byKey(const Key('asetup-about')), 'Les femmes de Gounghin');
    await tester.tap(find.byKey(const Key('asetup-next-0')));
    await settle(tester);
    expect(a.log, ['identify Entraide XOF tontine Les femmes de Gounghin']);

    // Members: a name without a phone is fine, a wrong length is said.
    expect(find.text('Vos premiers membres'), findsOneWidget);
    expect(find.byKey(const Key('asetup-whatsapp')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('asetup-member-0')), 'Awa');
    await tester.enterText(
        find.descendant(of: find.byKey(const Key('asetup-member-phone-0')), matching: find.byType(TextField)),
        '7012');
    await tester.enterText(find.byKey(const Key('asetup-member-1')), 'Bintou');
    await tester.tap(find.byKey(const Key('asetup-next-1')));
    await settle(tester);
    expect(find.text('8 chiffres pour Burkina Faso (+226)'), findsOneWidget);
    await tester.enterText(
        find.descendant(of: find.byKey(const Key('asetup-member-phone-0')), matching: find.byType(TextField)),
        '70123456');
    await tester.tap(find.byKey(const Key('asetup-next-1')));
    await settle(tester);
    expect(a.log.sublist(1), ['member Awa +22670123456', 'member Bintou ']);

    // The vitrine: a service needs its price.
    expect(find.text('Votre vitrine'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('asetup-service')), 'Location de la salle');
    await tester.tap(find.byKey(const Key('asetup-next-2')));
    await settle(tester);
    expect(find.text('Un nom et un prix, s\'il vous plaît.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('asetup-price')), '10 000');
    await tester.enterText(find.byKey(const Key('asetup-address')), 'Gounghin');
    await tester.tap(find.byKey(const Key('asetup-next-2')));
    await settle(tester);
    expect(a.log.sublist(3), [
      'service Location de la salle 10000.0',
      'vitrine true Les femmes de Gounghin  Gounghin',
      'finish',
    ]);
    expect(find.byKey(const Key('setup-ready')), findsOneWidget);
    expect(find.text('Ouvrir mon association'), findsOneWidget);
    await tester.tap(find.byKey(const Key('setup-enter')));
    expect(opened, isTrue);
  });

  testWidgets('members and the vitrine may both wait', (tester) async {
    final a = await start(tester);
    await tester.tap(find.byKey(const Key('asetup-kind-eglise')));
    await tester.tap(find.byKey(const Key('asetup-next-0')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('asetup-skip-1')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('asetup-later')));
    await settle(tester);
    expect(a.log, ['identify Entraide XOF eglise ', 'finish']);
    expect(find.byKey(const Key('setup-ready')), findsOneWidget);
  });

  testWidgets('the guide card after the walkthrough', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FirstContributionCard(onTap: () => tapped = true))));
    expect(find.text('Encaissez la première cotisation'), findsOneWidget);
    await tester.tap(find.byKey(const Key('first-contribution')));
    expect(tapped, isTrue);
  });

  test('the server says whether money came in; silence draws no card', () {
    expect(FeatureStates.fromJson(const {'first_income': false}).firstIncome, isFalse);
    expect(FeatureStates.fromJson(const {'first_income': true}).firstIncome, isTrue);
    expect(FeatureStates.fromJson(const {}).firstIncome, isNull);
  });
}
