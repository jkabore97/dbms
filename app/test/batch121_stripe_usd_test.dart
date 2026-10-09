import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/pay/wave_pay.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/pay/stripe_button.dart';

/// Mara Pro by card, charged in dollars (121): the FCFA price stays on the
/// button, the dollars the server computed are said under it, and the rate
/// is a Réglages number that is never zero.
class _Pay extends WavePay {
  _Pay() : super(null, url: 'https://pay.example');

  @override
  bool get compiledIn => true;
}

class _Center extends CommandCenterRepository {
  _Center() : super(null);

  final calls = <String>[];
  Map<String, SettingValue> values = const {};

  @override
  bool get isConfigured => true;

  @override
  Future<Map<String, SettingValue>> settings() async => values;

  @override
  Future<String?> setSetting(String key, Object? value) async {
    calls.add('set:$key=$value');
    values = {...values, key: SettingValue(value: value)};
    return 'act-$key';
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Future<void> button(WidgetTester tester, PlanTerms terms, String period) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StripeCardButton(orgId: 'o1', terms: terms, period: period, pay: _Pay()),
      ),
    ));
    await tester.pump();
  }

  const terms = PlanTerms(
    stripeOn: true,
    priceMonth: 15000,
    priceYear: 150000,
    stripeUsdMonthCents: 2500,
    stripeUsdYearCents: 125050,
  );

  testWidgets('the FCFA price on the button, the server\'s dollars under it', (tester) async {
    await button(tester, terms, 'month');
    expect(find.textContaining(RegExp(r"S'abonner par carte · 15.000 F / mois")), findsOneWidget);
    expect(find.text('≈ \$25.00 par mois, payé en dollars'), findsOneWidget);

    await button(tester, terms, 'year');
    expect(find.textContaining(RegExp(r"S'abonner par carte · 150.000 F / an")), findsOneWidget);
    expect(find.text('≈ \$1,250.50 par an, payé en dollars'), findsOneWidget);
  });

  test('in English as well', () {
    expect(translate('en', '≈ {usd} par mois, payé en dollars', {'usd': '\$25.00'}),
        '≈ \$25.00 a month, paid in dollars');
    expect(translate('en', '≈ {usd} par an, payé en dollars', {'usd': '\$250.00'}),
        '≈ \$250.00 a year, paid in dollars');
    expect(translate('en', 'Taux pour la carte : FCFA pour 1 \$'), 'Card rate: FCFA for \$1');
    expect(translate('en', 'Un nombre entier plus grand que zéro.'), 'A whole number above zero.');
  });

  testWidgets('no dollars from the server (before 121, or no rate): no line, the button as before',
      (tester) async {
    await button(tester, const PlanTerms(stripeOn: true, priceMonth: 15000), 'month');
    expect(find.byKey(const Key('stripe-card')), findsOneWidget);
    expect(find.byKey(const Key('stripe-usd')), findsNothing);
  });

  test('plan_terms: the cents read as the server says them, kept for every kind', () {
    final t = PlanTerms.fromJson(const {
      'stripe_on': true,
      'pro_price_month': 2900,
      'pro_price_year': 29900,
      'stripe_usd_month': 484,
      'stripe_usd_year': 4984,
      'kinds': {
        'farm': {'free_max_staff': 2},
      },
    });
    expect(t.priceMonth, 2900, reason: 'the FCFA price is unchanged');
    expect(t.stripeUsdMonthCents, 484);
    expect(t.stripeUsdYearCents, 4984);
    for (final kind in ['retail', 'farm', 'association', 'church']) {
      final k = t.forProfile(kind);
      expect(k.stripeUsdMonthCents, 484, reason: kind);
      expect(k.stripeUsdYearCents, 4984, reason: kind);
    }
    expect(t.forProfile('farm').freeMaxStaff, 2);
    final none = PlanTerms.fromJson(const {'stripe_usd_month': null});
    expect(none.stripeUsdMonthCents, isNull);
    expect(none.stripeUsdYearCents, isNull);
  });

  testWidgets('Réglages: the card\'s rate by its name, a whole number above zero', (tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final center = _Center()
      ..values = {
        'stripe_on': const SettingValue(value: true),
        'stripe_xof_per_usd': const SettingValue(value: 600),
      };
    await tester.pumpWidget(MaterialApp(home: SettingsSection(center: center)));
    await tester.pumpAndSettle();
    expect(find.text('Taux pour la carte : FCFA pour 1 \$'), findsOneWidget);
    expect(find.text('600'), findsOneWidget);

    await tester.tap(find.byKey(const Key('setting-stripe_xof_per_usd')));
    await tester.pumpAndSettle();
    for (final text in ['0', '-600', '600,5', 'six cents']) {
      await tester.enterText(find.byKey(const Key('setting-field')), text);
      await tester.tap(find.byKey(const Key('setting-save')));
      await tester.pumpAndSettle();
      expect(find.text('Un nombre entier plus grand que zéro.'), findsOneWidget, reason: text);
    }
    expect(center.calls, isEmpty);
    await tester.enterText(find.byKey(const Key('setting-field')), '610');
    await tester.tap(find.byKey(const Key('setting-save')));
    await tester.pumpAndSettle();
    expect(center.calls, ['set:stripe_xof_per_usd=610']);
    expect(find.text('610'), findsOneWidget);
  });

  test('the rate is listed once, in the Pro group, as a whole number', () {
    final defs = platformSettingDefs.where((d) => d.key == 'stripe_xof_per_usd').toList();
    expect(defs, hasLength(1));
    expect(defs.single.group, 'pro');
    expect(defs.single.type, SettingType.count);
    expect(decimalSettings.contains('stripe_xof_per_usd'), isFalse);
  });
}
