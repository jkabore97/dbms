import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaj_app/core/pay/wave_pay.dart';
import 'package:kaj_app/features/pro/store_billing.dart';
import 'package:kaj_app/features/pro/store_watcher.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'batch130_store_test.dart' show FakeStore;

/// The TestFlight bug (« Le paiement est fait, mais Marakaj n'a pas encore
/// pu le vérifier… » at every launch and on every screen): an Apple
/// purchase the Worker could not verify is left open, so the store hands it
/// back at each launch. Its snackbar is now said once per purchase and
/// reason in a run, with the real reason, and logged with its HTTP status.
void main() {
  const purchase = StorePurchase(
    status: StorePurchaseStatus.purchased,
    productId: 'bf.kaj.app.pro.monthly',
    transactionId: '2000000111',
    signedTransaction: 'eyJ.header.sig',
    needsCompletion: true,
    orgId: '52000000-0000-0000-0000-0000000000a1',
  );
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a passing refusal of the same purchase, handed back again and again: one snackbar, logged with its status',
      () async {
    final fake = FakeStore('apple');
    final outside = <StoreNotice>[];
    final logged = <String>[];
    var asked = 0;
    final w = StoreWatcher(
      billing: fake,
      verify: (_) async {
        asked++;
        throw const StoreVerifyRefused('App Store answered 502', 'upstream', status: 502);
      },
      outside: outside.add,
      log: logged.add,
    )..start();
    addTearDown(w.dispose);
    for (var i = 0; i < 3; i++) {
      fake.controller.add(const [purchase]);
      await settle();
    }
    expect(asked, 3, reason: 'asked again each time: the next one may pass');
    expect(fake.completed, isEmpty, reason: 'left open: nothing charged twice, the store hands it back');
    expect(outside, hasLength(1), reason: 'said once this run, not on every screen');
    expect(logged, everyElement(contains('(upstream, left open) apple bf.kaj.app.pro.monthly http 502')));
    expect(logged.join(), isNot(contains('2000000111')), reason: 'never the transaction id');
    expect(logged.join(), isNot(contains('eyJ')), reason: 'never the signed transaction');
    // The Pro page still draws the last word.
    expect(w.notice.value, isNotNull);
  });

  test('another reason, or another purchase, is said; « checking… » is never a snackbar', () async {
    final fake = FakeStore('apple');
    final outside = <StoreNotice>[];
    var answer = 0;
    final w = StoreWatcher(
      billing: fake,
      verify: (_) async {
        answer++;
        if (answer == 1) throw const StoreVerifyRefused('', 'upstream', status: 502);
        if (answer == 2) throw const StoreVerifyRefused('', 'session', status: 401);
        if (answer == 3) throw StateError('Pas de connexion au serveur de Marakaj.');
        return const StoreVerdict(pro: true, state: 'active');
      },
      outside: outside.add,
    )..start();
    addTearDown(w.dispose);
    for (var i = 0; i < 4; i++) {
      fake.controller.add(const [purchase]);
      await settle();
    }
    expect(outside, hasLength(4), reason: 'upstream, session, unreached, then Pro on — never « Vérification… »');
    expect(outside.last.good, isTrue);
    expect(fake.completed, hasLength(1), reason: 'completed on the Worker\'s yes only');
  });

  test('the same purchase delivered twice while its check runs is asked once', () async {
    final fake = FakeStore('apple');
    final gate = Completer<StoreVerdict>();
    var asked = 0;
    final w = StoreWatcher(
      billing: fake,
      verify: (_) {
        asked++;
        return gate.future;
      },
    )..start();
    addTearDown(w.dispose);
    fake.controller.add(const [purchase]);
    await settle();
    fake.controller.add(const [purchase]);
    await settle();
    expect(asked, 1);
    gate.complete(const StoreVerdict(pro: true, state: 'active'));
    await settle();
    expect(fake.completed, hasLength(1));
  });

  testWidgets('each reason is said for what it is, in French and English, and keeps « nothing charged twice »',
      (tester) async {
    final said = <String, List<String>>{};
    for (final locale in [null, const Locale('en')]) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: locale == null ? null : Strings.localizationsDelegates,
        supportedLocales: locale == null ? const [Locale('en', 'US')] : Strings.supportedLocales,
        home: Builder(builder: (context) {
          for (final code in ['upstream', 'config', 'unknown', 'session', 'not_admin', 'whatever']) {
            said.putIfAbsent(code, () => []).add(
                storeRefusalText(context, StoreVerifyRefused('', code, status: 502), 'App Store'));
          }
          said.putIfAbsent('unreached', () => []).add(storeUnreachedText(context));
          return const SizedBox();
        }),
      ));
    }
    for (final e in said.entries) {
      expect(e.value[0], isNot(e.value[1]), reason: '${e.key}: English differs from French');
    }
    for (final code in ['upstream', 'config', 'unknown', 'unreached']) {
      expect(said[code]![0], contains('rien ne sera prélevé deux fois'), reason: code);
      expect(said[code]![1], contains('nothing will be charged twice'), reason: code);
      expect(said[code]![0], isNot(said['whatever']![0]), reason: '$code has its own words');
    }
    expect(said['upstream']![1], contains('App Store has not answered'));
  });

  group('WavePay.verifyStore', () {
    late SupabaseClient client;
    setUp(() async {
      client = SupabaseClient('https://db.example', 'publishable',
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      await client.auth.recoverSession(jsonEncode({
        'access_token': 'owner-jwt',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': exp,
        'refresh_token': 'r',
        'user': {
          'id': '51000000-0000-0000-0000-000000000001',
          'aud': 'authenticated',
          'app_metadata': <String, Object?>{},
          'user_metadata': <String, Object?>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }));
    });
    tearDown(() => client.dispose());

    test('sends the signed transaction; a 5xx is a refusal with its code and status, not « unreachable »',
        () async {
      Map<String, dynamic>? sent;
      final pay = WavePay(client, url: 'https://pay.example', httpClient: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'error': 'App Store answered 401', 'code': 'upstream'}), 502);
      }));
      await expectLater(
        pay.verifyStore(
          platform: 'apple',
          orgId: purchase.orgId,
          productId: purchase.productId,
          transactionId: purchase.transactionId,
          signedTransaction: purchase.signedTransaction,
        ),
        throwsA(isA<StoreVerifyRefused>()
            .having((e) => e.code, 'code', 'upstream')
            .having((e) => e.status, 'status', 502)),
      );
      expect(sent?['signed_transaction'], 'eyJ.header.sig');
      expect(sent?['transaction_id'], '2000000111');
    });

    test('no answer at all is still « unreachable » (left open)', () async {
      final pay = WavePay(client, url: 'https://pay.example', httpClient: MockClient((_) async {
        throw http.ClientException('offline');
      }));
      await expectLater(
        pay.verifyStore(platform: 'apple', productId: purchase.productId, transactionId: '1'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
