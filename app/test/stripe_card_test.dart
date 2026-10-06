import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/pay/wave_pay.dart';
import 'package:kaj_app/features/admin/pro_console_screen.dart';
import 'package:kaj_app/features/pay/stripe_button.dart';
import 'package:kaj_app/features/pro/pro_plans_screen.dart';

/// Kaj Pro by card, as a Stripe subscription (082): the button on the
/// comparison page, the way back from Stripe, the owner's own page to
/// change it, and the platform's switch.
class _Pay extends WavePay {
  _Pay({this.sub}) : super(null, url: 'https://pay.example');

  final CardSubscription? sub;
  final asked = <String>[];

  @override
  bool get compiledIn => true;

  @override
  Future<String> subscribeByCard({
    required String orgId,
    required String period,
  }) async {
    asked.add('$orgId/$period');
    return 'https://checkout.stripe.com/c/cs_1';
  }

  @override
  Future<String> cardPortal(String orgId) async {
    asked.add('portal/$orgId');
    return 'https://billing.stripe.com/p/1';
  }

  @override
  Future<CardSubscription?> cardSubscription(String orgId) async => sub;
}

class _Admin extends AdminRepository {
  _Admin({this.terms = PlanTerms.defaults}) : super(null);

  final PlanTerms terms;
  final settings = <String, Object?>{};

  @override
  Future<PlanTerms> planTerms() async => terms;

  @override
  Future<List<PlanRequest>> planRequestsOpen() async => const [];

  @override
  Future<void> setPlatformSetting(String key, Object? value) async {
    settings[key] = value;
  }
}

const _free = OrgSummary(
    id: 'o1', name: 'Elim Shop', profile: 'retail', roles: ['owner']);
const _pro = OrgSummary(
    id: 'o1', name: 'Elim Shop', profile: 'retail', roles: ['owner'], plan: 'pro');

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Future<void> open(
    WidgetTester tester, {
    required OrgSummary org,
    required PlanTerms terms,
    required _Pay pay,
    List<Uri>? launched,
    String? stripeReturn,
    VoidCallback? onPaid,
  }) async {
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ProPlansScreen(
        org: org,
        terms: terms,
        admin: _Admin(terms: terms),
        cardButton: (period) => StripeCardButton(
          orgId: org.id,
          terms: terms,
          period: period,
          pay: pay,
          launch: (uri) async {
            launched?.add(uri);
            return true;
          },
        ),
        cardManage: StripeManage(
          orgId: org.id,
          pay: pay,
          launch: (uri) async {
            launched?.add(uri);
            return true;
          },
        ),
        stripeReturn: stripeReturn,
        onPaid: onPaid,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  const open_ = PlanTerms(stripeOn: true, priceMonth: 3000, priceYear: 30000);

  testWidgets('closed by the platform, there is no card button', (tester) async {
    await open(tester, org: _free, terms: const PlanTerms(), pay: _Pay());
    expect(find.byKey(const Key('stripe-card')), findsNothing);
  });

  testWidgets('open, it says the platform\'s price for the period chosen, '
      'and sends the owner to Stripe', (tester) async {
    final pay = _Pay();
    final launched = <Uri>[];
    await open(tester, org: _free, terms: open_, pay: pay, launched: launched);

    expect(find.textContaining(RegExp(r"S'abonner par carte · 30.000 F / an")),
        findsOneWidget);
    await tester.tap(find.text('Mensuel'));
    await tester.pump();
    expect(find.textContaining(RegExp(r"S'abonner par carte · 3.000 F / mois")),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('stripe-card')));
    await tester.pump();
    await tester.pump();
    expect(pay.asked, ['o1/month']);
    expect(launched.single.host, 'checkout.stripe.com');
  });

  testWidgets('back from Stripe: thanked, and the business read again until '
      'Pro shows', (tester) async {
    var reads = 0;
    await open(tester,
        org: _free, terms: open_, pay: _Pay(),
        stripeReturn: 'ok', onPaid: () => reads++);
    expect(find.byKey(const Key('stripe-returned')), findsOneWidget);
    expect(find.textContaining('Paiement reçu'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(reads, 3);
  });

  testWidgets('cancelled at Stripe: nothing taken, nothing re-read',
      (tester) async {
    var reads = 0;
    await open(tester,
        org: _free, terms: open_, pay: _Pay(),
        stripeReturn: 'annule', onPaid: () => reads++);
    expect(find.textContaining('rien n\'a été prélevé'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    expect(reads, 0);
  });

  testWidgets('a Pro business paying by card sees when it renews and '
      'Stripe\'s own page', (tester) async {
    final pay = _Pay(
        sub: CardSubscription(
            status: 'active', period: 'month', until: DateTime(2030, 3, 10, 12)));
    final launched = <Uri>[];
    await open(tester, org: _pro, terms: open_, pay: pay, launched: launched);
    expect(find.text('Payé par carte, renouvelé le 10 mars 2030.'), findsOneWidget);
    expect(find.byKey(const Key('stripe-card')), findsNothing);
    await tester.tap(find.byKey(const Key('stripe-manage')));
    await tester.pump();
    await tester.pump();
    expect(pay.asked, ['portal/o1']);
    expect(launched.single.host, 'billing.stripe.com');
  });

  testWidgets('a Pro business with no card subscription sees no card page',
      (tester) async {
    await open(tester, org: _pro, terms: open_, pay: _Pay());
    expect(find.byKey(const Key('stripe-manage')), findsNothing);
  });

  testWidgets('the platform switches the card on from the console',
      (tester) async {
    final admin = _Admin();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ProConsoleScreen(admin: admin)));
    await tester.pump();
    await tester.pump();
    final sw = find.byKey(const Key('stripe-on'));
    await tester.ensureVisible(sw);
    expect(tester.widget<SwitchListTile>(sw).value, isFalse);
    await tester.tap(sw);
    await tester.pump();
    await tester.pump();
    expect(admin.settings['stripe_on'], true);
    expect(tester.widget<SwitchListTile>(sw).value, isTrue);
  });

  test('plan_terms says whether the card is open', () {
    expect(PlanTerms.fromJson(const {'stripe_on': true}).stripeOn, isTrue);
    expect(PlanTerms.fromJson(const {}).stripeOn, isFalse);
  });
}
