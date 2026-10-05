import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaj_app/core/orders/orders.dart';
import 'package:kaj_app/core/pay/wave_pay.dart';
import 'package:kaj_app/features/pay/payment_screen.dart';
import 'package:kaj_app/features/pay/wave_buttons.dart';

/// Paying by Wave or card through Kaj (076).
///
/// Every payment used to close by hand. Now the platform's switch opens
/// Wave checkout; an order needs its shop's payout number; the amount is
/// never the app's; and the page Wave sends the person back to waits for
/// Wave's own word.
class _Pay extends WavePay {
  _Pay(this.t, {this.statuses = const []}) : super(null, url: 'https://pay.example');

  final WaveTerms t;
  final List<String> statuses;
  final started = <String>[];
  int _asked = 0;

  @override
  bool get compiledIn => true;

  @override
  Future<WaveTerms> terms({String? orgId}) async => t;

  @override
  Future<WaveCheckout> start({
    required String kind,
    required String ref,
    bool card = false,
    String period = 'month',
  }) async {
    started.add('$kind:$ref:${card ? 'card' : 'wave'}:$period');
    return const WaveCheckout(url: 'https://pay.wave.com/c/cos-1', paymentId: 'pay-1');
  }

  @override
  Future<String?> status(String paymentId) async =>
      statuses[_asked < statuses.length ? _asked++ : statuses.length - 1];
}

Widget _host(Widget child, {List<String>? pushed}) => MaterialApp.router(
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => Scaffold(body: Center(child: child))),
        GoRoute(
          path: '/paiement/:id',
          builder: (_, state) {
            pushed?.add(state.pathParameters['id']!);
            return const Text('page de paiement');
          },
        ),
      ]),
    );

void main() {
  group('when Wave is offered', () {
    testWidgets('off: the old way of paying stands', (tester) async {
      await tester.pumpWidget(_host(WaveButtons(
        kind: 'order',
        ref: 'o1',
        orgId: 'org1',
        pay: _Pay(const WaveTerms(on: false)),
        onUnavailable: const Text('lien Wave de la boutique'),
      )));
      await tester.pump();
      expect(find.text('Payer avec Wave'), findsNothing);
      expect(find.text('lien Wave de la boutique'), findsOneWidget);
    });

    testWidgets('on, but the shop has no payout number: still the old way',
        (tester) async {
      await tester.pumpWidget(_host(WaveButtons(
        kind: 'order',
        ref: 'o1',
        orgId: 'org1',
        pay: _Pay(const WaveTerms(on: true, shopReady: false)),
        onUnavailable: const Text('lien Wave de la boutique'),
      )));
      await tester.pump();
      expect(find.text('Payer avec Wave'), findsNothing);
    });

    testWidgets('on: Wave opens its app, card its page, then the payment page',
        (tester) async {
      final pay = _Pay(const WaveTerms(on: true, shopReady: true, card: true));
      final launched = <String>[];
      final pushed = <String>[];
      await tester.pumpWidget(_host(
        WaveButtons(
          kind: 'order',
          ref: 'o1',
          orgId: 'org1',
          pay: pay,
          launch: (uri, {required card}) async {
            launched.add('${card ? 'card' : 'wave'} $uri');
            return true;
          },
        ),
        pushed: pushed,
      ));
      await tester.pump();
      expect(find.text('Payer avec Wave'), findsOneWidget);
      expect(find.text('Payer par carte'), findsOneWidget);

      await tester.tap(find.text('Payer par carte'));
      await tester.pumpAndSettle();
      expect(pay.started, ['order:o1:card:month']);
      expect(launched, ['card https://pay.wave.com/c/cos-1']);
      expect(pushed, ['pay-1']);
    });
  });

  testWidgets('the payment page waits for Wave, then says it is paid',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PaymentScreen(
        paymentId: 'pay-1',
        pay: _Pay(const WaveTerms(), statuses: const ['open', 'open', 'succeeded']),
      ),
    ));
    await tester.pump();
    expect(find.text('Confirmation en cours…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Paiement reçu'), findsOneWidget);
  });

  test('an order is payable by Wave once the shop has accepted it, and once', () {
    CustomerOrder order(String status, {DateTime? paidAt, String method = 'wave'}) =>
        CustomerOrder(
          id: 'o1',
          shopName: 'B',
          shopSlug: 'b',
          status: status,
          fulfilment: 'pickup',
          total: 5000,
          currency: 'XOF',
          createdAt: DateTime(2026, 10, 5),
          lines: const [],
          paymentMethod: method,
          paidAt: paidAt,
          orgId: 'org1',
        );
    expect(order('pending').canPayByWave, isFalse,
        reason: 'before the shop says yes, the money would be in limbo');
    expect(order('accepted').canPayByWave, isTrue);
    expect(order('accepted', paidAt: DateTime(2026, 10, 5)).canPayByWave, isFalse);
    expect(order('accepted', method: 'cash').canPayByWave, isFalse);
  });
}
