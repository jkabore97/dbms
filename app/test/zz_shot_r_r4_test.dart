import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/onboarding/business_creation.dart';
import 'package:kaj_app/features/setup/create_my_business_screen.dart';

import 'zz_shot_r_lib.dart';

class _Api implements BusinessCreation {
  @override
  Future<BusinessStart> start() async => const BusinessStart();
  @override
  Future<AddressCheck> checkAddress(String slug) async => AddressCheck(slug: slug);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(loadFonts);
  for (final lang in ['fr', 'en']) {
    testWidgets('r4 $lang', (tester) async {
      size(tester, 390, 844);
      await tester.pumpWidget(app(CreateMyBusinessScreen(api: _Api()), lang: lang));
      await settle(tester);
      await tester.tap(find.byKey(const Key('create-kind-retail')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('create-next')));
      await settle(tester);
      await shoot(tester, 'b122_R_r4_name_$lang');
      await tester.enterText(find.byKey(const Key('create-name')), 'Chez Awa');
      await settle(tester);
      await tester.tap(find.byKey(const Key('create-next')));
      await settle(tester);
      await shoot(tester, 'b122_R_r4_about_$lang');
      await tester.tap(find.byKey(const Key('create-activity-alimentation')));
      await tester.enterText(find.byKey(const Key('create-about')), 'Riz');
      await settle(tester);
      await tester.tap(find.byKey(const Key('create-next')));
      await settle(tester);
      await shoot(tester, 'b122_R_r4_place_$lang');
    });
  }
}
