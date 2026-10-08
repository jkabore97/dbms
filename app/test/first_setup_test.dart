import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/features/setup/setup_screen.dart';

/// The first setup (091): name, first article, vitrine, position — or
/// « Plus tard » — then « C'est prêt ! » and the store opens.
class _Actions implements SetupActions {
  final log = <String>[];

  @override
  Future<void> rename(String orgId, String name, String currency) async =>
      log.add('rename $name');

  @override
  Future<void> addArticle(String orgId,
          {required String name, required double price, required double quantity}) async =>
      log.add('article $name $price $quantity');

  @override
  Future<void> saveVitrine(String orgId,
          {required bool open, required String blurb, required String phone, required String address}) async =>
      log.add('vitrine $open $blurb $phone $address');

  @override
  Future<void> savePosition(String orgId, double lat, double lng) async =>
      log.add('position');

  @override
  Future<void> finish(String orgId) async => log.add('finish');
}

const _org = OrgSummary(
    id: 'o1', name: 'Boutique Awa', profile: 'retail', roles: ['owner'], slug: 'awa');

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('the four steps, the article required, then the store opens',
      (tester) async {
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final a = _Actions();
    var opened = false;
    await tester.pumpWidget(MaterialApp(
        home: SetupScreen(org: _org, actions: a, onDone: () => opened = true)));
    await settle(tester);

    expect(find.text('Votre boutique'), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);
    await tester.tap(find.byKey(const Key('setup-next-0')));
    await settle(tester);
    expect(a.log, ['rename Boutique Awa']);

    // The article: nothing goes on without a name and a price.
    expect(find.text('Votre premier article'), findsOneWidget);
    expect(find.byKey(const Key('setup-next-1')), findsNothing);
    await tester.tap(find.byKey(const Key('setup-add')));
    await settle(tester);
    expect(find.text('Un nom et un prix.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('setup-article')), 'Riz 25 kg');
    await tester.enterText(find.byKey(const Key('setup-price')), '17 500');
    await tester.enterText(find.byKey(const Key('setup-quantity')), '10');
    await tester.tap(find.byKey(const Key('setup-add')));
    await settle(tester);
    expect(a.log.last, 'article Riz 25 kg 17500.0 10.0');
    expect(find.text('1 article sur la vitrine'), findsOneWidget);
    await tester.tap(find.byKey(const Key('setup-next-1')));
    await settle(tester);

    // The vitrine: a wrong phone length is said, then fixed.
    expect(find.text('Votre vitrine'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('setup-blurb')), 'Le riz du quartier');
    await tester.enterText(find.byType(TextField).at(1), '9733365729');
    await tester.tap(find.byKey(const Key('setup-next-2')));
    await settle(tester);
    expect(find.text('8 chiffres pour Burkina Faso (+226)'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), '70123456');
    await tester.enterText(find.byKey(const Key('setup-address')), 'Gounghin');
    await tester.tap(find.byKey(const Key('setup-next-2')));
    await settle(tester);
    expect(a.log.last, 'vitrine true Le riz du quartier +22670123456 Gounghin');

    // The position may wait. It is the shop's own place (108).
    expect(find.text('La position de ma boutique'), findsOneWidget);
    expect(find.text('Sans position, pas de cauris de vitrine complète.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('setup-later')));
    await settle(tester);
    expect(a.log.last, 'finish');
    expect(find.byKey(const Key('setup-ready')), findsOneWidget);
    await tester.tap(find.byKey(const Key('setup-enter')));
    expect(opened, isTrue);
  });

  test('the server says whether the setup is done; silence is done', () {
    expect(FeatureStates.fromJson(const {'setup_done': false}).setupDone, isFalse);
    expect(FeatureStates.fromJson(const {}).setupDone, isTrue);
  });
}
